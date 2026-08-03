"""
Enterprise inventory analytics for the Super-Admin command center.

These are READ aggregations over the existing immutable ledger + StockItem cache
(plus a physical-count writer). Everything here is derived from real data. Two
heuristics are clearly labelled as assumptions because the backend does not track
the underlying signal yet:

  * LEAD_TIME_DAYS — supplier lead time is not modelled, so the reorder engine and
    transfer suggestions assume a flat lead time.
  * CARRYING_RATE — annual inventory holding-cost rate used for the finance view.

No demand forecasting / seasonality is attempted (needs historical depth + a model);
the velocity figures are trailing-window actuals, not predictions.
"""
import math
from datetime import timedelta
from decimal import Decimal

from django.db.models import Max, Sum
from django.utils import timezone
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import Product
from core.permissions import IsAdmin
from stores.models import Store

from .models import (
    GRN,
    InventoryLedger,
    LowStockAlert,
    PurchaseOrder,
    StockBatch,
    StockItem,
    StockTransfer,
    Warehouse,
)
from .services import InventoryService, stock_valuation, weighted_average_cost

ZERO = Decimal("0.00")

# ── Heuristic assumptions (surfaced to the UI as such) ───────────────────
LEAD_TIME_DAYS = 5
CARRYING_RATE = Decimal("0.24")  # 24%/yr typical FMCG carrying cost
DEAD_STOCK_DAYS = 90
VELOCITY_WINDOW = 30

SALE_TYPES = [InventoryLedger.Type.SALE, InventoryLedger.Type.ORDER]
INBOUND_TYPES = [
    InventoryLedger.Type.GRN,
    InventoryLedger.Type.PURCHASE,
    InventoryLedger.Type.TRANSFER_IN,
]
SHRINK_TYPES = [InventoryLedger.Type.DAMAGE, InventoryLedger.Type.EXPIRY]


def _now():
    return timezone.now()


def _units_sold(since, *, by_warehouse=False):
    """Map of product_id (or (product_id, warehouse_id)) -> units sold since `since`."""
    fields = ["product_id"] + (["warehouse_id"] if by_warehouse else [])
    rows = (
        InventoryLedger.objects.filter(type__in=SALE_TYPES, created_at__gte=since)
        .values(*fields)
        .annotate(q=Sum("quantity"))
    )
    out = {}
    for r in rows:
        key = (r["product_id"], r["warehouse_id"]) if by_warehouse else r["product_id"]
        out[key] = -int(r["q"] or 0)  # ledger stores sales as negative
    return out


def _last_sale_map():
    rows = (
        InventoryLedger.objects.filter(type__in=SALE_TYPES)
        .values("product_id")
        .annotate(last=Max("created_at"))
    )
    return {r["product_id"]: r["last"] for r in rows}


def _valuation_index(warehouse=None):
    """stock_valuation rows + handy aggregates. Returns (rows, by_pw, value_by_product,
    wac_by_product)."""
    rows = stock_valuation(warehouse=warehouse)
    by_pw = {}
    value_by_product = {}
    wac_qty = {}
    wac_cost = {}
    for r in rows:
        pid = str(r["product_id"])
        wid = str(r["warehouse_id"])
        by_pw[(pid, wid)] = r
        value_by_product[pid] = value_by_product.get(pid, ZERO) + r["value"]
        wac_qty[pid] = wac_qty.get(pid, 0) + r["quantity"]
        wac_cost[pid] = wac_cost.get(pid, ZERO) + r["unit_cost"] * r["quantity"]
    wac_by_product = {
        pid: (wac_cost[pid] / wac_qty[pid]).quantize(Decimal("0.01"))
        if wac_qty.get(pid)
        else ZERO
        for pid in value_by_product
    }
    return rows, by_pw, value_by_product, wac_by_product


class NetworkOverviewView(APIView):
    """GET /inventory/overview — network command-center KPIs."""

    permission_classes = [IsAdmin]

    def get(self, request):
        now = _now()
        today = now.date()
        rows, _, value_by_product, wac_by_product = _valuation_index()

        total_value = sum((r["value"] for r in rows), ZERO)
        total_units = sum((r["quantity"] for r in rows), 0)
        total_skus = len({r["product_id"] for r in rows})

        low = LowStockAlert.objects.filter(status=LowStockAlert.Status.ACTIVE).count()

        # OOS = active products whose network on-hand is zero
        on_hand_by_product = {}
        for si in StockItem.objects.values("product_id").annotate(q=Sum("quantity")):
            on_hand_by_product[si["product_id"]] = si["q"] or 0
        active_ids = set(
            Product.objects.filter(is_active=True).values_list("id", flat=True)
        )
        oos = sum(1 for pid in active_ids if on_hand_by_product.get(pid, 0) <= 0)

        damaged_units = StockItem.objects.aggregate(s=Sum("damaged"))["s"] or 0
        damaged_value = ZERO
        for si in StockItem.objects.filter(damaged__gt=0).select_related("product", "warehouse"):
            damaged_value += Decimal(si.damaged) * weighted_average_cost(si.product, si.warehouse)

        # Dead stock (no sale in DEAD_STOCK_DAYS, still holding stock)
        last_sale = _last_sale_map()
        cutoff = now - timedelta(days=DEAD_STOCK_DAYS)
        dead_count = 0
        dead_value = ZERO
        for pid, qty in on_hand_by_product.items():
            if qty <= 0:
                continue
            ls = last_sale.get(pid)
            if ls is None or ls < cutoff:
                dead_count += 1
                dead_value += value_by_product.get(str(pid), ZERO)

        near = StockBatch.objects.filter(
            quantity__gt=0, expiry_date__isnull=False, expiry_date__lte=today + timedelta(days=30)
        )
        near_expiry_value = sum((Decimal(b.quantity) * b.unit_cost for b in near), ZERO)

        pending_po = PurchaseOrder.objects.exclude(
            status__in=["received", "cancelled", "closed"]
        ).count()
        pending_transfers = StockTransfer.objects.filter(
            status=StockTransfer.Status.PENDING
        ).count()

        consumed_today = -(
            InventoryLedger.objects.filter(type__in=SALE_TYPES, created_at__date=today).aggregate(
                s=Sum("quantity")
            )["s"]
            or 0
        )
        received_today = (
            InventoryLedger.objects.filter(type__in=INBOUND_TYPES, created_at__date=today).aggregate(
                s=Sum("quantity")
            )["s"]
            or 0
        )

        return Response(
            {
                "total_inventory_value": total_value,
                "total_skus": total_skus,
                "total_units": total_units,
                "low_stock": low,
                "out_of_stock": oos,
                "damaged_units": damaged_units,
                "damaged_value": damaged_value,
                "dead_stock_count": dead_count,
                "dead_stock_value": dead_value,
                "near_expiry_value": near_expiry_value,
                "pending_purchase_orders": pending_po,
                "pending_transfers": pending_transfers,
                "consumption_today": consumed_today,
                "replenishment_today": received_today,
            }
        )


class StoreRollupView(APIView):
    """GET /inventory/stores — per-store inventory health for the network grid."""

    permission_classes = [IsAdmin]

    def get(self, request):
        now = _now()
        today = now.date()
        sold_today = {}
        for r in (
            InventoryLedger.objects.filter(type__in=SALE_TYPES, created_at__date=today)
            .values("warehouse_id")
            .annotate(q=Sum("quantity"))
        ):
            sold_today[r["warehouse_id"]] = -int(r["q"] or 0)

        out = []
        stores = Store.objects.select_related("warehouse").filter(warehouse__isnull=False)
        for store in stores:
            wh = store.warehouse
            items = list(StockItem.objects.filter(warehouse=wh).select_related("product"))
            tracked = len(items)
            in_stock = sum(1 for i in items if i.available > 0)
            low = sum(1 for i in items if 0 < i.available < i.low_stock_threshold)
            oos = sum(1 for i in items if i.available <= 0)
            value = ZERO
            for i in items:
                if i.quantity > 0:
                    value += Decimal(i.quantity) * weighted_average_cost(i.product, wh)
            fill_rate = round(in_stock / tracked * 100) if tracked else 0
            # health score (heuristic): fill rate, penalised by low-stock share
            low_pct = (low / tracked * 100) if tracked else 0
            health = max(0, min(100, round(fill_rate - low_pct * 0.3)))
            pending_t = StockTransfer.objects.filter(
                status=StockTransfer.Status.PENDING
            ).filter(from_warehouse=wh).count() + StockTransfer.objects.filter(
                status=StockTransfer.Status.PENDING, to_warehouse=wh
            ).count()
            out.append(
                {
                    "store_id": str(store.id),
                    "store_name": store.name,
                    "warehouse_id": str(wh.id),
                    "status": store.status,
                    "inventory_value": value.quantize(Decimal("0.01")),
                    "sku_count": tracked,
                    "low_stock": low,
                    "out_of_stock": oos,
                    "fill_rate": fill_rate,
                    "health_score": health,
                    "sales_today": sold_today.get(wh.id, 0),
                    "pending_transfers": pending_t,
                }
            )
        out.sort(key=lambda s: s["inventory_value"], reverse=True)
        return Response(out)


class HeatmapView(APIView):
    """GET /inventory/heatmap?limit=40 — product × store on-hand matrix (top products)."""

    permission_classes = [IsAdmin]

    def get(self, request):
        try:
            limit = min(int(request.query_params.get("limit", 40)), 100)
        except ValueError:
            limit = 40
        stores = list(
            Store.objects.select_related("warehouse").filter(warehouse__isnull=False)
        )
        wh_to_store = {s.warehouse_id: s for s in stores}

        _, _, value_by_product, _ = _valuation_index()
        top_ids = [int(pid) for pid, _ in sorted(value_by_product.items(), key=lambda kv: kv[1], reverse=True)[:limit]]

        qty = {}
        for si in StockItem.objects.filter(product_id__in=top_ids, warehouse_id__in=wh_to_store.keys()):
            qty[(si.product_id, si.warehouse_id)] = si.quantity
        names = {p.id: p.name for p in Product.objects.filter(id__in=top_ids)}

        products = []
        for pid in top_ids:
            products.append(
                {
                    "product_id": str(pid),
                    "name": names.get(pid, f"#{pid}"),
                    "cells": {str(s.warehouse_id): qty.get((pid, s.warehouse_id), 0) for s in stores},
                }
            )
        return Response(
            {
                "stores": [
                    {"warehouse_id": str(s.warehouse_id), "store_name": s.name} for s in stores
                ],
                "products": products,
            }
        )


class MoversView(APIView):
    """GET /inventory/movers?days=30&limit=10 — fast & slow movers by sales velocity."""

    permission_classes = [IsAdmin]

    def get(self, request):
        try:
            days = max(1, int(request.query_params.get("days", VELOCITY_WINDOW)))
            limit = min(int(request.query_params.get("limit", 10)), 50)
        except ValueError:
            days, limit = VELOCITY_WINDOW, 10
        since = _now() - timedelta(days=days)
        sold = _units_sold(since)
        last_sale = _last_sale_map()
        _, _, value_by_product, _ = _valuation_index()
        on_hand = {
            r["product_id"]: r["q"] or 0
            for r in StockItem.objects.values("product_id").annotate(q=Sum("quantity"))
        }
        # Every product that moved or holds stock — NOT just active ones. A catalog
        # delete is a soft-delete (catalog.admin_views sets is_active=False), and an
        # archived product keeps its stock and its ledger history, so filtering on
        # is_active here left those rows rendering as the raw "#<pk>" fallback.
        names = {p.id: (p.name, p.price, p.is_active) for p in Product.objects.all()}

        def row(pid):
            name, price, active = names.get(pid, (f"#{pid}", ZERO, True))
            units = sold.get(pid, 0)
            return {
                "product_id": str(pid),
                "name": name,
                "archived": not active,
                "units_sold": units,
                "revenue": (Decimal(units) * price).quantize(Decimal("0.01")),
                "on_hand": on_hand.get(pid, 0),
                "value": value_by_product.get(str(pid), ZERO),
                "last_sale": last_sale.get(pid),
            }

        fast = sorted(
            (row(pid) for pid in sold if sold[pid] > 0),
            key=lambda r: r["units_sold"],
            reverse=True,
        )[:limit]
        # slow = products that still hold stock but sold the least in the window
        slow_ids = [pid for pid, q in on_hand.items() if q > 0]
        slow = sorted((row(pid) for pid in slow_ids), key=lambda r: r["units_sold"])[:limit]
        return Response({"days": days, "fast": fast, "slow": slow})


class DeadStockView(APIView):
    """GET /inventory/dead-stock?days=90 — stock with no sale in N days."""

    permission_classes = [IsAdmin]

    def get(self, request):
        try:
            days = max(1, int(request.query_params.get("days", DEAD_STOCK_DAYS)))
        except ValueError:
            days = DEAD_STOCK_DAYS
        now = _now()
        cutoff = now - timedelta(days=days)
        last_sale = _last_sale_map()
        _, _, value_by_product, _ = _valuation_index()
        on_hand = {
            r["product_id"]: r["q"] or 0
            for r in StockItem.objects.values("product_id").annotate(q=Sum("quantity"))
        }
        names = {p.id: p.name for p in Product.objects.all()}
        archived = set(
            Product.objects.filter(is_active=False).values_list("id", flat=True)
        )
        out = []
        for pid, qty in on_hand.items():
            if qty <= 0:
                continue
            ls = last_sale.get(pid)
            if ls is not None and ls >= cutoff:
                continue
            out.append(
                {
                    "product_id": str(pid),
                    "name": names.get(pid, f"#{pid}"),
                    "archived": pid in archived,
                    "quantity": qty,
                    "value": value_by_product.get(str(pid), ZERO),
                    "last_sale": ls,
                    "days_since_sale": (now - ls).days if ls else None,
                }
            )
        out.sort(key=lambda r: r["value"], reverse=True)
        return Response({"days": days, "items": out})


class AgingExpiryView(APIView):
    """GET /inventory/aging — batch aging buckets + near-expiry list."""

    permission_classes = [IsAdmin]

    def get(self, request):
        now = _now()
        today = now.date()
        batches = list(
            StockBatch.objects.filter(quantity__gt=0).select_related("product", "warehouse")
        )
        # aging by batch age (receipt -> now)
        buckets = {"0-30": [0, ZERO], "30-60": [0, ZERO], "60-90": [0, ZERO], "90+": [0, ZERO]}
        for b in batches:
            age = (now - b.created_at).days
            key = "0-30" if age <= 30 else "30-60" if age <= 60 else "60-90" if age <= 90 else "90+"
            buckets[key][0] += b.quantity
            buckets[key][1] += Decimal(b.quantity) * b.unit_cost
        aging = [
            {"bucket": k, "quantity": v[0], "value": v[1].quantize(Decimal("0.01"))}
            for k, v in buckets.items()
        ]

        near = []
        for b in batches:
            if not b.expiry_date:
                continue
            dte = (b.expiry_date - today).days
            if dte <= 30:
                near.append(
                    {
                        "product_id": str(b.product_id),
                        "name": b.product.name,
                        "warehouse_id": str(b.warehouse_id),
                        "batch_no": b.batch_no,
                        "expiry_date": b.expiry_date,
                        "quantity": b.quantity,
                        "value": (Decimal(b.quantity) * b.unit_cost).quantize(Decimal("0.01")),
                        "days_to_expiry": dte,
                    }
                )
        near.sort(key=lambda r: r["days_to_expiry"])
        return Response({"aging": aging, "near_expiry": near})


class FinanceView(APIView):
    """GET /inventory/finance?days=30 — turnover, GMROI, holding & shrinkage."""

    permission_classes = [IsAdmin]

    def get(self, request):
        try:
            days = max(1, int(request.query_params.get("days", 30)))
        except ValueError:
            days = 30
        now = _now()
        since = now - timedelta(days=days)
        rows, _, value_by_product, wac_by_product = _valuation_index()
        total_value = sum((r["value"] for r in rows), ZERO)

        sold = _units_sold(since)
        prices = {str(p.id): p.price for p in Product.objects.all()}
        cogs = ZERO
        gross_margin = ZERO
        for pid, units in sold.items():
            wac = wac_by_product.get(str(pid), prices.get(str(pid), ZERO))
            price = prices.get(str(pid), ZERO)
            cogs += Decimal(units) * wac
            gross_margin += Decimal(units) * (price - wac)

        annualizer = Decimal(365) / Decimal(days)
        cogs_annual = (cogs * annualizer).quantize(Decimal("0.01"))
        turnover = (cogs_annual / total_value).quantize(Decimal("0.01")) if total_value else ZERO
        gmroi = (gross_margin / total_value).quantize(Decimal("0.01")) if total_value else ZERO
        holding = (total_value * CARRYING_RATE * Decimal(days) / Decimal(365)).quantize(Decimal("0.01"))

        shrink_units = 0
        shrink_value = ZERO
        for r in (
            InventoryLedger.objects.filter(type__in=SHRINK_TYPES, created_at__gte=since)
            .values("product_id")
            .annotate(q=Sum("quantity"))
        ):
            u = -int(r["q"] or 0)
            shrink_units += u
            shrink_value += Decimal(u) * wac_by_product.get(str(r["product_id"]), ZERO)

        # dead stock value (90d)
        last_sale = _last_sale_map()
        cutoff = now - timedelta(days=DEAD_STOCK_DAYS)
        on_hand = {
            r["product_id"]: r["q"] or 0
            for r in StockItem.objects.values("product_id").annotate(q=Sum("quantity"))
        }
        dead_value = ZERO
        for pid, qty in on_hand.items():
            if qty > 0 and (last_sale.get(pid) is None or last_sale.get(pid) < cutoff):
                dead_value += value_by_product.get(str(pid), ZERO)

        expected_revenue = ZERO
        margin_potential = ZERO
        for si in StockItem.objects.select_related("product"):
            if si.available > 0:
                price = si.product.price
                expected_revenue += Decimal(si.available) * price
                margin_potential += Decimal(si.available) * (price - wac_by_product.get(str(si.product_id), ZERO))

        return Response(
            {
                "period_days": days,
                "inventory_value": total_value,
                "cogs_period": cogs.quantize(Decimal("0.01")),
                "cogs_annualized": cogs_annual,
                "gross_margin_period": gross_margin.quantize(Decimal("0.01")),
                "turnover_ratio": turnover,
                "gmroi": gmroi,
                "holding_cost": holding,
                "shrinkage_units": shrink_units,
                "shrinkage_value": shrink_value.quantize(Decimal("0.01")),
                "shrinkage_pct": (shrink_value / total_value * 100).quantize(Decimal("0.01"))
                if total_value
                else ZERO,
                "dead_stock_value": dead_value.quantize(Decimal("0.01")),
                "expected_revenue": expected_revenue.quantize(Decimal("0.01")),
                "margin_potential": margin_potential.quantize(Decimal("0.01")),
                "assumptions": {"carrying_rate": CARRYING_RATE, "lead_time_days": LEAD_TIME_DAYS},
            }
        )


class ReorderView(APIView):
    """GET /inventory/reorder — reorder recommendations (avg daily × lead time + safety)."""

    permission_classes = [IsAdmin]

    def get(self, request):
        try:
            lead = max(1, int(request.query_params.get("lead_time", LEAD_TIME_DAYS)))
        except ValueError:
            lead = LEAD_TIME_DAYS
        since = _now() - timedelta(days=VELOCITY_WINDOW)
        sold_pw = _units_sold(since, by_warehouse=True)
        wh_names = {w.id: w.code for w in Warehouse.objects.all()}
        store_names = {s.warehouse_id: s.name for s in Store.objects.filter(warehouse__isnull=False)}

        out = []
        for si in StockItem.objects.select_related("product", "warehouse"):
            units = sold_pw.get((si.product_id, si.warehouse_id), 0)
            avg_daily = units / VELOCITY_WINDOW
            safety = si.low_stock_threshold
            available = si.available
            suggested = math.ceil(avg_daily * lead + safety - available)
            if suggested <= 0 and available >= safety:
                continue
            days_left = round(available / avg_daily, 1) if avg_daily > 0 else None
            out.append(
                {
                    "product_id": str(si.product_id),
                    "name": si.product.name,
                    "warehouse_id": str(si.warehouse_id),
                    "warehouse": store_names.get(si.warehouse_id) or wh_names.get(si.warehouse_id, ""),
                    "available": available,
                    "avg_daily_sales": round(avg_daily, 2),
                    "days_remaining": days_left,
                    "safety_stock": safety,
                    "suggested_qty": max(0, suggested),
                }
            )
        out.sort(key=lambda r: (r["days_remaining"] is None, r["days_remaining"] if r["days_remaining"] is not None else 1e9))
        return Response({"lead_time_days": lead, "items": out})


class TransferSuggestionView(APIView):
    """GET /inventory/transfer-suggestions — move surplus to shortage, per product."""

    permission_classes = [IsAdmin]

    def get(self, request):
        lead = LEAD_TIME_DAYS
        since = _now() - timedelta(days=VELOCITY_WINDOW)
        sold_pw = _units_sold(since, by_warehouse=True)
        names = {p.id: p.name for p in Product.objects.all()}
        store_names = {s.warehouse_id: s.name for s in Store.objects.filter(warehouse__isnull=False)}
        wh_codes = {w.id: w.code for w in Warehouse.objects.all()}

        # group stock items by product
        by_product = {}
        for si in StockItem.objects.all():
            by_product.setdefault(si.product_id, []).append(si)

        out = []
        for pid, items in by_product.items():
            surpluses, shortages = [], []
            for si in items:
                avg_daily = sold_pw.get((pid, si.warehouse_id), 0) / VELOCITY_WINDOW
                need = avg_daily * lead + si.low_stock_threshold
                diff = si.available - need
                if diff > si.low_stock_threshold:  # meaningful surplus
                    surpluses.append((si.warehouse_id, int(diff)))
                elif diff < 0:
                    shortages.append((si.warehouse_id, int(-diff)))
            if not surpluses or not shortages:
                continue
            surpluses.sort(key=lambda x: x[1], reverse=True)
            shortages.sort(key=lambda x: x[1], reverse=True)
            for sh_wh, sh_qty in shortages:
                for idx, (su_wh, su_qty) in enumerate(surpluses):
                    if su_qty <= 0:
                        continue
                    move = min(su_qty, sh_qty)
                    if move <= 0:
                        continue
                    out.append(
                        {
                            "product_id": str(pid),
                            "name": names.get(pid, f"#{pid}"),
                            "from_warehouse_id": str(su_wh),
                            "from_warehouse": store_names.get(su_wh) or wh_codes.get(su_wh, ""),
                            "to_warehouse_id": str(sh_wh),
                            "to_warehouse": store_names.get(sh_wh) or wh_codes.get(sh_wh, ""),
                            "quantity": move,
                            "reason": "Surplus at source vs shortage at destination",
                        }
                    )
                    surpluses[idx] = (su_wh, su_qty - move)
                    sh_qty -= move
                    if sh_qty <= 0:
                        break
        return Response({"lead_time_days": lead, "suggestions": out})


class ProductOverviewView(APIView):
    """GET /inventory/products/<id>/overview — full product inventory intelligence."""

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        product = get_object_or_404(Product, pk=pk)
        now = _now()
        wac = weighted_average_cost(product, None) if False else None  # per-warehouse below

        # distribution per warehouse
        store_by_wh = {s.warehouse_id: s.name for s in Store.objects.filter(warehouse__isnull=False)}
        wh_codes = {w.id: w.code for w in Warehouse.objects.all()}
        distribution = []
        on_hand = reserved = available = damaged = 0
        net_value = ZERO
        costs = []
        for si in StockItem.objects.filter(product=product).select_related("warehouse"):
            wcost = weighted_average_cost(product, si.warehouse)
            costs.append((si.quantity, wcost))
            distribution.append(
                {
                    "warehouse_id": str(si.warehouse_id),
                    "warehouse": store_by_wh.get(si.warehouse_id) or wh_codes.get(si.warehouse_id, ""),
                    "on_hand": si.quantity,
                    "reserved": si.reserved,
                    "available": si.available,
                    "damaged": si.damaged,
                }
            )
            on_hand += si.quantity
            reserved += si.reserved
            available += si.available
            damaged += si.damaged
            net_value += Decimal(si.quantity) * wcost
        tot_qty = sum(c[0] for c in costs)
        wac_avg = (sum((Decimal(c[0]) * c[1] for c in costs), ZERO) / tot_qty).quantize(Decimal("0.01")) if tot_qty else product.price

        # velocity
        def sold_in(days):
            since = now - timedelta(days=days)
            q = InventoryLedger.objects.filter(
                product=product, type__in=SALE_TYPES, created_at__gte=since
            ).aggregate(s=Sum("quantity"))["s"]
            return -int(q or 0)

        u7, u30, u90 = sold_in(7), sold_in(30), sold_in(90)
        last_sale = (
            InventoryLedger.objects.filter(product=product, type__in=SALE_TYPES)
            .aggregate(last=Max("created_at"))["last"]
        )
        avg_daily = u30 / 30
        days_remaining = round(available / avg_daily, 1) if avg_daily > 0 else None
        suggested = max(0, math.ceil(avg_daily * LEAD_TIME_DAYS + 0 - available)) if avg_daily else 0

        # supplier history (from purchase orders)
        from .models import PurchaseOrderItem

        supplier_rows = {}
        for poi in (
            PurchaseOrderItem.objects.filter(product=product)
            .select_related("purchase_order", "purchase_order__supplier")
        ):
            po = poi.purchase_order
            sup = getattr(po, "supplier", None)
            name = sup.name if sup else "—"
            agg = supplier_rows.setdefault(name, {"supplier": name, "qty": 0, "cost_sum": ZERO, "n": 0, "last": None})
            agg["qty"] += poi.quantity
            agg["cost_sum"] += poi.unit_cost * poi.quantity
            agg["n"] += 1
            ts = po.created_at
            if agg["last"] is None or (ts and ts > agg["last"]):
                agg["last"] = ts
        suppliers = [
            {
                "supplier": v["supplier"],
                "total_qty": v["qty"],
                "avg_cost": (v["cost_sum"] / v["qty"]).quantize(Decimal("0.01")) if v["qty"] else ZERO,
                "orders": v["n"],
                "last_order": v["last"],
            }
            for v in supplier_rows.values()
        ]

        ledger = [
            {
                "id": str(e.id),
                "warehouse_id": str(e.warehouse_id),
                "type": e.type,
                "quantity": e.quantity,
                "balance_after": e.balance_after,
                "note": e.note,
                "created_at": e.created_at,
            }
            for e in InventoryLedger.objects.filter(product=product).order_by("-id")[:30]
        ]

        return Response(
            {
                "summary": {
                    "id": str(product.id),
                    "name": product.name,
                    "brand": product.brand,
                    "category": product.category.name if product.category_id else "",
                    "unit": product.unit,
                    "selling_price": product.price,
                    "mrp": product.mrp,
                    "credit_price": product.credit_price,
                    "avg_cost": wac_avg,
                    "margin": (product.price - wac_avg).quantize(Decimal("0.01")),
                    "margin_pct": ((product.price - wac_avg) / product.price * 100).quantize(Decimal("0.01"))
                    if product.price
                    else ZERO,
                },
                "totals": {
                    "on_hand": on_hand,
                    "reserved": reserved,
                    "available": available,
                    "damaged": damaged,
                    "network_value": net_value.quantize(Decimal("0.01")),
                },
                "distribution": distribution,
                "velocity": {
                    "units_7d": u7,
                    "units_30d": u30,
                    "units_90d": u90,
                    "avg_daily": round(avg_daily, 2),
                    "last_sale": last_sale,
                },
                "reorder": {
                    "avg_daily": round(avg_daily, 2),
                    "days_remaining": days_remaining,
                    "suggested_qty": suggested,
                    "lead_time_days": LEAD_TIME_DAYS,
                },
                "suppliers": suppliers,
                "ledger": ledger,
            }
        )


class PhysicalCountView(APIView):
    """POST /inventory/physical-count — record a counted figure, post the variance."""

    permission_classes = [IsAdmin]

    def post(self, request):
        product = get_object_or_404(Product, pk=request.data.get("product"))
        wh_id = request.data.get("warehouse")
        warehouse = Warehouse.objects.filter(pk=wh_id).first() if wh_id else None
        counted = int(request.data.get("counted", 0))
        reason = request.data.get("reason", "")
        from .services import StockCalculationService

        system = StockCalculationService.on_hand(product, warehouse) if warehouse else (product.stock_count or 0)
        new_count = InventoryService.adjust(
            product,
            set=counted,
            warehouse=warehouse,
            reason=f"Physical count: {reason}".strip(": "),
            created_by=request.user,
        )
        from ops.models import StockAdjustment

        StockAdjustment.objects.create(
            product=product, delta=new_count - system, new_count=new_count, reason=f"Physical count: {reason}", by=request.user
        )
        return Response(
            {
                "product_id": str(product.id),
                "system_count": system,
                "physical_count": counted,
                "variance": counted - system,
                "new_count": new_count,
            }
        )


class StoreProductsView(APIView):
    """GET /inventory/stores/<wid>/products — a store's catalog: per-store stock +
    availability + selling price (store-centric Products tab)."""

    permission_classes = [IsAdmin]

    def get(self, request, wid):
        from stores.models import StoreProduct
        from stores.services import warehouse_store

        warehouse = Warehouse.objects.filter(pk=wid).first()
        if warehouse is None:
            return Response([])
        store = warehouse_store(warehouse)
        sp_map = {}
        if store is not None:
            sp_map = {sp.product_id: sp for sp in StoreProduct.objects.filter(store=store)}

        rows = []
        for si in StockItem.objects.filter(warehouse=warehouse).select_related("product"):
            p = si.product
            sp = sp_map.get(p.id)
            rows.append(
                {
                    "product_id": str(p.id),
                    "name": p.name,
                    "brand": p.brand,
                    "on_hand": si.quantity,
                    "reserved": si.reserved,
                    "available": si.available,
                    "low_stock_threshold": si.low_stock_threshold,
                    "is_available": sp.is_available if sp else True,
                    "global_price": p.price,
                    "store_price": sp.selling_price if (sp and sp.selling_price is not None) else None,
                    "effective_price": sp.selling_price if (sp and sp.selling_price is not None) else p.price,
                    "mrp": sp.mrp if (sp and sp.mrp is not None) else p.mrp,
                }
            )
        rows.sort(key=lambda r: r["name"])
        return Response(rows)


class StoreProductDetailView(APIView):
    """PATCH /inventory/stores/<wid>/products/<pid> — set per-store availability /
    selling price / mrp / reorder level (upserts a StoreProduct)."""

    permission_classes = [IsAdmin]

    def patch(self, request, wid, pid):
        from stores.models import StoreProduct
        from stores.services import warehouse_store
        from .services import set_reorder_level

        warehouse = get_object_or_404(Warehouse, pk=wid)
        store = warehouse_store(warehouse)
        product = get_object_or_404(Product, pk=pid)
        if store is None:
            return Response(
                {"error": {"code": "no_store", "message": "Warehouse has no store.", "fields": {}}},
                status=400,
            )
        sp, _ = StoreProduct.objects.get_or_create(store=store, product=product)
        data = request.data
        if "is_available" in data:
            sp.is_available = bool(data["is_available"])
        if "selling_price" in data:
            v = data["selling_price"]
            sp.selling_price = None if v in ("", None) else Decimal(str(v))
        if "mrp" in data:
            v = data["mrp"]
            sp.mrp = None if v in ("", None) else Decimal(str(v))
        sp.save()
        if "reorder_level" in data and data["reorder_level"] not in ("", None):
            set_reorder_level(product, threshold=int(data["reorder_level"]), warehouse=warehouse)
        si = StockItem.objects.filter(warehouse=warehouse, product=product).first()
        return Response(
            {
                "product_id": str(product.id),
                "is_available": sp.is_available,
                "store_price": sp.selling_price,
                "mrp": sp.mrp if sp.mrp is not None else product.mrp,
                "low_stock_threshold": si.low_stock_threshold if si else None,
            }
        )


class AuditTrailView(APIView):
    """GET /inventory/audit — recent stock adjustments / variance events."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from ops.models import StockAdjustment

        rows = StockAdjustment.objects.select_related("product", "by").order_by("-created_at")[:100]
        return Response(
            [
                {
                    "id": str(a.id),
                    "product": a.product.name,
                    "delta": a.delta,
                    "new_count": a.new_count,
                    "reason": a.reason,
                    "by": a.by.name if a.by else "—",
                    "created_at": a.created_at,
                }
                for a in rows
            ]
        )
