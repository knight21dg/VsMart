"""Return-pickup engine — the field-agent half of a return.

A customer submits a return with photos; that submission immediately creates a
``ReturnPickupTask`` and auto-assigns it to a store-scoped field agent. The agent
travels to the customer, inspects the goods against the customer's photos, takes
their own condition photos, and settles the return **at the door**:

  • accept (optionally only part of a line)  → goods collected, return `picked`
  • reject with a reason code                → return `rejected`, closed
  • reschedule                               → deferred, stays on the agent's list

Money never moves here. Accepting only records that the goods are in hand and the
condition checks out; the store still presses refund in the panel, which runs the
existing ``admin_service.set_return_status(..., 'refunded')`` path (credit
reversal / gateway refund + inventory restock).

Every action writes an Audit Log + an Analytics Event, mirroring
``delivery.services`` and ``cashcollections.services``.
"""
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from core.app_errors import AppError
from core.audit import write_audit
from core.events import record_event
from core.response_codes import CATALOG

from .models import (
    ReturnAssignmentHistory,
    ReturnEvidence,
    ReturnPickupTask,
    ReturnRequest,
    ReturnStatus,
)

S = ReturnPickupTask.Status
ZERO = Decimal("0.00")

ALLOWED = {
    S.ASSIGNED: {S.ACCEPTED, S.REASSIGNED, S.CANCELLED},
    S.ACCEPTED: {S.EN_ROUTE, S.RESCHEDULED, S.REASSIGNED, S.CANCELLED},
    S.EN_ROUTE: {S.REACHED, S.RESCHEDULED, S.CANCELLED},
    S.REACHED: {S.COMPLETED, S.REJECTED, S.RESCHEDULED},
    # A rescheduled visit is reattempted from the top of the agent's flow.
    S.RESCHEDULED: {S.EN_ROUTE, S.REACHED, S.REASSIGNED, S.CANCELLED},
}

_TS = {
    S.ACCEPTED: "accepted_at", S.EN_ROUTE: "en_route_at",
    S.REACHED: "reached_at", S.COMPLETED: "completed_at",
}


# ───────────────────────── helpers ─────────────────────────
def _audit(code, task, actor, *, success=True, message=""):
    spec = CATALOG.get(code, CATALOG["SYSTEM_ERROR"])
    write_audit(code, spec, actor=actor, success=success,
                entity_type="return_pickup", entity_id=task.id if task else "",
                message=message)
    record_event("return_event",
                 {"code": code, "task": task.id if task else None,
                  "return": task.return_request_id if task else None,
                  "status": task.status if task else None}, actor=actor)


def _transition(task, to_status, *, actor=None, audit_code=None):
    cur = task.status
    if to_status != cur and to_status not in ALLOWED.get(cur, set()):
        raise AppError("INVALID_RETURN_TRANSITION",
                       message=f"Can't move a pickup from '{cur}' to '{to_status}'.")
    task.status = to_status
    fields = ["status", "updated_at"]
    ts = _TS.get(to_status)
    if ts and getattr(task, ts, None) is None:
        setattr(task, ts, timezone.now())
        fields.append(ts)
    task.save(update_fields=list(set(fields)))
    if audit_code:
        _audit(audit_code, task, actor)
    return task


def _assert_owner(task, agent):
    if task.agent_id != agent.id:
        raise AppError("INSUFFICIENT_PERMISSIONS",
                       message="This pickup isn't assigned to you.")


def _dest_coords(order):
    snap = getattr(order, "address_snapshot", None) or {}
    return (snap.get("latitude") or snap.get("lat"),
            snap.get("longitude") or snap.get("lng"))


def return_store(ret):
    """The store that owns this return — the order's serving store."""
    return getattr(ret.order, "store", None) if ret.order_id else None


# ───────────────────────── assignment ─────────────────────────
def _agent_open_load(agent):
    return ReturnPickupTask.objects.filter(agent=agent).exclude(
        status__in=ReturnPickupTask.TERMINAL).count()


def _record_assignment(task, agent, action, by=None, reason=""):
    ReturnAssignmentHistory.objects.create(
        task=task, agent=agent, action=action, by=by, reason=reason)


def _notify_agent(task):
    if task.agent is None:
        return
    from notifications.services import notify

    ret = task.return_request
    notify(task.agent, type="return", title="New return pickup",
           body=f"Collect return {ret.code} from "
                f"{getattr(ret.user, 'name', '') or getattr(ret.user, 'phone', '')}",
           data={"taskId": str(task.id), "returnCode": ret.code,
                 "kind": "return_pickup_assignment", "route": "return-pickups"})


def _alert_store_unassigned(ret, reason):
    """Nobody could take the pickup — make that visible instead of letting the
    return sit silently unassigned forever."""
    try:
        from notifications.services import notify_store_staff

        notify_store_staff(
            return_store(ret), type="return", title="Return pickup needs an agent",
            body=f"Return {ret.code} couldn't be auto-assigned ({reason}). "
                 f"Assign a pickup partner manually.",
            data={"returnCode": ret.code, "kind": "return_pickup_unassigned",
                  "route": "returns"})
    except Exception:  # noqa: BLE001 — an alert must never undo the return
        pass


def create_pickup(ret, *, by=None, attempt_no=1):
    """Open a pickup task for a return and try to assign it immediately.

    Returns the task (assigned or not). A task is always created so the work is
    visible on the store's board even when no agent could take it.
    """
    dlat, dlng = _dest_coords(ret.order)
    task = ReturnPickupTask.objects.create(
        return_request=ret, status=S.ASSIGNED, attempt_no=attempt_no,
        dest_lat=dlat, dest_lng=dlng,
    )
    return auto_assign(task, by=by)


def auto_assign(task, *, by=None):
    """Assign to the least-loaded free agent of the return's store; fall back to
    whoever clears soonest when everyone is busy. Leaves the task unassigned (and
    alerts the store) when nobody is eligible."""
    from agents.candidates import candidate_agents, unassignable_reason
    from agents.dispatch import rank_for_new_task

    ret = task.return_request
    store = return_store(ret)
    agents = candidate_agents(store=store)
    if not agents:
        reason = unassignable_reason(store=store)
        record_event("return_event",
                     {"code": "AGENT_UNAVAILABLE", "return": ret.id, "reason": reason})
        _alert_store_unassigned(ret, reason)
        return task

    free, busy_by_soonest = rank_for_new_task(agents)
    if free:
        agent = min(free, key=_agent_open_load)
    elif busy_by_soonest:
        agent = busy_by_soonest[0]
    else:
        agent = min(agents, key=_agent_open_load)

    task.agent = agent
    task.assigned_at = timezone.now()
    task.save(update_fields=["agent", "assigned_at", "updated_at"])
    if task.status != S.ASSIGNED:
        _transition(task, S.ASSIGNED, actor=by)
    _record_assignment(task, agent, ReturnAssignmentHistory.Action.AUTO_ASSIGNED, by=by)
    _audit("RETURN_PICKUP_ASSIGNED", task, by or agent)
    _notify_agent(task)
    _notify_customer_assigned(task)
    return task


def _notify_customer_assigned(task):
    if task.agent is None:
        return
    try:
        from notifications.services import notify

        ret = task.return_request
        notify(ret.user, type="return", title="Pickup partner assigned",
               body=f"{getattr(task.agent, 'name', '') or 'A partner'} will collect "
                    f"return {ret.code}. Keep the item and packaging ready.",
               data={"returnCode": ret.code, "kind": "return_pickup_assigned",
                     "route": "returns"})
    except Exception:  # noqa: BLE001
        pass


def manual_assign(task, agent, *, by, reason=""):
    """Store/admin hands the pickup to a specific agent (or reassigns it)."""
    if task.is_terminal:
        raise AppError("INVALID_RETURN_TRANSITION",
                       message="This pickup is already closed.")
    action = (ReturnAssignmentHistory.Action.REASSIGNED if task.agent_id
              else ReturnAssignmentHistory.Action.MANUAL_ASSIGNED)
    task.agent = agent
    task.assigned_at = timezone.now()
    task.status = S.ASSIGNED
    task.save(update_fields=["agent", "assigned_at", "status", "updated_at"])
    _record_assignment(task, agent, action, by=by, reason=reason)
    _audit("RETURN_PICKUP_ASSIGNED", task, by)
    _notify_agent(task)
    _notify_customer_assigned(task)
    return task


# ───────────────────────── agent workflow ─────────────────────────
def accept(task, agent):
    _assert_owner(task, agent)
    _transition(task, S.ACCEPTED, actor=agent, audit_code="RETURN_PICKUP_ASSIGNED")
    _record_assignment(task, agent, ReturnAssignmentHistory.Action.ACCEPTED)
    return task


def reject_task(task, agent, reason=""):
    """The agent declines the JOB (not the goods) — back to the pool."""
    _assert_owner(task, agent)
    _record_assignment(task, agent, ReturnAssignmentHistory.Action.REJECTED,
                       reason=reason)
    task.agent = None
    task.save(update_fields=["agent", "updated_at"])
    return auto_assign(task, by=agent)


def en_route(task, agent):
    _assert_owner(task, agent)
    return _transition(task, S.EN_ROUTE, actor=agent)


def reach(task, agent):
    _assert_owner(task, agent)
    return _transition(task, S.REACHED, actor=agent)


def add_evidence(ret, user, *, photo=None, file_key="", source=None, task=None,
                 lat=None, lng=None, meta=None):
    """Ingest a return photo through the self-hosted media engine.

    ``photo`` is an uploaded file / raw bytes → validated, EXIF-stripped and
    WebP'd into a PRIVATE asset owned by the return's customer. ``file_key`` is
    the legacy loose-string path, used only when no file is supplied.
    """
    meta = dict(meta or {})
    if photo is not None:
        from mediastore.pipeline import store_image

        asset = store_image(
            photo, category="return", visibility="private", owner=ret.user,
            original_name=getattr(photo, "name", "") or "",
        )
        file_key = str(asset.id)
        meta.setdefault("media_asset", file_key)
    if not file_key:
        raise AppError("RETURN_PHOTOS_REQUIRED")
    return ReturnEvidence.objects.create(
        return_request=ret, task=task,
        source=source or ReturnEvidence.Source.CUSTOMER,
        file_key=file_key, latitude=lat, longitude=lng,
        captured_at=timezone.now(), uploaded_by=user, meta=meta,
    )


def _settle_items(ret, decisions):
    """Apply the agent's per-line accept decision and return the settled refund.

    ``decisions`` maps ReturnItem id → accepted quantity. A line the agent didn't
    touch settles at the full requested quantity. Amount is prorated off the
    requested line amount so a partial accept refunds proportionally.
    """
    total = ZERO
    items = list(ret.items.all())
    for it in items:
        if it.id in decisions:
            qty = decisions[it.id]
            if qty < 0 or qty > it.quantity:
                raise AppError("RETURN_QUANTITY_INVALID")
            unit = (it.amount / it.quantity) if it.quantity else ZERO
            it.accepted_quantity = qty
            it.accepted_amount = (unit * qty).quantize(Decimal("0.01"))
            it.save(update_fields=["accepted_quantity", "accepted_amount",
                                   "updated_at"])
        total += it.settled_amount
    return total, items


@transaction.atomic
def complete(task, agent, *, decisions=None, note=""):
    """Agent accepts the return at the door: goods are in hand and the condition
    checks out. Moves the return to `picked` and hands it to the store for the
    refund. No money moves here."""
    _assert_owner(task, agent)
    if task.status != S.REACHED:
        raise AppError("INVALID_RETURN_TRANSITION",
                       message="Mark that you've reached the customer first.")
    # Lock the return so a double-tap can't settle it twice.
    ret = ReturnRequest.objects.select_for_update().get(pk=task.return_request_id)
    if ret.status in (ReturnStatus.REFUNDED, ReturnStatus.REJECTED,
                      ReturnStatus.PICKED):
        raise AppError("INVALID_RETURN_TRANSITION",
                       message=f"Return {ret.code} is already {ret.status}.")
    if not task.evidence.filter(source=ReturnEvidence.Source.AGENT).exists():
        raise AppError("RETURN_EVIDENCE_REQUIRED")

    settled, items = _settle_items(ret, decisions or {})
    if settled <= ZERO:
        # Every line was refused → this is a rejection, not a collection.
        raise AppError(
            "RETURN_QUANTITY_INVALID",
            message="Nothing was accepted — reject the return instead.")

    ret.refund_amount = settled
    ret.status = ReturnStatus.PICKED
    ret.decided_by = agent
    if note:
        ret.decision_note = note
    ret.save(update_fields=["refund_amount", "status", "decided_by",
                            "decision_note", "updated_at"])

    task.note = note
    task.save(update_fields=["note", "updated_at"])
    _transition(task, S.COMPLETED, actor=agent, audit_code="RETURN_PICKUP_COMPLETED")

    _notify_store_settled(ret, task, accepted=True)
    _notify_customer_settled(ret, accepted=True)
    return task


@transaction.atomic
def reject_return(task, agent, *, reason_code, note=""):
    """Agent refuses the goods at the door — the return is closed as rejected."""
    _assert_owner(task, agent)
    if task.status != S.REACHED:
        raise AppError("INVALID_RETURN_TRANSITION",
                       message="Mark that you've reached the customer first.")
    if reason_code not in ReturnPickupTask.ReasonCode.values:
        raise AppError("INVALID_RETURN_TRANSITION",
                       message=f"Unknown reason '{reason_code}'.")
    ret = ReturnRequest.objects.select_for_update().get(pk=task.return_request_id)
    if ret.status in (ReturnStatus.REFUNDED, ReturnStatus.REJECTED):
        raise AppError("INVALID_RETURN_TRANSITION",
                       message=f"Return {ret.code} is already {ret.status}.")

    ret.status = ReturnStatus.REJECTED
    ret.decided_by = agent
    ret.decision_note = note or ret.decision_note
    ret.resolved_at = timezone.now()
    ret.save(update_fields=["status", "decided_by", "decision_note",
                            "resolved_at", "updated_at"])

    task.reason_code = reason_code
    task.note = note
    task.save(update_fields=["reason_code", "note", "updated_at"])
    _transition(task, S.REJECTED, actor=agent, audit_code="RETURN_PICKUP_REJECTED")

    _notify_store_settled(ret, task, accepted=False)
    _notify_customer_settled(ret, accepted=False, reason_code=reason_code)
    return task


def reschedule(task, agent, *, reason_code="customer_unavailable", note="", at=None):
    """Defer the visit — the task stays open and is reattempted."""
    _assert_owner(task, agent)
    if task.status not in (S.ACCEPTED, S.EN_ROUTE, S.REACHED, S.RESCHEDULED):
        raise AppError("INVALID_RETURN_TRANSITION",
                       message="Accept the pickup before rescheduling it.")
    task.reason_code = reason_code
    task.note = note
    task.reschedule_at = at
    task.attempt_no = task.attempt_no + 1
    # Clear the leg timestamps so the next attempt records its own timeline.
    task.en_route_at = None
    task.reached_at = None
    task.save(update_fields=["reason_code", "note", "reschedule_at", "attempt_no",
                             "en_route_at", "reached_at", "updated_at"])
    _transition(task, S.RESCHEDULED, actor=agent,
                audit_code="RETURN_PICKUP_RESCHEDULED")
    _record_assignment(task, agent, ReturnAssignmentHistory.Action.RESCHEDULED,
                       reason=reason_code)
    try:
        from notifications.services import notify

        ret = task.return_request
        notify(ret.user, type="return", title="Pickup rescheduled",
               body=f"We couldn't collect return {ret.code} — we'll try again.",
               data={"returnCode": ret.code, "kind": "return_pickup_rescheduled",
                     "route": "returns"})
    except Exception:  # noqa: BLE001
        pass
    return task


# ───────────────────────── notifications ─────────────────────────
def _notify_store_settled(ret, task, *, accepted):
    try:
        from notifications.services import notify_store_staff

        if accepted:
            title, body = ("Return collected — refund pending",
                           f"Return {ret.code} collected by "
                           f"{getattr(task.agent, 'name', '') or 'an agent'}. "
                           f"₹{ret.refund_amount} awaiting refund.")
        else:
            title, body = ("Return rejected at the door",
                           f"Return {ret.code} — {task.reason_code}")
        notify_store_staff(return_store(ret), type="return", title=title, body=body,
                           data={"returnCode": ret.code, "route": "returns"})
    except Exception:  # noqa: BLE001
        pass


def _notify_customer_settled(ret, *, accepted, reason_code=""):
    try:
        from notifications.services import notify

        if accepted:
            title, body = ("Return collected",
                           f"We've collected return {ret.code}. Your refund of "
                           f"₹{ret.refund_amount} will be processed shortly.")
        else:
            title, body = ("Return not accepted",
                           f"Return {ret.code} couldn't be accepted ({reason_code}). "
                           f"Contact support if you disagree.")
        notify(ret.user, type="return", title=title, body=body,
               data={"returnCode": ret.code, "route": "returns",
                     "kind": "return_settled"})
    except Exception:  # noqa: BLE001
        pass


# ───────────────────────── recovery sweep ─────────────────────────
def assign_orphan_pickups(limit=200):
    """Retry assignment for pickups nobody could take when they were raised.

    Without this a return raised while every agent was off-duty stays invisible
    forever. Run periodically (``run_dispatch``). Returns the count assigned.
    """
    stranded = (
        ReturnPickupTask.objects
        .filter(agent__isnull=True)
        .exclude(status__in=ReturnPickupTask.TERMINAL)
        .select_related("return_request__order__store", "return_request__user")[:limit]
    )
    assigned = 0
    for task in stranded:
        if auto_assign(task).agent_id:
            assigned += 1
    return assigned
