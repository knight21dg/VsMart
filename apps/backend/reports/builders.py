"""Each builder returns {title, columns, rows, summary?} computed from live data.

Two things were wrong here before the 2026-08-11 accuracy review, and both made
the reports quietly untrustworthy rather than visibly broken:

* **The filters didn't exist.** `ReportView` documents `?date_from&date_to&store&zone`
  and `filters.py` implements the helpers, but every builder took `params=None` and
  ignored it. Narrowing to a date range changed nothing on screen.
* **Rows were silently truncated.** `orders` and `collections` cut to the first 200,
  `inventory` to 500, with no indication anywhere. `paginate_sort` then reported
  `meta.total` as the size of the *truncated* list, so a 5,000-order month showed 200
  rows and claimed the total was 200 — and the CSV/Excel/PDF export carried the same
  200 into a file someone would file as the month's record.

Builders now honour the window and return every matching row; `paginate_sort`
does the slicing, so `meta.total` is the real count and an export is the real set.
"""
from datetime import datetime, time, timedelta

from django.db.models import Count, Q, Sum
from django.utils import timezone

from .filters import date_range, scope_orders, store_id, zone_id


#: Safety ceiling for row-per-record reports. Removing the old 200/500 cut entirely
#: would trade a silent wrong answer for an unbounded query, so there is still a
#: ceiling — high enough not to bite in practice, and when it does bite the report
#: SAYS SO in its title and summary, which carries into the export as well.
MAX_ROWS = 20000


def _num(v):
    return float(v or 0)


def _capped(qs, build):
    """`(rows, truncated)` — materialise at most MAX_ROWS, detecting overflow.

    Fetches one extra row so "exactly at the limit" and "over the limit" are
    distinguishable without a second COUNT.
    """
    items = list(qs[: MAX_ROWS + 1])
    truncated = len(items) > MAX_ROWS
    return [build(o) for o in items[:MAX_ROWS]], truncated


def _cap_note(report, truncated):
    if truncated:
        report["title"] += f" · CAPPED at {MAX_ROWS:,} rows — narrow the date range"
        report.setdefault("summary", {})["Capped at"] = MAX_ROWS
    return report


def _bounds(params):
    """The window as timezone-aware datetimes, plus a label for the title."""
    start, end = date_range(params or {})
    tz = timezone.get_current_timezone()
    # Inclusive on both ends: `date_to=2026-08-11` must include everything that
    # happened on the 11th, not stop at midnight.
    start_dt = timezone.make_aware(datetime.combine(start, time.min), tz)
    end_dt = timezone.make_aware(datetime.combine(end, time.max), tz)
    return start_dt, end_dt, f"{start.isoformat()} → {end.isoformat()}"


def _scope_label(params):
    bits = []
    if store_id(params):
        bits.append("store-filtered")
    if zone_id(params):
        bits.append("zone-filtered")
    return f" ({', '.join(bits)})" if bits else ""


def sales(params=None):
    from orders.models import Order

    params = params or {}
    start, end, label = _bounds(params)
    qs = scope_orders(
        Order.objects.exclude(status="cancelled").filter(
            placed_at__gte=start, placed_at__lte=end
        ),
        params,
    )
    # One grouped query rather than a query per day.
    per_day = {}
    for r in qs.values("placed_at__date").annotate(
        n=Count("id"), gmv=Sum("total"), pf=Sum("platform_fee")
    ):
        per_day[r["placed_at__date"]] = r

    rows = []
    d = start.date()
    while d <= end.date():
        a = per_day.get(d)
        rows.append([
            d.isoformat(),
            a["n"] if a else 0,
            _num(a["gmv"]) if a else 0.0,
            _num(a["pf"]) if a else 0.0,
        ])
        d += timedelta(days=1)
    return {
        "title": f"Sales · {label}{_scope_label(params)}",
        "columns": ["Date", "Orders", "GMV", "Platform Fee"],
        "rows": rows,
        "summary": {
            "Orders": sum(r[1] for r in rows),
            "GMV": round(sum(r[2] for r in rows), 2),
            "Platform Fee": round(sum(r[3] for r in rows), 2),
        },
    }


def orders(params=None):
    from orders.models import Order

    params = params or {}
    start, end, label = _bounds(params)
    qs = scope_orders(
        Order.objects.filter(placed_at__gte=start, placed_at__lte=end), params
    ).select_related("user").order_by("-placed_at")
    rows, truncated = _capped(qs, lambda o: [
        o.code, o.user.name or o.user.phone, o.status, _num(o.total),
        o.placed_at.strftime("%Y-%m-%d %H:%M"),
    ])
    return _cap_note({
        "title": f"Orders · {label}{_scope_label(params)}",
        "columns": ["Code", "Customer", "Status", "Total", "Placed"],
        "rows": rows,
        "summary": {"Orders": len(rows), "Total": round(sum(r[3] for r in rows), 2)},
    }, truncated)


def credit(params=None):
    from credit.models import CreditAccount

    # Balances are a position, not a flow — a date window would be meaningless, so
    # this one is deliberately as-of-now and says so.
    rows = [
        [a.user.name or a.user.phone, _num(a.credit_limit), _num(a.outstanding),
         _num(a.available), a.status]
        for a in CreditAccount.objects.select_related("user").order_by("-outstanding")
    ]
    return {
        "title": "Credit · balances as of now",
        "columns": ["Customer", "Limit", "Outstanding", "Available", "Status"],
        "rows": rows,
        "summary": {
            "Accounts": len(rows),
            "Limit": round(sum(r[1] for r in rows), 2),
            "Outstanding": round(sum(r[2] for r in rows), 2),
        },
    }


def collections(params=None):
    from payments.models import CashCollection

    params = params or {}
    start, end, label = _bounds(params)
    # Window on assignment so in-flight and failed attempts are visible too — a
    # collections report that only shows successes hides the recovery problem.
    qs = (
        CashCollection.objects.filter(created_at__gte=start, created_at__lte=end)
        .select_related("user", "agent").order_by("-created_at")
    )
    rows, truncated = _capped(qs, lambda c: [
        c.user.name or c.user.phone,
        (c.agent.name if c.agent else "—"),
        _num(c.amount),
        _num(c.collected_amount),
        c.status,
        c.collected_at.strftime("%Y-%m-%d") if c.collected_at else "—",
    ])
    return _cap_note({
        "title": f"Collections · {label}",
        # `Due` vs `Recovered` split: the old report showed only `amount` (what we set
        # out to recover) and called it Amount, so a partial collection read as a full one.
        "columns": ["Customer", "Agent", "Due", "Recovered", "Status", "Collected"],
        "rows": rows,
        "summary": {
            "Cases": len(rows),
            "Due": round(sum(r[2] for r in rows), 2),
            "Recovered": round(sum(r[3] for r in rows), 2),
        },
    }, truncated)


def inventory(params=None):
    from inventory.models import StockItem

    params = params or {}
    sid = store_id(params)
    # On-hand comes from StockItem, the ledger-backed source, per product×variant×
    # warehouse. The old report read `Product.stock_count`, a denormalised
    # company-wide field that ignores warehouses and variants entirely — on a
    # per-variant catalogue it is not the stock of anything.
    qs = StockItem.objects.select_related("product", "variant", "warehouse")
    if sid:
        from stores.models import Store

        wh = Store.objects.filter(pk=sid).values_list("warehouse_id", flat=True).first()
        if wh:
            qs = qs.filter(warehouse_id=wh)
    def row(it):
        label = f" · {it.variant.label}" if it.variant_id else ""
        available = (it.quantity or 0) - (it.reserved or 0)
        return [
            f"{it.product.name}{label}",
            it.product.brand,
            it.warehouse.name,
            it.quantity or 0,
            it.reserved or 0,
            available,
            "Yes" if available > 0 else "No",
        ]

    rows, truncated = _capped(qs.order_by("product__name"), row)
    return _cap_note({
        "title": "Inventory · on-hand by warehouse",
        "columns": ["Product", "Brand", "Warehouse", "On hand", "Reserved", "Available", "In stock"],
        "rows": rows,
        "summary": {
            "SKUs": len(rows),
            "On hand": sum(r[3] for r in rows),
            "Available": sum(r[5] for r in rows),
        },
    }, truncated)


def agents(params=None):
    from accounts.models import Role, User
    from delivery.models import DeliveryTask
    from payments.models import CashCollection

    params = params or {}
    start, end, label = _bounds(params)
    # Grouped once each, then joined in memory — the old version ran two queries per
    # agent inside a loop.
    delivered = {
        r["agent_id"]: r["n"]
        for r in DeliveryTask.objects.filter(
            status="delivered", updated_at__gte=start, updated_at__lte=end
        ).values("agent_id").annotate(n=Count("id"))
    }
    collected = {
        r["agent_id"]: (r["n"], _num(r["s"]))
        for r in CashCollection.objects.filter(
            status__in=("collected", "partially_collected"),
            collected_at__gte=start, collected_at__lte=end,
        ).values("agent_id").annotate(n=Count("id"), s=Sum("collected_amount"))
    }
    earnings = {}
    try:
        from delivery.models import DeliveryEarnings

        earnings = {
            r["agent_id"]: (_num(r["s"]), _num(r["u"] or 0))
            for r in DeliveryEarnings.objects.values("agent_id").annotate(
                s=Sum("total"),
                u=Sum("total", filter=Q(released=False)),
            )
        }
    except Exception:
        pass

    rows = []
    for u in User.objects.filter(role=Role.AGENT).order_by("name"):
        n_coll, amt_coll = collected.get(u.id, (0, 0.0))
        earned, unpaid = earnings.get(u.id, (0.0, 0.0))
        rows.append([
            u.name or u.phone,
            delivered.get(u.id, 0),
            n_coll,
            round(amt_coll, 2),
            round(earned, 2),
            round(unpaid, 2),
        ])
    return {
        "title": f"Agents · {label}",
        "columns": ["Agent", "Deliveries", "Collections", "Cash recovered",
                    "Earned (lifetime)", "Unpaid"],
        "rows": rows,
        "summary": {
            "Agents": len(rows),
            "Deliveries": sum(r[1] for r in rows),
            "Cash recovered": round(sum(r[3] for r in rows), 2),
            "Unpaid": round(sum(r[5] for r in rows), 2),
        },
    }


from .executive import EXECUTIVE_BUILDERS  # noqa: E402

BUILDERS = {
    "sales": sales, "orders": orders, "credit": credit,
    "collections": collections, "inventory": inventory, "agents": agents,
    **EXECUTIVE_BUILDERS,
}
