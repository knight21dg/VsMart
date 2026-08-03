"""Cash book — the chain from a customer's cash to the bank.

    customer pays agent  →  CashCollection (collected)
                         →  CashDeposit    (agent hands it over)
                         →  verified       (finance counts it)

Before this only the first step was recorded. Cash was collected and the credit
ledger repaid, but nothing tracked the physical notes afterwards, so there was
no way to answer "how much cash is sitting with agents right now?" or "did what
we collected on Tuesday actually reach the bank?".

Every state change here writes an audit row, so the whole chain is reviewable
after the fact.
"""
from decimal import Decimal

from django.core.exceptions import ObjectDoesNotExist
from django.db import transaction
from django.db.models import Count, Sum
from django.utils import timezone

from accounts.services import record_audit
from core.app_errors import AppError

from .gateway import get_gateway
from .models import CashCollection, CashDeposit

ZERO = Decimal("0.00")

#: Collections whose money is genuinely in hand and therefore bankable.
BANKABLE_STATUSES = (
    CashCollection.Status.COLLECTED,
    CashCollection.Status.PARTIALLY_COLLECTED,
)


def undeposited_collections(agent=None, store=None):
    """Collections whose cash the agent is still holding.

    ``store`` scopes to the agents THAT STORE OWNS (agents are store-owned, per
    ``AgentProfile.store``) — the Store panel's own cash-collection page, so a
    store only ever sees cash its own riders are holding, never another
    store's.
    """
    qs = CashCollection.objects.filter(
        status__in=BANKABLE_STATUSES,
        deposit__isnull=True,
        collected_amount__gt=0,
        # Money paid at the store counter is already banked with the store —
        # counting it here inflated cash-in-hand with notes no agent is holding.
        collected_at_store=False,
    ).exclude(agent__isnull=True).select_related("agent", "user")
    if agent is not None:
        qs = qs.filter(agent=agent)
    if store is not None:
        qs = qs.filter(agent__agent_profile__store=store)
    return qs.order_by("collected_at", "id")


def cash_in_hand(agent=None, store=None):
    """How much collected cash has NOT yet been deposited, per agent.

    This is the number that tells you your exposure to cash sitting in the
    field. It was previously unknowable. ``store`` scopes it to one store's own
    agents (the Store panel's cash-collection page), matching the customer-side
    ``store=`` filter ``undeposited_collections`` already supports.
    """
    rows = (
        undeposited_collections(agent=agent, store=store)
        .values("agent_id", "agent__name", "agent__phone")
        .annotate(amount=Sum("collected_amount"), count=Count("id"))
        .order_by("-amount")
    )
    return [
        {
            "agentId": str(r["agent_id"]) if r["agent_id"] else None,
            "agent": r["agent__name"] or "Unassigned",
            "phone": r["agent__phone"] or "",
            "amount": r["amount"] or ZERO,
            "collections": r["count"],
        }
        for r in rows
    ]


def agent_store(agent):
    """The store that manages this agent — the destination for a hand-over.

    Agents are store-owned (``AgentProfile.store``), so an online transfer has an
    unambiguous recipient without the agent choosing one. Returns None for a
    legacy/unassigned agent; the online path treats that as a hard error, while
    physical cash can still be handed over in person.
    """
    # agent_profile is a reverse OneToOne: accessing it raises when absent, so
    # getattr's default won't catch it — guard explicitly.
    try:
        profile = agent.agent_profile
    except ObjectDoesNotExist:
        return None
    return profile.store


def _claim_collections(agent, collection_ids, deposit):
    """Attach the named collections to ``deposit``, exclusively.

    select_for_update so two concurrent hand-overs can't claim the same
    collection and double-count the cash. Raises if any id isn't a bankable,
    still-in-hand collection belonging to this agent.
    """
    if not collection_ids:
        return
    claimed = (
        CashCollection.objects.select_for_update()
        .filter(id__in=collection_ids, agent=agent,
                status__in=BANKABLE_STATUSES, deposit__isnull=True)
    )
    ids = list(claimed.values_list("id", flat=True))
    if len(ids) != len(set(collection_ids)):
        raise AppError(
            "DEPOSIT_COLLECTION_CONFLICT",
            message="Some of those collections are already deposited or "
                    "don't belong to this agent.",
        )
    CashCollection.objects.filter(id__in=ids).update(deposit=deposit)


@transaction.atomic
def create_deposit(agent, *, amount, method, deposited_on=None, reference="",
                   collection_ids=None, notes="", slip_key="", store=None,
                   actor=None):
    """Record an agent handing PHYSICAL cash over.

    The named collections are attached to this deposit so each one can only ever
    be banked once — that link is what stops the same cash being counted twice
    across two deposits.
    """
    amount = Decimal(str(amount or 0))
    if amount <= ZERO:
        raise AppError("VALIDATION_ERROR",
                       message="A deposit must be greater than zero.")

    deposit = CashDeposit.objects.create(
        agent=agent,
        store=store or agent_store(agent),
        amount=amount,
        method=method or CashDeposit.Method.BANK,
        deposited_on=deposited_on or timezone.localdate(),
        reference=reference or "",
        slip_key=slip_key or "",
        notes=notes or "",
    )
    _claim_collections(agent, collection_ids, deposit)

    record_audit(actor or agent, "cash.deposit.create", target=deposit,
                 after={"amount": str(amount), "method": deposit.method,
                        "collections": len(collection_ids or [])})
    return deposit


@transaction.atomic
def start_online_handover(agent, *, collection_ids, actor=None):
    """Begin an online hand-over: raise a Razorpay link for the selected cash.

    The money flows agent → store digitally. Unlike physical cash there is no
    count step — the gateway confirming the payment IS the proof it arrived, so a
    confirmed online hand-over settles straight to VERIFIED.

    The deposit is created up front in INITIATED state with the collections
    already reserved onto it, so the same cash can't be handed over twice (in
    person or online) while the link is unpaid. If the link is never paid,
    :func:`confirm_online_handover` releases the reservation.
    """
    store = agent_store(agent)
    if store is None:
        raise AppError("CASH_HANDOVER_STORE_MISSING")

    ids = list(dict.fromkeys(collection_ids or []))  # de-dup, keep order
    if not ids:
        raise AppError("VALIDATION_ERROR",
                       message="Select at least one collection to hand over.")

    # Compute the amount from the rows themselves, then reserve them — never from
    # a client-supplied figure, so the link can only ever be for real held cash.
    held = (
        CashCollection.objects.select_for_update()
        .filter(id__in=ids, agent=agent,
                status__in=BANKABLE_STATUSES, deposit__isnull=True)
    )
    rows = list(held)
    if len(rows) != len(ids):
        raise AppError(
            "DEPOSIT_COLLECTION_CONFLICT",
            message="Some of those collections are already deposited or "
                    "don't belong to this agent.",
        )
    amount = sum((r.collected_amount for r in rows), ZERO)
    if amount <= ZERO:
        raise AppError("VALIDATION_ERROR",
                       message="There's no cash to hand over on those items.")

    from .models import Payment

    payment = Payment.objects.create(
        user=agent,
        purpose=Payment.Purpose.HANDOVER,
        amount=amount,
        method=Payment.Method.UPI,
        gateway=Payment.Gateway.RAZORPAY,
        status=Payment.Status.PENDING,
    )
    deposit = CashDeposit.objects.create(
        agent=agent,
        store=store,
        amount=amount,
        method=CashDeposit.Method.UPI,
        deposited_on=timezone.localdate(),
        status=CashDeposit.Status.INITIATED,
        payment=payment,
    )
    CashCollection.objects.filter(id__in=[r.id for r in rows]).update(deposit=deposit)

    gateway = get_gateway()
    link = gateway.create_payment_link(
        amount,
        reference=f"HANDOVER-{deposit.id}",
        description=f"Cash hand-over to {getattr(store, 'name', 'store')}",
        customer_phone=getattr(agent, "phone", "") or "",
        customer_name=getattr(agent, "name", "") or "",
    )
    payment.gateway_order_id = link.get("link_id", "")
    payment.save(update_fields=["gateway_order_id"])

    record_audit(actor or agent, "cash.handover.online.start", target=deposit,
                 after={"amount": str(amount), "collections": len(rows),
                        "link": payment.gateway_order_id})

    # A trusted mock (dev/CI) reports the link already paid so the flow is
    # exercisable end to end without live keys.
    if link.get("status") in ("paid",):
        confirm_online_handover(deposit, by=actor or agent)
        deposit.refresh_from_db()
    return deposit, payment, link


@transaction.atomic
def cancel_online_handover(deposit, *, by=None):
    """The AGENT abandons an unpaid online hand-over: cancel the gateway link
    (best-effort) and put the cash straight back in their hands.

    Before this, backing out of the payment left the deposit INITIATED with the
    collections reserved onto it — the money looked neither in-hand nor handed
    over until someone tapped "I've paid" against a dead link. Cancelling is an
    explicit, immediate act now. Idempotent; only an awaiting-payment hand-over
    can be cancelled.
    """
    if deposit.status == CashDeposit.Status.CANCELLED:
        return deposit
    if deposit.status != CashDeposit.Status.INITIATED:
        raise AppError("INVALID_DEPOSIT_TRANSITION",
                       message="This hand-over is no longer awaiting payment.")

    payment = deposit.payment
    if payment is not None and payment.gateway_order_id:
        try:  # best-effort: a link that won't cancel still gets released locally
            get_gateway().cancel_payment_link(payment.gateway_order_id)
        except Exception:  # noqa: BLE001
            pass
    if payment is not None and payment.status != payment.Status.FAILED:
        payment.status = payment.Status.FAILED
        payment.save(update_fields=["status", "updated_at"])

    deposit.collections.update(deposit=None)  # cash back in the agent's hands
    deposit.status = CashDeposit.Status.CANCELLED
    deposit.save(update_fields=["status", "updated_at"])
    record_audit(by or deposit.agent, "cash.handover.online.cancelled",
                 target=deposit, after={"reason": "agent_cancelled"})
    return deposit


def confirm_online_handover(deposit, *, by=None):
    """Ask the gateway whether the hand-over link is paid, and settle if so.

    Idempotent: an already-settled hand-over short-circuits, so double-tapping
    "I've paid" can't double-book. On a dead link the reservation is released so
    the cash correctly shows as still in the agent's hands.
    """
    if deposit.status == CashDeposit.Status.VERIFIED:
        return deposit
    if deposit.status != CashDeposit.Status.INITIATED:
        raise AppError("INVALID_DEPOSIT_TRANSITION",
                       message="This hand-over is no longer awaiting payment.")

    payment = deposit.payment
    if payment is None or not payment.gateway_order_id:
        raise AppError("VALIDATION_ERROR",
                       message="This hand-over has no payment link to check.")

    state = get_gateway().fetch_payment_link(payment.gateway_order_id)
    status = state.get("status", "")

    if status in ("paid",):
        gateway_payment_id = state.get("payment_id", "")
        payment.status = payment.Status.SUCCESS
        if gateway_payment_id:
            payment.gateway_payment_id = gateway_payment_id
        payment.save(update_fields=["status", "gateway_payment_id", "updated_at"])

        # The gateway is the authority that the money moved, so an online
        # hand-over is verified on confirmation — there is nothing to count.
        deposit.reference = gateway_payment_id or payment.gateway_order_id
        deposit.verified_amount = deposit.amount
        deposit.verified_at = timezone.now()
        deposit.status = CashDeposit.Status.VERIFIED
        deposit.save(update_fields=["reference", "verified_amount", "verified_at",
                                    "status", "updated_at"])
        record_audit(by or deposit.agent, "cash.handover.online.confirmed",
                     target=deposit, after={"amount": str(deposit.amount),
                                            "ref": deposit.reference})
        from accounting.posting import post_cash_deposit

        post_cash_deposit(deposit)
        return deposit

    if status in ("cancelled", "expired"):
        deposit.collections.update(deposit=None)  # release the reservation
        deposit.status = CashDeposit.Status.CANCELLED
        deposit.save(update_fields=["status", "updated_at"])
        if payment.status != payment.Status.FAILED:
            payment.status = payment.Status.FAILED
            payment.save(update_fields=["status", "updated_at"])
        record_audit(by or deposit.agent, "cash.handover.online.cancelled",
                     target=deposit, after={"reason": status})
        # Deliberately NOT raising here: this function is @atomic, so raising
        # would roll back the CANCELLED status and the release we just did. The
        # caller inspects the returned status and signals CASH_ONLINE_FAILED.
        return deposit

    return deposit  # still pending — caller polls again


# Give a payment link a fair window before sweeping it — Razorpay links can take
# a few minutes to settle, and this must never race an agent mid-payment.
STALE_HANDOVER_MIN = 30


def sweep_stale_handovers(*, older_than_minutes=STALE_HANDOVER_MIN, limit=200):
    """Resolve online hand-overs nobody ever came back to confirm.

    `confirm_online_handover` is normally agent-triggered — they tap "I've
    paid", or the app silently re-checks when they resume it after paying.
    But if an agent closes the app (or the payment failed for a reason that
    never sends them back — no network, insufficient balance, they just gave
    up) without ever returning to that screen, the deposit sits INITIATED
    forever: not in-hand, not banked, invisible to everyone until someone
    notices. (The generic `reconcile_payments` sweep doesn't cover this — it
    queries Razorpay's Orders API, but a hand-over raises a Payment *Link*,
    a different Razorpay object with its own status endpoint.)

    Reuses `confirm_online_handover` itself for every stale row — same
    gateway truth-check, so this can only settle a deposit that's actually
    paid or cancel one that's actually dead; it never guesses from age alone.
    """
    cutoff = timezone.now() - timezone.timedelta(minutes=older_than_minutes)
    stale = (
        CashDeposit.objects.filter(
            status=CashDeposit.Status.INITIATED, created_at__lt=cutoff,
        )
        .select_related("payment")
        .order_by("created_at")[:limit]
    )
    summary = {"checked": 0, "verified": 0, "cancelled": 0, "errors": 0}
    for deposit in stale:
        summary["checked"] += 1
        try:
            resolved = confirm_online_handover(deposit)
        except Exception:  # noqa: BLE001 — one bad row must not stop the sweep
            summary["errors"] += 1
            continue
        if resolved.status == CashDeposit.Status.VERIFIED:
            summary["verified"] += 1
        elif resolved.status == CashDeposit.Status.CANCELLED:
            summary["cancelled"] += 1
    return summary


@transaction.atomic
def verify_deposit(deposit, verifier, *, counted_amount=None, notes=""):
    """Finance counts a deposit.

    A shortfall is recorded as its own status rather than quietly adjusting the
    amount, so the difference stays visible and attributable to an agent.
    """
    if deposit.status != CashDeposit.Status.PENDING:
        raise AppError("INVALID_DEPOSIT_TRANSITION",
                       message="This deposit has already been reviewed.")

    counted = (
        Decimal(str(counted_amount)) if counted_amount is not None else deposit.amount
    )
    if counted < ZERO:
        raise AppError("VALIDATION_ERROR",
                       message="A counted amount can't be negative.")

    deposit.verified_amount = counted
    deposit.verified_by = verifier
    deposit.verified_at = timezone.now()
    deposit.notes = (notes or deposit.notes)[:300]
    deposit.status = (
        CashDeposit.Status.VERIFIED if counted >= deposit.amount
        else CashDeposit.Status.SHORT
    )
    deposit.save(update_fields=[
        "verified_amount", "verified_by", "verified_at", "status", "notes",
        "updated_at",
    ])
    record_audit(verifier, f"cash.deposit.{deposit.status}", target=deposit,
                 after={"declared": str(deposit.amount),
                        "counted": str(counted),
                        "shortfall": str(deposit.shortfall)})
    # Book it: cash leaves the agent, lands in bank/cash, any shortfall becomes
    # an expense. Fail-soft — bookkeeping must never undo a counted deposit.
    from accounting.posting import post_cash_deposit

    post_cash_deposit(deposit)
    # The agent only used to find out about a shortfall by reopening the app
    # and pulling to refresh. Fail-soft — a stuck push must never undo a
    # deposit that's already been counted and booked.
    try:
        from notifications.services import notify

        if deposit.status == CashDeposit.Status.SHORT:
            notify(deposit.agent, type="cash",
                  title="Deposit short",
                  body=f"₹{deposit.shortfall} short on your ₹{deposit.amount} deposit.",
                  data={"depositId": str(deposit.id)})
        else:
            notify(deposit.agent, type="cash",
                  title="Deposit counted in",
                  body=f"Your ₹{deposit.amount} deposit was verified.",
                  data={"depositId": str(deposit.id)})
    except Exception:  # noqa: BLE001
        pass
    return deposit


@transaction.atomic
def reject_deposit(deposit, verifier, *, reason):
    """Reject a declared deposit (e.g. the money never arrived).

    The attached collections are released back to 'undeposited' so the cash is
    correctly shown as still outstanding with the agent, rather than vanishing.
    """
    if deposit.status != CashDeposit.Status.PENDING:
        raise AppError("INVALID_DEPOSIT_TRANSITION",
                       message="This deposit has already been reviewed.")
    if not (reason or "").strip():
        raise AppError("VALIDATION_ERROR",
                       message="A reason is required to reject a deposit.")

    deposit.collections.update(deposit=None)
    deposit.status = CashDeposit.Status.REJECTED
    deposit.verified_by = verifier
    deposit.verified_at = timezone.now()
    deposit.notes = reason.strip()[:300]
    deposit.save(update_fields=["status", "verified_by", "verified_at", "notes",
                                "updated_at"])
    record_audit(verifier, "cash.deposit.rejected", target=deposit,
                 after={"reason": deposit.notes})
    try:
        from notifications.services import notify

        notify(deposit.agent, type="cash", title="Deposit rejected",
              body=f"Your ₹{deposit.amount} deposit was rejected: {deposit.notes}",
              data={"depositId": str(deposit.id)})
    except Exception:  # noqa: BLE001
        pass
    return deposit


def reconciliation(date_from=None, date_to=None, agent=None, store=None):
    """The cash book summary: collected vs deposited vs verified vs in hand.

    Every figure is derived from the same rows the detail lists show, so the
    summary and the lists can never disagree.
    """
    collections = CashCollection.objects.filter(status__in=BANKABLE_STATUSES)
    deposits = CashDeposit.objects.all()

    if agent is not None:
        collections = collections.filter(agent=agent)
        deposits = deposits.filter(agent=agent)
    if store is not None:
        collections = collections.filter(agent__agent_profile__store=store)
        deposits = deposits.filter(store=store)
    if date_from:
        collections = collections.filter(collected_at__date__gte=date_from)
        deposits = deposits.filter(deposited_on__gte=date_from)
    if date_to:
        collections = collections.filter(collected_at__date__lte=date_to)
        deposits = deposits.filter(deposited_on__lte=date_to)

    collected = collections.aggregate(s=Sum("collected_amount"))["s"] or ZERO
    # Only real hand-overs count as declared. An INITIATED online link (money not
    # yet arrived) or a CANCELLED/REJECTED one must not inflate the figure.
    declared = deposits.filter(
        status__in=CashDeposit.LIVE_STATUSES
    ).aggregate(s=Sum("amount"))["s"] or ZERO
    verified = deposits.filter(
        status__in=[CashDeposit.Status.VERIFIED, CashDeposit.Status.SHORT]
    ).aggregate(s=Sum("verified_amount"))["s"] or ZERO
    pending_count = deposits.filter(status=CashDeposit.Status.PENDING).count()

    # Shortfalls are summed per row: max(declared - counted, 0) can't be done
    # in one aggregate without going negative on over-counts.
    shortfall = sum(
        (d.shortfall for d in deposits.filter(status=CashDeposit.Status.SHORT)),
        ZERO,
    )
    in_hand_rows = cash_in_hand(agent=agent, store=store)
    in_hand = sum((r["amount"] for r in in_hand_rows), ZERO)

    return {
        "collected": collected,
        "declared": declared,
        "verified": verified,
        "shortfall": shortfall,
        "inHand": in_hand,
        "pendingDeposits": pending_count,
        "byAgent": in_hand_rows,
    }
