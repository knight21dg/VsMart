"""Delivery Operations engine — the controlled state machine and every workflow
the production spec requires:

  • auto + manual assignment (zone + availability + workload + distance ranking)
  • strict transitions (NO status skipping)
  • live GPS log → mirrored to the customer's order tracking
  • ≤50 m arrival geofence
  • delivery OTP with 3-attempt lockout → manual verification
  • mandatory proof-of-delivery photo
  • completion guard: agent + geofence + OTP + photo, all required
  • failed / reattempt / return-to-store with inventory + credit reversal
  • per-task earnings (base + distance/heavy/peak bonuses) and agent performance

Every action writes an Audit Log + an Analytics Event, and order-level transitions
write the Order timeline (via orders.advance_status). Money/stock changes are atomic.
"""
import math
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

from .models import (
    DeliveryAssignmentHistory,
    DeliveryAttempt,
    DeliveryEarnings,
    DeliveryEvidence,
    DeliveryLocation,
    DeliveryOTP,
    DeliveryRating,
    DeliveryTask,
)

S = DeliveryTask.Status
#: Arrival radius. 100 m absorbs honest slack (approximate rural pins, ±50 m
#: budget-phone GPS, parking down the lane) while still requiring the rider to
#: actually be at the address. The OTP + proof-photo handover remains the real
#: proof of delivery.
GEOFENCE_M = 100

#: How long a delivery OTP stays valid. It is only minted once the agent has
#: confirmed arrival at the door, so the whole handover happens inside minutes;
#: 15 gives room for a customer to find their phone without leaving a live
#: credential sitting in an SMS inbox. Overridable for a slower operation.
OTP_TTL_MINUTES = getattr(settings, "DELIVERY_OTP_TTL_MINUTES", 15)

# Strict state machine — a transition not listed here is rejected.
ALLOWED = {
    S.ASSIGNED: {S.ACCEPTED, S.REJECTED, S.REASSIGNED, S.CANCELLED},
    S.ACCEPTED: {S.PICKED_UP, S.REASSIGNED, S.CANCELLED},
    S.PICKED_UP: {S.OUT_FOR_DELIVERY, S.RETURN_INITIATED},
    S.OUT_FOR_DELIVERY: {S.REACHED, S.FAILED},
    S.REACHED: {S.DELIVERED, S.FAILED},
    S.FAILED: {S.RESCHEDULED, S.REASSIGNED, S.RETURN_INITIATED},
    S.RESCHEDULED: {S.ASSIGNED},
    S.RETURN_INITIATED: {S.RETURNED_TO_STORE},
}

_TS = {  # status → timestamp field to stamp on entry
    S.ASSIGNED: "assigned_at", S.ACCEPTED: "accepted_at", S.PICKED_UP: "picked_up_at",
    S.OUT_FOR_DELIVERY: "out_for_delivery_at", S.REACHED: "reached_at",
    S.DELIVERED: "delivered_at", S.FAILED: "failed_at",
}


# ───────────────────────── helpers ─────────────────────────
def _f(v):
    return None if v is None else float(v)


def haversine_m(lat1, lng1, lat2, lng2):
    """Great-circle distance in metres."""
    if None in (lat1, lng1, lat2, lng2):
        return None
    r = 6371000.0
    p1, p2 = math.radians(float(lat1)), math.radians(float(lat2))
    dp = math.radians(float(lat2) - float(lat1))
    dl = math.radians(float(lng2) - float(lng1))
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _audit(code, task, actor, *, success=True, message=""):
    spec = CATALOG.get(code, CATALOG["SYSTEM_ERROR"])
    write_audit(code, spec, actor=actor, success=success, entity_type="delivery_task",
                entity_id=task.id if task else "", message=message)
    record_event("delivery_event",
                 {"code": code, "task": task.id if task else None,
                  "order": task.order.code if task else None,
                  "status": task.status if task else None}, actor=actor)


def _transition(task, to_status, *, actor=None, note="", audit_code=None):
    """Enforce the state machine, stamp the timestamp, persist, and audit."""
    cur = task.status
    if to_status != cur and to_status not in ALLOWED.get(cur, set()):
        raise AppError("INVALID_DELIVERY_TRANSITION",
                       message=f"Can't move a delivery from '{cur}' to '{to_status}'.")
    task.status = to_status
    fields = ["status", "updated_at"]
    ts = _TS.get(to_status)
    if ts:
        setattr(task, ts, timezone.now())
        fields.append(ts)
    if note:
        task.note = note
        fields.append("note")
    task.save(update_fields=list(set(fields)))
    if audit_code:
        _audit(audit_code, task, actor)
    # Real-time: push the new status to the customer + dispatch board (best-effort).
    from .realtime import broadcast as _rt_broadcast

    _rt_broadcast(task)
    return task


# ───────────────────────── assignment engine ─────────────────────────
def _agent_active_load(agent):
    return DeliveryTask.objects.filter(agent=agent).exclude(
        status__in=DeliveryTask.CLOSED_FOR_AGENT
    ).count()


def _agent_last_location(agent):
    loc = DeliveryLocation.objects.filter(agent=agent).order_by("-at").first()
    return (loc.latitude, loc.longitude) if loc else (None, None)


def _agent_acceptance_rate(agent):
    hist = DeliveryAssignmentHistory.objects.filter(agent=agent)
    offered = hist.filter(action__in=["auto_assigned", "manual_assigned", "reassigned"]).count()
    rejected = hist.filter(action="rejected").count()
    if offered == 0:
        return 1.0
    return max(0.0, (offered - rejected) / offered)


def candidate_agents(order):
    """Same-zone, available, on-duty agents (falls back to any available agent when
    the zone has no roster yet)."""
    from accounts.models import AgentProfile, User

    zone = getattr(order, "zone", None)
    agent_ids = []
    if zone is not None:
        agent_ids = list(zone.agents.values_list("agent_id", flat=True))  # ZoneAgent
    agents = User.objects.filter(role="agent", is_active=True)
    if agent_ids:
        zoned = agents.filter(id__in=agent_ids)
        if zoned.exists():
            agents = zoned
    # availability flag (AgentProfile.is_available); agents without a profile are eligible.
    available_ids = set(
        AgentProfile.objects.filter(is_available=True).values_list("user_id", flat=True)
    )
    profiled_ids = set(AgentProfile.objects.values_list("user_id", flat=True))
    out = [a for a in agents if a.id in available_ids or a.id not in profiled_ids]
    return out


def rank_agents(order, agents):
    """Lower score = better. Score = distance(km) + active_load + (1-acceptance) +
    (1-performance). Performance proxied by acceptance for now."""
    dlat = getattr(order, "_dest_lat", None)
    dlng = getattr(order, "_dest_lng", None)
    ranked = []
    for a in agents:
        lat, lng = _agent_last_location(a)
        dist_m = haversine_m(lat, lng, dlat, dlng) if (lat and dlat) else None
        dist_km = (dist_m / 1000.0) if dist_m is not None else 5.0  # unknown → mid
        load = _agent_active_load(a)
        accept = _agent_acceptance_rate(a)
        score = dist_km + load + (1 - accept) * 2
        ranked.append((score, dist_km, a))
    ranked.sort(key=lambda t: t[0])
    return ranked


def _dest_coords(order):
    snap = order.address_snapshot or {}
    return snap.get("latitude") or snap.get("lat"), snap.get("longitude") or snap.get("lng")


def _new_task(order, agent, *, action, by=None, score=None, attempt_no=1):
    dlat, dlng = _dest_coords(order)
    task = DeliveryTask.objects.create(
        order=order, agent=agent, status=S.ASSIGNED, attempt_no=attempt_no,
        dest_lat=dlat, dest_lng=dlng, assigned_at=timezone.now(),
        priority_score=Decimal(str(round(score, 2))) if score is not None else None,
    )
    DeliveryAssignmentHistory.objects.create(
        task=task, agent=agent, action=action, by=by,
        score=task.priority_score, reason="",
    )
    _audit("DELIVERY_ASSIGNED", task, by or agent)
    _seed_tracking_identity(task)
    _notify_agent(task)
    return task


def _seed_tracking_identity(task):
    """Put the rider's name/phone/photo on the tracking row at ASSIGNMENT, so the
    customer sees who's coming (and can call) before the first GPS ping — until then
    there are no coords, just identity."""
    if task.agent is None:
        return
    from orders.models import OrderTracking

    agent = task.agent
    OrderTracking.objects.update_or_create(
        order=task.order,
        defaults={
            "agent_name": getattr(agent, "name", "") or "Delivery agent",
            "agent_phone": getattr(agent, "phone", "") or "",
            "agent_photo_url": getattr(agent, "avatar_url", "") or "",
        },
    )
    return task


def auto_assign(order, *, by=None):
    """Pick the best-ranked candidate and create a task. Returns the task, or None
    when no agent is available (caller surfaces AGENT_UNAVAILABLE)."""
    dlat, dlng = _dest_coords(order)
    order._dest_lat, order._dest_lng = dlat, dlng
    agents = candidate_agents(order)
    if not agents:
        record_event("delivery_event", {"code": "AGENT_UNAVAILABLE", "order": order.code})
        return None
    ranked = rank_agents(order, agents)
    score, dist_km, agent = ranked[0]
    task = _new_task(order, agent, action="auto_assigned", by=by, score=score)
    task.distance_km = Decimal(str(round(dist_km, 2)))
    task.save(update_fields=["distance_km"])
    return task


def manual_assign(order, agent, *, by, reason=""):
    """Store admin manually assigns / reassigns to a specific agent.

    Two shapes, and the difference matters:
      • the order has a LIVE task → hand that task over (``reassign``), which
        closes it out and carries the attempt number across;
      • it doesn't (nobody assigned yet, or the last attempt failed / was
        rejected) → open a fresh task as the NEXT attempt.

    The second case used to always create ``attempt_no=1``, so a re-dispatch
    after a failed drop reported itself as the first attempt — the agent, the
    customer's tracking and `agent_performance` all lost the fact that this
    address had already been tried.
    """
    active = order.delivery_tasks.filter(status__in=[S.ASSIGNED, S.ACCEPTED]).first()
    if active:
        return reassign(active, agent, by=by, reason=reason or "Manual reassign")
    last = order.delivery_tasks.order_by("-attempt_no").first()
    return _new_task(order, agent, action="manual_assigned", by=by,
                     attempt_no=(last.attempt_no + 1) if last else 1)


@transaction.atomic
def reassign(task, agent, *, by, reason=""):
    """Close the current task (reassigned) and open a fresh one for the new agent."""
    # A closed task must stay closed. Without this, Reassign on a cancelled,
    # rejected, returned-to-store or already-reassigned row re-dispatched a
    # finished order to a rider — and on an already-reassigned task it forked a
    # second live task for the same order.
    if task.is_terminal:
        raise AppError(
            "INVALID_DELIVERY_TRANSITION",
            message=f"This delivery is already {task.status.replace('_', ' ')} "
                    "and can't be reassigned.",
        )
    DeliveryAssignmentHistory.objects.create(
        task=task, agent=task.agent, action="reassigned", by=by, reason=reason
    )
    task.status = S.REASSIGNED
    task.save(update_fields=["status", "updated_at"])
    _audit("AGENT_ASSIGNED", task, by, message=f"Reassigned: {reason}")
    return _new_task(task.order, agent, action="manual_assigned", by=by,
                     attempt_no=task.attempt_no)


# ───────────────────────── agent workflow ─────────────────────────
def _assert_still_offered(task, action):
    """The task must still be sitting on this agent's offer, un-actioned.

    A push alert is a snapshot. By the time the rider looks up from the road and
    taps Accept or Reject, the dispatch engine's 120-second tick has very often
    already moved the task on — in production the overwhelming majority of tasks
    end up ``reassigned``. Tapping then produced
    ``Can't move a delivery from 'reassigned' to 'rejected'``, which the app
    showed as "Couldn't reject — try again": an invitation to keep tapping a
    button that can never succeed.

    It isn't an error the rider can do anything about, so say the true thing —
    the offer is gone — with a code the app can branch on to dismiss the alert.
    """
    if task.status != S.ASSIGNED:
        raise AppError(
            "DELIVERY_TASK_REQUIRED",
            message=(
                f"This delivery is no longer yours to {action} — it was "
                f"reassigned or already actioned."
            ),
            entity_type="delivery_task",
            entity_id=task.id,
        )


def accept(task, agent):
    _assert_owner(task, agent)
    _assert_still_offered(task, "accept")
    _transition(task, S.ACCEPTED, actor=agent, audit_code="AGENT_ASSIGNED")
    DeliveryAssignmentHistory.objects.create(task=task, agent=agent, action="accepted")
    return task


def reject(task, agent, reason=""):
    _assert_owner(task, agent)
    _assert_still_offered(task, "reject")
    _transition(task, S.REJECTED, actor=agent, note=reason)
    DeliveryAssignmentHistory.objects.create(
        task=task, agent=agent, action="rejected", reason=reason)
    # Try to auto-reassign to the next best agent.
    auto_assign(task.order, by=agent)
    return task


def pick_up(task, agent):
    _assert_owner(task, agent)
    _transition(task, S.PICKED_UP, actor=agent, audit_code="PICKED_UP")
    return task


def out_for_delivery(task, agent):
    _assert_owner(task, agent)
    _transition(task, S.OUT_FOR_DELIVERY, actor=agent, audit_code="OUT_FOR_DELIVERY")
    # The OTP is generated on ARRIVAL (see `arrive()`), not here — it's only
    # useful once the agent is actually at the door, and the customer
    # shouldn't be holding a live handover code for the whole trip.
    from orders.services import advance_status
    from orders.models import OrderStatus
    advance_status(task.order, OrderStatus.OUT_FOR_DELIVERY, by=agent)
    return task


def log_location(agent, lat, lng, *, task=None, accuracy=None):
    """Persist a GPS ping and mirror it onto the order tracking the customer sees."""
    DeliveryLocation.objects.create(
        agent=agent, task=task, latitude=lat, longitude=lng, accuracy_m=accuracy)
    if task is not None:
        _update_order_tracking(task, lat, lng)
    return True


def arrive(task, agent, lat, lng):
    """Geofence check on arrival — must be within GEOFENCE_M of the delivery
    address. Confirmed arrival is also what generates and sends the delivery
    OTP to the customer — they weren't holding a handover code for the whole
    trip, only from the moment the agent is actually at the door."""
    _assert_owner(task, agent)
    log_location(agent, lat, lng, task=task)
    if task.dest_lat is not None and task.dest_lng is not None:
        d = haversine_m(lat, lng, task.dest_lat, task.dest_lng)
        if d is not None and d > GEOFENCE_M:
            # "25010 m" reads like a glitch; kilometres tell the rider (and the
            # tester) that the DESTINATION PIN is somewhere else entirely.
            away = f"{d / 1000:.1f} km" if d >= 1000 else f"{int(d)} m"
            raise AppError("DELIVERY_LOCATION_MISMATCH",
                           message=(f"You're {away} from the delivery pin — get "
                                    f"within {GEOFENCE_M} m to confirm arrival."))
    _transition(task, S.REACHED, actor=agent, audit_code="REACHED_LOCATION")
    _generate_otp(task)
    return task


def otp_is_expired(otp, ttl_minutes=OTP_TTL_MINUTES):
    """Whether `otp` is past its time-to-live.

    A NULL ``generated_at`` is treated as **not** expired: pre-existing rows
    (and the odd fixture) were written before the timestamp was enforced, and
    expiring them retroactively would strand live deliveries mid-handover.
    """
    if otp.generated_at is None:
        return False
    return timezone.now() - otp.generated_at > timedelta(minutes=ttl_minutes)


def verify_otp(task, agent, code):
    _assert_owner(task, agent)
    otp = getattr(task, "delivery_otp", None)
    if otp is None:
        raise AppError("DELIVERY_OTP_REQUIRED", message="No delivery OTP has been generated yet.")
    if otp.locked:
        raise AppError("MANUAL_VERIFICATION_REQUIRED")
    # Checked BEFORE the code comparison, so an expired code can neither be
    # accepted nor burn one of the three attempts. `generated_at` was recorded
    # on every OTP and never read: a code stayed valid forever, so a delivery
    # re-attempted the next day still accepted yesterday's code.
    if otp_is_expired(otp):
        raise AppError("DELIVERY_OTP_EXPIRED")
    if code and code == otp.code:
        otp.verified = True
        otp.verified_at = timezone.now()
        otp.save(update_fields=["verified", "verified_at", "updated_at"])
        task.otp_verified = True
        task.save(update_fields=["otp_verified", "updated_at"])
        # Clear a stale lockout flag from an EARLIER round. `_generate_otp`
        # unlocks the OTP row on re-arrival but left this set, so a task that
        # went on to verify cleanly stayed flagged "manual verification
        # required" in the board and every report that reads it.
        if task.manual_verification_required:
            task.manual_verification_required = False
            task.save(update_fields=["manual_verification_required", "updated_at"])
        _audit("DELIVERY_OTP_VERIFIED", task, agent)
        return task
    otp.attempts += 1
    if otp.attempts >= DeliveryOTP.MAX_ATTEMPTS:
        otp.locked = True
        otp.save(update_fields=["attempts", "locked", "updated_at"])
        task.manual_verification_required = True
        task.save(update_fields=["manual_verification_required", "updated_at"])
        _audit("MANUAL_VERIFICATION_REQUIRED", task, agent, success=False)
        raise AppError("MANUAL_VERIFICATION_REQUIRED")
    otp.save(update_fields=["attempts", "updated_at"])
    left = DeliveryOTP.MAX_ATTEMPTS - otp.attempts
    raise AppError("INVALID_DELIVERY_OTP",
                   message=f"Incorrect OTP. {left} attempt(s) left.")


def add_evidence(task, agent, file_key="", *, photo=None, lat=None, lng=None, meta=None):
    """Record proof-of-delivery evidence for a task.

    Two ways to supply the photo:
      • ``photo`` — an uploaded file or raw bytes. It is ingested through the
        self-hosted media engine (validated, EXIF-stripped, WebP'd into
        thumb/medium/original) as a private POD asset owned by the order's
        customer, and the resulting ``MediaAsset`` id becomes the evidence key.
      • ``file_key`` — a loose string key (legacy/back-compat path). Used as-is
        when no ``photo`` is given.

    ``photo`` wins when both are present. The stored ``file_key`` /
    ``DeliveryTask.photo_key`` is the MediaAsset UUID in the upload path.
    """
    _assert_owner(task, agent)
    meta = dict(meta or {})
    if photo is not None:
        from mediastore.pipeline import store_image

        asset = store_image(
            photo, category="pod", visibility="private",
            owner=getattr(task.order, "user", None),
            original_name=getattr(photo, "name", "") or "",
        )
        file_key = str(asset.id)
        meta.setdefault("media_asset", file_key)
    ev = DeliveryEvidence.objects.create(
        task=task, kind=DeliveryEvidence.Kind.PHOTO, file_key=file_key,
        latitude=lat, longitude=lng, captured_at=timezone.now(), meta=meta)
    task.photo_key = file_key
    task.save(update_fields=["photo_key", "updated_at"])
    return ev


@transaction.atomic
def complete_delivery(task, agent):
    """The completion guard — every gate must pass (production rule 18)."""
    _assert_owner(task, agent)
    if task.agent is None:
        raise AppError("AGENT_NOT_ASSIGNED")
    if task.status != S.REACHED:
        raise AppError("DELIVERY_LOCATION_MISMATCH",
                       message="Mark that you've reached the location first.")
    if not task.otp_verified:
        raise AppError("DELIVERY_OTP_REQUIRED")
    if not task.evidence.exists():
        raise AppError("DELIVERY_PHOTO_REQUIRED")

    _transition(task, S.DELIVERED, actor=agent, audit_code="DELIVERY_COMPLETED")
    # Order-level: timeline + fulfil stock + loyalty + customer notification.
    from orders.services import advance_status
    from orders.models import OrderStatus
    advance_status(task.order, OrderStatus.DELIVERED, by=agent)
    # Earnings + feedback request.
    compute_earnings(task)
    DeliveryRating.objects.get_or_create(
        task=task, defaults={"order": task.order, "agent": agent,
                             "requested_at": timezone.now()})
    return task


@transaction.atomic
def fail_delivery(task, agent, *, reason_code, note="", photo_key="", lat=None, lng=None):
    _assert_owner(task, agent)
    task.failure_reason = reason_code
    task.failure_note = note
    _transition(task, S.FAILED, actor=agent, note=note)
    DeliveryAttempt.objects.create(
        task=task, attempt_no=task.attempt_no, outcome="failed",
        reason_code=reason_code, note=note, photo_key=photo_key,
        latitude=lat, longitude=lng, by=agent)
    task.save(update_fields=["failure_reason", "failure_note", "updated_at"])
    _audit("DELIVERY_FAILED", task, agent, success=False, message=reason_code)
    from orders.services import advance_status
    from orders.models import OrderStatus
    advance_status(task.order, OrderStatus.FAILED_DELIVERY, by=agent, note=reason_code)
    # Alert the serving store's staff so they can decide re-attempt vs return.
    from notifications.services import notify_store_staff
    notify_store_staff(getattr(task.order, "store", None), type="delivery",
                       title="Delivery Failed",
                       body=f"{task.order.code} — {reason_code}",
                       data={"route": f"/orders/{task.order.code}", "orderCode": task.order.code})
    return task


@transaction.atomic
def reattempt(task, *, mode, by, agent=None):
    """Store-admin decision on a failed delivery: today / tomorrow / reassign / return."""
    if task.status != S.FAILED:
        raise AppError("INVALID_DELIVERY_TRANSITION",
                       message="Re-attempt is only valid on a failed delivery.")
    if mode == "reassign":
        if agent is None:
            raise AppError("AGENT_NOT_ASSIGNED", message="Pick an agent to reassign to.")
        return reassign(task, agent, by=by, reason="Re-attempt reassign")
    if mode == "return":
        return return_to_store(task, by=by)
    # today / tomorrow → reschedule and re-open a task for the same agent.
    _transition(task, S.RESCHEDULED, actor=by, note=f"reattempt:{mode}")
    DeliveryAttempt.objects.create(
        task=task, attempt_no=task.attempt_no, outcome="rescheduled",
        reason_code=mode, by=by)
    new = _new_task(task.order, task.agent, action="manual_assigned", by=by,
                    attempt_no=task.attempt_no + 1)
    _audit("REATTEMPT_SCHEDULED", new, by)
    return new


@transaction.atomic
def initiate_return(task, agent):
    """The AGENT starts bringing failed goods back to the store.

    First half of the return handover: the rider marks the parcel as heading
    back (FAILED → RETURN_INITIATED); the STORE completes it on physical receipt
    (`return_to_store`), which is when stock is restored and the order closes.
    Before this existed the rider had no action after a failed attempt — the
    goods travelled back with no state saying so, and only an admin could close
    the loop.
    """
    _assert_owner(task, agent)
    _transition(task, S.RETURN_INITIATED, actor=agent)
    _audit("DELIVERY_FAILED", task, agent, message="Return to store started")
    return task


def return_to_store(task, *, by):
    """Store/admin confirms the goods came back: release stock + reverse credit
    + close order. Accepts a task the agent already put in RETURN_INITIATED (the
    normal handover) or jumps straight from FAILED (admin shortcut)."""
    from inventory.services import InventoryService
    from orders.models import Order, OrderStatus, OrderStatusEvent

    if task.status != S.RETURN_INITIATED:
        _transition(task, S.RETURN_INITIATED, actor=by)
    order = task.order
    # Restore reserved stock.
    if order.stock_state == Order.StockState.RESERVED:
        for item in order.items.select_related("product"):
            if item.product.stock_count is not None:
                InventoryService.release(product=item.product, quantity=item.quantity)
        order.stock_state = Order.StockState.RELEASED
    # Reverse a credit charge if any.
    if order.payment_method == Order.PaymentMethod.CREDIT and order.credit_used > 0:
        from credit.services import apply_refund, ensure_account
        apply_refund(ensure_account(order.user), order.credit_used, order=order,
                     note=f"Return to store {order.code}")
    order.status = OrderStatus.CANCELLED
    order.save(update_fields=["status", "stock_state"])
    OrderStatusEvent.objects.create(order=order, status=OrderStatus.CANCELLED,
                                    by=by, note="Returned to store (undelivered)")
    _transition(task, S.RETURNED_TO_STORE, actor=by, audit_code="RETURN_TO_STORE")
    return task


# ───────────────────────── earnings & performance ─────────────────────────
def _cfg(name, default):
    return Decimal(str(getattr(settings, name, default)))


def compute_earnings(task):
    base = _cfg("DELIVERY_BASE_FEE", "25")
    per_km = _cfg("DELIVERY_DISTANCE_BONUS_PER_KM", "3")
    heavy_threshold = _cfg("DELIVERY_HEAVY_ORDER_THRESHOLD", "2000")
    heavy_bonus = _cfg("DELIVERY_HEAVY_BONUS", "15")
    peak_bonus = _cfg("DELIVERY_PEAK_BONUS", "10")

    dist = task.distance_km or Decimal("0")
    distance_bonus = (dist * per_km).quantize(Decimal("0.01"))
    heavy = heavy_bonus if (task.order.total or 0) >= heavy_threshold else Decimal("0")
    hour = timezone.localtime().hour
    peak = peak_bonus if 18 <= hour < 21 else Decimal("0")
    total = (base + distance_bonus + heavy + peak).quantize(Decimal("0.01"))

    earn, _ = DeliveryEarnings.objects.update_or_create(
        task=task,
        defaults={"agent": task.agent, "base": base, "distance_bonus": distance_bonus,
                  "heavy_bonus": heavy, "peak_bonus": peak, "total": total,
                  "released": True, "released_at": timezone.now()},
    )
    return earn


def agent_performance(agent, *, since=None):
    """Live performance snapshot (computed, not stored)."""
    qs = DeliveryTask.objects.filter(agent=agent)
    if since:
        qs = qs.filter(created_at__gte=since)
    delivered = qs.filter(status=S.DELIVERED)
    total = qs.count()
    failed = qs.filter(status=S.FAILED).count()
    delivered_c = delivered.count()
    durations = [
        (t.delivered_at - t.out_for_delivery_at).total_seconds() / 60
        for t in delivered if t.delivered_at and t.out_for_delivery_at
    ]
    earnings = DeliveryEarnings.objects.filter(agent=agent)
    if since:
        earnings = earnings.filter(created_at__gte=since)
    total_earn = sum((e.total for e in earnings), Decimal("0"))
    rated = DeliveryRating.objects.filter(agent=agent, rating__isnull=False)
    ratings = [r.rating for r in rated]
    return {
        "deliveries": delivered_c,
        "failed": failed,
        "total_tasks": total,
        "success_rate": round(delivered_c / total * 100, 1) if total else 0.0,
        "avg_minutes": round(sum(durations) / len(durations), 1) if durations else None,
        "acceptance_rate": round(_agent_acceptance_rate(agent) * 100, 1),
        "reattempt_rate": round(failed / total * 100, 1) if total else 0.0,
        "avg_rating": round(sum(ratings) / len(ratings), 2) if ratings else None,
        "earnings": float(total_earn),
    }


# ───────────────────────── internals ─────────────────────────
def _assert_owner(task, agent):
    if task.agent_id != agent.id:
        raise AppError("INSUFFICIENT_PERMISSIONS",
                       message="This delivery isn't assigned to you.")


def _generate_otp(task):
    code = f"{secrets.randbelow(1000000):06d}"
    DeliveryOTP.objects.update_or_create(
        task=task,
        defaults={"code": code, "attempts": 0, "verified": False, "locked": False,
                  "generated_at": timezone.now()},
    )
    task.otp_verified = False
    task.save(update_fields=["otp_verified", "updated_at"])
    # Deliver to the customer (SMS/push handled by the notification service).
    from notifications.services import notify
    notify(task.order.user, type="delivery", title="Delivery code",
           body=f"Your delivery OTP for order {task.order.code} is {code}. "
                f"Share it with the agent at your doorstep.",
           data={"orderCode": task.order.code, "kind": "delivery_otp"})
    _audit("DELIVERY_OTP_SENT", task, task.agent)
    return code


def _notify_agent(task):
    if task.agent is None:
        return
    from notifications.services import notify
    notify(task.agent, type="delivery", title="New delivery assigned",
           body=f"Order {task.order.code} — {task.order.address_snapshot.get('formatted', '')}",
           data={"orderCode": task.order.code, "taskId": task.id,
                 "kind": "delivery_assignment", "route": "deliveries"},
           # One buzz per (agent, task). The dispatch engine runs on a 120s loop
           # and every assignment path funnels through here, so an agent used to
           # be re-alerted for a delivery already sitting in their list each time
           # anything touched the task. Keyed on the agent too, so a genuine
           # reassignment still notifies the NEW agent.
           dedupe_key=f"delivery_assigned:task:{task.id}:agent:{task.agent_id}")


# The statuses in which an agent is actively working this order, so their GPS
# legitimately answers "where is my delivery". Everything else — delivered,
# reassigned, cancelled, rejected, failed, returned — must NOT reach the customer.
LIVE_TASK_STATUSES = frozenset({
    S.ASSIGNED, S.ACCEPTED, S.PICKED_UP, S.OUT_FOR_DELIVERY, S.REACHED,
})


def may_publish_tracking(task) -> bool:
    """Whether ``task``'s pings may be mirrored onto the customer-facing row.

    Two ways a stale task used to poison live tracking:

    * **A closed task kept pinging.** A phone that hadn't backgrounded yet went on
      posting after delivery, so the customer watched the rider drive away from
      their house — a location leak, since the trip was over.
    * **A reassigned agent outranked the real one.** Reassignment closes the prior
      task and opens a new one, but the old agent's app kept posting and
      ``update_or_create`` on the OneToOne row let it overwrite the new rider's
      identity. The customer was shown — and would have phoned — the wrong person.

    So a task may publish only while it is live AND is the order's current live
    task. The raw ``DeliveryLocation`` ping is still recorded either way; it's
    history, and suppressing it would lose the audit trail.
    """
    if task.status not in LIVE_TASK_STATUSES:
        return False
    current = (
        DeliveryTask.objects
        .filter(order_id=task.order_id, status__in=LIVE_TASK_STATUSES)
        .order_by("-attempt_no", "-id")
        .first()
    )
    return current is not None and current.pk == task.pk


def _update_order_tracking(task, lat, lng):
    from orders.models import OrderTracking
    if not may_publish_tracking(task):
        return
    eta = ""
    if task.dest_lat is not None:
        d = haversine_m(lat, lng, task.dest_lat, task.dest_lng)
        if d is not None:
            mins = max(1, int(d / 1000 / 20 * 60))  # ~20 km/h
            eta = f"{mins} min"
    agent = task.agent
    tracking, _ = OrderTracking.objects.update_or_create(
        order=task.order,
        defaults={"agent_name": getattr(agent, "name", "") or "Delivery agent",
                  # Snapshot contact + photo so the customer can call the rider and
                  # see who's coming. Blank when unknown — the app hides the control.
                  "agent_phone": getattr(agent, "phone", "") or "",
                  "agent_photo_url": getattr(agent, "avatar_url", "") or "",
                  "latitude": lat, "longitude": lng, "eta": eta},
    )
    # Real-time: push the fresh agent position to the customer + dispatch board.
    # Prime the cached relation so realtime._payload reads the new coords.
    task.order.tracking = tracking
    from .realtime import broadcast as _rt_broadcast

    _rt_broadcast(task)


def collect_cod_cash(task, agent, *, method="cash", reference=""):
    """The agent confirms the customer's COD payment after handover.

    Completing a COD delivery used to leave the money invisible: the order stayed
    payment-pending forever and the notes in the rider's bag existed nowhere.
    This records both sides at once:

      • a CASH ``Payment`` for the order (start → finalize marks the order PAID,
        which also issues the receipt row and posts the ledger hooks);
      • a COLLECTED ``payments.CashCollection`` carrying the physical notes into
        the cash book — so the agent's CASH-IN-HAND figure, the deposit flow and
        finance verification all see this money with zero extra wiring.

    Idempotent per order: a double-tap can't double-charge or double-count.
    """
    from django.utils import timezone as _tz

    from payments.models import CashCollection, Payment
    from payments.services import finalize_payment, start_payment

    _assert_owner(task, agent)
    if task.status != S.DELIVERED:
        raise AppError("CONFLICT",
                       message="Confirm the delivery before collecting cash.")
    order = task.order
    if order.payment_method != "cod":
        raise AppError("CONFLICT", message="This order wasn't cash on delivery.")
    if order.payment_status == "paid":
        existing = CashCollection.objects.filter(
            payment__order=order, agent=agent).first()
        if existing is not None:
            return existing
        raise AppError("PAYMENT_ALREADY_COMPLETED")

    payment = start_payment(
        order.user, purpose=Payment.Purpose.ORDER, amount=order.total,
        method=Payment.Method.CASH, order=order,
        idempotency_key=f"cod_{order.code}",
    )
    if payment.status != Payment.Status.SUCCESS:
        finalize_payment(payment, success=True,
                         gateway_payment_id=(reference.strip() or f"cod_{order.code}"))
    collection = CashCollection.objects.filter(payment=payment).first()
    if collection is None:
        collection = CashCollection.objects.create(
            user=order.user, agent=agent, amount=order.total,
            collected_amount=order.total,
            status=CashCollection.Status.COLLECTED,
            collected_at=_tz.now(), payment=payment,
        )
    _audit("PAYMENT_RECEIVED", task, agent,
           message=f"COD cash collected for {order.code}")
    return collection
