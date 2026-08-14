import logging
from decimal import Decimal

from django.db import IntegrityError, transaction
from django.utils import timezone

from core.app_errors import AppError
from credit.services import apply_repayment, ensure_account

from .gateway import get_gateway
from .models import CashCollection, Payment, PaymentEvent

logger = logging.getLogger(__name__)


def log_payment_event(payment, status, *, note="", gateway_ref="", by=None,
                      previous_status="", amount=None):
    """Append a status transition to the payment's audit trail. Best-effort — a
    logging failure must never break the money operation itself."""
    try:
        PaymentEvent.objects.create(
            payment=payment, status=status, note=note,
            gateway_ref=gateway_ref, created_by=by,
            previous_status=previous_status or "", amount=amount,
        )
    except Exception:
        pass


def start_payment(user, *, purpose, amount, method, order=None, statement=None,
                  idempotency_key="") -> Payment:
    """Create a payment and (for gateway methods) a gateway order. Idempotent on
    idempotency_key — a repeat returns the existing payment."""
    amount = Decimal(amount)
    if idempotency_key:
        existing = Payment.objects.filter(
            user=user, idempotency_key=idempotency_key
        ).first()
        if existing:
            return existing

    gateway = get_gateway()
    try:
        payment = Payment.objects.create(
            user=user, purpose=purpose, amount=amount, method=method,
            order=order, statement=statement, gateway=gateway.name,
            status=Payment.Status.PENDING, idempotency_key=idempotency_key,
        )
    except IntegrityError:
        # A concurrent same-key start won the race; the unique constraint rejected
        # this one. Return the payment that landed so the user has exactly one.
        if idempotency_key:
            existing = Payment.objects.filter(
                user=user, idempotency_key=idempotency_key
            ).first()
            if existing:
                return existing
        raise
    log_payment_event(payment, Payment.Status.PENDING, note=f"Initiated ({purpose})")
    if method != Payment.Method.CASH:
        info = gateway.create_order(amount, receipt=f"pay_{payment.id}")
        payment.gateway_order_id = info["gateway_order_id"]
        payment.save(update_fields=["gateway_order_id"])
        # Dev convenience: with the mock gateway there's no hosted page/webhook, so
        # auto-settle non-cash payments immediately. Prod (real Razorpay) waits for
        # the signed webhook. Idempotent — the later webhook is a no-op.
        from django.conf import settings

        if settings.DEBUG and gateway.name in ("mock", "manual"):
            finalize_payment(payment, success=True,
                             gateway_payment_id=f"dev_{payment.id}")
    return payment


@transaction.atomic
def finalize_payment(payment: Payment, *, success=True, gateway_payment_id="",
                     settled_amount=None, by=None, previous_status=None,
                     reason="") -> Payment:
    """Settle a payment exactly once. Order payments mark the order paid; repayments
    post a repayment to the credit ledger.

    ``settled_amount`` is what the GATEWAY says it actually captured. When supplied
    it must equal ``payment.amount`` — a short capture must never mark an order
    fully paid. Callers that genuinely have no amount (the dev auto-settle) may
    omit it, but every real gateway event carries one.
    """
    payment = Payment.objects.select_for_update().get(pk=payment.pk)
    if payment.status == Payment.Status.SUCCESS:
        return payment  # already settled (idempotent)
    # `by` / `previous_status` / `reason` let a caller enrich the ONE settlement
    # event this writes, rather than appending a second one beside it. A manual
    # reconciliation needs the actor and the pre-transition status on the record;
    # two SUCCESS events for one settlement would be its own kind of lie.
    was = previous_status or payment.status
    if not success:
        payment.status = Payment.Status.FAILED
        payment.save(update_fields=["status"])
        log_payment_event(
            payment, Payment.Status.FAILED, by=by, previous_status=was,
            note=reason or "Gateway reported failure")
        return payment

    if settled_amount is not None and Decimal(settled_amount) != payment.amount:
        # Refuse to settle rather than credit an order for less than it costs.
        # Left PENDING on purpose: the money is real and needs a human to reconcile
        # or refund it, which a FAILED row would hide.
        log_payment_event(
            payment, payment.status,
            note=(f"Amount mismatch: gateway settled {settled_amount}, "
                  f"expected {payment.amount}"),
            gateway_ref=gateway_payment_id,
        )
        raise AppError("PAYMENT_AMOUNT_MISMATCH")

    payment.status = Payment.Status.SUCCESS
    payment.gateway_payment_id = gateway_payment_id
    payment.save(update_fields=["status", "gateway_payment_id"])
    log_payment_event(
        payment, Payment.Status.SUCCESS, by=by, previous_status=was,
        amount=Decimal(settled_amount) if settled_amount is not None else None,
        gateway_ref=gateway_payment_id, note=reason)

    if payment.purpose == Payment.Purpose.ORDER and payment.order:
        order = payment.order
        order.payment_status = order.PaymentStatus.PAID
        if order.status == "pending":
            order.status = "confirmed"
        order.save(update_fields=["payment_status", "status"])
        # Delivered first, paid later (COD cash confirm): the invoice becomes
        # issuable NOW. Fail-soft — paperwork never blocks a settlement.
        if order.status == "delivered":
            try:
                from billing.services import invoice_for_order

                invoice_for_order(order)
            except Exception:  # noqa: BLE001
                pass
    elif payment.purpose == Payment.Purpose.REPAYMENT:
        account = ensure_account(payment.user)
        apply_repayment(account, payment.amount, payment=payment,
                        note=f"Repayment via {payment.method}")
        if payment.statement:
            _apply_statement_payment(payment.statement, payment.amount)
    # Issue the receipt row (fail-soft). Like invoices, billing.Receipt had
    # readers and a numbering scheme but no producer — nothing was ever issued.
    try:
        from billing.services import receipt_for_payment

        receipt_for_payment(payment)
    except Exception:  # noqa: BLE001
        pass
    return payment


def _apply_statement_payment(statement, amount):
    """Credit ``amount`` against a statement, marking it PAID only once covered.

    This used to set ``payments = closing_balance`` and status PAID for ANY amount,
    so a ₹1 part-payment against an ₹8,000 statement fabricated a full ₹8,000
    receipt, stopped dunning, and left the statement disagreeing with the credit
    ledger by ₹7,999. Part-payments are legitimate — they just aren't settlement.
    """
    statement.payments = (statement.payments or Decimal("0")) + Decimal(amount)
    if statement.payments >= statement.closing_balance:
        statement.status = statement.Status.PAID
    statement.save(update_fields=["status", "payments"])


@transaction.atomic
def collect_cash(collection: CashCollection, agent, method="cash", reference="",
                 at_store=True) -> CashCollection:
    """Record money the customer paid the STORE directly → a repayment payment is
    created and the credit ledger gets the repayment.

    `method` is how the money came in (cash / upi / card / netbanking — defaults
    to cash for backward compatibility) and `reference` is the optional external
    receipt / UPI txn id, stored on the payment as its gateway id for audit.

    Only the OUTSTANDING balance is booked. This used to post
    ``collection.amount`` — the full original debt — and overwrite
    ``collected_amount``, so recording a store payment against a collection an
    agent had already partially recovered credited the customer twice for the
    part already paid and silently erased the agent's ₹ from the books. It also
    only short-circuited on ``COLLECTED``, so ``partially_collected`` rows were
    re-collectable in full.

    ``at_store`` marks the money as sitting at the store rather than in a field
    agent's pocket, keeping it out of cash-in-hand. The row is locked for the
    duration so two staff clicking at once can't both post a repayment.
    """
    collection = CashCollection.objects.select_for_update().get(pk=collection.pk)
    if collection.status == CashCollection.Status.COLLECTED:
        return collection
    outstanding = collection.remaining
    if outstanding <= Decimal("0"):
        return collection
    if method not in Payment.Method.values:
        method = Payment.Method.CASH
    payment = start_payment(
        collection.user, purpose=Payment.Purpose.REPAYMENT,
        amount=outstanding, method=method,
        statement=collection.statement,
    )
    finalize_payment(
        payment, success=True,
        gateway_payment_id=(reference.strip() or f"cash_{payment.id}"),
    )
    fields = ["payment", "status", "collected_amount", "collected_at",
              "collected_at_store"]
    # Money paid at the store isn't held by anyone in the field, so `.agent`
    # (which means "who owes a hand-over for these notes") stays untouched.
    if agent is not None and not at_store:
        collection.agent = agent
        fields.append("agent")
    collection.payment = payment
    collection.collected_amount = collection.collected_amount + outstanding
    collection.status = CashCollection.Status.COLLECTED
    collection.collected_at = timezone.now()
    collection.collected_at_store = bool(at_store)
    collection.save(update_fields=fields)
    return collection


#: How long a gateway payment may stay unresolved before it stops being "in flight"
#: and becomes an explicit operational task. Not a cancellation deadline — nothing is
#: cancelled and no stock is released; it only makes the row visible to a human.
RECONCILE_WINDOW_MINUTES = 180


def _reconcile_window():
    from django.conf import settings

    return int(getattr(settings, "PAYMENT_RECONCILE_WINDOW_MINUTES",
                       RECONCILE_WINDOW_MINUTES))


def _note_attempt(payment, note):
    """Record that we asked the gateway, and what it said."""
    from django.utils import timezone

    payment.reconcile_attempts = (payment.reconcile_attempts or 0) + 1
    payment.last_reconciled_at = timezone.now()
    payment.reconcile_note = note[:200]
    payment.save(update_fields=[
        "reconcile_attempts", "last_reconciled_at", "reconcile_note", "updated_at",
    ])


def _flag_for_review(payment, note):
    """Promote an unresolvable PENDING payment to RECONCILIATION_REQUIRED.

    Deliberately NOT a failure: the money may be captured. This only stops the row
    hiding in an ever-growing PENDING pile and puts it on an operator's screen.
    """
    from django.utils import timezone

    if payment.status != Payment.Status.PENDING:
        return False
    age = timezone.now() - payment.created_at
    if age < timezone.timedelta(minutes=_reconcile_window()):
        return False
    payment.status = Payment.Status.RECONCILIATION_REQUIRED
    payment.save(update_fields=["status", "updated_at"])
    log_payment_event(
        payment, Payment.Status.RECONCILIATION_REQUIRED,
        note=f"Unresolved after {int(age.total_seconds() // 60)}m: {note}"[:200],
    )
    return True


def reconcile_pending_payments(*, older_than_minutes=10, limit=200):
    """Ask the gateway what happened to payments we never heard back about.

    An online payment is settled by the app's confirm call or by the webhook. If
    the app dies after the money is captured and the webhook doesn't land, nothing
    tells us — and `release_expired_reservations` then cancels the order while the
    customer has been charged. This is the backstop: for each stale PENDING gateway
    payment, ask the gateway directly and settle (or fail) it.

    Deliberately only looks at payments older than ``older_than_minutes`` so it
    never races a checkout still in progress. Returns a summary dict.
    """
    from django.utils import timezone

    cutoff = timezone.now() - timezone.timedelta(minutes=older_than_minutes)
    stale = (
        Payment.objects.filter(
            status__in=(
                Payment.Status.PENDING,
                # Keep asking: an outage resolves, and a row that answers itself
                # should clear without anyone touching it.
                Payment.Status.RECONCILIATION_REQUIRED,
            ),
            created_at__lt=cutoff,
        )
        .exclude(gateway_order_id="")
        .exclude(method=Payment.Method.CASH)
        .order_by("created_at")[:limit]
    )

    summary = {"checked": 0, "settled": 0, "failed": 0, "unresolved": 0,
               "errors": 0, "flagged": 0}
    gateway = get_gateway()
    for payment in stale:
        summary["checked"] += 1
        try:
            info = gateway.fetch_order_payment(payment.gateway_order_id)
        except Exception as exc:  # noqa: BLE001 — one bad row must not stop the sweep
            logger.exception("Reconcile failed for payment %s", payment.pk)
            summary["errors"] += 1
            # A gateway outage must not look like a resolved payment. Record the
            # attempt; flag only once the row is genuinely old.
            _note_attempt(payment, f"gateway error: {exc}")
            summary["flagged"] += int(_flag_for_review(payment, "gateway unreachable"))
            continue
        if not info:
            summary["unresolved"] += 1
            _note_attempt(payment, "gateway returned no payment for this order")
            summary["flagged"] += int(_flag_for_review(payment, "no gateway record"))
            continue
        if info["status"] == "captured":
            try:
                finalize_payment(
                    payment, success=True,
                    gateway_payment_id=info["gateway_payment_id"],
                    settled_amount=info["amount"],
                )
                summary["settled"] += 1
            except AppError:
                # Amount mismatch — never auto-settle an order for less than it
                # costs. Flagged immediately rather than after the window: the
                # gateway HAS answered, and the answer needs a human now.
                logger.exception("Reconcile amount mismatch on payment %s", payment.pk)
                summary["errors"] += 1
                _note_attempt(
                    payment,
                    f"amount mismatch: gateway {info.get('amount')} vs {payment.amount}")
                if payment.status == Payment.Status.PENDING:
                    payment.status = Payment.Status.RECONCILIATION_REQUIRED
                    payment.save(update_fields=["status", "updated_at"])
                    log_payment_event(
                        payment, Payment.Status.RECONCILIATION_REQUIRED,
                        note="Amount mismatch — manual reconciliation required")
                    summary["flagged"] += 1
        elif info["status"] in ("failed", "cancelled"):
            finalize_payment(payment, success=False)
            summary["failed"] += 1
        else:
            # created / authorized / pending at the gateway — still in flight.
            summary["unresolved"] += 1
            _note_attempt(payment, f"gateway status: {info['status']}")
            summary["flagged"] += int(
                _flag_for_review(payment, f"gateway still {info['status']}"))
    return summary


def has_inflight_gateway_payment(order) -> bool:
    """Whether ``order`` has an online payment we haven't resolved yet.

    The expiry job must not cancel such an order: the money may already be
    captured and simply unreported.
    """
    return (
        Payment.objects.filter(
            order=order, purpose=Payment.Purpose.ORDER,
            # RECONCILIATION_REQUIRED is still unresolved money — flagging a row for
            # review must never make it eligible for auto-cancellation.
            status__in=(
                Payment.Status.PENDING,
                Payment.Status.RECONCILIATION_REQUIRED,
            ),
        )
        .exclude(gateway_order_id="")
        .exclude(method=Payment.Method.CASH)
        .exists()
    )


@transaction.atomic
def refund_payment(order, amount, *, by=None, reason="", idempotency_key=""):
    """Record an outbound refund transaction for an order and, when it was paid on
    an online instrument, reverse the money through the gateway.

    Creates a `Payment(purpose=refund)` linked to the original order payment so
    every refund has a transaction id + audit trail. For online payments it calls
    the gateway's refund API (capturing `gateway_refund_id`); for cash/COD/manual
    it records the refund without a gateway call. Idempotent on `idempotency_key`
    (e.g. a return code) so a double-approval can't double-refund. Returns the
    refund Payment, or None for a non-positive amount.

    Credit-order reversals stay in the credit ledger (returns.apply_refund) — no
    money left the customer's instrument there, so there's nothing to send back.
    """
    amount = Decimal(amount)
    if amount <= 0:
        return None
    if idempotency_key:
        existing = Payment.objects.filter(
            user=order.user, purpose=Payment.Purpose.REFUND,
            idempotency_key=idempotency_key,
        ).first()
        if existing:
            return existing

    original = (
        Payment.objects.filter(
            order=order, purpose=Payment.Purpose.ORDER, status=Payment.Status.SUCCESS
        )
        .order_by("-created_at")
        .first()
    )
    method = original.method if original else Payment.Method.CASH
    gateway_name = original.gateway if original else Payment.Gateway.MANUAL
    try:
        refund = Payment.objects.create(
            user=order.user, purpose=Payment.Purpose.REFUND, amount=amount,
            method=method, order=order, refund_of=original, gateway=gateway_name,
            status=Payment.Status.PENDING, idempotency_key=idempotency_key,
        )
    except IntegrityError:
        if idempotency_key:
            existing = Payment.objects.filter(
                user=order.user, purpose=Payment.Purpose.REFUND,
                idempotency_key=idempotency_key,
            ).first()
            if existing:
                return existing
        raise
    log_payment_event(refund, Payment.Status.PENDING,
                      note=f"Refund initiated: {reason}"[:200], by=by)

    # Only online, captured payments can be reversed through the gateway.
    gateway_refund_id = ""
    if original and original.gateway_payment_id and original.method != Payment.Method.CASH:
        try:
            res = get_gateway().refund(original.gateway_payment_id, amount)
            gateway_refund_id = res.get("refund_id", "")
        except Exception:
            # Leave the refund PENDING so it can be retried / settled manually;
            # never crash the return-approval transaction on a gateway hiccup.
            log_payment_event(refund, Payment.Status.PENDING,
                              note="Gateway refund failed; needs retry", by=by)
            return refund

    refund.gateway_refund_id = gateway_refund_id
    refund.gateway_payment_id = gateway_refund_id
    refund.status = Payment.Status.SUCCESS
    refund.save(update_fields=["gateway_refund_id", "gateway_payment_id", "status"])
    log_payment_event(refund, Payment.Status.SUCCESS, gateway_ref=gateway_refund_id,
                      note="Refund completed", by=by)

    if original and original.status == Payment.Status.SUCCESS:
        # Only flip the ORIGINAL to REFUNDED once it has been refunded in FULL.
        # Marking it refunded for any amount meant a ₹200 return against a ₹2,000
        # order dropped the whole ₹2,000 out of collected revenue in the admin
        # ledger, and left a second, legitimate return unable to find a SUCCESS
        # payment to chain from.
        from django.db.models import Sum

        refunded_total = Payment.objects.filter(
            refund_of=original, purpose=Payment.Purpose.REFUND,
            status=Payment.Status.SUCCESS,
        ).aggregate(total=Sum("amount"))["total"] or Decimal("0")
        if refunded_total >= original.amount:
            original.status = Payment.Status.REFUNDED
            original.save(update_fields=["status"])
            log_payment_event(original, Payment.Status.REFUNDED,
                              note=f"Fully refunded via payment {refund.id}", by=by)
        else:
            log_payment_event(
                original, original.status,
                note=(f"Partially refunded {refunded_total} of {original.amount} "
                      f"via payment {refund.id}"),
                by=by,
            )
    return refund
