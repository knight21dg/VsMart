"""Accounts payable: supplier invoices and the payments that settle them.

`PurchaseInvoice.amount_paid` and `.status` are caches derived from the payment
rows — they are only ever written here, by `_recalc`, so the balance can't drift
from the payments that produced it.
"""
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from core.app_errors import AppError

from .models import PurchaseInvoice, VendorPayment

ZERO = Decimal("0.00")


def _recalc(invoice):
    """Recompute amount_paid + status from the payment rows."""
    paid = invoice.payments.aggregate(s=Sum("amount"))["s"] or ZERO
    invoice.amount_paid = paid
    if invoice.status == PurchaseInvoice.Status.CANCELLED:
        pass                                   # cancelled stays cancelled
    elif paid <= ZERO:
        invoice.status = PurchaseInvoice.Status.AWAITING
    elif paid < invoice.total:
        invoice.status = PurchaseInvoice.Status.PARTIAL
    else:
        invoice.status = PurchaseInvoice.Status.PAID
    invoice.save(update_fields=["amount_paid", "status", "updated_at"])
    return invoice


@transaction.atomic
def record_payment(invoice, *, amount, method, paid_on=None, reference="",
                   notes="", actor=None):
    """Pay (part of) a supplier invoice.

    Overpayment is refused: paying more than is owed silently creates a negative
    balance that reads as a credit note nobody issued.
    """
    invoice = PurchaseInvoice.objects.select_for_update().get(pk=invoice.pk)

    if invoice.status == PurchaseInvoice.Status.CANCELLED:
        raise AppError("INVALID_AP_TRANSITION",
                       message="This invoice was cancelled and can't be paid.")
    if invoice.status == PurchaseInvoice.Status.DRAFT:
        raise AppError("INVALID_AP_TRANSITION",
                       message="Approve the invoice before paying it.")

    amount = Decimal(str(amount))
    if amount <= ZERO:
        raise AppError("VALIDATION_ERROR",
                       message="A payment must be greater than zero.")
    if amount > invoice.balance_due:
        raise AppError(
            "AP_OVERPAYMENT",
            message=f"That exceeds the ₹{invoice.balance_due} still owed on this invoice.",
        )

    payment = VendorPayment.objects.create(
        invoice=invoice,
        amount=amount,
        method=method,
        paid_on=paid_on or timezone.localdate(),
        reference=reference or "",
        notes=notes or "",
        created_by=actor,
    )
    _recalc(invoice)
    from accounting.posting import post_vendor_payment

    post_vendor_payment(payment)
    return payment


@transaction.atomic
def approve_invoice(invoice, actor=None):
    """Move a draft invoice into the payables ledger."""
    if invoice.status != PurchaseInvoice.Status.DRAFT:
        raise AppError("INVALID_AP_TRANSITION",
                       message="Only a draft invoice can be approved.")
    invoice.status = PurchaseInvoice.Status.AWAITING
    invoice.save(update_fields=["status", "updated_at"])
    # Approving is what makes it a liability, so that's when it hits the ledger.
    from accounting.posting import post_purchase_invoice

    post_purchase_invoice(invoice)
    return invoice


@transaction.atomic
def cancel_invoice(invoice, actor=None):
    """Cancel an invoice. Refused once money has been paid against it — the
    payment really happened, so the liability has to be corrected with a credit
    note rather than erased."""
    if invoice.payments.exists():
        raise AppError(
            "INVALID_AP_TRANSITION",
            message="This invoice has payments against it and can't be cancelled.",
        )
    invoice.status = PurchaseInvoice.Status.CANCELLED
    invoice.save(update_fields=["status", "updated_at"])
    return invoice


#: Payables aging buckets, in days past due.
AGING_BUCKETS = ((0, 0, "current"), (1, 30, "1-30"), (31, 60, "31-60"),
                 (61, 90, "61-90"), (91, None, "90+"))


def payables_aging(store=None, supplier=None, as_of=None):
    """Outstanding payables bucketed by how overdue they are.

    An invoice with no due date is treated as current rather than dropped —
    otherwise money owed silently disappears from the total.
    """
    as_of = as_of or timezone.localdate()
    qs = PurchaseInvoice.objects.filter(
        status__in=[PurchaseInvoice.Status.AWAITING, PurchaseInvoice.Status.PARTIAL]
    ).select_related("supplier")
    if store is not None:
        qs = qs.filter(store=store)
    if supplier is not None:
        qs = qs.filter(supplier=supplier)

    buckets = {label: {"count": 0, "amount": ZERO} for *_, label in AGING_BUCKETS}
    total = ZERO
    by_supplier = {}

    for inv in qs:
        due = inv.balance_due
        if due <= ZERO:
            continue
        total += due
        days = (as_of - inv.due_date).days if inv.due_date else 0
        label = "current"
        for low, high, name in AGING_BUCKETS:
            if days >= low and (high is None or days <= high):
                label = name
                break
        buckets[label]["count"] += 1
        buckets[label]["amount"] += due

        key = inv.supplier_id
        row = by_supplier.setdefault(
            key, {"supplierId": str(key), "supplier": inv.supplier.name,
                  "amount": ZERO, "invoices": 0}
        )
        row["amount"] += due
        row["invoices"] += 1

    return {
        "asOf": as_of,
        "totalOutstanding": total,
        "buckets": [
            {"bucket": label, **buckets[label]} for *_, label in AGING_BUCKETS
        ],
        "bySupplier": sorted(
            by_supplier.values(), key=lambda r: r["amount"], reverse=True
        ),
    }
