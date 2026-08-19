"""Blinkit/Zepto-style assignment engine.

Turns a store's pool of ready orders (+ pending collections) into capacity-bounded,
route-optimized **batches** and assigns each to the best-scoring available agent —
instead of handing agents random single tasks.

Pipeline: gather → cluster (proximity + caps) → sequence stops → merge on-route
collections → score agents (distance 40 / load 20 / deadline 15 / traffic 10 /
collections 10 / rating 5) → atomic dispatch + broadcast. Priority order is
express → perishable → medicine → normal → collections.

Geometry is haversine-based (deterministic, works with no external calls, so tests
run offline); the Google Routes polyline + ETA are a best-effort enhancement.
"""
from decimal import Decimal

from django.db import transaction
from django.utils import timezone


from .models import BatchStop, DeliveryAssignmentHistory, DeliveryBatch, DeliveryTask
from .services import (
    _agent_active_load,
    _agent_last_location,
    _audit,
    _notify_agent,
    _seed_tracking_identity,
    haversine_m,
)

# Global clustering caps (per-agent caps are enforced at assignment time).
MAX_ORDERS = 5
MAX_WEIGHT_KG = 20.0
MAX_LINK_KM = 2.5           # a new order must be within this of an existing stop
MERGE_COLLECTION_KM = 1.5   # a pending collection joins a batch within this of a stop
UNIT_WEIGHT_KG = 0.5        # no per-product weight yet → approximate per unit
PRIORITY_RANK = {"express": 0, "perishable": 1, "medicine": 2, "normal": 3}
S = DeliveryTask.Status


# ── small helpers ───────────────────────────────────────────
def _f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _order_point(order):
    snap = order.address_snapshot or {}
    return _f(snap.get("latitude") or snap.get("lat")), _f(snap.get("longitude") or snap.get("lng"))


def _order_weight(order):
    units = sum(i.quantity for i in order.items.all()) or 1
    return units * UNIT_WEIGHT_KG


def _order_priority(order):
    slot = (order.delivery_slot or "").lower()
    if "express" in slot or "instant" in slot:
        return "express"
    return "normal"


def _km(a, b):
    if not a or not b or a[0] is None or b[0] is None:
        return None
    m = haversine_m(a[0], a[1], b[0], b[1])
    return (m / 1000.0) if m is not None else None


def _store_point(store):
    return _f(store.latitude), _f(store.longitude)


def _profile(agent):
    return getattr(agent, "agent_profile", None)


# ── gathering ───────────────────────────────────────────────
def _ready_orders(store):
    """Orders parked at the store awaiting a rider, not already on a batch/task."""
    from orders.models import Order

    qs = (
        Order.objects.filter(store=store, status="ready_for_dispatch")
        .exclude(delivery_tasks__status__in=[S.ASSIGNED, S.ACCEPTED, S.PICKED_UP, S.OUT_FOR_DELIVERY])
        .prefetch_related("items")
        .distinct()
    )
    out = []
    for o in qs:
        pt = _order_point(o)
        if pt[0] is not None:
            out.append(o)
    return out


def _pending_collections(store):
    """Un-assigned cash collections for this store's customers, to fold into
    delivery routes."""
    from payments.models import CashCollection
    from storeops.views import _store_customer_ids

    cust_ids = _store_customer_ids(store)
    return list(
        CashCollection.objects.filter(user_id__in=cust_ids, status="requested")
        .select_related("user")
    )


def _available_agents(store):
    """On-duty agents THIS STORE may dispatch to.

    `store` was accepted and then ignored, so the engine pooled every active
    agent on the platform and a store could batch its orders onto another
    store's rider. Routes through the shared, store-scoped pool that collections
    and returns-pickup already use, which keeps the legacy-parity rule that an
    agent with no AgentProfile stays eligible (`_score` defaults every
    profile-derived factor, so unprofiled agents rank fine).
    """
    from agents.candidates import candidate_agents

    return candidate_agents(store=store)


# ── clustering + sequencing ─────────────────────────────────
def _cluster(orders):
    """Greedy geographic clustering into capacity-bounded groups. Orders are seeded
    by priority then distance to the first seed, and linked in while within
    MAX_LINK_KM of the growing cluster and under the order/weight caps."""
    pool = sorted(orders, key=lambda o: (PRIORITY_RANK.get(_order_priority(o), 3),))
    clusters = []
    used = set()
    for seed in pool:
        if seed.id in used:
            continue
        cluster = [seed]
        used.add(seed.id)
        weight = _order_weight(seed)
        grew = True
        while grew and len(cluster) < MAX_ORDERS:
            grew = False
            best, best_d = None, None
            for o in pool:
                if o.id in used:
                    continue
                w = _order_weight(o)
                if weight + w > MAX_WEIGHT_KG:
                    continue
                d = min((_km(_order_point(o), _order_point(c)) or 9e9) for c in cluster)
                if d <= MAX_LINK_KM and (best_d is None or d < best_d):
                    best, best_d = o, d
            if best is not None:
                cluster.append(best)
                used.add(best.id)
                weight += _order_weight(best)
                grew = True
        clusters.append(cluster)
    return clusters


def _sequence(store, orders):
    """Nearest-neighbour visit order starting from the store."""
    remaining = list(orders)
    seq = []
    cur = _store_point(store)
    while remaining:
        remaining.sort(key=lambda o: (_km(cur, _order_point(o)) or 9e9))
        nxt = remaining.pop(0)
        seq.append(nxt)
        cur = _order_point(nxt)
    return seq


def _merge_collections(sequenced_orders, collections):
    """Attach pending collections whose customer sits near the route. Mutates
    `collections` (removes merged). Returns list of (collection, point)."""
    from addresses.models import Address

    merged = []
    stop_points = [_order_point(o) for o in sequenced_orders]
    for coll in list(collections):
        addr = (
            Address.objects.filter(user_id=coll.user_id, is_default=True).first()
            or Address.objects.filter(user_id=coll.user_id).first()
        )
        if not addr or addr.latitude is None:
            continue
        cp = (_f(addr.latitude), _f(addr.longitude))
        if any((_km(cp, sp) or 9e9) <= MERGE_COLLECTION_KM for sp in stop_points):
            merged.append((coll, cp))
            collections.remove(coll)
    return merged


# ── scoring ─────────────────────────────────────────────────
def _fits(agent, n_deliveries, n_stops, weight, collections_amount):
    p = _profile(agent)
    if not p:
        return n_deliveries <= MAX_ORDERS  # unprofiled agent → default cap
    return (
        n_deliveries <= p.bag_capacity
        and n_stops <= p.max_stops
        and weight <= p.weight_capacity_kg
        and collections_amount <= float(p.cash_capacity)
    )


def _score(agent, first_point, collections_amount):
    p = _profile(agent)
    lat, lng = _agent_last_location(agent)
    apt = (_f(lat), _f(lng))
    d = _km(apt, first_point)
    dist_score = 1 - min((d if d is not None else 5.0) / 8.0, 1.0)
    max_stops = p.max_stops if p else MAX_ORDERS
    load_score = 1 - min(_agent_active_load(agent) / max(max_stops, 1), 1.0)
    deadline_score = 0.7  # no SLA windows yet
    traffic_score = 0.6   # no live-traffic feed yet
    cash_cap = float(p.cash_capacity) if p else 10000.0
    coll_score = 1.0 if collections_amount <= cash_cap else 0.3
    rating_score = (float(p.rating) / 5.0) if p else 1.0
    return round(
        0.40 * dist_score + 0.20 * load_score + 0.15 * deadline_score
        + 0.10 * traffic_score + 0.10 * coll_score + 0.05 * rating_score,
        4,
    )


def _best_agent(agents, seq, merged):
    """Prefer an agent who's currently FREE (no active delivery/collection/
    verification anywhere), scored as before by distance/load/rating. Only
    when no free agent fits does this fall back to busy agents — picked by
    whoever's current workload will clear soonest, not by route score, since
    minimizing this task's wait matters more than route optimality once
    every agent is already working."""
    from agents.dispatch import rank_for_new_task

    n_deliveries = len(seq)
    n_stops = n_deliveries + len(merged)
    weight = sum(_order_weight(o) for o in seq)
    coll_amt = float(sum((c.amount or 0) for c, _ in merged))
    first_pt = _order_point(seq[0]) if seq else None

    free, busy_by_soonest = rank_for_new_task(agents)

    best, best_score = None, -1
    for a in free:
        if not _fits(a, n_deliveries, n_stops, weight, coll_amt):
            continue
        s = _score(a, first_pt, coll_amt)
        if s > best_score:
            best, best_score = a, s
    if best is not None:
        return best, best_score

    for a in busy_by_soonest:
        if _fits(a, n_deliveries, n_stops, weight, coll_amt):
            return a, _score(a, first_pt, coll_amt)
    return None, None


# ── persistence + dispatch ──────────────────────────────────
def _pickup_code(batch_id):
    # Deterministic-ish 6-digit handoff code (no crypto dep in this path).
    return f"{(batch_id * 7919) % 1000000:06d}"


@transaction.atomic
def _persist_batch(store, agent, seq, merged, *, score, route, by=None):
    priority = "express" if any(_order_priority(o) == "express" for o in seq) else "normal"
    batch = DeliveryBatch.objects.create(
        store=store, agent=agent,
        status=DeliveryBatch.Status.ASSIGNED,
        score=Decimal(str(score)) if score is not None else None,
        priority=priority,
        assigned_at=timezone.now(), created_by=by,
    )
    batch.pickup_code = _pickup_code(batch.id)
    if route:
        batch.encoded_polyline = route.get("encodedPolyline", "")
        batch.total_distance_km = Decimal(str(round((route.get("distanceMeters") or 0) / 1000.0, 2)))
        batch.estimated_duration_secs = route.get("durationSeconds") or 0
    batch.save(update_fields=["pickup_code", "encoded_polyline",
                              "total_distance_km", "estimated_duration_secs"])

    seqno = 0
    for order in seq:
        seqno += 1
        dlat, dlng = _order_point(order)
        task = DeliveryTask.objects.create(
            order=order, agent=agent, status=S.ASSIGNED, batch=batch,
            dest_lat=dlat, dest_lng=dlng, assigned_at=timezone.now(),
        )
        # Same linkage the single-task path writes — without these, a batch
        # assignment left no assignment history (acceptance metrics counted the
        # offer as never made), no audit row, and no rider identity on the
        # customer's tracking card until the first GPS ping.
        DeliveryAssignmentHistory.objects.create(
            task=task, agent=agent, action="auto_assigned", by=by,
            score=Decimal(str(score)) if score is not None else None,
            reason="batch",
        )
        _audit("DELIVERY_ASSIGNED", task, by or agent)
        _seed_tracking_identity(task)
        BatchStop.objects.create(
            batch=batch, sequence=seqno, kind=BatchStop.Kind.DELIVERY, task=task,
            label=(order.user.name if order.user else order.code) or order.code,
            latitude=dlat, longitude=dlng, status=BatchStop.Status.PENDING,
        )
    for coll, cp in merged:
        seqno += 1
        # Route the assignment through the collections engine rather than
        # writing `agent`/`status` straight to the row: the direct write skipped
        # `assigned_at`, the CollectionAssignmentHistory row and the audit entry,
        # so a batch-merged collection had no assignment trail at all and the
        # store couldn't tell who it went to or when.
        from cashcollections.services import manual_assign

        try:
            manual_assign(coll, agent, by=by, reason="batch")
        except Exception:  # noqa: BLE001 — never lose the batch over one stop
            coll.agent = agent
            if coll.status == "requested":
                coll.status = "assigned"
            coll.save(update_fields=["agent", "status"])
        BatchStop.objects.create(
            batch=batch, sequence=seqno, kind=BatchStop.Kind.COLLECTION, collection=coll,
            label=(coll.user.name if coll.user else "Collection"),
            latitude=cp[0], longitude=cp[1], amount=coll.amount or 0,
            status=BatchStop.Status.PENDING,
        )
    _broadcast_batch(batch)
    # Notify the agent once for the batch (reuse the per-task notifier on the
    # first task) — but a batch made up ONLY of collection stops has no
    # DeliveryTask at all, so `first_task` is None and the agent silently got
    # no notification whatsoever for it. Fall back to a generic batch alert.
    first_task = batch.tasks.first()
    try:
        if first_task:
            _notify_agent(first_task)
        elif merged:
            from notifications.services import notify

            notify(agent, type="collection", title="New collections assigned",
                  body=f"{len(merged)} collection{'s' if len(merged) != 1 else ''} assigned to you.",
                  data={"batchId": batch.id, "kind": "collection_batch", "route": "collections"})
    except Exception:
        pass
    return batch


def _broadcast_event(kind, batch, **extra):
    try:
        from core.events import record_event

        record_event("dispatch", {
            "type": kind, "batch": batch.id,
            "agent": batch.agent_id, "store": batch.store_id, **extra,
        })
    except Exception:
        pass


def _broadcast_batch(batch):
    _broadcast_event("batch_assigned", batch, stops=batch.stops.count())


# ── entry points ────────────────────────────────────────────
def run_auto_assign(store, *, by=None, exclude_agent_ids=None):
    """Plan + assign as many batches as agents can take. Orders that no available
    agent can fit are left in the queue (reported as `queued`). `exclude_agent_ids`
    skips agents (e.g. the one who just rejected a batch)."""
    from system import maps_client

    orders = _ready_orders(store)
    result = {"orders": len(orders), "batches": 0, "assigned": 0, "queued": 0}
    if not orders:
        return result
    clusters = _cluster(orders)
    collections = _pending_collections(store)
    agents = _available_agents(store)
    if exclude_agent_ids:
        skip = set(exclude_agent_ids)
        agents = [a for a in agents if a.id not in skip]
    used = set()
    for cluster in clusters:
        seq = _sequence(store, cluster)
        merged = _merge_collections(seq, collections)
        pool = [a for a in agents if a.id not in used]
        agent, score = _best_agent(pool, seq, merged)
        if not agent:
            result["queued"] += len(seq)
            continue
        pts = [_store_point(store)] + [_order_point(o) for o in seq] + [cp for _, cp in merged]
        route = maps_client.route_multi([p for p in pts if p[0] is not None])
        _persist_batch(store, agent, seq, merged, score=score, route=route, by=by)
        used.add(agent.id)
        result["batches"] += 1
        result["assigned"] += 1
    return result


@transaction.atomic
def create_manual_batch(store, order_ids, agent, *, collection_ids=None, by=None):
    """Store hand-picks orders (+ optional collections) for a specific agent. Route
    is still optimized. Raises ValueError on empty/invalid input."""
    from orders.models import Order
    from payments.models import CashCollection
    from system import maps_client

    orders = list(
        Order.objects.filter(code__in=order_ids, store=store, status="ready_for_dispatch")
        .prefetch_related("items")
    )
    if not orders:
        raise ValueError("No eligible orders selected.")
    seq = _sequence(store, orders)
    merged = []
    if collection_ids:
        from addresses.models import Address

        for coll in CashCollection.objects.filter(id__in=collection_ids):
            addr = (
                Address.objects.filter(user_id=coll.user_id, is_default=True).first()
                or Address.objects.filter(user_id=coll.user_id).first()
            )
            cp = (_f(addr.latitude), _f(addr.longitude)) if addr else (None, None)
            merged.append((coll, cp))
    pts = [_store_point(store)] + [_order_point(o) for o in seq] + [cp for _, cp in merged if cp[0] is not None]
    route = maps_client.route_multi([p for p in pts if p[0] is not None])
    return _persist_batch(store, agent, seq, merged, score=None, route=route, by=by)


# ── real-time reassignment ──────────────────────────────────
@transaction.atomic
def release_batch(batch, *, reason="", by=None):
    """Return a batch's UNFINISHED stops to the queue and close the batch. Already
    delivered/collected stops keep their outcome; everything else is reopened —
    orders back to `ready_for_dispatch`, collections back to `requested` — so the
    next engine pass (or an immediate reassign) can re-plan them onto other agents.
    Safe to call on reject (pre-pickup) or a mid-route breakdown.
    """
    from delivery.models import DeliveryBatch

    for task in batch.tasks.all():
        if task.status == S.DELIVERED or task.status in DeliveryTask.TERMINAL:
            continue
        task.status = S.REASSIGNED
        task.batch = None
        task.save(update_fields=["status", "batch"])
        o = task.order
        if o and o.status not in ("delivered", "cancelled", "returned", "partially_returned"):
            o.status = "ready_for_dispatch"
            o.save(update_fields=["status"])
    for stop in batch.stops.filter(kind=BatchStop.Kind.COLLECTION).select_related("collection"):
        c = stop.collection
        if c and c.status in ("assigned", "accepted", "en_route", "reached"):
            c.status = "requested"
            c.agent = None
            c.save(update_fields=["status", "agent"])
    batch.status = DeliveryBatch.Status.CANCELLED
    batch.save(update_fields=["status"])
    _broadcast_event("batch_released", batch, reason=reason)
    return batch


def reassign_batch(batch, *, reason="", by=None, exclude_agent_ids=None):
    """Release a batch and immediately re-run the engine so its stops land on other
    available agents. Returns the run summary."""
    store = batch.store
    release_batch(batch, reason=reason, by=by)
    return run_auto_assign(store, by=by, exclude_agent_ids=exclude_agent_ids)


# Auto-release a batch an agent was OFFERED but never answered, after this many
# minutes. Only `assigned` (offered, unanswered) qualifies — see sweep_stale_batches.
STALE_ACCEPT_MIN = 12


def sweep_stale_batches(store):
    """SLA guard: re-offer batches an agent never answered. Returns the count reassigned.

    Two things here are deliberate, and both were bugs:

    * **`assigned` only, never `accepted`.** An accepted batch has a rider already
      riding to the store. Reclaiming it took the job out from under them, and
      because reassigning mints a *fresh* batch with a fresh clock, the same job
      bounced between riders every SLA window indefinitely — a new "New delivery
      assigned" push each time, and that push opens a full-screen alert that rings
      until answered. Once a rider accepts, the job is theirs until pickup,
      abandon, or a manual reassign from the dispatch board.
    * **Measured from `assigned_at`, not `created_at`.** `created_at` is when the
      batch was *planned*; one that sat queued before anyone was offered it
      arrived with its accept window already part-spent.
    """
    from datetime import timedelta

    from delivery.models import DeliveryBatch

    cutoff = timezone.now() - timedelta(minutes=STALE_ACCEPT_MIN)
    stale = list(
        DeliveryBatch.objects.filter(
            store=store,
            status=DeliveryBatch.Status.ASSIGNED,
            assigned_at__isnull=False,
            assigned_at__lt=cutoff,
        )
    )
    for b in stale:
        agent_id = b.agent_id
        reassign_batch(b, reason="SLA: not accepted in time",
                       exclude_agent_ids=[agent_id] if agent_id else None)
    return len(stale)
