"""Admin Orders module — dashboard KPIs, list (filters + sort), and the full
order detail. Aggregates live from the orders/credit/delivery data; the heart of
the Super-Admin operations view.
"""
from django.db.models import Case, Count, IntegerField, Prefetch, Q, Sum, Value, When
from django.utils import timezone

from .models import ACTIVE_STATUSES, DeliveryAssignment, Order, OrderStatus

ONLINE_METHODS = ["upi", "card", "netbanking"]

ORDER_SORTS = {
    "newest": ["-placed_at"],
    "oldest": ["placed_at"],
    "highest_value": ["-total"],
    "lowest_value": ["total"],
}


def _f(v):
    return float(v or 0)


# ── Dashboard ────────────────────────────────────────────
def order_dashboard() -> dict:
    today = timezone.localdate()
    qs = Order.objects.all()
    not_cancelled = qs.exclude(status__in=["cancelled", "rejected"])
    today_qs = qs.filter(placed_at__date=today)
    agg = today_qs.exclude(status__in=["cancelled", "rejected"]).aggregate(
        revenue=Sum("total"), n=Count("id")
    )
    by_status = {
        s: qs.filter(status=s).count()
        for s in ["pending", "placed", "confirmed", "packed", "ready_for_dispatch",
                  "out_for_delivery", "delivered", "cancelled"]
    }
    by_method = qs.aggregate(
        credit=Count("id", filter=Q(payment_method="credit")),
        cod=Count("id", filter=Q(payment_method="cod")),
        online=Count("id", filter=Q(payment_method__in=ONLINE_METHODS)),
    )
    aov = not_cancelled.aggregate(a=Sum("total"))["a"]
    n_all = not_cancelled.count()
    return {
        "ordersToday": today_qs.count(),
        "revenueToday": _f(agg["revenue"]),
        "pending": by_status["pending"] + by_status["placed"] + by_status["confirmed"],
        "packed": by_status["packed"] + by_status["ready_for_dispatch"],
        "outForDelivery": by_status["out_for_delivery"],
        "deliveredToday": today_qs.filter(status="delivered").count(),
        "cancelledToday": today_qs.filter(status__in=["cancelled", "rejected"]).count(),
        "averageOrderValue": round(_f(aov) / n_all, 2) if n_all else 0,
        "creditOrders": by_method["credit"],
        "codOrders": by_method["cod"],
        "onlineOrders": by_method["online"],
    }


# ── List ─────────────────────────────────────────────────
def _latest_task_prefetch():
    """Same fix as `order_detail()`'s: `order.delivery` (DeliveryAssignment)
    is a legacy, mostly-unpopulated parallel model — the real one is
    `DeliveryTask` (`related_name="delivery_tasks"`), which every order
    actually gets one of via the assignment engine. Prefetched (not
    select_related, since it's reverse-FK/to-many) so a list of orders stays
    one extra query, not N+1."""
    from delivery.models import DeliveryTask

    return Prefetch(
        "delivery_tasks",
        queryset=DeliveryTask.objects.select_related("agent").order_by("-created_at"),
        to_attr="_latest_tasks",
    )


def _summary(o):
    tasks = getattr(o, "_latest_tasks", None)
    d = tasks[0] if tasks else None
    return {
        "code": o.code,
        "placedAt": o.placed_at,
        "customer": (o.user.name or o.user.phone) if o.user else None,
        "phone": o.user.phone if o.user else None,
        "store": o.store.name if o.store else None,
        "zone": o.zone.name if o.zone else None,
        "items": getattr(o, "_items", 0),
        "value": _f(o.total),
        "paymentMethod": o.payment_method,
        "paymentStatus": o.payment_status,
        "status": o.status,
        "deliveryStatus": d.status if d else None,
        "agent": d.agent.name if d and d.agent else None,
    }


def search_orders_qs(params):
    """The filtered/sorted admin orders QUERYSET (unsliced).

    Kept separate from :func:`search_orders` so the view can paginate it — slicing
    to a hard `limit` made every order past that limit unreachable in the console."""
    p = params or {}
    qs = (
        Order.objects.select_related("user", "store", "zone")
        .prefetch_related(_latest_task_prefetch())
        .annotate(_items=Count("items"))
    )
    q = (p.get("q") or "").strip()
    if q:
        qs = qs.filter(
            Q(code__icontains=q) | Q(user__name__icontains=q) | Q(user__phone__icontains=q)
        )
    if p.get("store"):
        qs = qs.filter(store_id=p["store"])
    if p.get("zone"):
        qs = qs.filter(zone_id=p["zone"])
    if p.get("status"):
        qs = qs.filter(status=p["status"])
    if p.get("payment_method"):
        qs = qs.filter(payment_method=p["payment_method"])
    if p.get("payment_status"):
        qs = qs.filter(payment_status=p["payment_status"])
    if p.get("agent"):
        qs = qs.filter(delivery_tasks__agent_id=p["agent"]).distinct()
    if p.get("date_from"):
        qs = qs.filter(placed_at__date__gte=p["date_from"])
    if p.get("date_to"):
        qs = qs.filter(placed_at__date__lte=p["date_to"])

    sort = p.get("sort") or "newest"
    if sort == "pending_first":
        qs = qs.annotate(
            _pri=Case(When(status__in=ACTIVE_STATUSES, then=Value(1)),
                      default=Value(0), output_field=IntegerField())
        ).order_by("-_pri", "-placed_at")
    elif sort == "cancelled_first":
        qs = qs.annotate(
            _pri=Case(When(status__in=["cancelled", "rejected", "failed_delivery"], then=Value(1)),
                      default=Value(0), output_field=IntegerField())
        ).order_by("-_pri", "-placed_at")
    else:
        qs = qs.order_by(*ORDER_SORTS.get(sort, ["-placed_at"]))

    return qs


def summarize_orders(orders):
    """Serialize an iterable of Orders to the admin list payload."""
    return [_summary(o) for o in orders]


def search_orders(params, limit=100):
    """Back-compat: the first `limit` matches as a plain list. Prefer
    :func:`search_orders_qs` + pagination for anything user-facing."""
    return summarize_orders(search_orders_qs(params)[:limit])


# ── Operational queues (packing / dispatch board) ────────
def order_queues(store_id=None, with_items=False) -> dict:
    """The store-ops kanban: orders bucketed by operational stage. `store_id`
    scopes it to a single store (store-admin view).

    ``with_items`` attaches each order's lines so the board doubles as a PICK
    LIST — without it a packer only sees an item count and has to open every
    order to learn what to pull off the shelf. The lines are prefetched, so this
    stays one extra query rather than one per order.
    """
    qs = (
        Order.objects.select_related("user", "store", "zone")
        .prefetch_related(_latest_task_prefetch())
        .annotate(_items=Count("items"))
    )
    if with_items:
        qs = qs.prefetch_related("items")
    if store_id:
        qs = qs.filter(store_id=store_id)

    def row(o):
        data = _summary(o)
        if with_items:
            data["lines"] = [
                {"name": it.name, "unit": it.unit, "quantity": it.quantity}
                for it in o.items.all()
            ]
        return data

    def bucket(*statuses):
        return [row(o) for o in qs.filter(status__in=statuses).order_by("placed_at")[:100]]

    to_pack = bucket("placed", "pending", "confirmed")
    packed = bucket("packed")
    ready = bucket("ready_for_dispatch")
    ofd = bucket("out_for_delivery")
    return {
        "toPack": to_pack,
        "packed": packed,
        "readyForDispatch": ready,
        "outForDelivery": ofd,
        "counts": {
            "toPack": len(to_pack), "packed": len(packed),
            "readyForDispatch": len(ready), "outForDelivery": len(ofd),
        },
    }


# ── Detail helpers ───────────────────────────────────────
def _timeline_times(order):
    """First timestamp per status, for the delivery milestone times."""
    out = {}
    for e in order.timeline.all():
        out.setdefault(e.status, e.at)
    return out


def _haversine_km(a, b, c, d):
    import math

    r = 6371.0
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return r * 2 * math.asin(math.sqrt(h))


def _delivery_distance(order):
    store = order.store
    if not (store and store.latitude and store.longitude and order.user):
        return None
    a = order.user.addresses.filter(latitude__isnull=False, longitude__isnull=False).first()
    if not a:
        return None
    return round(_haversine_km(float(store.latitude), float(store.longitude),
                               float(a.latitude), float(a.longitude)), 1)


def _payment_txn(order):
    """Gateway transaction ids for the order's payment + any refund, so panels can
    reconcile against the gateway dashboard."""
    from payments.models import Payment

    paid = (
        Payment.objects.filter(
            order=order, purpose=Payment.Purpose.ORDER, status=Payment.Status.SUCCESS
        )
        .order_by("-created_at").first()
    )
    refund = (
        Payment.objects.filter(order=order, purpose=Payment.Purpose.REFUND)
        .order_by("-created_at").first()
    )
    return {
        "gatewayOrderId": paid.gateway_order_id if paid else "",
        "gatewayPaymentId": paid.gateway_payment_id if paid else "",
        "refundId": (refund.gateway_refund_id or refund.gateway_payment_id) if refund else "",
        "refundStatus": refund.status if refund else None,
    }


def _credit_block(order):
    if order.payment_method != "credit":
        return {"isCredit": False}
    from credit.models import CreditLedgerEntry

    acc = getattr(order.user, "credit_account", None)
    entry = (
        CreditLedgerEntry.objects.filter(order=order, type="purchase")
        .order_by("created_at").first()
    )
    after = _f(entry.balance_after) if entry else None
    before = round(after - _f(entry.amount), 2) if entry else None
    return {
        "isCredit": True,
        "creditUsed": _f(order.credit_used),
        "availableLimit": _f(acc.available) if acc else 0,
        "outstandingBefore": before,
        "outstandingAfter": after,
        "dueDate": order.credit_due_date,
        "collectionStatus": "Cleared" if order.payment_status == "paid" else "Pending",
    }


def _inventory_impact(order):
    from inventory.models import InventoryLedger, StockItem

    wh_id = order.store.warehouse_id if order.store and order.store.warehouse_id else None
    rows = []
    for it in order.items.select_related("product"):
        if not it.product:
            continue
        entry = (
            InventoryLedger.objects.filter(
                product=it.product, type=InventoryLedger.Type.ORDER, ref_id=order.code
            ).order_by("-created_at").first()
        )
        if entry:
            remaining = entry.balance_after
            before = remaining - entry.quantity  # quantity is negative
        else:
            si = StockItem.objects.filter(
                product=it.product, **({"warehouse_id": wh_id} if wh_id else {})
            ).first()
            before = si.quantity if si else None
            remaining = (before - it.quantity) if before is not None else None
        rows.append({"name": it.name, "ordered": it.quantity,
                     "before": before, "remaining": remaining})
    return rows


def _exceptions(order):
    from django.utils import timezone

    from support.models import SupportTicket

    badges = []
    d = getattr(order, "delivery", None)
    if order.status == "returned":
        badges.append("Returned")
    if order.status == "partially_returned":
        badges.append("Partial Delivery")
    if order.status == "failed_delivery":
        badges.append("Delivery Failed")
    if order.payment_status == "pending" and order.status == "delivered":
        badges.append("Payment Pending")
    late = (
        order.estimated_delivery
        and order.status not in ("delivered", "cancelled", "rejected")
        and order.estimated_delivery < timezone.now()
    ) or (
        d and d.delivered_at and order.estimated_delivery
        and d.delivered_at > order.estimated_delivery
    )
    if late:
        badges.append("Late Delivery")
    if SupportTicket.objects.filter(order_code=order.code).exists():
        badges.append("Customer Complaint")
    # dedupe, preserve order
    seen = []
    for b in badges:
        if b not in seen:
            seen.append(b)
    return seen or ["No Exceptions"]


# ── Detail ───────────────────────────────────────────────
def order_detail(order) -> dict:
    from .views import _customer_delivery_otp

    user = order.user
    acc = getattr(user, "credit_account", None) if user else None
    # `order.delivery` isn't a real relation (DeliveryTask's FK is
    # `related_name="delivery_tasks"`, plural — this always silently
    # returned None). The most recent attempt is "the" delivery to show.
    d = order.delivery_tasks.select_related("agent").order_by("-created_at").first()
    addr = order.address_snapshot or {}
    times = _timeline_times(order)
    items = [
        {
            "name": it.name, "brand": it.brand, "quantity": it.quantity,
            "mrp": _f(it.mrp), "price": _f(it.price),
            "discount": _f((it.mrp - it.price) * it.quantity),
            "total": _f(it.price * it.quantity),
        }
        for it in order.items.all()
    ]
    timeline = [
        {"status": e.status, "note": e.note, "at": e.at,
         "by": e.by.name if e.by else None}
        for e in order.timeline.all()
    ]
    return {
        "header": {
            "code": order.code,
            "placedAt": order.placed_at,
            "store": order.store.name if order.store else None,
            "zone": order.zone.name if order.zone else None,
            "status": order.status,
            "paymentStatus": order.payment_status,
            "deliveryStatus": d.status if d else None,
            "estimatedDelivery": order.estimated_delivery,
            "source": order.get_source_display(),
            "createdBy": "Customer" if order.source == "app" else order.get_source_display(),
            "customerType": "Credit" if order.payment_method == "credit" else "Cash",
        },
        "customer": {
            "id": str(user.id) if user else None,
            "name": (user.name or user.phone) if user else addr.get("name"),
            "phone": user.phone if user else addr.get("phone"),
            "address": addr.get("formatted"),
            "pincode": addr.get("pincode"),
            "vsScore": acc.vs_score if acc else None,
            "outstanding": _f(acc.outstanding) if acc else 0,
            "since": user.created_at if user else None,
        },
        "items": items,
        "totals": {
            "subtotal": _f(order.subtotal),
            "discount": _f(order.discount),
            "gst": _f(order.gst),
            "deliveryFee": _f(order.delivery_fee),
            "platformFee": _f(order.platform_fee),
            "total": _f(order.total),
        },
        "financialSummary": {
            "grossRevenue": _f(order.subtotal),
            "discount": _f(order.discount),
            "gst": _f(order.gst),
            "deliveryFee": _f(order.delivery_fee),
            "platformFee": _f(order.platform_fee),
            "netRevenue": _f(order.total),
        },
        "payment": {
            "method": order.payment_method,
            "status": order.payment_status,
            "creditUsed": _f(order.credit_used),
            "creditPlan": order.credit_plan or None,
            "creditDueDate": order.credit_due_date,
            **_payment_txn(order),
        },
        "credit": _credit_block(order),
        "delivery": {
            "agent": d.agent.name if d and d.agent else None,
            "agentId": str(d.agent_id) if d and d.agent_id else None,
            "status": d.status if d else None,
            "assignedAt": d.assigned_at if d else None,
            "pickedUpAt": times.get("ready_for_dispatch") or times.get("packed"),
            "outForDeliveryAt": times.get("out_for_delivery"),
            "deliveredAt": (d.delivered_at if d else None) or times.get("delivered"),
            "distanceKm": _delivery_distance(order),
            "eta": order.estimated_delivery,
            # Staff-only, for phone support: "the agent says the OTP isn't
            # working" is unresolvable without the store being able to see
            # it too. Empty once verified/locked/not yet out for delivery.
            "otp": _customer_delivery_otp(order),
            # The agent's proof-of-delivery/confirmation photo — store staff
            # had no way to see this at all before (DeliveryProofPhotoView
            # only recognised the customer, the agent, or admin/superadmin;
            # now also an active staff member of this order's own store).
            # No /api/v1 prefix — same convention as every other auth-gated
            # media path here (AuthImage prepends the app's own API_BASE).
            "photoUrl": f"/deliveries/{d.id}/proof-photo" if d and d.photo_key else None,
        },
        "inventoryImpact": _inventory_impact(order),
        "exceptions": _exceptions(order),
        "timeline": timeline,
    }


# ── Mutations ────────────────────────────────────────────
def set_order_status(order, status, by=None, note=""):
    from .services import CheckoutError, advance_status, cancel_order

    if status == OrderStatus.CANCELLED:
        # Carry the actor and the reason through — dropping them recorded every
        # staff cancellation as the customer's own.
        return cancel_order(order, by=by, note=note)
    advance_status(order, status, by=by, note=note or f"Status set to {status}")
    return order


def assign_agent(order, agent, by=None):
    """Manually dispatch `order` to `agent` from the admin console (the
    Packing & Dispatch board's "Dispatch" button).

    This used to touch ONLY the legacy `DeliveryAssignment` relation — no
    `DeliveryTask` was ever created, so the agent app (which reads
    `delivery_tasks`, not `DeliveryAssignment`) never actually received the
    dispatch. The order would show an agent's name and "Out for Delivery" in
    the admin console while that agent's own app showed nothing at all.
    `delivery.services.manual_assign` is the real assignment path (creates
    the task, records assignment history, sends the push) — same one the
    store's own manual-assign flow uses.
    """
    from delivery.services import manual_assign

    manual_assign(order, agent, by=by, reason="Dispatched from admin console")
    # Keep the legacy relation in sync too, defensively, for any code that
    # might still read it.
    da, _ = DeliveryAssignment.objects.get_or_create(order=order)
    da.agent = agent
    da.save(update_fields=["agent"])
    # Also create the agent's delivery task if the delivery app expects it.
    from delivery.models import DeliveryTask

    DeliveryTask.objects.get_or_create(
        order=order, defaults={"agent": agent, "status": "assigned"}
    )
    return da
