"""Delivery Control Center (admin) — dashboard KPIs, the delivery queue (filters),
per-agent load, and reassign / mark-status actions. Built on DeliveryTask + Order.
"""
from django.db.models import Count, Q
from django.utils import timezone

from .models import DeliveryTask

# Derived from the model so these can't drift from the state machine again.
# The old hand-written list was ["pending", "accepted", "started"] — "pending"
# and "started" are not DeliveryTask.Status members at all, so every rider who
# had picked up (picked_up / out_for_delivery / reached) counted as 0 active and
# looked free to the dispatcher.
ACTIVE = [s for s in DeliveryTask.Status.values if s not in DeliveryTask.TERMINAL]
TERMINAL = sorted(DeliveryTask.TERMINAL)


def _f(v):
    return float(v) if v is not None else None


def _haversine_km(a, b, c, d):
    import math

    r = 6371.0
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return r * 2 * math.asin(math.sqrt(h))


def _distance(order):
    store = order.store
    if not (store and store.latitude and store.longitude and order.user):
        return None
    a = order.user.addresses.filter(latitude__isnull=False, longitude__isnull=False).first()
    if not a:
        return None
    return round(_haversine_km(float(store.latitude), float(store.longitude),
                               float(a.latitude), float(a.longitude)), 1)


# ── Dashboard ────────────────────────────────────────────
def delivery_dashboard() -> dict:
    from agents.services import attendance_today

    today = timezone.localdate()
    qs = DeliveryTask.objects.all()
    delivered = qs.filter(status="delivered", delivered_at__date=today)

    # Average delivery time (started → delivered), minutes.
    spans = (
        qs.filter(status="delivered")
        .exclude(started_at__isnull=True).exclude(delivered_at__isnull=True)
        .values_list("started_at", "delivered_at")[:2000]
    )
    mins = [(d - s).total_seconds() / 60 for s, d in spans if d and s and d > s]
    avg_min = round(sum(mins) / len(mins), 1) if mins else 0.0

    # On-time: delivered on/before the order's estimated_delivery.
    ontime = late = 0
    for t in delivered.select_related("order"):
        eta = t.order.estimated_delivery if t.order else None
        if eta and t.delivered_at:
            if t.delivered_at <= eta:
                ontime += 1
            else:
                late += 1
    total_ot = ontime + late
    return {
        "activeDeliveries": qs.filter(status__in=ACTIVE).count(),
        "pendingAcceptance": qs.filter(status="pending").count(),
        "outForDelivery": qs.filter(status="started").count(),
        "deliveredToday": delivered.count(),
        "failedToday": qs.filter(status__in=["failed", "rejected"], updated_at__date=today).count(),
        "agentsOnDuty": sum(1 for a in attendance_today() if a.on_duty),
        "avgDeliveryMinutes": avg_min,
        "onTimeRate": round(ontime / total_ot * 100, 1) if total_ot else 0.0,
    }


# ── Queue / list ─────────────────────────────────────────
def _row(t):
    o = t.order
    addr = (o.address_snapshot or {}) if o else {}
    return {
        "id": t.id,
        "orderCode": o.code if o else None,
        "customer": (o.user.name or o.user.phone) if o and o.user else addr.get("name"),
        "phone": (o.user.phone if o and o.user else addr.get("phone")),
        "address": addr.get("formatted"),
        "store": o.store.name if o and o.store else None,
        "zone": o.zone.name if o and o.zone else None,
        "agent": t.agent.name if t.agent else None,
        "agentId": str(t.agent_id) if t.agent_id else None,
        "status": t.status,
        "assignedAt": t.created_at,
        "startedAt": t.started_at,
        "deliveredAt": t.delivered_at,
        "distanceKm": _distance(o) if o else None,
    }


def delivery_list(params, limit=200):
    p = params or {}
    qs = DeliveryTask.objects.select_related(
        "order", "order__user", "order__store", "order__zone", "agent"
    )
    status = p.get("status")
    if status == "active":
        qs = qs.filter(status__in=ACTIVE)
    elif status == "failed":
        qs = qs.filter(status__in=["failed", "rejected"])
    elif status:
        qs = qs.filter(status=status)
    if p.get("agent"):
        qs = qs.filter(agent_id=p["agent"])
    if p.get("store"):
        qs = qs.filter(order__store_id=p["store"])
    if p.get("zone"):
        qs = qs.filter(order__zone_id=p["zone"])
    if p.get("date_from"):
        qs = qs.filter(created_at__date__gte=p["date_from"])
    if p.get("date_to"):
        qs = qs.filter(created_at__date__lte=p["date_to"])
    return [_row(t) for t in qs.order_by("-created_at")[:limit]]


def agent_load(store=None):
    """Per-agent live delivery load (active count + completed today).

    Pass ``store`` for a store panel: agents are store-owned
    (``AgentProfile.store``), and this list is what a store's reassign pickers
    (delivery + collections) are populated from. Unscoped, it returned every
    agent on the platform, so a store could hand its delivery or collection to
    another store's rider — the task then vanishes from the owning store's board
    and lands with somebody who physically can't do it. Eligibility mirrors
    ``agents.candidates.candidate_agents``: that store's agents, else the
    store-less legacy pool.

    Unlike ``candidate_agents`` this does NOT filter to on-duty — a human
    picking a name may deliberately choose someone starting their shift — but
    every row carries ``onDuty`` so the UI can say so. Inactive (deactivated)
    accounts are always excluded; they can never work a task.
    """
    from accounts.models import Role, User
    from agents.candidates import assignable_agents
    from agents.services import attendance_today

    today = timezone.localdate()
    on_duty = {a.agent_id for a in attendance_today() if a.on_duty}
    rows = []
    agg = (
        DeliveryTask.objects.values("agent_id")
        .annotate(
            active=Count("id", filter=Q(status__in=ACTIVE)),
            delivered=Count("id", filter=Q(status="delivered", delivered_at__date=today)),
        )
    )
    by_agent = {a["agent_id"]: a for a in agg}
    candidates = (
        assignable_agents(store) if store is not None
        else list(User.objects.filter(role=Role.AGENT, is_active=True))
    )
    for u in candidates:
        a = by_agent.get(u.id, {})
        rows.append({
            "id": str(u.id), "name": u.name or u.phone,
            "onDuty": u.id in on_duty,
            "active": a.get("active", 0),
            "deliveredToday": a.get("delivered", 0),
        })
    rows.sort(key=lambda r: (r["onDuty"], r["active"]), reverse=True)
    return rows


# ── Actions ──────────────────────────────────────────────
def reassign(task, agent):
    task.agent = agent
    if task.status in ("rejected", "failed"):
        task.status = "accepted"
    task.save(update_fields=["agent", "status", "updated_at"])
    # Keep the order's DeliveryAssignment in sync.
    from orders.models import DeliveryAssignment

    if task.order_id:
        da, _ = DeliveryAssignment.objects.get_or_create(order=task.order)
        da.agent = agent
        da.save(update_fields=["agent"])
    return task


def set_status(task, status, by=None):
    from core.app_errors import AppError
    from orders.services import advance_status

    # DELIVERED IS FINAL — everywhere. This panel path wrote task.status raw,
    # so a store user could flip a delivered task back to any earlier state
    # (and with it, un-deliver the order). Nothing leaves a terminal state from
    # any panel; corrections go through returns/refunds, not status edits.
    if task.status in task.TERMINAL or task.status == "delivered":
        raise AppError(
            "CONFLICT",
            message=(f"This delivery is already {task.status} and can no "
                     "longer be changed."),
        )
    # "delivered" only means something once the agent has proved it — reached
    # the location, verified the OTP, attached a photo
    # (delivery.services.complete_delivery). This panel used to write it raw,
    # which — now that delivery is what triggers the credit-ledger debit and
    # stock fulfilment (see orders.services.advance_status) — would let staff
    # charge a customer and release stock for a delivery nobody proved
    # happened. There is no admin-panel override for this; a genuinely stuck
    # OTP lockout goes through Manual Verify, not a raw status write.
    if status == "delivered":
        raise AppError(
            "VALIDATION_ERROR",
            message=(
                "Delivery can only be completed by the assigned agent's own "
                "OTP + photo verification, not from this panel."
            ),
        )

    task.status = status
    fields = ["status", "updated_at"]
    task.save(update_fields=fields)
    # Sync the order lifecycle.
    if task.order_id:
        if status == "failed":
            advance_status(task.order, "failed_delivery", by=by, note="Delivery failed")
        elif status == "started":
            advance_status(task.order, "out_for_delivery", by=by, note="Out for delivery")
    return task
