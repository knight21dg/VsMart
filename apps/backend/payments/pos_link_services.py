"""Counter payments: charging a customer's UPI/card from the POS.

The POS has no card terminal. `POSPayment.Method.UPI/CARD` existed, but only as
*tender types* — the cashier typed a reference and the sale was marked paid on
their word alone. Nothing verified that money had actually moved, so a mistyped
reference or a plain mistake booked an unpaid sale as paid.

This routes those tenders through Razorpay Payment Links: the cashier raises a
link (shown as a QR or texted), the customer pays from their own phone, and the
POS polls until **Razorpay** confirms it. The gateway is the authority on
whether the sale was paid.
"""
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from accounts.services import record_audit
from core.app_errors import AppError

from .gateway import get_gateway
from .models import Payment, PaymentEvent

ZERO = Decimal("0.00")

#: Link states Razorpay reports once money has actually been captured.
PAID_STATES = ("paid",)
#: Terminal states where no money will arrive.
DEAD_STATES = ("cancelled", "expired")


@transaction.atomic
def create_counter_link(*, amount, store, cashier, customer=None, note=""):
    """Raise a payment link for an over-the-counter sale.

    Returns the local :class:`Payment` (status ``pending``) plus the link the
    cashier should show. The Payment row exists from the start so an abandoned
    link is still visible in the ledger rather than vanishing.
    """
    amount = Decimal(str(amount or 0))
    if amount <= ZERO:
        raise AppError("VALIDATION_ERROR",
                       message="A counter payment must be greater than zero.")

    payment = Payment.objects.create(
        user=customer or cashier,
        purpose=Payment.Purpose.ORDER,
        amount=amount,
        method=Payment.Method.UPI,
        gateway=Payment.Gateway.RAZORPAY,
        status=Payment.Status.PENDING,
    )

    gateway = get_gateway()
    link = gateway.create_payment_link(
        amount,
        reference=f"POS-{payment.id}",
        description=note or "VS Mart counter sale",
        customer_phone=getattr(customer, "phone", "") or "",
        customer_name=getattr(customer, "name", "") or "",
    )

    payment.gateway_order_id = link.get("link_id", "")
    payment.save(update_fields=["gateway_order_id"])
    PaymentEvent.objects.create(
        payment=payment, status=Payment.Status.PENDING,
        note="Counter payment link raised",
        gateway_ref=payment.gateway_order_id, created_by=cashier,
    )
    record_audit(cashier, "pos.payment_link.create", target=payment,
                 after={"amount": str(amount), "link": payment.gateway_order_id})

    # A mock gateway in a trusted (dev/CI) environment settles immediately so the
    # keyless flow is exercisable end to end.
    if link.get("status") in PAID_STATES:
        _settle(payment, gateway_payment_id="", by=cashier)

    return payment, link


@transaction.atomic
def poll_counter_link(payment, *, by=None):
    """Ask the gateway whether this link has been paid, and settle if so.

    Idempotent: an already-settled payment short-circuits, so double-polling
    can't double-book.
    """
    if payment.status == Payment.Status.SUCCESS:
        return payment
    if not payment.gateway_order_id:
        raise AppError("VALIDATION_ERROR",
                       message="This payment has no gateway link to check.")

    state = get_gateway().fetch_payment_link(payment.gateway_order_id)
    status = state.get("status", "")

    if status in PAID_STATES:
        _settle(payment, gateway_payment_id=state.get("payment_id", ""), by=by)
    elif status in DEAD_STATES and payment.status != Payment.Status.FAILED:
        payment.status = Payment.Status.FAILED
        payment.save(update_fields=["status", "updated_at"])
        PaymentEvent.objects.create(
            payment=payment, status=Payment.Status.FAILED,
            note=f"Payment link {status}", created_by=by,
        )
    return payment


def _settle(payment, *, gateway_payment_id, by=None):
    """Mark a counter payment captured. Only ever called off a gateway verdict."""
    payment.status = Payment.Status.SUCCESS
    if gateway_payment_id:
        payment.gateway_payment_id = gateway_payment_id
    payment.save(update_fields=["status", "gateway_payment_id", "updated_at"])
    PaymentEvent.objects.create(
        payment=payment, status=Payment.Status.SUCCESS,
        note="Counter payment captured",
        gateway_ref=gateway_payment_id or payment.gateway_order_id,
        created_by=by,
    )
    # Book it. Fail-soft: bookkeeping must never undo a captured payment.
    from accounting.posting import post_payment

    post_payment(payment)
    return payment


def link_payload(payment, link=None):
    """What the POS needs to render the QR and keep polling."""
    return {
        "paymentId": str(payment.id),
        "amount": payment.amount,
        "status": payment.status,
        "linkId": payment.gateway_order_id,
        "shortUrl": (link or {}).get("short_url", ""),
        "gatewayPaymentId": payment.gateway_payment_id,
        "createdAt": payment.created_at or timezone.now(),
    }
