"""Agent attendance + the Live Operations feed.

Aggregates live geo (latest agent location pings), active deliveries/collections,
and on-duty attendance into one admin payload — the data behind the dashboard's
Live Operations panel. Derived live from source modules; nothing cached.
"""
from datetime import timedelta

from django.utils import timezone

# An agent is "online" if they pinged a location within this window.
ONLINE_WINDOW_MIN = 15


def check_in(agent):
    from .models import AgentAttendance

    today = timezone.localdate()
    att, _ = AgentAttendance.objects.get_or_create(agent=agent, date=today)
    if att.check_in_at is None:
        att.check_in_at = timezone.now()
    att.check_out_at = None
    att.save(update_fields=["check_in_at", "check_out_at", "updated_at"])
    return att


def check_out(agent):
    from .models import AgentAttendance

    today = timezone.localdate()
    att, _ = AgentAttendance.objects.get_or_create(agent=agent, date=today)
    att.check_out_at = timezone.now()
    att.save(update_fields=["check_out_at", "updated_at"])
    return att


def attendance_today():
    from .models import AgentAttendance

    return AgentAttendance.objects.filter(date=timezone.localdate()).select_related("agent")


def _f(v):
    return float(v) if v is not None else None


def live_operations() -> dict:
    """The Live Operations payload: agent live positions + on-duty status, active
    deliveries, active collections, and headline counts."""
    from accounts.models import Role, User
    from delivery.models import DeliveryLocation, DeliveryTask
    from orders.models import Order
    from payments.models import CashCollection

    now = timezone.now()
    online_since = now - timedelta(minutes=ONLINE_WINDOW_MIN)

    on_duty_ids = set(
        a.agent_id for a in attendance_today() if a.on_duty
    )
    active_deliveries = (
        DeliveryTask.objects.exclude(status__in=["delivered", "failed", "rejected"])
        .select_related("agent", "order")
    )
    deliveries_by_agent = {}
    for d in active_deliveries:
        deliveries_by_agent.setdefault(d.agent_id, 0)
        deliveries_by_agent[d.agent_id] += 1

    agents = []
    online_now = 0
    for u in User.objects.filter(role=Role.AGENT):
        loc = DeliveryLocation.objects.filter(agent=u).order_by("-at").first()
        online = bool(loc and loc.at >= online_since)
        if online:
            online_now += 1
        agents.append({
            "id": str(u.id),
            "name": u.name or u.phone,
            "onDuty": u.id in on_duty_ids,
            "online": online,
            "lastSeenAt": loc.at if loc else None,
            "lat": _f(loc.latitude) if loc else None,
            "lng": _f(loc.longitude) if loc else None,
            "activeDeliveries": deliveries_by_agent.get(u.id, 0),
        })
    agents.sort(key=lambda a: (a["onDuty"], a["online"], a["activeDeliveries"]), reverse=True)

    # Latest known location per agent (for placing deliveries on the map).
    last_loc = {}
    for a in agents:
        if a["lat"] is not None:
            last_loc[a["id"]] = (a["lat"], a["lng"])

    deliveries = []
    for d in active_deliveries[:100]:
        pos = last_loc.get(str(d.agent_id))
        deliveries.append({
            "orderCode": d.order.code if d.order else None,
            "agent": d.agent.name if d.agent else None,
            "status": d.status,
            "lat": pos[0] if pos else None,
            "lng": pos[1] if pos else None,
        })

    active_collections = (
        CashCollection.objects.filter(status__in=["requested", "assigned"])
        .select_related("user", "agent")[:100]
    )
    collections = [
        {
            "customer": c.user.name or c.user.phone,
            "agent": c.agent.name if c.agent else None,
            "amount": float(c.amount),
            "status": c.status,
        }
        for c in active_collections
    ]

    return {
        "summary": {
            "agentsOnDuty": len(on_duty_ids),
            "totalAgents": User.objects.filter(role=Role.AGENT).count(),
            "agentsOnline": online_now,
            "activeDeliveries": active_deliveries.count(),
            "activeCollections": len(collections),
            "ordersOutForDelivery": Order.objects.filter(status="out_for_delivery").count(),
        },
        "agents": agents,
        "deliveries": deliveries,
        "collections": collections,
        "asOf": now,
    }


def store_live_operations(store) -> dict:
    """Live-duty payload scoped to ONE store's own roster — its agents' live position,
    on-duty state, and active load. The store panel had only a static roster; this is
    the store-level equivalent of the admin's platform-wide live board, restricted to
    the agents this store hired (``AgentProfile.store``)."""
    from accounts.models import Role, User
    from delivery.models import DeliveryLocation, DeliveryTask

    now = timezone.now()
    online_since = now - timedelta(minutes=ONLINE_WINDOW_MIN)
    roster = list(
        User.objects.filter(role=Role.AGENT, agent_profile__store=store)
        .select_related("agent_profile")
    )
    ids = {u.id for u in roster}
    on_duty_ids = {a.agent_id for a in attendance_today() if a.on_duty and a.agent_id in ids}

    active = (
        DeliveryTask.objects.filter(agent_id__in=ids)
        .exclude(status__in=["delivered", "failed", "rejected"])
    )
    load = {}
    for d in active:
        load[d.agent_id] = load.get(d.agent_id, 0) + 1

    agents, online_now = [], 0
    for u in roster:
        loc = DeliveryLocation.objects.filter(agent=u).order_by("-at").first()
        online = bool(loc and loc.at >= online_since)
        if online:
            online_now += 1
        prof = getattr(u, "agent_profile", None)
        agents.append({
            "id": str(u.id),
            "name": u.name or u.phone,
            "phone": u.phone,
            "vehicle": getattr(prof, "vehicle_type", None),
            "onDuty": u.id in on_duty_ids,
            "online": online,
            "lastSeenAt": loc.at if loc else None,
            "lat": _f(loc.latitude) if loc else None,
            "lng": _f(loc.longitude) if loc else None,
            "activeDeliveries": load.get(u.id, 0),
        })
    agents.sort(key=lambda a: (a["onDuty"], a["online"], a["activeDeliveries"]), reverse=True)

    return {
        "summary": {
            "totalAgents": len(roster),
            "agentsOnDuty": len(on_duty_ids),
            "agentsOnline": online_now,
            "activeDeliveries": active.count(),
        },
        "agents": agents,
        "asOf": now,
    }
