"""Executive / BI report builders — recovery, store, zone, cohorts, credit
utilization, collection efficiency, and the executive dashboard.

All figures derive live from the source-of-truth modules (orders, credit,
payments/collections, inventory, accounts, delivery, verification, zones,
returns). Aggregation is DB-side (grouped annotations); cross-module attribution
(collections/outstanding → store/zone) uses a single user→store/zone map.
"""
from datetime import timedelta

from django.db.models import (
    Avg,
    Count,
    DecimalField,
    F,
    Max,
    Min,
    Q,
    Sum,
)
from django.utils import timezone

from .filters import date_range, scope_orders, user_store_zone_map


def _num(v):
    return float(v or 0)


def _pct(part, whole):
    return round(_num(part) / _num(whole) * 100, 1) if whole else 0.0


# ── Executive dashboard ──────────────────────────────────
def dashboard(params=None):
    from accounts.models import Role, User
    from credit.models import CreditAccount
    from delivery.models import DeliveryTask
    from inventory.models import StockItem
    from orders.models import Order
    from payments.models import CashCollection
    from verification.models import VerificationTask

    today = timezone.now().date()
    month_start = today.replace(day=1)
    orders = Order.objects.exclude(status="cancelled")
    coll = CashCollection.objects.filter(status="collected")
    acc = CreditAccount.objects.aggregate(out=Sum("outstanding"), lim=Sum("credit_limit"))
    customers = User.objects.filter(role=Role.CUSTOMER)
    inv_val = StockItem.objects.aggregate(
        v=Sum(F("quantity") * F("product__price"), output_field=DecimalField())
    )["v"]
    low_stock = (
        StockItem.objects.annotate(avail=F("quantity") - F("reserved"))
        .filter(avail__lte=F("low_stock_threshold"))
        .count()
    )
    widgets = {
        "revenueToday": _num(orders.filter(placed_at__date=today).aggregate(s=Sum("total"))["s"]),
        "revenueMtd": _num(orders.filter(placed_at__date__gte=month_start).aggregate(s=Sum("total"))["s"]),
        "ordersToday": orders.filter(placed_at__date=today).count(),
        "ordersMtd": orders.filter(placed_at__date__gte=month_start).count(),
        "collectionsToday": _num(coll.filter(collected_at__date=today).aggregate(s=Sum("amount"))["s"]),
        "collectionsMtd": _num(coll.filter(collected_at__date__gte=month_start).aggregate(s=Sum("amount"))["s"]),
        "outstandingCredit": _num(acc["out"]),
        "creditUtilization": _pct(acc["out"], acc["lim"]),
        "activeCustomers": customers.filter(is_active=True).count(),
        "newCustomers": customers.filter(created_at__date__gte=month_start).count(),
        "pendingDeliveries": DeliveryTask.objects.exclude(status__in=["delivered", "failed"]).count(),
        "pendingVerifications": VerificationTask.objects.filter(
            status__in=["pending", "assigned", "in_progress"]
        ).count(),
        "inventoryValue": _num(inv_val),
        "lowStockCount": low_stock,
    }
    return {"title": "Executive Dashboard", "widgets": widgets}


# ── Report 01 — Recovery performance ─────────────────────
def recovery_performance(params=None):
    from credit.models import CreditAccount, Statement
    from payments.models import CashCollection

    today = timezone.now().date()
    month_start = today.replace(day=1)
    start, end = date_range(params)

    coll = CashCollection.objects.all()
    collected = coll.filter(status="collected")
    total_outstanding = _num(CreditAccount.objects.aggregate(s=Sum("outstanding"))["s"])
    overdue = _num(Statement.objects.filter(status="overdue").aggregate(s=Sum("closing_balance"))["s"])
    collected_month = _num(collected.filter(collected_at__date__gte=month_start).aggregate(s=Sum("amount"))["s"])
    collected_today = _num(collected.filter(collected_at__date=today).aggregate(s=Sum("amount"))["s"])
    assigned = coll.exclude(status__in=["cancelled", "requested"]).count()
    completed = collected.count()

    # Average collection time (request → collected), days.
    spans = collected.exclude(collected_at__isnull=True).annotate(
        secs=F("collected_at") - F("created_at")
    ).values_list("secs", flat=True)[:2000]
    days = [s.total_seconds() / 86400 for s in spans if s is not None]
    avg_collection_time = round(sum(days) / len(days), 1) if days else 0.0

    summary = {
        "totalOutstanding": total_outstanding,
        "currentOutstanding": total_outstanding - overdue,
        "collectedThisMonth": collected_month,
        "collectedToday": collected_today,
        "overdueAmount": overdue,
        "recoveryRate": _pct(collected_month, collected_month + overdue),
        "collectionEfficiency": _pct(completed, assigned),
        "averageCollectionTimeDays": avg_collection_time,
        # No promise-to-pay records yet → reported as null, not faked.
        "promiseToPayFulfillment": None,
    }

    # Agent recovery ranking (one grouped query).
    agent_rows = []
    for r in (
        coll.values("agent_id", "agent__name")
        .annotate(
            assigned=Count("id", filter=~Q(status__in=["cancelled", "requested"])),
            collected=Count("id", filter=Q(status="collected")),
            amount=Sum("amount", filter=Q(status="collected")),
        )
        .order_by("-amount")
    ):
        if r["agent_id"] is None:
            continue
        agent_rows.append([
            r["agent__name"] or "-", r["assigned"], r["collected"],
            _num(r["amount"]), _pct(r["collected"], r["assigned"]),
        ])

    # Recovery trend over the selected range.
    trend = []
    d = start
    while d <= end:
        amt = _num(collected.filter(collected_at__date=d).aggregate(s=Sum("amount"))["s"])
        trend.append({"date": d.isoformat(), "collected": amt})
        d += timedelta(days=1)

    return {
        "title": "Recovery Performance",
        "summary": summary,
        "columns": ["Agent", "Assigned", "Collected", "Amount", "Success %"],
        "rows": agent_rows,
        "charts": {"recoveryTrend": trend},
    }


# ── Report 02 — Store performance ────────────────────────
def store_performance(params=None):
    from inventory.models import StockItem
    from orders.models import Order
    from payments.models import CashCollection
    from returns.models import ReturnRequest
    from stores.models import Store

    stores = {s.id: s for s in Store.objects.select_related("warehouse")}
    rows_by_store = {
        sid: {
            "name": s.name, "revenue": 0.0, "orders": 0, "customers": 0,
            "creditIssued": 0.0, "collections": 0.0, "inventoryValue": 0.0,
            "returns": 0, "delivered": 0, "deliveriesTotal": 0,
        }
        for sid, s in stores.items()
    }

    o_qs = scope_orders(Order.objects.exclude(status="cancelled"), params)
    for r in o_qs.values("store_id").annotate(
        revenue=Sum("total"), n=Count("id"), customers=Count("user", distinct=True),
        credit=Sum("credit_used"),
    ):
        b = rows_by_store.get(r["store_id"])
        if b:
            b["revenue"] = _num(r["revenue"])
            b["orders"] = r["n"]
            b["customers"] = r["customers"]
            b["creditIssued"] = _num(r["credit"])

    # Inventory value per store (warehouse → store).
    wh_to_store = {s.warehouse_id: sid for sid, s in stores.items() if s.warehouse_id}
    for r in StockItem.objects.values("warehouse_id").annotate(
        val=Sum(F("quantity") * F("product__price"), output_field=DecimalField())
    ):
        sid = wh_to_store.get(r["warehouse_id"])
        if sid in rows_by_store:
            rows_by_store[sid]["inventoryValue"] = _num(r["val"])

    # Returns + delivery success per store (order-attributed).
    for r in ReturnRequest.objects.values("order__store_id").annotate(n=Count("id")):
        b = rows_by_store.get(r["order__store_id"])
        if b:
            b["returns"] = r["n"]
    from delivery.models import DeliveryTask

    for r in DeliveryTask.objects.values("order__store_id").annotate(
        total=Count("id"), delivered=Count("id", filter=Q(status="delivered"))
    ):
        b = rows_by_store.get(r["order__store_id"])
        if b:
            b["deliveriesTotal"] = r["total"]
            b["delivered"] = r["delivered"]

    rows = []
    for b in rows_by_store.values():
        rows.append([
            b["name"], b["revenue"], b["orders"], b["customers"],
            round(b["revenue"] / b["orders"], 2) if b["orders"] else 0,
            round(b["revenue"] / b["customers"], 2) if b["customers"] else 0,
            b["creditIssued"], b["inventoryValue"], b["returns"],
            _pct(b["delivered"], b["deliveriesTotal"]),
        ])
    rows.sort(key=lambda x: x[1], reverse=True)  # rank by revenue
    return {
        "title": "Store Performance",
        "columns": ["Store", "Revenue", "Orders", "Customers", "Rev/Order",
                    "Rev/Customer", "Credit Issued", "Inventory Value",
                    "Returns", "Delivery Success %"],
        "rows": rows,
    }


# ── Report 03 — Zone performance (heatmap-ready) ─────────
def zone_performance(params=None):
    from orders.models import Order
    from zones.models import Zone

    zones = {z.id: z for z in Zone.objects.all()}
    data = {
        zid: {"name": z.name, "revenue": 0.0, "orders": 0, "customers": 0,
              "outstanding": 0.0, "collections": 0.0}
        for zid, z in zones.items()
    }

    for r in (
        Order.objects.exclude(status="cancelled")
        .exclude(zone__isnull=True)
        .values("zone_id")
        .annotate(revenue=Sum("total"), n=Count("id"), customers=Count("user", distinct=True))
    ):
        b = data.get(r["zone_id"])
        if b:
            b["revenue"] = _num(r["revenue"])
            b["orders"] = r["n"]
            b["customers"] = r["customers"]

    # Outstanding + collections attributed to zone via the customer→zone map.
    umap = user_store_zone_map()
    from credit.models import CreditAccount
    from payments.models import CashCollection

    for a in CreditAccount.objects.values("user_id", "outstanding"):
        z = umap.get(a["user_id"], {}).get("zone_id")
        if z in data:
            data[z]["outstanding"] += _num(a["outstanding"])
    for c in CashCollection.objects.filter(status="collected").values("user_id", "amount"):
        z = umap.get(c["user_id"], {}).get("zone_id")
        if z in data:
            data[z]["collections"] += _num(c["amount"])

    rows, heatmap = [], []
    for zid, b in data.items():
        rows.append([
            b["name"], b["revenue"], b["orders"], b["customers"],
            round(b["revenue"] / b["customers"], 2) if b["customers"] else 0,
            b["outstanding"], b["collections"],
            _pct(b["collections"], b["collections"] + b["outstanding"]),
        ])
        heatmap.append({"zoneId": str(zid), "zone": b["name"],
                        "revenue": b["revenue"], "orders": b["orders"]})
    rows.sort(key=lambda x: x[1], reverse=True)
    return {
        "title": "Zone Performance",
        "columns": ["Zone", "Revenue", "Orders", "Customers", "Rev/Customer",
                    "Outstanding", "Collections", "Collection Efficiency %"],
        "rows": rows,
        "charts": {"heatmap": heatmap},
    }


# ── Report 04 — Customer cohort analytics ────────────────
def customer_cohorts(params=None):
    from accounts.models import Role, User
    from credit.models import CreditAccount
    from orders.models import Order

    # First/last order + count per customer (one grouped query).
    order_stats = {
        r["user_id"]: r
        for r in Order.objects.values("user_id").annotate(
            first=Min("placed_at"), last=Max("placed_at"), n=Count("id")
        )
    }
    credit_users = set(CreditAccount.objects.values_list("user_id", flat=True))

    cohorts = {}
    for u in User.objects.filter(role=Role.CUSTOMER).values("id", "created_at"):
        key = u["created_at"].strftime("%Y-%m")
        c = cohorts.setdefault(key, {"size": 0, "r30": 0, "r60": 0, "r90": 0,
                                     "repeat": 0, "credit": 0})
        c["size"] += 1
        st = order_stats.get(u["id"])
        if st and st["last"]:
            active_days = (st["last"] - u["created_at"]).days
            if active_days >= 30:
                c["r30"] += 1
            if active_days >= 60:
                c["r60"] += 1
            if active_days >= 90:
                c["r90"] += 1
            if st["n"] > 1:
                c["repeat"] += 1
        if u["id"] in credit_users:
            c["credit"] += 1

    rows = []
    for month in sorted(cohorts):
        c = cohorts[month]
        rows.append([
            month, c["size"], _pct(c["r30"], c["size"]), _pct(c["r60"], c["size"]),
            _pct(c["r90"], c["size"]), _pct(c["repeat"], c["size"]),
            _pct(c["credit"], c["size"]),
        ])
    return {
        "title": "Customer Cohort Analytics",
        "columns": ["Cohort", "Customers", "30d Retention %", "60d Retention %",
                    "90d Retention %", "Repeat %", "Credit Adoption %"],
        "rows": rows,
    }


# ── Report 05 — Credit utilization ───────────────────────
def credit_utilization(params=None):
    from credit.models import CreditAccount
    from crm.services import compute_risk

    accounts = list(CreditAccount.objects.select_related("user"))
    totals = {"limit": 0.0, "available": 0.0, "used": 0.0, "outstanding": 0.0}
    util_bands = {"0-25": 0, "25-50": 0, "50-75": 0, "75-100": 0, "100+": 0}
    risk_bands = {"low": 0, "medium": 0, "high": 0, "critical": 0}

    for a in accounts:
        totals["limit"] += _num(a.credit_limit)
        totals["available"] += _num(a.available)
        totals["used"] += _num(a.outstanding)
        totals["outstanding"] += _num(a.outstanding)
        util = _num(a.outstanding) / _num(a.credit_limit) * 100 if a.credit_limit else 0
        band = ("0-25" if util <= 25 else "25-50" if util <= 50 else
                "50-75" if util <= 75 else "75-100" if util <= 100 else "100+")
        util_bands[band] += 1
        risk_bands[compute_risk(a.user)["level"]] += 1

    rows = [[b, n, _pct(n, len(accounts))] for b, n in util_bands.items()]
    return {
        "title": "Credit Utilization",
        "summary": {
            "totalCreditLimit": round(totals["limit"], 2),
            "availableCredit": round(totals["available"], 2),
            "usedCredit": round(totals["used"], 2),
            "outstanding": round(totals["outstanding"], 2),
            "portfolioUtilization": _pct(totals["used"], totals["limit"]),
        },
        "columns": ["Utilization Band", "Accounts", "Share %"],
        "rows": rows,
        "charts": {"utilizationDistribution": util_bands, "riskDistribution": risk_bands},
    }


# ── Report 06 — Collection efficiency ────────────────────
def collection_efficiency(params=None):
    from payments.models import CashCollection

    qs = CashCollection.objects.all()
    assigned = qs.exclude(status="requested").count()
    completed = qs.filter(status="collected").count()
    failed = qs.filter(status="cancelled").count()

    spans = qs.filter(status="collected").exclude(collected_at__isnull=True).annotate(
        secs=F("collected_at") - F("created_at")
    ).values_list("secs", flat=True)[:2000]
    days = [s.total_seconds() / 86400 for s in spans if s is not None]
    avg_recovery = round(sum(days) / len(days), 1) if days else 0.0

    # Agent ranking (grouped).
    agent_rows = []
    for r in (
        qs.values("agent__name")
        .annotate(
            assigned=Count("id", filter=~Q(status="requested")),
            completed=Count("id", filter=Q(status="collected")),
            amount=Sum("amount", filter=Q(status="collected")),
        )
        .order_by("-completed")
    ):
        if r["agent__name"] is None:
            continue
        agent_rows.append([
            r["agent__name"], r["assigned"], r["completed"],
            _num(r["amount"]), _pct(r["completed"], r["assigned"]),
        ])

    # Zone ranking via the customer→zone map.
    umap = user_store_zone_map()
    zone_agg = {}
    for c in qs.values("user_id", "status", "amount"):
        z = umap.get(c["user_id"], {})
        name = z.get("zone__name")
        if not name:
            continue
        za = zone_agg.setdefault(name, {"assigned": 0, "completed": 0, "amount": 0.0})
        if c["status"] != "requested":
            za["assigned"] += 1
        if c["status"] == "collected":
            za["completed"] += 1
            za["amount"] += _num(c["amount"])
    zone_rows = sorted(
        ([n, v["assigned"], v["completed"], v["amount"], _pct(v["completed"], v["assigned"])]
         for n, v in zone_agg.items()),
        key=lambda x: x[2], reverse=True,
    )

    return {
        "title": "Collection Efficiency",
        "summary": {
            "assigned": assigned, "completed": completed, "failed": failed,
            "averageRecoveryTimeDays": avg_recovery,
            "successRate": _pct(completed, assigned),
        },
        "columns": ["Agent", "Assigned", "Completed", "Amount", "Success %"],
        "rows": agent_rows,
        "charts": {
            "zoneRankings": [
                {"zone": r[0], "assigned": r[1], "completed": r[2],
                 "amount": r[3], "successRate": r[4]} for r in zone_rows
            ],
        },
    }


EXECUTIVE_BUILDERS = {
    "recovery_performance": recovery_performance,
    "store_performance": store_performance,
    "zone_performance": zone_performance,
    "customer_cohorts": customer_cohorts,
    "credit_utilization": credit_utilization,
    "collection_efficiency": collection_efficiency,
    "dashboard": dashboard,
}
