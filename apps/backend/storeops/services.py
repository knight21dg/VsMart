"""Store-scoped aggregations + staff helpers for the Store-Admin panel.

Everything here takes an explicit ``store`` and only ever reads/writes rows that
belong to it (orders with ``store=``, stock in ``store.warehouse``, staff in
``store.staff``). There is no cross-store path.
"""
from datetime import timedelta
from decimal import Decimal

from django.db.models import Count, F, Q, Sum
from django.utils import timezone

ZERO = Decimal("0.00")
ONLINE_METHODS = ["upi", "card", "netbanking"]
ACTIVE_ORDER_STATUSES = [
    "placed", "pending", "confirmed", "packed", "ready_for_dispatch", "out_for_delivery",
]


def _f(v):
    return float(v or 0)


# ── /store/me ────────────────────────────────────────────
def membership_payload(membership) -> dict:
    u = membership.user
    s = membership.store
    return {
        "user": {
            "id": str(u.id),
            "name": u.name or u.phone,
            "phone": u.phone,
            "email": u.email or None,
        },
        "store": {
            "id": str(s.id),
            "code": s.code,
            "name": s.name,
            "address": s.address,
            "phone": s.phone,
            # A printed tax receipt must carry the seller's GSTIN.
            "gstin": s.gstin,
            "status": s.status,
            "warehouseId": str(s.warehouse_id) if s.warehouse_id else None,
        },
        "staffRole": membership.staff_role,
        "staffRoleLabel": membership.get_staff_role_display(),
        "title": membership.title or membership.get_staff_role_display(),
        "isManager": membership.is_manager,
        "permissions": membership.effective_permissions(),
    }


# ── Stock valuation helpers (store warehouse) ────────────
def _avg_costs(warehouse_id) -> dict:
    """Weighted-average unit cost per product from on-hand batches in the warehouse."""
    from inventory.models import StockBatch

    rows = (
        StockBatch.objects.filter(warehouse_id=warehouse_id, quantity__gt=0)
        .values("product_id")
        .annotate(qty=Sum("quantity"), val=Sum(F("quantity") * F("unit_cost")))
    )
    out = {}
    for r in rows:
        qty = r["qty"] or 0
        out[r["product_id"]] = (r["val"] / qty) if qty else ZERO
    return out


def stock_value(warehouse_id) -> float:
    """Σ on-hand × unit cost (batch weighted-avg, else the product price)."""
    from inventory.models import StockItem

    costs = _avg_costs(warehouse_id)
    total = ZERO
    items = StockItem.objects.filter(warehouse_id=warehouse_id, quantity__gt=0).select_related(
        "product"
    )
    for it in items:
        cost = costs.get(it.product_id)
        if cost is None:
            cost = it.product.price or ZERO
        total += Decimal(it.quantity) * Decimal(cost)
    return round(float(total), 2)


def _low_stock_rows(warehouse_id, limit=None):
    from inventory.models import StockItem

    rows = []
    qs = StockItem.objects.filter(warehouse_id=warehouse_id).select_related("product")
    for it in qs:
        available = it.quantity - it.reserved
        if available <= it.low_stock_threshold:
            rows.append({
                "productId": str(it.product_id),
                "name": it.product.name,
                "available": available,
                "reorderLevel": it.low_stock_threshold,
            })
    rows.sort(key=lambda r: r["available"])
    return rows[:limit] if limit else rows


def _expiry_rows(warehouse_id, within_days=30, limit=None):
    from inventory.models import StockBatch

    today = timezone.localdate()
    horizon = today + timedelta(days=within_days)
    qs = (
        StockBatch.objects.filter(
            warehouse_id=warehouse_id, quantity__gt=0,
            expiry_date__isnull=False, expiry_date__lte=horizon,
        )
        .select_related("product")
        .order_by("expiry_date")
    )
    rows = []
    for b in qs:
        days = (b.expiry_date - today).days
        rows.append({
            "batchId": str(b.id),
            "productId": str(b.product_id),
            "name": b.product.name,
            "batchNo": b.batch_no,
            "quantity": b.quantity,
            "expiryDate": b.expiry_date,
            "daysLeft": days,
            "expired": days < 0,
        })
    return rows[:limit] if limit else rows


# ── Dashboard ────────────────────────────────────────────
def _counter_sales(store):
    """This store's POS (counter) transactions.

    POS sales are ``POSTransaction`` rows with no FK to ``Order`` — they reach a
    store through their session's warehouse. Every figure on this dashboard used
    to be built from ``Order`` alone, so for a grocery store, where most trade
    happens at the till, the headline revenue was reporting online orders only
    while being labelled as the store's.

    Returns are excluded here and netted off separately by the caller.
    """
    from pos.models import POSTransaction

    if not store.warehouse_id:
        return POSTransaction.objects.none()
    return POSTransaction.objects.filter(session__warehouse_id=store.warehouse_id)


def store_dashboard(store) -> dict:
    from orders.models import Order, OrderItem

    today = timezone.localdate()
    month_start = today.replace(day=1)
    wh = store.warehouse_id

    orders = Order.objects.filter(store=store)
    sellable = orders.exclude(status__in=["cancelled", "rejected"])
    today_qs = sellable.filter(placed_at__date=today)
    month_qs = sellable.filter(placed_at__date__gte=month_start)

    today_agg = today_qs.aggregate(revenue=Sum("total"), subtotal=Sum("subtotal"), n=Count("id"))

    # Counter trade, netted for refunds, so the KPIs describe the whole store
    # rather than just its online half.
    pos_all = _counter_sales(store)
    pos_sales = pos_all.filter(type="sale")
    pos_returns = pos_all.filter(type="return")

    def _pos_net(qs_sales, qs_returns):
        sold = qs_sales.aggregate(a=Sum("total"))["a"] or 0
        refunded = qs_returns.aggregate(a=Sum("total"))["a"] or 0
        return sold - refunded

    pos_today_sales = pos_sales.filter(created_at__date=today)
    pos_today_returns = pos_returns.filter(created_at__date=today)
    pos_today_revenue = _pos_net(pos_today_sales, pos_today_returns)
    pos_today_subtotal = pos_today_sales.aggregate(a=Sum("subtotal"))["a"] or 0
    pos_today_count = pos_today_sales.count()
    pos_month_revenue = _pos_net(
        pos_sales.filter(created_at__date__gte=month_start),
        pos_returns.filter(created_at__date__gte=month_start),
    )

    # COD owed: COD orders not yet paid.
    cod_pending = orders.filter(payment_method="cod").exclude(payment_status="paid").aggregate(
        amt=Sum("total"), n=Count("id")
    )
    # Outstanding credit attributable to this store: credit orders not cleared.
    credit_out = orders.filter(payment_method="credit").exclude(payment_status="paid").aggregate(
        amt=Sum("credit_used"), n=Count("id")
    )

    active_customers = (
        sellable.filter(placed_at__date__gte=today - timedelta(days=30))
        .values("user").distinct().count()
    )

    low = _low_stock_rows(wh) if wh else []
    expiring = _expiry_rows(wh) if wh else []

    # ── Widgets ──
    # 14-day sales + orders trend.
    trend = (
        sellable.filter(placed_at__date__gte=today - timedelta(days=13))
        .values("placed_at__date")
        .annotate(revenue=Sum("total"), orders=Count("id"))
    )
    by_day = {r["placed_at__date"]: r for r in trend}
    # Same 14-day window over the till, so the trend line matches the KPI above it.
    pos_trend = (
        pos_sales.filter(created_at__date__gte=today - timedelta(days=13))
        .values("created_at__date")
        .annotate(revenue=Sum("total"), sales=Count("id"))
    )
    pos_by_day = {r["created_at__date"]: r for r in pos_trend}
    pos_refund_by_day = {
        r["created_at__date"]: r["revenue"]
        for r in (
            pos_returns.filter(created_at__date__gte=today - timedelta(days=13))
            .values("created_at__date")
            .annotate(revenue=Sum("total"))
        )
    }
    sales_trend, orders_trend = [], []
    for i in range(13, -1, -1):
        d = today - timedelta(days=i)
        r = by_day.get(d, {})
        p = pos_by_day.get(d, {})
        day_revenue = (
            (r.get("revenue") or 0)
            + (p.get("revenue") or 0)
            - (pos_refund_by_day.get(d) or 0)
        )
        sales_trend.append({"date": d.isoformat(), "value": _f(day_revenue)})
        orders_trend.append({
            "date": d.isoformat(),
            "value": (r.get("orders", 0) or 0) + (p.get("sales", 0) or 0),
        })

    # Top products (by units sold) at this store — online lines AND till lines,
    # merged on name. Counting orders alone ranked a store's bestsellers off a
    # minority of its trade.
    from pos.models import POSTransactionItem

    merged: dict[str, dict] = {}
    for r in (
        OrderItem.objects.filter(order__store=store)
        .exclude(order__status__in=["cancelled", "rejected"])
        .values("name")
        .annotate(qty=Sum("quantity"), revenue=Sum(F("price") * F("quantity")))
    ):
        merged[r["name"]] = {"quantity": r["qty"] or 0, "revenue": r["revenue"] or 0}
    if store.warehouse_id:
        for r in (
            POSTransactionItem.objects
            .filter(transaction__session__warehouse_id=store.warehouse_id,
                    transaction__type="sale")
            .values("product__name")
            .annotate(qty=Sum("quantity"), revenue=Sum(F("unit_price") * F("quantity")))
        ):
            row = merged.setdefault(r["product__name"], {"quantity": 0, "revenue": 0})
            row["quantity"] += r["qty"] or 0
            row["revenue"] += r["revenue"] or 0
    top_products = [
        {"name": name, "quantity": v["quantity"], "revenue": _f(v["revenue"])}
        for name, v in sorted(
            merged.items(), key=lambda kv: kv[1]["quantity"], reverse=True)[:8]
    ]

    # Top customers (by spend) at this store.
    top_customers = []
    for r in (
        sellable.values("user").annotate(spend=Sum("total"), orders=Count("id")).order_by("-spend")[:8]
    ):
        if not r["user"]:
            continue
        top_customers.append({
            "customerId": str(r["user"]),
            "spend": _f(r["spend"]),
            "orders": r["orders"],
        })
    _attach_names(top_customers)

    return {
        "kpis": {
            "todaySales": _f((today_agg["subtotal"] or 0) + pos_today_subtotal),
            "todayRevenue": _f((today_agg["revenue"] or 0) + pos_today_revenue),
            "todayOrders": (today_agg["n"] or 0) + pos_today_count,
            # Split out so the operator can see how the day divides between the
            # till and online, rather than only a merged figure.
            "todayCounterRevenue": _f(pos_today_revenue),
            "todayOnlineRevenue": _f(today_agg["revenue"]),
            "todayCounterSales": pos_today_count,
            "pendingOrders": orders.filter(status__in=ACTIVE_ORDER_STATUSES).count(),
            "deliveredToday": today_qs.filter(status="delivered").count(),
            "codPending": _f(cod_pending["amt"]),
            "codPendingCount": cod_pending["n"] or 0,
            "outstandingCredit": _f(credit_out["amt"]),
            "creditOrders": credit_out["n"] or 0,
            "activeCustomers": active_customers,
            "lowStockItems": len(low),
            "expiringItems": len(expiring),
            "stockValue": stock_value(wh) if wh else 0.0,
            "monthlyRevenue": _f(
                (month_qs.aggregate(a=Sum("total"))["a"] or 0) + pos_month_revenue
            ),
        },
        "salesTrend": sales_trend,
        "ordersTrend": orders_trend,
        "topProducts": top_products,
        "topCustomers": top_customers,
        "lowStockAlerts": low[:8],
        "expiryAlerts": expiring[:8],
        "staffActivity": staff_activity(store, limit=12),
    }


def _attach_names(rows):
    """Backfill customer display names onto rows carrying ``customerId``."""
    from accounts.models import User

    ids = [r["customerId"] for r in rows]
    if not ids:
        return
    names = {str(u.id): (u.name or u.phone) for u in User.objects.filter(id__in=ids)}
    for r in rows:
        r["customer"] = names.get(r["customerId"], "—")


# ── Staff activity feed (audit by this store's staff) ────
def staff_user_ids(store):
    return list(store.staff.values_list("user_id", flat=True))


def staff_activity(store, limit=20, *, action="", actor="", date_from=None, date_to=None):
    from django.db.models import Q

    from accounts.models import AuditLog

    ids = staff_user_ids(store)
    if not ids:
        return []
    qs = AuditLog.objects.filter(actor_id__in=ids).select_related("actor")
    if action:
        qs = qs.filter(action__icontains=action)
    if actor:
        qs = qs.filter(Q(actor__name__icontains=actor) | Q(actor__phone__icontains=actor))
    if date_from:
        qs = qs.filter(created_at__date__gte=date_from)
    if date_to:
        qs = qs.filter(created_at__date__lte=date_to)
    qs = qs[:limit]
    return [
        {
            "actor": (a.actor.name or a.actor.phone) if a.actor else "System",
            "action": a.action,
            "targetType": a.target_type,
            "targetId": a.target_id,
            "at": a.created_at,
        }
        for a in qs
    ]
