"""Accounting admin (spec §MODULE 14): operational P&L, cash flow and agent
settlements. Figures derive live from orders, procurement (GRN), payments and
collections. COGS is a procurement-based proxy (clearly labelled) — full
weighted-average COGS lives in the inventory finance view."""
from datetime import timedelta
from decimal import Decimal

from django.db.models import Count, Sum
from django.utils import timezone
from rest_framework.response import Response
from rest_framework.views import APIView

from core.permissions import IsAdmin

ZERO = Decimal("0.00")
PER_DELIVERY = Decimal("20")
PER_COLLECTION = Decimal("30")


def _f(v):
    return float(v or 0)


def _window(request, default=30):
    try:
        days = max(1, int(request.query_params.get("days", default)))
    except ValueError:
        days = default
    end = timezone.now()
    return end - timedelta(days=days), end, days


class AccountingSummaryView(APIView):
    """GET /admin/accounting/summary?days=30 — operational P&L."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from inventory.models import GRN
        from orders.models import Order
        from payments.models import CashCollection, Payment

        start, end, days = _window(request)
        orders = Order.objects.exclude(status="cancelled").filter(placed_at__gte=start)
        rev = orders.aggregate(gmv=Sum("total"), pf=Sum("platform_fee"))
        revenue = _f(rev["gmv"])
        platform_fees = _f(rev["pf"])
        procurement = _f(
            GRN.objects.filter(status="posted", posted_at__gte=start).aggregate(s=Sum("total_cost"))["s"]
        )
        # Sum what was actually RECOVERED, not the amount we set out to recover,
        # and include partial collections — filtering to `collected` and summing
        # `amount` both overstated a full recovery and dropped partials entirely.
        collected = _f(
            CashCollection.objects.filter(
                status__in=(
                    CashCollection.Status.COLLECTED,
                    CashCollection.Status.PARTIALLY_COLLECTED,
                ),
                collected_at__gte=start,
            ).aggregate(s=Sum("collected_amount"))["s"]
        )
        # Payment.Status has no "captured" member (created|pending|success|
        # failed|refunded), so this filter matched nothing and the Repayments
        # KPI rendered a confident ₹0 forever.
        repayments = _f(
            Payment.objects.filter(
                purpose="repayment",
                status=Payment.Status.SUCCESS,
                created_at__gte=start,
            ).aggregate(s=Sum("amount"))["s"]
        )
        gross_profit = revenue - procurement
        return Response({
            "periodDays": days,
            "income": {
                "revenue": revenue,
                "platformFees": platform_fees,
                "cashCollected": collected,
                "repayments": repayments,
            },
            "expenses": {
                "procurement": procurement,
            },
            "pnl": {
                "grossRevenue": revenue,
                "cogsProxy": procurement,
                "grossProfit": gross_profit,
                "grossMarginPct": round(gross_profit / revenue * 100, 1) if revenue else 0.0,
            },
            "note": "COGS is a procurement (GRN) proxy for the period; see Inventory → Finance for weighted-average COGS.",
        })


class AccountingCashflowView(APIView):
    """GET /admin/accounting/cashflow?days=30 — daily inflow vs outflow."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from inventory.models import GRN
        from orders.models import Order
        from payments.models import CashCollection

        start, end, days = _window(request)
        today = timezone.now().date()
        series = []
        for i in range(days - 1, -1, -1):
            d = today - timedelta(days=i)
            inflow = _f(Order.objects.exclude(status="cancelled").filter(placed_at__date=d).aggregate(s=Sum("total"))["s"])
            inflow += _f(CashCollection.objects.filter(status="collected", collected_at__date=d).aggregate(s=Sum("amount"))["s"])
            outflow = _f(GRN.objects.filter(status="posted", posted_at__date=d).aggregate(s=Sum("total_cost"))["s"])
            series.append({"date": d.isoformat(), "inflow": round(inflow, 2), "outflow": round(outflow, 2), "net": round(inflow - outflow, 2)})
        return Response({"periodDays": days, "series": series})


class AccountingByStoreView(APIView):
    """GET /admin/accounting/by-store?days=30 — revenue, procurement and margin per
    store (answers 'where is the money coming from / going to')."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from inventory.models import GRN
        from orders.models import Order
        from stores.models import Store

        start, end, days = _window(request)
        stores = {s.id: {"storeId": str(s.id), "store": s.name, "warehouseId": s.warehouse_id,
                         "revenue": 0.0, "orders": 0, "platformFees": 0.0, "procurement": 0.0}
                  for s in Store.objects.all()}
        unassigned = {"storeId": None, "store": "Unassigned", "warehouseId": None,
                      "revenue": 0.0, "orders": 0, "platformFees": 0.0, "procurement": 0.0}

        for r in (
            Order.objects.exclude(status="cancelled").filter(placed_at__gte=start)
            .values("store_id").annotate(rev=Sum("total"), n=Count("id"), pf=Sum("platform_fee"))
        ):
            b = stores.get(r["store_id"], unassigned)
            b["revenue"] += _f(r["rev"])
            b["orders"] += r["n"]
            b["platformFees"] += _f(r["pf"])

        wh_to_store = {s["warehouseId"]: sid for sid, s in stores.items() if s["warehouseId"]}
        for r in (
            GRN.objects.filter(status="posted", posted_at__gte=start)
            .values("warehouse_id").annotate(c=Sum("total_cost"))
        ):
            sid = wh_to_store.get(r["warehouse_id"])
            b = stores.get(sid, unassigned)
            b["procurement"] += _f(r["c"])

        rows = list(stores.values())
        if unassigned["revenue"] or unassigned["orders"] or unassigned["procurement"]:
            rows.append(unassigned)
        for b in rows:
            b["margin"] = round(b["revenue"] - b["procurement"], 2)
            b["revenue"] = round(b["revenue"], 2)
            b["procurement"] = round(b["procurement"], 2)
            b["platformFees"] = round(b["platformFees"], 2)
        rows.sort(key=lambda b: b["revenue"], reverse=True)
        return Response({"periodDays": days, "stores": rows})


class AccountingSettlementsView(APIView):
    """GET /admin/accounting/settlements — payable to each agent (deliveries +
    collections + incentives)."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from accounts.models import Role, User
        from agents.models import AgentIncentive
        from delivery.models import DeliveryTask
        from payments.models import CashCollection

        rows = []
        for u in User.objects.filter(role=Role.AGENT):
            deliveries = DeliveryTask.objects.filter(agent=u, status="delivered").count()
            collections = CashCollection.objects.filter(agent=u, status="collected").count()
            incentives = AgentIncentive.objects.filter(agent=u).aggregate(s=Sum("amount"))["s"] or ZERO
            base = deliveries * PER_DELIVERY + collections * PER_COLLECTION
            payable = base + incentives
            if payable <= 0:
                continue
            rows.append({
                "agentId": str(u.id),
                "name": u.name or u.phone,
                "deliveries": deliveries,
                "collections": collections,
                "incentives": _f(incentives),
                "base": _f(base),
                "payable": _f(payable),
            })
        rows.sort(key=lambda r: r["payable"], reverse=True)
        total = sum(r["payable"] for r in rows)
        return Response({"settlements": rows, "totalPayable": round(total, 2)})
