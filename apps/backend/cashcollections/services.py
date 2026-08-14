"""Collections (debt recovery) engine — the controlled state machine and every
workflow the production spec needs:

  • auto + manual assignment of recovery tasks to field agents (workload + zone)
  • strict transitions (NO status skipping)
  • collection OTP with 3-attempt lockout → supervisor verification
  • FULL or PARTIAL cash collection → posts a cash repayment to the credit ledger,
    issues a receipt, and closes recovery when the account hits zero
  • dispute + failed-visit handling with reasons
  • dunning: aging buckets (0-30 / 31-60 / 61-90 / 90+) + escalation
  • per-agent recovery performance

Every action writes an Audit Log + an Analytics Event. Money posts atomically via
the existing payments → credit ledger path.
"""
import secrets
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from core.app_errors import AppError
from core.audit import write_audit
from core.events import record_event
from core.response_codes import CATALOG
from payments.models import CashCollection

from .models import (
    CollectionAssignmentHistory,
    CollectionAttempt,
    CollectionOTP,
    CollectionReceipt,
)

S = CashCollection.Status

#: How long a collection confirmation code stays valid. It authorises a specific
#: cash amount and is minted with the agent already at the customer, so the
#: window is short by design.
OTP_TTL_MINUTES = getattr(settings, "COLLECTION_OTP_TTL_MINUTES", 15)
ZERO = Decimal("0.00")

ALLOWED = {
    S.REQUESTED: {S.ASSIGNED, S.CANCELLED},
    S.ASSIGNED: {S.ACCEPTED, S.REQUESTED, S.CANCELLED},  # back to pool on reject
    S.ACCEPTED: {S.EN_ROUTE, S.CANCELLED},
    S.EN_ROUTE: {S.REACHED, S.FAILED},
    S.REACHED: {S.COLLECTED, S.PARTIALLY_COLLECTED, S.FAILED, S.DISPUTED},
    S.FAILED: {S.ASSIGNED, S.CANCELLED},  # reattempt / give up
    S.DISPUTED: {S.ASSIGNED, S.CANCELLED},
}

_TS = {
    S.ASSIGNED: "assigned_at", S.ACCEPTED: "accepted_at", S.EN_ROUTE: "en_route_at",
    S.REACHED: "reached_at", S.FAILED: "failed_at", S.COLLECTED: "collected_at",
}


# ───────────────────────── helpers ─────────────────────────
def _audit(code, coll, actor, *, success=True, message=""):
    spec = CATALOG.get(code, CATALOG["SYSTEM_ERROR"])
    write_audit(code, spec, actor=actor, success=success, entity_type="cash_collection",
                entity_id=coll.id if coll else "", message=message)
    record_event("collection_event",
                 {"code": code, "collection": coll.id if coll else None,
                  "status": coll.status if coll else None}, actor=actor)


def _transition(coll, to_status, *, actor=None, note="", audit_code=None):
    cur = coll.status
    if to_status != cur and to_status not in ALLOWED.get(cur, set()):
        raise AppError("INVALID_COLLECTION_TRANSITION",
                       message=f"Can't move a collection from '{cur}' to '{to_status}'.")
    coll.status = to_status
    fields = ["status", "updated_at"]
    ts = _TS.get(to_status)
    if ts and getattr(coll, ts, None) is None:
        setattr(coll, ts, timezone.now())
        fields.append(ts)
    if note:
        fields.append("failure_reason" if to_status == S.FAILED else "dispute_note")
    coll.save(update_fields=list(set(fields)))
    if audit_code:
        _audit(audit_code, coll, actor)
    return coll


def _assert_owner(coll, agent):
    if coll.agent_id != agent.id:
        raise AppError("INSUFFICIENT_PERMISSIONS",
                       message="This collection isn't assigned to you.")


# ───────────────────────── assignment ─────────────────────────
def _agent_open_load(agent):
    return CashCollection.objects.filter(agent=agent).exclude(
        status__in=CashCollection.TERMINAL).count()


def collection_store(coll):
    """The store that should service this collection — the customer's serving
    store, falling back to the store on the linked statement/order when the
    customer has no resolvable address."""
    from stores.services import resolve_user_store

    store = resolve_user_store(coll.user)
    if store is not None:
        return store
    statement = getattr(coll, "statement", None)
    return getattr(statement, "store", None) if statement is not None else None


def candidate_agents(store=None):
    """Agents eligible for a collection. Delegates to the shared, store-scoped
    pool — assignment used to consider every agent on the platform, so a
    collection raised in one town could land on an agent in another and never
    appear on the board of the store that owned it."""
    from agents.candidates import candidate_agents as _candidates

    return _candidates(store=store)


def _record_assignment(coll, agent, action, by=None, reason=""):
    CollectionAssignmentHistory.objects.create(
        collection=coll, agent=agent, action=action, by=by, reason=reason)


def auto_assign(coll, *, by=None):
    """Assign to a free agent (lowest open-collection load among them); only
    when every candidate is already working does this fall back to whoever's
    current workload (across delivery/collections/verification) will clear
    soonest — see agents.dispatch.rank_for_new_task."""
    store = collection_store(coll)
    agents = candidate_agents(store=store)
    if not agents:
        from agents.candidates import unassignable_reason

        reason = unassignable_reason(store=store)
        record_event("collection_event",
                     {"code": "AGENT_UNAVAILABLE", "collection": coll.id,
                      "reason": reason})
        _alert_store_unassigned(coll, store, reason)
        return None
    from agents.dispatch import rank_for_new_task

    free, busy_by_soonest = rank_for_new_task(agents)
    if free:
        agent = min(free, key=_agent_open_load)
    elif busy_by_soonest:
        agent = busy_by_soonest[0]
    else:
        agent = min(agents, key=_agent_open_load)
    coll.agent = agent
    coll.save(update_fields=["agent", "updated_at"])
    _transition(coll, S.ASSIGNED, actor=by, audit_code="COLLECTION_ASSIGNED")
    _record_assignment(coll, agent, "auto_assigned", by=by)
    _notify_agent(coll)
    return coll


def manual_assign(coll, agent, *, by, reason=""):
    if coll.status not in (S.REQUESTED, S.ASSIGNED, S.FAILED, S.DISPUTED):
        raise AppError("INVALID_COLLECTION_TRANSITION",
                       message="This collection can't be (re)assigned now.")
    action = "reassigned" if coll.agent_id else "manual_assigned"
    coll.agent = agent
    coll.save(update_fields=["agent", "updated_at"])
    if coll.status != S.ASSIGNED:
        _transition(coll, S.ASSIGNED, actor=by)
    _record_assignment(coll, agent, action, by=by, reason=reason)
    _audit("COLLECTION_ASSIGNED", coll, by)
    _notify_agent(coll)
    return coll


# ───────────────────────── agent workflow ─────────────────────────
def _assert_still_offered(coll, action):
    """The collection must still be sitting on this agent's offer.

    Same race as the delivery alert: the push is a snapshot, and auto-assignment
    can hand the collection to someone else before the agent taps. Without this
    the tap produced a raw transition error that the app showed as a retryable
    "try again", on a button that could never succeed.
    """
    if coll.status != S.ASSIGNED:
        raise AppError(
            "COLLECTION_TASK_REQUIRED",
            message=(
                f"This collection is no longer yours to {action} — it was "
                f"reassigned or already actioned."
            ),
            entity_type="cash_collection",
            entity_id=coll.id,
        )


def accept(coll, agent):
    _assert_owner(coll, agent)
    _assert_still_offered(coll, "accept")
    _transition(coll, S.ACCEPTED, actor=agent, audit_code="COLLECTION_ACCEPTED")
    _record_assignment(coll, agent, "accepted")
    return coll


def reject(coll, agent, reason=""):
    _assert_owner(coll, agent)
    _assert_still_offered(coll, "reject")
    _record_assignment(coll, agent, "rejected", reason=reason)
    coll.agent = None
    coll.save(update_fields=["agent", "updated_at"])
    _transition(coll, S.REQUESTED, actor=agent, note=reason)
    auto_assign(coll, by=agent)  # back to the pool → next best agent
    return coll


def en_route(coll, agent):
    _assert_owner(coll, agent)
    _transition(coll, S.EN_ROUTE, actor=agent, audit_code="COLLECTION_EN_ROUTE")
    return coll


def reach(coll, agent):
    # Reaching the customer no longer sends an OTP by itself — the agent first
    # enters the amount being collected (request_collection_otp), which sends an
    # amount-bound OTP the customer confirms.
    _assert_owner(coll, agent)
    _transition(coll, S.REACHED, actor=agent, audit_code="COLLECTION_REACHED")
    return coll


def _paise_ok(amt):
    return amt == amt.quantize(Decimal("0.01"))


def request_collection_otp(coll, agent, amount):
    """Agent enters the amount they're collecting → send the customer an OTP that
    authorises exactly that amount. The customer sees the figure in the alert and
    only shares the code if it's correct."""
    _assert_owner(coll, agent)
    if coll.status not in (S.REACHED,):
        raise AppError("INVALID_COLLECTION_TRANSITION",
                       message="Mark that you've reached the customer first.")
    if amount is None:
        raise AppError("COLLECTION_AMOUNT_INVALID")
    amt = Decimal(str(amount))
    if amt <= 0 or amt > coll.remaining or not _paise_ok(amt):
        raise AppError("COLLECTION_AMOUNT_INVALID")

    # Admin-configurable floor. Zero was always refused, but there was no way to
    # say "don't record a ₹20 collection" — a doorstep visit has a cost, and a
    # trickle of tiny part-payments keeps a recovery open indefinitely. Default
    # 0 means no floor, so nothing changes until someone sets one.
    #
    # The floor never blocks CLEARING the account: if the whole remaining
    # balance is below it, that payment must still be collectable or the debt
    # could never be closed.
    floor = _min_collection_amount()
    if floor > 0 and amt < floor and amt < coll.remaining:
        raise AppError(
            "COLLECTION_AMOUNT_INVALID",
            message=(
                f"The smallest amount you can collect is ₹{floor:,.0f}. "
                f"Collect at least that, or the full ₹{coll.remaining:,.0f} due."
            ),
        )
    _generate_otp(coll, amt)
    return coll


def _min_collection_amount():
    """Platform floor for a single cash collection (0 = no floor)."""
    from siteconfig.models import PlatformConfig

    return Decimal(str(PlatformConfig.load().min_collection_amount or 0))


def otp_is_expired(otp, ttl_minutes=OTP_TTL_MINUTES):
    """Whether `otp` is past its time-to-live. A NULL ``generated_at`` counts as
    not expired — rows written before the timestamp was enforced must not be
    invalidated retroactively under an agent standing at a customer's door."""
    if otp.generated_at is None:
        return False
    return timezone.now() - otp.generated_at > timedelta(minutes=ttl_minutes)


def verify_otp(coll, agent, code):
    _assert_owner(coll, agent)
    otp = getattr(coll, "collection_otp", None)
    if otp is None:
        raise AppError("COLLECTION_OTP_REQUIRED", message="No collection OTP generated yet.")
    if otp.locked:
        raise AppError("COLLECTION_OTP_LOCKED")
    # Before the comparison, so an expired code neither verifies nor burns one
    # of the three attempts. `generated_at` was written on every OTP and never
    # read — a confirmation code authorising a specific cash amount stayed valid
    # indefinitely.
    if otp_is_expired(otp):
        raise AppError("COLLECTION_OTP_EXPIRED")
    if code and code == otp.code:
        otp.verified = True
        otp.verified_at = timezone.now()
        otp.save(update_fields=["verified", "verified_at", "updated_at"])
        coll.otp_verified = True
        coll.save(update_fields=["otp_verified", "updated_at"])
        # Clear a lockout flag left over from an earlier round — re-requesting an
        # OTP unlocks the row but left this set, so a collection that went on to
        # verify cleanly stayed flagged for manual verification forever.
        if coll.manual_verification_required:
            coll.manual_verification_required = False
            coll.save(update_fields=["manual_verification_required", "updated_at"])
        _audit("COLLECTION_OTP_VERIFIED", coll, agent)
        return coll
    otp.attempts += 1
    if otp.attempts >= CollectionOTP.MAX_ATTEMPTS:
        otp.locked = True
        otp.save(update_fields=["attempts", "locked", "updated_at"])
        coll.manual_verification_required = True
        coll.save(update_fields=["manual_verification_required", "updated_at"])
        _audit("COLLECTION_OTP_LOCKED", coll, agent, success=False)
        raise AppError("COLLECTION_OTP_LOCKED")
    otp.save(update_fields=["attempts", "updated_at"])
    left = CollectionOTP.MAX_ATTEMPTS - otp.attempts
    raise AppError("INVALID_COLLECTION_OTP",
                   message=f"Incorrect OTP. {left} attempt(s) left.")


@transaction.atomic
def collect(coll, agent, amount=None):
    """Record a FULL or PARTIAL cash collection. Posts a cash repayment to the
    credit ledger, issues a receipt, and closes recovery if the account clears."""
    _assert_owner(coll, agent)
    if not coll.otp_verified:
        raise AppError("COLLECTION_OTP_REQUIRED")
    if coll.status not in (S.REACHED,):
        raise AppError("INVALID_COLLECTION_TRANSITION",
                       message="Mark that you've reached the customer first.")
    # The settled figure is the amount the customer confirmed via OTP — the agent
    # can't collect a different amount than the one that was approved.
    otp = getattr(coll, "collection_otp", None)
    if otp is not None and otp.amount is not None:
        amt = otp.amount
        if amount is not None and Decimal(str(amount)) != amt:
            raise AppError("COLLECTION_AMOUNT_INVALID",
                           message="Amount doesn't match the confirmed OTP.")
    else:
        amt = Decimal(str(amount)) if amount is not None else coll.remaining
    if amt <= 0 or amt > coll.remaining:
        raise AppError("COLLECTION_AMOUNT_INVALID")
    # Strict money precision: reject sub-paise (more than 2 decimal places) so an
    # amount like 100.999 can never enter the ledger.
    if amt != amt.quantize(Decimal("0.01")):
        raise AppError("COLLECTION_AMOUNT_INVALID",
                       message="Amount can have at most 2 decimal places.")

    # Post the cash repayment via the existing payments → credit ledger path.
    from payments.models import Payment
    from payments.services import finalize_payment, start_payment
    payment = start_payment(
        coll.user, purpose=Payment.Purpose.REPAYMENT, amount=amt,
        method=Payment.Method.CASH, statement=coll.statement)
    finalize_payment(payment, success=True, gateway_payment_id=f"cash_{payment.id}")

    CollectionReceipt.objects.create(
        collection=coll, payment=payment, amount=amt, agent=agent,
        issued_at=timezone.now())
    coll.collected_amount = coll.collected_amount + amt
    coll.payment = payment

    full = coll.collected_amount >= coll.amount
    # The OTP is single-use: a partial leaves a balance, and recovering the rest
    # needs a fresh amount-bound OTP the customer re-confirms.
    if not full:
        coll.otp_verified = False
    coll.save(update_fields=["collected_amount", "payment", "otp_verified",
                             "updated_at"])
    _transition(coll, S.COLLECTED if full else S.PARTIALLY_COLLECTED, actor=agent,
                audit_code="COLLECTION_COMPLETED" if full else "PARTIAL_PAYMENT")
    CollectionAttempt.objects.create(
        collection=coll, attempt_no=coll.attempt_no,
        outcome="collected" if full else "partial", amount=amt, by=agent)

    _check_recovery_closed(coll, agent)
    return coll


def _agent_store(agent):
    """The store that manages this agent (agents are store-owned) — the
    same resolution `payments.cashbook_services.agent_store` uses. None for
    a legacy/unassigned agent."""
    profile = getattr(agent, "agent_profile", None)
    return getattr(profile, "store", None) if profile else None


def dispute(coll, agent, note=""):
    _assert_owner(coll, agent)
    coll.dispute_note = note
    _transition(coll, S.DISPUTED, actor=agent, note=note, audit_code="PAYMENT_DISPUTE")
    CollectionAttempt.objects.create(
        collection=coll, attempt_no=coll.attempt_no, outcome="disputed", note=note, by=agent)
    # Unlike a failed delivery (which alerts the store), a disputed collection
    # used to only surface on the store's next manual refresh of the
    # Collections page. Fail-soft — a stuck push must never undo the dispute.
    try:
        from notifications.services import notify_store_staff

        notify_store_staff(_agent_store(agent), type="collection",
                           title="Collection disputed",
                           body=f"{coll.user.name or coll.user.phone} disputed a ₹{coll.amount} collection.",
                           data={"collectionId": str(coll.id)})
    except Exception:  # noqa: BLE001
        pass
    return coll


def fail(coll, agent, *, reason_code="CUSTOMER_NOT_AVAILABLE", note=""):
    _assert_owner(coll, agent)
    coll.failure_reason = reason_code
    _transition(coll, S.FAILED, actor=agent, note=note, audit_code="COLLECTION_FAILED")
    coll.save(update_fields=["failure_reason", "updated_at"])
    CollectionAttempt.objects.create(
        collection=coll, attempt_no=coll.attempt_no, outcome="failed",
        reason_code=reason_code, note=note, by=agent)
    # Mirrors delivery.services.fail_delivery's "alert the store" pattern —
    # a store previously only learned about a failed collection by polling.
    try:
        from notifications.services import notify_store_staff

        notify_store_staff(_agent_store(agent), type="collection",
                           title="Collection failed",
                           body=f"{coll.user.name or coll.user.phone} — {reason_code}",
                           data={"collectionId": str(coll.id)})
    except Exception:  # noqa: BLE001
        pass
    return coll


# ───────────────────────── dunning / aging ─────────────────────────
def aging_bucket(coll, today=None):
    today = today or timezone.localdate()
    days = (today - coll.created_at.date()).days
    if days <= 30:
        return "0-30"
    if days <= 60:
        return "31-60"
    if days <= 90:
        return "61-90"
    return "90+"


def aging_buckets():
    """Summary of OPEN collections by aging bucket (count + amount)."""
    out = {b: {"bucket": b, "count": 0, "amount": ZERO}
           for b in ("0-30", "31-60", "61-90", "90+")}
    today = timezone.localdate()
    for c in CashCollection.objects.exclude(status__in=CashCollection.TERMINAL):
        b = out[aging_bucket(c, today)]
        b["count"] += 1
        b["amount"] += c.remaining
    return list(out.values())


def run_dunning():
    """Escalate aged, still-open collections (61+ days) → mark priority + escalated.
    Returns the count escalated. Run periodically (cron)."""
    today = timezone.localdate()
    escalated = 0
    for c in CashCollection.objects.exclude(status__in=CashCollection.TERMINAL):
        if aging_bucket(c, today) in ("61-90", "90+") and not c.escalated:
            c.escalated = True
            c.is_priority = True
            c.save(update_fields=["escalated", "is_priority", "updated_at"])
            record_event("collection_event", {"code": "DUNNING_ESCALATED", "collection": c.id})
            escalated += 1
    return escalated


def agent_performance(agent, *, since=None):
    qs = CashCollection.objects.filter(agent=agent)
    if since:
        qs = qs.filter(created_at__gte=since)
    assigned = qs.count()
    collected = qs.filter(status=S.COLLECTED).count()
    partial = qs.filter(status=S.PARTIALLY_COLLECTED).count()
    failed = qs.filter(status=S.FAILED).count()
    recovered = sum((c.collected_amount for c in qs), ZERO)
    return {
        "assigned": assigned,
        "collected": collected,
        "partial": partial,
        "failed": failed,
        "recoveredAmount": float(recovered),
        "recoveryRate": round((collected + partial) / assigned * 100, 1) if assigned else 0.0,
    }


# ───────────────────────── internals ─────────────────────────
def _generate_otp(coll, amount):
    code = "".join(secrets.choice("0123456789") for _ in range(6))
    CollectionOTP.objects.update_or_create(
        collection=coll,
        defaults={"code": code, "amount": amount, "attempts": 0,
                  "verified": False, "locked": False,
                  "generated_at": timezone.now()})
    coll.otp_verified = False
    coll.save(update_fields=["otp_verified", "updated_at"])
    agent_name = getattr(coll.agent, "name", "") or "the agent"
    # The code is NEVER put in the message — the customer views it inside the app
    # (GET /collections/confirm) so it can't leak via SMS/notification history.
    from notifications.services import notify
    notify(coll.user, type="payment", title=f"Confirm ₹{amount} payment",
           body=f"{agent_name} is collecting ₹{amount}. Open the app to view and "
                f"share your confirmation code.",
           data={"kind": "collection_confirm", "collectionId": coll.id,
                 "amount": str(amount), "route": "collection-confirm"})
    _audit("COLLECTION_OTP_SENT", coll, coll.agent)
    return code


def _alert_store_unassigned(coll, store, reason):
    """Nobody could take the collection — say so, loudly. Previously a request
    raised while every agent was off duty stayed in `requested` with no agent,
    invisible to both the agent app and anyone who could have fixed it."""
    try:
        from notifications.services import notify_store_staff

        notify_store_staff(
            store, type="payment", title="Collection needs an agent",
            body=f"₹{coll.remaining} from "
                 f"{getattr(coll.user, 'name', '') or getattr(coll.user, 'phone', '')} "
                 f"couldn't be auto-assigned ({reason}). Assign someone manually.",
            data={"collectionId": str(coll.id), "kind": "collection_unassigned",
                  "route": "collections"})
    except Exception:  # noqa: BLE001 — an alert must never undo the request
        pass


def assign_orphan_collections(limit=200):
    """Retry assignment for collections nobody could take when they were raised.

    Without this a customer-raised collection made while every agent was off duty
    never reaches an agent, no matter how many come on duty later. Run
    periodically (``run_dispatch``). Returns the count newly assigned.
    """
    stranded = (
        CashCollection.objects
        .filter(agent__isnull=True, status=S.REQUESTED)
        .select_related("user")[:limit]
    )
    assigned = 0
    for coll in stranded:
        if auto_assign(coll) is not None:
            assigned += 1
    return assigned


def _notify_agent(coll):
    if coll.agent is None:
        return
    from notifications.services import notify
    notify(coll.agent, type="payment", title="New collection assigned",
           body=f"Collect ₹{coll.remaining} from {getattr(coll.user, 'name', '')}",
           data={"collectionId": coll.id, "kind": "collection_assignment",
                 "route": "collections"})


def _check_recovery_closed(coll, actor):
    from credit.services import ensure_account
    acct = ensure_account(coll.user)
    if acct.outstanding <= ZERO:
        _audit("RECOVERY_CLOSED", coll, actor)
        from notifications.services import notify
        notify(coll.user, type="credit", title="Dues cleared",
               body="Your outstanding balance is fully cleared. Thank you!",
               data={"kind": "recovery_closed"})
