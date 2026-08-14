"""Manual reconciliation of payments the gateway could not settle for us.

A payment reaches `RECONCILIATION_REQUIRED` only after every automated path has run
and failed to establish what the provider did. At that point the answer exists — in
the provider's dashboard — and the system's job is to let an authorised human record
it, not to guess.

Two deliberate absences:

* **There is no "Mark Paid".** The action is `confirm_captured`, and it demands the
  captured amount plus an explicit attestation that the operator has seen the capture
  at the provider. A one-click way to clear the queue is a one-click way to make
  unresolved money look settled.
* **Nothing here writes `Payment.status = SUCCESS`.** Every settlement goes through
  `finalize_payment`, which owns once-only finalisation, the order's payment state,
  invoice/receipt issuance, and the refusal to settle a short capture. Bypassing it
  to "just update the status" is how those guarantees get lost.

Both actions are idempotent. The sweep runs every ~10 minutes while an operator may
be looking at the same row, so whoever settles first wins and the other side reports
the state instead of creating a second settlement.
"""
import logging
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.utils import timezone

from core.app_errors import AppError

from .models import Payment
from .services import finalize_payment, refund_payment

logger = logging.getLogger(__name__)


def _reconcile_refund_key(payment):
    """Stable per payment, so repeated confirmations cannot raise a second refund."""
    return f"reconcile-refund:{payment.pk}"


def _already_final(payment):
    return payment.status in (
        Payment.Status.SUCCESS, Payment.Status.FAILED, Payment.Status.REFUNDED,
    )


def _require_resolver(by):
    if by is None:
        raise AppError(
            "PAYMENT_RESOLVER_REQUIRED",
            message="A manual reconciliation must record who made the decision.",
        )


def _require_under_review(payment):
    if payment.status != Payment.Status.RECONCILIATION_REQUIRED:
        raise AppError(
            "PAYMENT_NOT_UNDER_REVIEW",
            message="This payment is not awaiting manual reconciliation.",
        )


def payments_needing_reconciliation(*, limit=200):
    """Payments a human has to decide about, oldest exposure first."""
    return (
        Payment.objects.filter(status=Payment.Status.RECONCILIATION_REQUIRED)
        .select_related("order", "user")
        .order_by("created_at")[:limit]
    )


@transaction.atomic
def confirm_captured(payment, *, captured_amount, by, attested=False,
                     gateway_payment_id="", reason=""):
    """Record that an administrator VERIFIED this capture at the provider.

    Returns `(payment, applied)`. `applied` is False when the payment was already
    final — the scheduler settling it first is a normal race, not an error, and must
    never produce a second settlement.

    A short capture raises `PAYMENT_AMOUNT_MISMATCH` from `finalize_payment` and
    rolls the whole block back, so a part-captured payment cannot be recorded as
    settled by this path any more than by the automatic one.
    """
    from accounts.services import record_audit

    payment = Payment.objects.select_for_update().get(pk=payment.pk)
    _require_resolver(by)
    if not attested:
        raise AppError(
            "PAYMENT_ATTESTATION_REQUIRED",
            message=("Confirm you have verified this capture in the payment "
                     "provider's dashboard."),
        )
    if _already_final(payment):
        return payment, False
    _require_under_review(payment)

    if captured_amount is None or str(captured_amount).strip() == "":
        raise AppError(
            "PAYMENT_CAPTURED_AMOUNT_REQUIRED",
            message="Enter the amount the provider actually captured.",
        )
    try:
        captured = Decimal(str(captured_amount))
    except (InvalidOperation, TypeError, ValueError):
        raise AppError(
            "PAYMENT_CAPTURED_AMOUNT_REQUIRED",
            message="Enter the amount the provider actually captured.",
        ) from None

    previous = payment.status
    order = payment.order
    was_cancelled = bool(order and order.status == "cancelled")

    # Back to PENDING purely so `finalize_payment` sees a settleable row; it remains
    # the only code that decides whether this becomes SUCCESS.
    payment.status = Payment.Status.PENDING
    payment.save(update_fields=["status", "updated_at"])
    # finalize_payment writes THE settlement event; the actor, the pre-transition
    # status and the captured amount ride along on it so there is exactly one
    # record of this settlement rather than two.
    payment = finalize_payment(
        payment, success=True,
        gateway_payment_id=gateway_payment_id or payment.gateway_payment_id,
        settled_amount=captured, by=by, previous_status=previous,
        reason=f"Confirmed captured by admin. {reason}"[:200],
    )

    payment.resolved_by = by
    payment.resolved_at = timezone.now()
    payment.reconcile_note = (reason or "verified captured at provider")[:200]
    payment.save(update_fields=[
        "resolved_by", "resolved_at", "reconcile_note", "updated_at",
    ])
    record_audit(
        by, "payment.confirm_captured", target=payment,
        before={"status": previous, "attempts": payment.reconcile_attempts},
        after={
            "status": payment.status,
            "capturedAmount": str(captured),
            "orderCode": getattr(order, "code", None),
            "orderStatus": getattr(order, "status", None),
            "gatewayPaymentId": gateway_payment_id,
            "reason": reason,
        },
    )

    # A capture against a CANCELLED order is money held for goods never delivered.
    # It is recorded as captured first — the ledger must show what actually
    # happened — and then reversed through the existing refund path, so the trail
    # preserves capture, refund and the net position instead of pretending a
    # cancelled order was simply "paid".
    if was_cancelled:
        try:
            refund_payment(
                order, payment.amount, by=by,
                reason=f"Cancelled order - captured payment reversed. {reason}"[:180],
                idempotency_key=_reconcile_refund_key(payment),
            )
        except Exception:  # noqa: BLE001 — the capture stands either way
            logger.exception(
                "Refund after reconcile-capture failed for payment %s", payment.pk)
    return payment, True


@transaction.atomic
def confirm_not_captured(payment, *, by, reason=""):
    """Record that the provider has NO capture for this payment.

    Marks it failed through `finalize_payment`, which lifts the in-flight guard so
    the normal expiry path can release the order's stock. For use only when the
    provider's own record shows nothing was taken — never as a way to clear a row
    nobody could resolve.
    """
    from accounts.services import record_audit

    payment = Payment.objects.select_for_update().get(pk=payment.pk)
    _require_resolver(by)
    if _already_final(payment):
        return payment, False
    _require_under_review(payment)

    previous = payment.status
    payment.status = Payment.Status.PENDING
    payment.save(update_fields=["status", "updated_at"])
    payment = finalize_payment(
        payment, success=False, by=by, previous_status=previous,
        reason=f"Confirmed NOT captured by admin. {reason}"[:200],
    )

    payment.resolved_by = by
    payment.resolved_at = timezone.now()
    payment.reconcile_note = (reason or "provider has no capture")[:200]
    payment.save(update_fields=[
        "resolved_by", "resolved_at", "reconcile_note", "updated_at",
    ])
    record_audit(
        by, "payment.confirm_not_captured", target=payment,
        before={"status": previous},
        after={"status": payment.status,
               "orderCode": getattr(payment.order, "code", None),
               "reason": reason},
    )
    return payment, True
