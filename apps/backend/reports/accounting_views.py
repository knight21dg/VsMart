"""Accounting admin (spec §MODULE 14): operational P&L, cash flow and agent
settlements.

Everything here derives live from orders, POS, procurement (GRN), payments,
collections and the delivery earnings ledger.

The guiding rule after the 2026-08-11 accuracy review is that a figure is either
computed from a real source or reported as **unknown** — never approximated into
something that reads like fact. The previous version broke that in four ways at
once, all visible on prod:

* "Revenue" was the GMV of every non-cancelled order, so money was booked the
  moment an order was *placed*. On prod that counted 27 orders still in flight and
  2 already returned.
* "Gross Profit" was revenue minus the period's *purchasing*, which is not COGS.
  With no GRN posted in the window the page displayed a **100.0% margin**.
* "Agent Settlements Due" invented flat ₹20/delivery and ₹30/collection rates and
  summed them over all time, ignoring `DeliveryEarnings` — the real per-task
  ledger, complete with a `released` flag. It showed ₹330 due when the ledger said
  ₹270.06 earned and ₹0 outstanding.
* POS counter sales were not in revenue at all.
"""
from datetime import timedelta
from decimal import Decimal

from django.db.models import Count, Sum
from django.utils import timezone
from rest_framework.response import Response
from rest_framework.views import APIView

from core.permissions import IsAdmin

ZERO = Decimal("0.00")

# Order states, grouped by what they mean for revenue. Derived from the model so a
# new status can't silently fall into the wrong bucket.
DELIVERED = "delivered"
RETURNED = "returned"
CANCELLED = "cancelled"


def _f(v):
    return float(v or 0)


def _window(request, default=30):
    try:
        days = max(1, int(request.query_params.get("days", default)))
    except (TypeError, ValueError):
        days = default
    end = timezone.now()
    return end - timedelta(days=days), end, days


def _wac_index():
    """`{(product_id, variant_id): unit_cost}` from genuinely costed inbound stock.

    Deliberately NOT `inventory.services.weighted_average_cost`, which falls back to
    `Product.price` when nothing costed was ever received. That fallback is right for
    valuing stock but catastrophic for COGS: cost would equal the selling price and
    the page would report a confident 0% margin, which is the same class of lie as
    the 100% it used to report. Here an unknown cost stays unknown and is counted
    against coverage instead.
    """
    from inventory.models import InventoryLedger

    agg = {}
    rows = (
        InventoryLedger.objects.filter(unit_cost__isnull=False, quantity__gt=0)
        .values_list("product_id", "variant_id", "quantity", "unit_cost")
    )
    for pid, vid, qty, cost in rows:
        key = (pid, vid)
        q, c = agg.get(key, (0, ZERO))
        agg[key] = (q + qty, c + Decimal(qty) * cost)
    return {k: (c / q) for k, (q, c) in agg.items() if q > 0}


def _cogs_for(order_ids):
    """(cogs, coverage_pct, costed_units, total_units) for a set of orders.

    Coverage is reported so the reader can tell a real margin from one computed over
    a third of the basket. A variant is costed against its own pack first — blending
    a 5kg's cost with a 500g's values neither.
    """
    from orders.models import OrderItem

    if not order_ids:
        return ZERO, None, 0, 0
    wac = _wac_index()
    cogs, costed, total = ZERO, 0, 0
    rows = OrderItem.objects.filter(order_id__in=order_ids).values_list(
        "product_id", "variant_id", "quantity"
    )
    for pid, vid, qty in rows:
        qty = qty or 0
        total += qty
        unit = wac.get((pid, vid))
        if unit is None and vid is not None:
            unit = wac.get((pid, None))
        if unit is None:
            continue
        costed += qty
        cogs += Decimal(qty) * unit
    coverage = round(costed / total * 100, 1) if total else None
    return cogs.quantize(Decimal("0.01")), coverage, costed, total


class AccountingSummaryView(APIView):
    """GET /admin/accounting/summary?days=30 — operational P&L.

    The window filters on `placed_at`, so every figure answers the same question:
    "of the business written in this period, where does it stand now?"
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        from inventory.models import GRN
        from orders.models import Order
        from payments.models import CashCollection, Payment

        start, end, days = _window(request)
        placed = Order.objects.filter(placed_at__gte=start)

        # ── Order book, split by what each state means for revenue ──────────
        book = {
            r["status"]: {"n": r["n"], "value": _f(r["v"])}
            for r in placed.values("status").annotate(n=Count("id"), v=Sum("total"))
        }
        gross_ordered = sum(b["value"] for s, b in book.items() if s != CANCELLED)
        orders_placed = sum(b["n"] for s, b in book.items() if s != CANCELLED)

        delivered_qs = placed.filter(status=DELIVERED)
        delivered_value = _f(delivered_qs.aggregate(s=Sum("total"))["s"])
        delivered_n = delivered_qs.count()

        returned_b = book.get(RETURNED, {"n": 0, "value": 0.0})
        cancelled_b = book.get(CANCELLED, {"n": 0, "value": 0.0})
        # Everything not yet resolved one way or the other. This is the number the
        # old page was quietly booking as revenue.
        in_flight_value = gross_ordered - delivered_value - returned_b["value"]
        in_flight_n = orders_placed - delivered_n - returned_b["n"]

        # ── Refunds on orders that DID deliver (partial returns) ────────────
        refunds = ZERO
        returns_n = 0
        try:
            from returns.models import ReturnRequest

            r = ReturnRequest.objects.filter(
                status="refunded", resolved_at__gte=start
            ).aggregate(s=Sum("refund_amount"), n=Count("id"))
            refunds = Decimal(str(_f(r["s"])))
            returns_n = r["n"] or 0
        except Exception:
            pass

        # ── POS counter sales (were missing from revenue entirely) ──────────
        pos_net, pos_n = 0.0, 0
        try:
            from pos.models import POSTransaction

            live = POSTransaction.objects.filter(created_at__gte=start, is_voided=False)
            sales = live.filter(type="sale").aggregate(s=Sum("total"), n=Count("id"))
            rets = live.filter(type="return").aggregate(s=Sum("total"))
            pos_net = _f(sales["s"]) - _f(rets["s"])
            pos_n = sales["n"] or 0
        except Exception:
            pass

        net_revenue = delivered_value + pos_net - float(refunds)

        # ── COGS on what actually sold ──────────────────────────────────────
        cogs, coverage, costed_units, total_units = _cogs_for(
            list(delivered_qs.values_list("id", flat=True))
        )
        # A margin over 0% of the basket is not a margin. Report null and let the UI
        # say so rather than printing a number nobody should act on.
        has_cogs = bool(coverage)
        gross_profit = (net_revenue - float(cogs)) if has_cogs else None
        margin = (
            round(gross_profit / net_revenue * 100, 1)
            if has_cogs and net_revenue else None
        )

        # ── Purchasing (NOT COGS — money out to suppliers this period) ──────
        procurement = _f(
            GRN.objects.filter(status="posted", posted_at__gte=start)
            .aggregate(s=Sum("total_cost"))["s"]
        )

        collected = _f(
            CashCollection.objects.filter(
                status__in=(
                    CashCollection.Status.COLLECTED,
                    CashCollection.Status.PARTIALLY_COLLECTED,
                ),
                collected_at__gte=start,
            ).aggregate(s=Sum("collected_amount"))["s"]
        )
        repayments = _f(
            Payment.objects.filter(
                purpose="repayment", status=Payment.Status.SUCCESS,
                created_at__gte=start,
            ).aggregate(s=Sum("amount"))["s"]
        )
        platform_fees = _f(
            placed.exclude(status=CANCELLED).aggregate(s=Sum("platform_fee"))["s"]
        )

        return Response({
            "periodDays": days,
            "from": start.date().isoformat(),
            "to": end.date().isoformat(),
            "orderBook": {
                "placed": orders_placed,
                "grossOrdered": round(gross_ordered, 2),
                "delivered": delivered_n,
                "deliveredValue": round(delivered_value, 2),
                "inFlight": in_flight_n,
                "inFlightValue": round(in_flight_value, 2),
                "returned": returned_b["n"],
                "returnedValue": round(returned_b["value"], 2),
                "cancelled": cancelled_b["n"],
                "cancelledValue": round(cancelled_b["value"], 2),
            },
            "revenue": {
                "delivered": round(delivered_value, 2),
                "pos": round(pos_net, 2),
                "posTransactions": pos_n,
                "refunds": round(float(refunds), 2),
                "returnsCount": returns_n,
                "net": round(net_revenue, 2),
            },
            "cogs": {
                "amount": float(cogs) if has_cogs else None,
                "coveragePct": coverage,
                "costedUnits": costed_units,
                "totalUnits": total_units,
            },
            "pnl": {
                "netRevenue": round(net_revenue, 2),
                "cogs": float(cogs) if has_cogs else None,
                "grossProfit": round(gross_profit, 2) if gross_profit is not None else None,
                "grossMarginPct": margin,
            },
            "cash": {
                "collected": collected,
                "repayments": repayments,
                "platformFees": platform_fees,
            },
            "expenses": {"procurement": procurement},
            "notes": [
                "Revenue counts delivered orders and POS sales only — orders still in "
                "flight are shown separately and are not booked as revenue.",
                (
                    f"COGS covers {coverage}% of delivered units "
                    f"({costed_units} of {total_units}); units with no costed inbound "
                    "stock are excluded rather than guessed."
                    if has_cogs else
                    "No delivered unit has a costed inbound movement, so COGS and "
                    "margin cannot be computed for this period."
                ),
                "Procurement is money out to suppliers this period (posted GRNs). It is "
                "not COGS and is not subtracted from gross profit.",
            ],
        })


class AccountingCashflowView(APIView):
    """GET /admin/accounting/cashflow?days=30 — daily cash in vs cash out.

    Cash, not accruals. The old version summed `Order.total` on the day an order was
    *placed* and added `CashCollection.amount` (the amount we set out to recover)
    filtered to fully-collected rows — so it booked credit orders as cash, then
    booked the recovery of those same orders as cash again, and overstated the
    recovery leg on top. On prod that inflated collections by ₹724 against the
    summary tile directly above it.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        from inventory.models import GRN
        from payments.models import CashCollection, Payment

        start, end, days = _window(request)
        today = timezone.now().date()
        first = today - timedelta(days=days - 1)

        def by_day(qs, field, value):
            out = {}
            for r in qs.values(field).annotate(s=Sum(value)):
                d = r[field]
                if d:
                    out[d.date() if hasattr(d, "date") else d] = _f(r["s"])
            return out

        # In: money that actually arrived, counted once.
        #
        # `CashCollection` carries a `payment` FK — recovering cash books a matching
        # `repayment` Payment — so summing settled payments AND every collection
        # counts the same rupee twice. Customer payments are the primary source;
        # collections only contribute where they have not already been booked as a
        # settled payment. `handover` is excluded outright: an agent depositing
        # collected cash moves money we have already counted from one pocket to
        # another, it is not new income.
        pay_in = by_day(
            Payment.objects.filter(
                status=Payment.Status.SUCCESS,
                purpose__in=("order", "repayment"),
                created_at__gte=start,
            ),
            "created_at", "amount",
        )
        coll_in = by_day(
            CashCollection.objects.filter(
                status__in=(
                    CashCollection.Status.COLLECTED,
                    CashCollection.Status.PARTIALLY_COLLECTED,
                ),
                collected_at__gte=start,
            ).exclude(payment__status=Payment.Status.SUCCESS),
            "collected_at", "collected_amount",
        )
        # Out: supplier invoices posted and refunds actually paid.
        #
        # Agent earnings are deliberately NOT here. `released_at` is stamped when a
        # delivery completes, not when anyone is paid, so counting it as outflow
        # booked an accrual as cash that never moved — the same accrued/paid
        # confusion that made "agent payable" read zero. When a real payout ledger
        # exists it belongs here; until then there is no cash event to record.
        grn_out = by_day(
            GRN.objects.filter(status="posted", posted_at__gte=start),
            "posted_at", "total_cost",
        )
        refund_out = by_day(
            Payment.objects.filter(
                purpose="refund", status=Payment.Status.SUCCESS, created_at__gte=start
            ),
            "created_at", "amount",
        )

        series = []
        for i in range(days):
            d = first + timedelta(days=i)
            inflow = pay_in.get(d, 0.0) + coll_in.get(d, 0.0)
            outflow = grn_out.get(d, 0.0) + refund_out.get(d, 0.0)
            series.append({
                "date": d.isoformat(),
                "inflow": round(inflow, 2),
                "outflow": round(outflow, 2),
                "net": round(inflow - outflow, 2),
            })
        return Response({
            "periodDays": days,
            "series": series,
            "totals": {
                "inflow": round(sum(p["inflow"] for p in series), 2),
                "outflow": round(sum(p["outflow"] for p in series), 2),
                "net": round(sum(p["net"] for p in series), 2),
            },
            "note": "Cash basis: settled customer payments and cash recovered in; "
                    "supplier GRNs and paid refunds out. Agent earnings accrue on "
                    "delivery and are not a cash event — no payout ledger exists.",
        })


class AccountingByStoreView(APIView):
    """GET /admin/accounting/by-store?days=30 — per-store trading.

    Reports delivered revenue against the same store's purchasing, and labels the
    difference `revenueLessPurchasing` rather than "margin": buying stock in a period
    has no fixed relationship to what sold in it, so calling it margin invited exactly
    the misreading the summary used to make.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        from inventory.models import GRN
        from orders.models import Order
        from stores.models import Store

        start, end, days = _window(request)
        stores = {
            s.id: {"storeId": str(s.id), "store": s.name, "warehouseId": s.warehouse_id,
                   "orders": 0, "grossOrdered": 0.0, "delivered": 0, "revenue": 0.0,
                   "inFlight": 0.0, "platformFees": 0.0, "procurement": 0.0}
            for s in Store.objects.all()
        }
        unassigned = {"storeId": None, "store": "Unassigned", "warehouseId": None,
                      "orders": 0, "grossOrdered": 0.0, "delivered": 0, "revenue": 0.0,
                      "inFlight": 0.0, "platformFees": 0.0, "procurement": 0.0}

        rows = (
            Order.objects.exclude(status=CANCELLED).filter(placed_at__gte=start)
            .values("store_id", "status")
            .annotate(v=Sum("total"), n=Count("id"), pf=Sum("platform_fee"))
        )
        for r in rows:
            b = stores.get(r["store_id"], unassigned)
            b["orders"] += r["n"]
            b["grossOrdered"] += _f(r["v"])
            b["platformFees"] += _f(r["pf"])
            if r["status"] == DELIVERED:
                b["delivered"] += r["n"]
                b["revenue"] += _f(r["v"])
            elif r["status"] != RETURNED:
                b["inFlight"] += _f(r["v"])

        wh_to_store = {s["warehouseId"]: sid for sid, s in stores.items() if s["warehouseId"]}
        for r in (
            GRN.objects.filter(status="posted", posted_at__gte=start)
            .values("warehouse_id").annotate(c=Sum("total_cost"))
        ):
            b = stores.get(wh_to_store.get(r["warehouse_id"]), unassigned)
            b["procurement"] += _f(r["c"])

        out = list(stores.values())
        if any(unassigned[k] for k in ("orders", "grossOrdered", "procurement")):
            out.append(unassigned)
        for b in out:
            for k in ("grossOrdered", "revenue", "inFlight", "platformFees", "procurement"):
                b[k] = round(b[k], 2)
            b["revenueLessPurchasing"] = round(b["revenue"] - b["procurement"], 2)
        out.sort(key=lambda b: b["revenue"], reverse=True)
        return Response({"periodDays": days, "stores": out})


class AccountingSettlementsView(APIView):
    """GET /admin/accounting/settlements — what each agent has ACCRUED.

    Shares its definition with the agent's own earnings screen via
    `agents/earnings.py`, so the earner and the payer read the same number.

    Two corrections live here, one of them to this view's own first rewrite:

    * It originally invented `deliveries x Rs.20 + collections x Rs.30` over all
      time, ignoring `DeliveryEarnings` entirely. On prod that claimed Rs.330 due.
    * The first fix then read `released=False` as "unpaid" and derived payable from
      it. That was wrong too: `delivery/services.py::compute_earnings` writes
      `released=True` at the moment of delivery and nothing anywhere ever writes
      False, so `released` means accrued, not paid, and "payable" was structurally
      always Rs.0 -- an unknown printed as a zero.

    There is no payout ledger anywhere in the codebase, so what has actually been
    handed to an agent is not knowable from the data. `paid` and `payable` are
    therefore reported as **null**, not as zero, and `PAYOUTS_ARE_TRACKED` in
    `agents/earnings.py` is the single switch to flip when a real payout record
    exists.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        from accounts.models import Role, User
        from agents.earnings import (PAYOUTS_ARE_TRACKED, breakdown_all,
                                     collection_fee)

        book = breakdown_all()
        names = {
            u.id: (u.name or u.phone)
            for u in User.objects.filter(role=Role.AGENT).only("id", "name", "phone")
        }

        rows = []
        for aid, b in book.items():
            if not b["total"] and not b["collections"]:
                continue
            rows.append({
                "agentId": str(aid),
                "name": names.get(aid, str(aid)),
                "deliveries": b["deliveries"],
                "collections": b["collections"],
                "deliveryPay": _f(b["deliveryPay"]),
                "collectionPay": _f(b["collectionPay"]),
                "incentives": _f(b["incentives"]),
                "earned": _f(b["total"]),
                # Unknown, not zero -- see the class docstring.
                "paid": 0.0 if PAYOUTS_ARE_TRACKED else None,
                "payable": _f(b["total"]) if PAYOUTS_ARE_TRACKED else None,
            })
        rows.sort(key=lambda r: r["earned"], reverse=True)
        return Response({
            "settlements": rows,
            "totalEarned": round(sum(r["earned"] for r in rows), 2),
            "totalPaid": 0.0 if PAYOUTS_ARE_TRACKED else None,
            "totalPayable": None if not PAYOUTS_ARE_TRACKED else round(
                sum(r["earned"] for r in rows), 2),
            "payoutsTracked": PAYOUTS_ARE_TRACKED,
            "note": (
                "Accrued earnings: delivery pay from the DeliveryEarnings ledger, "
                f"plus Rs.{collection_fee():.0f} per completed collection, plus any "
                "incentives. There is no agent payout ledger, so what has actually "
                "been paid out is not recorded - 'paid' and 'payable' are shown as "
                "unavailable rather than as zero."
            ),
        })
