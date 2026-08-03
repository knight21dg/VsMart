"""Auto-posting: turning real money events into journal entries.

Each hook is **idempotent** via ``(source_module, source_ref)``, so replaying a
webhook, retrying a job or re-running a backfill can never book the same money
twice. Each is also **fail-soft**: a ledger problem must never roll back the
business transaction that caused it — a customer's payment succeeding is more
important than its bookkeeping succeeding, and an unposted event can be
backfilled, whereas a rejected payment cannot be un-rejected.

Anything that fails is left for ``backfill_gl`` to pick up, and logged.
"""
import logging

from django.utils import timezone

from . import chart
from .services import post_entry

log = logging.getLogger(__name__)


def _safe(fn):
    """Run a posting hook without ever letting it break the caller."""
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except Exception:  # noqa: BLE001 — bookkeeping must not break commerce
            log.exception("GL posting failed for %s", fn.__name__)
            return None
    return wrapper


@_safe
def post_payment(payment):
    """A customer payment landed.

    Dr the account the money arrived in, Cr what it settled:
    * an **order** payment clears the sale (revenue is recognised here for cash
      sales; a credit sale already booked receivable at order time),
    * a **repayment** clears the customer's receivable balance.
    """
    from payments.models import Payment

    if payment.status != Payment.Status.SUCCESS:
        return None

    # Where the money physically arrived.
    if payment.method == Payment.Method.CASH:
        debit_account = chart.CASH_ON_HAND
    elif payment.gateway and payment.gateway != "manual":
        debit_account = chart.GATEWAY_RECEIVABLE
    else:
        debit_account = chart.BANK

    if payment.purpose == Payment.Purpose.REPAYMENT:
        credit_account = chart.ACCOUNTS_RECEIVABLE
        narration = f"Credit repayment from {payment.user.name or payment.user.phone}"
    elif payment.purpose == Payment.Purpose.REFUND:
        # A refund is money going out: mirror the sides.
        return post_entry(
            entry_date=payment.created_at.date(),
            narration=f"Refund to {payment.user.name or payment.user.phone}",
            reference=payment.gateway_refund_id or str(payment.id),
            source_module="payment_refund", source_ref=payment.id,
            store=getattr(payment.order, "store", None),
            lines=[
                {"account": chart.SALES_REVENUE, "debit": payment.amount},
                {"account": debit_account, "credit": payment.amount},
            ],
        )
    else:
        credit_account = chart.SALES_REVENUE
        narration = f"Order payment {getattr(payment.order, 'code', '')}".strip()

    return post_entry(
        entry_date=payment.created_at.date(),
        narration=narration or f"Payment {payment.id}",
        reference=payment.gateway_payment_id or str(payment.id),
        source_module="payment", source_ref=payment.id,
        store=getattr(payment.order, "store", None),
        lines=[
            {"account": debit_account, "debit": payment.amount},
            {"account": credit_account, "credit": payment.amount},
        ],
    )


@_safe
def post_cash_collection(collection):
    """An agent took cash from a customer.

    The money is now the agent's responsibility, so it moves into 'Cash with
    Agents' rather than straight to bank — that account is the ledger's mirror
    of the cash-book's in-hand figure.
    """
    if not collection.collected_amount or collection.collected_amount <= 0:
        return None
    return post_entry(
        entry_date=(collection.collected_at or timezone.now()).date(),
        narration=f"Cash collected by {getattr(collection.agent, 'name', 'agent')}",
        reference=str(collection.id),
        source_module="cash_collection", source_ref=collection.id,
        lines=[
            {"account": chart.CASH_WITH_AGENTS, "debit": collection.collected_amount},
            {"account": chart.ACCOUNTS_RECEIVABLE, "credit": collection.collected_amount},
        ],
    )


@_safe
def post_cash_deposit(deposit):
    """A deposit was counted in.

    Moves the counted amount out of 'Cash with Agents' into bank/cash, and books
    any shortfall as an expense so the difference lands somewhere real instead of
    silently disappearing.
    """
    from payments.models import CashDeposit

    if deposit.status not in (CashDeposit.Status.VERIFIED, CashDeposit.Status.SHORT):
        return None

    counted = deposit.verified_amount or 0
    shortfall = deposit.shortfall
    destination = (
        chart.CASH_ON_HAND if deposit.method == CashDeposit.Method.OFFICE
        else chart.BANK
    )

    lines = [{"account": destination, "debit": counted}]
    if shortfall > 0:
        lines.append({"account": chart.CASH_SHORTAGE, "debit": shortfall,
                      "narration": "Short against declared"})
    lines.append({"account": chart.CASH_WITH_AGENTS, "credit": deposit.amount})

    return post_entry(
        entry_date=deposit.deposited_on,
        narration=f"Cash deposit by {getattr(deposit.agent, 'name', 'agent')}",
        reference=deposit.reference or str(deposit.id),
        source_module="cash_deposit", source_ref=deposit.id,
        store=deposit.store,
        lines=lines,
    )


@_safe
def post_purchase_invoice(invoice):
    """A supplier billed us: stock (and recoverable GST) in, payable out."""
    from inventory.models import PurchaseInvoice

    if invoice.status == PurchaseInvoice.Status.DRAFT:
        return None      # not a liability until approved

    lines = [{"account": chart.INVENTORY, "debit": invoice.subtotal}]
    if invoice.tax and invoice.tax > 0:
        lines.append({"account": chart.GST_INPUT, "debit": invoice.tax})
    lines.append({"account": chart.ACCOUNTS_PAYABLE, "credit": invoice.total})

    return post_entry(
        entry_date=invoice.invoice_date,
        narration=f"Purchase invoice {invoice.invoice_number} — {invoice.supplier.name}",
        reference=invoice.invoice_number,
        source_module="purchase_invoice", source_ref=invoice.id,
        store=invoice.store,
        lines=lines,
    )


@_safe
def post_vendor_payment(payment):
    """We paid a supplier: payable down, cash/bank down."""
    from inventory.models import VendorPayment

    source = (
        chart.CASH_ON_HAND if payment.method == VendorPayment.Method.CASH
        else chart.BANK
    )
    return post_entry(
        entry_date=payment.paid_on,
        narration=f"Paid {payment.invoice.supplier.name} "
                  f"against {payment.invoice.invoice_number}",
        reference=payment.reference or str(payment.id),
        source_module="vendor_payment", source_ref=payment.id,
        store=payment.invoice.store,
        lines=[
            {"account": chart.ACCOUNTS_PAYABLE, "debit": payment.amount},
            {"account": source, "credit": payment.amount},
        ],
    )
