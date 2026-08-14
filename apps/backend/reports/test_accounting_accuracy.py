"""Accuracy guards for the Accounting and Reports surfaces.

Written against the four defects the 2026-08-11 review found on live prod data,
each of which produced a confident, wrong number rather than an obvious failure:

* revenue booked on order PLACEMENT, so 27 in-flight and 2 returned orders counted
* "gross profit" = revenue − period purchasing, which showed a **100.0% margin**
* agent settlements invented ₹20/delivery + ₹30/collection over all time and never
  deducted anything paid, claiming ₹330 due against a ledger holding ₹0 outstanding
* POS counter sales missing from revenue entirely

Plus the reports layer, where the documented `?date_from/date_to/store/zone` filters
were never implemented and rows were silently cut to the first 200/500 — including
in the CSV/Excel/PDF export.
"""
from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product
from delivery.models import DeliveryEarnings, DeliveryTask
from inventory.models import InventoryLedger, Warehouse
from inventory.services import InventoryService
from orders.models import Order, OrderItem, OrderStatus
from payments.models import CashCollection, Payment
from reports.builders import BUILDERS
from stores.models import Store
from zones.models import Zone


def _data(resp):
    body = resp.json()
    return body.get("data", body)


class AccountingBase(TestCase):
    def setUp(self):
        self.cat = Category.objects.create(name="Grocery")
        self.wh = Warehouse.objects.create(code="WA", name="WH A", is_default=True)
        self.store = Store.objects.create(code="SA", name="Store A", warehouse=self.wh)
        self.zone = Zone.objects.create(code="ZA", name="Zone A", store=self.store)
        self.product = Product.objects.create(
            name="Rice", price=Decimal("100"), mrp=Decimal("120"), category=self.cat,
        )
        self.customer = User.objects.create(
            phone="+919000000900", name="Cust", role="customer",
        )
        self.agent = User.objects.create(
            phone="+919777777900", name="Agent A", role="agent",
        )
        self.admin = User.objects.create(
            phone="+919888888900", name="Admin", role="admin",
        )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def mk_order(self, *, status, total, days_ago=1, qty=1):
        o = Order.objects.create(
            user=self.customer, payment_method=Order.PaymentMethod.COD,
            status=status, store=self.store, zone=self.zone, total=Decimal(str(total)),
        )
        Order.objects.filter(pk=o.pk).update(
            placed_at=timezone.now() - timedelta(days=days_ago)
        )
        OrderItem.objects.create(
            order=o, product=self.product, quantity=qty, name=self.product.name,
            price=Decimal("100"), mrp=Decimal("120"),
        )
        return Order.objects.get(pk=o.pk)

    def summary(self, days=30):
        return _data(self.client.get("/api/v1/admin/accounting/summary", {"days": days}))

    def settlements(self):
        return _data(self.client.get("/api/v1/admin/accounting/settlements"))


class RevenueRecognitionTests(AccountingBase):
    def test_in_flight_orders_are_not_booked_as_revenue(self):
        """The headline defect: placing an order used to book its full value."""
        self.mk_order(status=OrderStatus.CONFIRMED, total=500)
        s = self.summary()
        self.assertEqual(s["revenue"]["net"], 0.0)
        self.assertEqual(s["orderBook"]["inFlight"], 1)
        self.assertEqual(s["orderBook"]["inFlightValue"], 500.0)
        # Still visible as written business — separated, not hidden.
        self.assertEqual(s["orderBook"]["grossOrdered"], 500.0)

    def test_delivered_orders_are_revenue(self):
        self.mk_order(status=OrderStatus.DELIVERED, total=500)
        s = self.summary()
        self.assertEqual(s["revenue"]["delivered"], 500.0)
        self.assertEqual(s["revenue"]["net"], 500.0)
        self.assertEqual(s["orderBook"]["delivered"], 1)

    def test_returned_orders_are_not_revenue(self):
        self.mk_order(status=OrderStatus.DELIVERED, total=500)
        self.mk_order(status="returned", total=300)
        s = self.summary()
        self.assertEqual(s["revenue"]["net"], 500.0)
        self.assertEqual(s["orderBook"]["returned"], 1)
        self.assertEqual(s["orderBook"]["returnedValue"], 300.0)

    def test_cancelled_orders_are_excluded_from_the_order_book(self):
        self.mk_order(status=OrderStatus.DELIVERED, total=500)
        self.mk_order(status="cancelled", total=900)
        s = self.summary()
        self.assertEqual(s["orderBook"]["grossOrdered"], 500.0)
        self.assertEqual(s["orderBook"]["cancelled"], 1)

    def test_refunds_reduce_net_revenue(self):
        o = self.mk_order(status=OrderStatus.DELIVERED, total=500)
        from returns.models import ReturnRequest

        r = ReturnRequest.objects.create(
            user=self.customer, order=o, reason="damaged",
            status="refunded", refund_amount=Decimal("120"),
        )
        ReturnRequest.objects.filter(pk=r.pk).update(resolved_at=timezone.now())
        s = self.summary()
        self.assertEqual(s["revenue"]["refunds"], 120.0)
        self.assertEqual(s["revenue"]["net"], 380.0)

    def test_pos_sales_are_counted_as_revenue(self):
        """POS was absent from accounting revenue altogether."""
        from pos.models import POSSession, POSTransaction

        session = POSSession.objects.create(cashier=self.admin, warehouse=self.wh)
        POSTransaction.objects.create(
            session=session, code="POS-1", type="sale", total=Decimal("177"),
        )
        s = self.summary()
        self.assertEqual(s["revenue"]["pos"], 177.0)
        self.assertEqual(s["revenue"]["net"], 177.0)

    def test_pos_returns_net_off_pos_sales(self):
        from pos.models import POSSession, POSTransaction

        session = POSSession.objects.create(cashier=self.admin, warehouse=self.wh)
        POSTransaction.objects.create(
            session=session, code="POS-2", type="sale", total=Decimal("200"))
        POSTransaction.objects.create(
            session=session, code="RET-2", type="return", total=Decimal("50"))
        self.assertEqual(self.summary()["revenue"]["pos"], 150.0)

    def test_voided_pos_sales_are_ignored(self):
        from pos.models import POSSession, POSTransaction

        session = POSSession.objects.create(cashier=self.admin, warehouse=self.wh)
        POSTransaction.objects.create(
            session=session, code="POS-3", type="sale", total=Decimal("999"),
            is_voided=True)
        self.assertEqual(self.summary()["revenue"]["pos"], 0.0)


class CogsTests(AccountingBase):
    def test_no_margin_is_claimed_when_no_cost_is_known(self):
        """The 100% margin. With nothing costed, margin must be null — not 100."""
        self.mk_order(status=OrderStatus.DELIVERED, total=500)
        s = self.summary()
        self.assertIsNone(s["pnl"]["grossMarginPct"])
        self.assertIsNone(s["pnl"]["grossProfit"])
        self.assertIsNone(s["cogs"]["amount"])
        self.assertEqual(s["cogs"]["coveragePct"], 0.0)

    def test_margin_uses_real_weighted_average_cost(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10, unit_cost=Decimal("60"),
        )
        self.mk_order(status=OrderStatus.DELIVERED, total=500, qty=2)
        s = self.summary()
        self.assertEqual(s["cogs"]["amount"], 120.0)      # 2 units × ₹60
        self.assertEqual(s["cogs"]["coveragePct"], 100.0)
        self.assertEqual(s["pnl"]["grossProfit"], 380.0)  # 500 − 120
        self.assertEqual(s["pnl"]["grossMarginPct"], 76.0)

    def test_coverage_reports_partially_costed_baskets(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=5, unit_cost=Decimal("60"),
        )
        uncosted = Product.objects.create(
            name="Dal", price=Decimal("80"), mrp=Decimal("90"), category=self.cat,
        )
        o = self.mk_order(status=OrderStatus.DELIVERED, total=500, qty=1)
        OrderItem.objects.create(
            order=o, product=uncosted, quantity=3, name=uncosted.name,
            price=Decimal("80"), mrp=Decimal("90"),
        )
        s = self.summary()
        # 1 of 4 units has a real cost — say so rather than guessing the other three.
        self.assertEqual(s["cogs"]["costedUnits"], 1)
        self.assertEqual(s["cogs"]["totalUnits"], 4)
        self.assertEqual(s["cogs"]["coveragePct"], 25.0)

    def test_procurement_is_not_subtracted_from_gross_profit(self):
        """Purchasing is cash out, not cost of what sold. Conflating them was the bug."""
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10, unit_cost=Decimal("60"),
        )
        self.mk_order(status=OrderStatus.DELIVERED, total=500, qty=1)
        s = self.summary()
        self.assertEqual(s["pnl"]["grossProfit"], 440.0)   # 500 − 60, NOT 500 − GRN total
        self.assertIn("procurement", s["expenses"])


class SettlementTests(AccountingBase):
    """Agent pay must mean the same thing to the earner and to the payer.

    `DeliveryEarnings.released` is written True at delivery and never written False,
    so it marks an earning as ACCRUED, not paid. Reading it as a paid flag made
    "payable" structurally zero — an unknown rendered as a number.
    """

    def _task_with_earning(self, *, total, released=True):
        order = self.mk_order(status=OrderStatus.DELIVERED, total=400)
        task = DeliveryTask.objects.create(order=order, agent=self.agent, status="delivered")
        return DeliveryEarnings.objects.create(
            task=task, agent=self.agent, base=Decimal(str(total)),
            total=Decimal(str(total)), released=released,
            released_at=timezone.now() if released else None,
        )

    def test_earned_is_the_full_ledger_total(self):
        self._task_with_earning(total=50)
        self._task_with_earning(total=30)
        s = self.settlements()
        row = next(r for r in s["settlements"] if r["agentId"] == str(self.agent.id))
        self.assertEqual(row["deliveryPay"], 80.0)
        self.assertEqual(s["totalEarned"], 80.0)

    def test_paid_and_payable_are_unavailable_not_zero(self):
        """No payout ledger exists, so the honest answer is 'unknown'."""
        self._task_with_earning(total=40)
        s = self.settlements()
        row = next(r for r in s["settlements"] if r["agentId"] == str(self.agent.id))
        self.assertIsNone(row["paid"])
        self.assertIsNone(row["payable"])
        self.assertIsNone(s["totalPayable"])
        self.assertFalse(s["payoutsTracked"])

    def test_released_flag_does_not_change_the_answer(self):
        """It carries no information — nothing ever writes False."""
        self._task_with_earning(total=25, released=True)
        self._task_with_earning(total=25, released=False)
        self.assertEqual(self.settlements()["totalEarned"], 50.0)

    def test_settlement_amounts_come_from_the_ledger_not_a_flat_rate(self):
        # Rs.73.50 is not a multiple of the old hardcoded Rs.20/delivery.
        self._task_with_earning(total=Decimal("73.50"))
        row = next(
            r for r in self.settlements()["settlements"]
            if r["agentId"] == str(self.agent.id)
        )
        self.assertEqual(row["deliveryPay"], 73.5)

    def test_finance_and_the_agent_app_report_the_same_total(self):
        """The defect this whole module exists to prevent."""
        from agents.earnings import breakdown

        self._task_with_earning(total=50)
        CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("1500"),
            collected_amount=Decimal("1500"), status="collected",
        )
        finance = next(
            r for r in self.settlements()["settlements"]
            if r["agentId"] == str(self.agent.id)
        )
        agent_view = breakdown(self.agent)
        self.assertEqual(finance["earned"], float(agent_view["total"]))

    def test_collection_pay_is_declared_not_buried_in_a_view(self):
        from agents.earnings import collection_fee

        CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("500"),
            collected_amount=Decimal("500"), status="collected",
        )
        row = next(
            r for r in self.settlements()["settlements"]
            if r["agentId"] == str(self.agent.id)
        )
        self.assertEqual(row["collections"], 1)
        self.assertEqual(row["collectionPay"], float(collection_fee()))


class CashflowTests(AccountingBase):
    def cashflow(self, days=30):
        return _data(self.client.get("/api/v1/admin/accounting/cashflow", {"days": days}))

    def test_recovered_cash_is_counted_once_when_it_books_a_repayment(self):
        """A collection creates a linked repayment Payment; counting both doubled it."""
        pay = Payment.objects.create(
            user=self.customer, purpose="repayment", amount=Decimal("649"),
            status=Payment.Status.SUCCESS, method="cash",
        )
        c = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("649"),
            collected_amount=Decimal("649"), status="collected", payment=pay,
        )
        CashCollection.objects.filter(pk=c.pk).update(collected_at=timezone.now())
        self.assertEqual(self.cashflow()["totals"]["inflow"], 649.0)

    def test_recovered_cash_with_no_payment_row_still_counts(self):
        c = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("500"),
            collected_amount=Decimal("500"), status="collected",
        )
        CashCollection.objects.filter(pk=c.pk).update(collected_at=timezone.now())
        self.assertEqual(self.cashflow()["totals"]["inflow"], 500.0)

    def test_placing_an_order_is_not_cash(self):
        self.mk_order(status=OrderStatus.CONFIRMED, total=5000)
        self.assertEqual(self.cashflow()["totals"]["inflow"], 0.0)

    def test_agent_handover_is_not_new_income(self):
        """An agent depositing collected cash moves money already counted."""
        Payment.objects.create(
            user=self.agent, purpose="handover", amount=Decimal("3245"),
            status=Payment.Status.SUCCESS, method="cash",
        )
        self.assertEqual(self.cashflow()["totals"]["inflow"], 0.0)

    def test_refunds_are_outflow(self):
        Payment.objects.create(
            user=self.customer, purpose="refund", amount=Decimal("808"),
            status=Payment.Status.SUCCESS, method="upi",
        )
        cf = self.cashflow()
        self.assertEqual(cf["totals"]["outflow"], 808.0)
        self.assertEqual(cf["totals"]["inflow"], 0.0)


class ReportBuilderTests(AccountingBase):
    def test_date_filters_actually_narrow_the_result(self):
        """`?date_from/date_to` were documented, implemented in filters.py, and ignored."""
        self.mk_order(status=OrderStatus.DELIVERED, total=100, days_ago=1)
        self.mk_order(status=OrderStatus.DELIVERED, total=200, days_ago=40)
        today = timezone.now().date()
        recent = BUILDERS["orders"]({
            "date_from": (today - timedelta(days=7)).isoformat(),
            "date_to": today.isoformat(),
        })
        self.assertEqual(len(recent["rows"]), 1)
        self.assertEqual(recent["summary"]["Total"], 100.0)

    def test_store_filter_narrows_the_result(self):
        other_wh = Warehouse.objects.create(code="WB", name="WH B")
        other = Store.objects.create(code="SB", name="Store B", warehouse=other_wh)
        self.mk_order(status=OrderStatus.DELIVERED, total=100)
        o = self.mk_order(status=OrderStatus.DELIVERED, total=250)
        Order.objects.filter(pk=o.pk).update(store=other)
        rows = BUILDERS["orders"]({"store": str(other.id)})["rows"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][3], 250.0)

    def test_orders_report_is_not_silently_truncated(self):
        """The old builder cut to 200 rows — on screen AND in the export."""
        for _ in range(205):
            self.mk_order(status=OrderStatus.DELIVERED, total=10)
        self.assertEqual(len(BUILDERS["orders"]({})["rows"]), 205)

    def test_pagination_reports_the_true_total(self):
        for _ in range(12):
            self.mk_order(status=OrderStatus.DELIVERED, total=10)
        r = self.client.get("/api/v1/reports/orders", {"page_size": 5, "page": 1})
        body = _data(r)
        self.assertEqual(len(body["rows"]), 5)
        self.assertEqual(body["meta"]["total"], 12)

    def test_collections_report_separates_due_from_recovered(self):
        """It showed only the amount we set OUT to recover, so partials read as full."""
        c = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("1000"),
            collected_amount=Decimal("400"), status="partially_collected",
        )
        CashCollection.objects.filter(pk=c.pk).update(collected_at=timezone.now())
        out = BUILDERS["collections"]({})
        self.assertIn("Recovered", out["columns"])
        self.assertEqual(out["summary"]["Due"], 1000.0)
        self.assertEqual(out["summary"]["Recovered"], 400.0)

    def test_inventory_report_reads_stock_items_not_the_denormalised_count(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=7, unit_cost=Decimal("60"),
        )
        out = BUILDERS["inventory"]({})
        self.assertIn("Warehouse", out["columns"])
        row = next(r for r in out["rows"] if r[0].startswith("Rice"))
        self.assertEqual(row[2], "WH A")
        self.assertEqual(row[3], 7)

    def test_every_basic_report_carries_a_summary_row(self):
        for name in ("sales", "orders", "credit", "collections", "inventory", "agents"):
            self.assertIn("summary", BUILDERS[name]({}), f"{name} has no summary")

    def test_hitting_the_row_ceiling_is_announced_not_hidden(self):
        """A cap is acceptable; a SILENT cap is the bug. Patched low to stay fast."""
        from reports import builders

        for _ in range(4):
            self.mk_order(status=OrderStatus.DELIVERED, total=10)
        original = builders.MAX_ROWS
        builders.MAX_ROWS = 2
        try:
            out = builders.orders({})
            self.assertEqual(len(out["rows"]), 2)
            self.assertIn("CAPPED", out["title"])
            self.assertEqual(out["summary"]["Capped at"], 2)
        finally:
            builders.MAX_ROWS = original

    def test_no_cap_notice_when_everything_fits(self):
        from reports import builders

        self.mk_order(status=OrderStatus.DELIVERED, total=10)
        out = builders.orders({})
        self.assertNotIn("CAPPED", out["title"])
        self.assertNotIn("Capped at", out["summary"])

    def test_export_respects_the_same_filters_as_the_screen(self):
        self.mk_order(status=OrderStatus.DELIVERED, total=100, days_ago=1)
        self.mk_order(status=OrderStatus.DELIVERED, total=200, days_ago=40)
        today = timezone.now().date()
        r = self.client.get("/api/v1/reports/export", {
            "type": "orders", "fmt": "csv",
            "date_from": (today - timedelta(days=7)).isoformat(),
            "date_to": today.isoformat(),
        })
        self.assertEqual(r.status_code, 200)
        body = r.content.decode()
        # header + exactly one in-window order
        self.assertEqual(len([ln for ln in body.strip().splitlines() if ln]), 2)


class DashboardConsistencyTests(AccountingBase):
    """The admin dashboard and the accounting page must mean the same thing.

    The dashboard is the most-read screen on the platform and it carried the exact
    defects the accounting rewrite removed: revenue summed every non-cancelled order
    (booked on placement, returns included, POS missing), collections summed the
    target rather than the recovery, and inventory was valued at the SELLING price.
    """

    def dashboard(self):
        return BUILDERS["dashboard"]({})["widgets"]

    def test_dashboard_revenue_matches_accounting_revenue(self):
        self.mk_order(status=OrderStatus.DELIVERED, total=500, days_ago=0)
        self.mk_order(status=OrderStatus.CONFIRMED, total=900, days_ago=0)
        self.assertEqual(self.dashboard()["revenueToday"], 500.0)

    def test_dashboard_does_not_book_in_flight_orders(self):
        self.mk_order(status=OrderStatus.CONFIRMED, total=900, days_ago=0)
        self.assertEqual(self.dashboard()["revenueToday"], 0.0)

    def test_dashboard_revenue_includes_pos(self):
        from pos.models import POSSession, POSTransaction

        session = POSSession.objects.create(cashier=self.admin, warehouse=self.wh)
        POSTransaction.objects.create(
            session=session, code="POS-D1", type="sale", total=Decimal("177"))
        self.assertEqual(self.dashboard()["revenueToday"], 177.0)

    def test_dashboard_collections_report_recovery_not_target(self):
        c = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("1000"),
            collected_amount=Decimal("400"), status="partially_collected",
        )
        CashCollection.objects.filter(pk=c.pk).update(collected_at=timezone.now())
        w = self.dashboard()
        # Old code summed `amount` AND dropped partials entirely by filtering
        # status="collected" — so this read either 1000 or 0, never 400.
        self.assertEqual(w["collectionsToday"], 400.0)

    def test_inventory_is_valued_at_cost_not_selling_price(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10, unit_cost=Decimal("60"),
        )
        # 10 units bought at Rs.60 = Rs.600, NOT 10 x the Rs.100 selling price.
        self.assertEqual(self.dashboard()["inventoryValue"], 600.0)

    def test_store_performance_values_inventory_at_cost(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10, unit_cost=Decimal("60"),
        )
        rows = BUILDERS["store_performance"]({})["rows"]
        row = next(r for r in rows if r[0] == "Store A")
        self.assertEqual(row[7], 600.0)

    def test_recovery_report_uses_recovered_amount(self):
        c = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("1000"),
            collected_amount=Decimal("250"), status="collected",
        )
        CashCollection.objects.filter(pk=c.pk).update(collected_at=timezone.now())
        out = BUILDERS["recovery_performance"]({})
        self.assertEqual(out["summary"]["collectedThisMonth"], 250.0)
        row = next(r for r in out["rows"] if r[0] == "Agent A")
        self.assertEqual(row[3], 250.0)


class InventoryValuationTests(AccountingBase):
    """Stock valued at cost — and honest about how much of it really is.

    `weighted_average_cost` falls back to `Product.price` when nothing costed was
    received. Defensible for a valuation, but unqualified it silently reintroduces
    the selling-price overstatement, so the costed share is published with it.
    """

    def test_costed_stock_is_valued_at_cost(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10, unit_cost=Decimal("60"),
        )
        w = BUILDERS["dashboard"]({})["widgets"]
        self.assertEqual(w["inventoryValue"], 600.0)
        self.assertEqual(w["inventoryValueCostedPct"], 100.0)

    def test_uncosted_stock_is_flagged_not_silently_priced(self):
        # Received with no unit cost -> falls back to the Rs.100 selling price.
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=5,
        )
        w = BUILDERS["dashboard"]({})["widgets"]
        self.assertEqual(w["inventoryValue"], 500.0)
        # The whole figure is fallback-priced, and the number says so.
        self.assertEqual(w["inventoryValueCostedPct"], 0.0)

    def test_mixed_stock_reports_a_partial_costed_share(self):
        other = Product.objects.create(
            name="Dal", price=Decimal("80"), mrp=Decimal("90"), category=self.cat,
        )
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10, unit_cost=Decimal("60"),
        )
        InventoryService.post_movement(
            product=other, warehouse=self.wh, type=InventoryLedger.Type.GRN, quantity=5,
        )
        w = BUILDERS["dashboard"]({})["widgets"]
        # 600 costed + 400 fallback-priced = 1000, 60% genuinely costed.
        self.assertEqual(w["inventoryValue"], 1000.0)
        self.assertEqual(w["inventoryValueCostedPct"], 60.0)


class SurfaceConsistencyTests(AccountingBase):
    """Store, CRM and Admin must apply the SAME formula — only the scope may differ.

    Each of these surfaces had grown its own arithmetic for a metric
    FINANCIAL_DEFINITIONS.md owns, and each produced a different answer from the
    same rows.
    """

    def test_store_dashboard_revenue_matches_the_shared_definition(self):
        from core.financials import net_revenue
        from storeops.services import store_dashboard

        self.mk_order(status=OrderStatus.DELIVERED, total=500, days_ago=0)
        self.mk_order(status=OrderStatus.CONFIRMED, total=900, days_ago=0)
        k = store_dashboard(self.store)["kpis"]
        self.assertEqual(k["todayRevenue"], 500.0)
        self.assertEqual(
            k["todayRevenue"],
            net_revenue(
                timezone.now().replace(hour=0, minute=0, second=0, microsecond=0),
                store=self.store.id, warehouse=self.wh.id,
            )["net"],
        )

    def test_store_dashboard_does_not_book_in_flight_orders(self):
        from storeops.services import store_dashboard

        self.mk_order(status=OrderStatus.CONFIRMED, total=900, days_ago=0)
        self.assertEqual(store_dashboard(self.store)["kpis"]["todayRevenue"], 0.0)

    def test_store_and_admin_agree_on_the_same_store(self):
        from storeops.services import store_dashboard

        self.mk_order(status=OrderStatus.DELIVERED, total=750, days_ago=0)
        self.mk_order(status=OrderStatus.CONFIRMED, total=1200, days_ago=0)
        store_rev = store_dashboard(self.store)["kpis"]["todayRevenue"]
        admin_rev = BUILDERS["dashboard"]({})["widgets"]["revenueToday"]
        # One store on the platform, so scope coincides and the numbers must match.
        self.assertEqual(store_rev, admin_rev)

    def test_customer_lifetime_revenue_counts_delivered_only(self):
        from core.financials import customer_lifetime_revenue

        self.mk_order(status=OrderStatus.DELIVERED, total=500)
        self.mk_order(status=OrderStatus.CONFIRMED, total=900)
        self.mk_order(status="cancelled", total=300)
        self.assertEqual(customer_lifetime_revenue(self.customer), 500.0)

    def test_customer_lifetime_revenue_nets_refunds(self):
        from core.financials import customer_lifetime_revenue
        from returns.models import ReturnRequest

        o = self.mk_order(status=OrderStatus.DELIVERED, total=500)
        ReturnRequest.objects.create(
            user=self.customer, order=o, reason="damaged",
            status="refunded", refund_amount=Decimal("120"),
        )
        self.assertEqual(customer_lifetime_revenue(self.customer), 380.0)

    def test_crm_health_uses_the_shared_definitions(self):
        from crm.services import _health

        self.mk_order(status=OrderStatus.DELIVERED, total=500)
        self.mk_order(status=OrderStatus.CONFIRMED, total=900)
        c = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("1000"),
            collected_amount=Decimal("400"), status="partially_collected",
        )
        CashCollection.objects.filter(pk=c.pk).update(collected_at=timezone.now())
        h = _health(self.customer)
        self.assertEqual(h["lifetimeRevenue"], 500.0)   # not 1400
        self.assertEqual(h["collections"], 400.0)       # recovered, not the 1000 due


class MissingDataTests(AccountingBase):
    """Absence of data must never be fabricated into a number.

    Every one of these has a tempting wrong answer: 0, 100%, "paid", "settled".
    """

    def test_no_orders_gives_zero_revenue_not_unknown(self):
        s = self.summary()
        self.assertEqual(s["revenue"]["net"], 0.0)   # a real, measured zero

    def test_no_costed_stock_gives_unknown_cogs_not_zero(self):
        self.mk_order(status=OrderStatus.DELIVERED, total=500)
        s = self.summary()
        self.assertIsNone(s["cogs"]["amount"])
        self.assertIsNone(s["pnl"]["grossProfit"])
        self.assertIsNone(s["pnl"]["grossMarginPct"])

    def test_no_earnings_at_all_reports_no_rows_not_zero_payable(self):
        s = self.settlements()
        self.assertEqual(s["settlements"], [])
        self.assertIsNone(s["totalPayable"])
        self.assertIsNone(s["totalPaid"])

    def test_no_payments_gives_zero_cashflow_not_a_fabricated_outflow(self):
        # Delivering an order accrues agent earnings; that must not become cash out.
        order = self.mk_order(status=OrderStatus.DELIVERED, total=400)
        task = DeliveryTask.objects.create(
            order=order, agent=self.agent, status="delivered")
        DeliveryEarnings.objects.create(
            task=task, agent=self.agent, base=Decimal("50"), total=Decimal("50"),
            released=True, released_at=timezone.now(),
        )
        cf = _data(self.client.get("/api/v1/admin/accounting/cashflow", {"days": 30}))
        self.assertEqual(cf["totals"]["outflow"], 0.0)

    def test_no_inventory_gives_zero_value_and_unknown_coverage(self):
        w = BUILDERS["dashboard"]({})["widgets"]
        self.assertEqual(w["inventoryValue"], 0.0)
        # Nothing to cost, so the costed share is unknowable rather than 0% or 100%.
        self.assertIsNone(w["inventoryValueCostedPct"])

    def test_no_promise_to_pay_records_report_null_not_a_rate(self):
        out = BUILDERS["recovery_performance"]({})
        self.assertIsNone(out["summary"]["promiseToPayFulfillment"])

    def test_empty_report_has_a_summary_of_zeroes_not_missing_keys(self):
        out = BUILDERS["orders"]({})
        self.assertEqual(out["rows"], [])
        self.assertEqual(out["summary"]["Orders"], 0)
        self.assertEqual(out["summary"]["Total"], 0)


class StoreScopingTests(AccountingBase):
    """A store-scoped figure must not silently include the whole platform.

    Caught by cross-surface reconciliation on prod: three different stores reported
    the identical monthly revenue, because one platform refund was being deducted
    from every store's revenue.
    """

    def setUp(self):
        super().setUp()
        self.wh_b = Warehouse.objects.create(code="WB", name="WH B")
        self.store_b = Store.objects.create(
            code="SB", name="Store B", warehouse=self.wh_b)

    def _order_for(self, store, *, total, status=OrderStatus.DELIVERED):
        o = self.mk_order(status=status, total=total, days_ago=0)
        Order.objects.filter(pk=o.pk).update(store=store)
        return Order.objects.get(pk=o.pk)

    def test_refunds_are_charged_only_to_their_own_store(self):
        from core.financials import net_revenue
        from returns.models import ReturnRequest

        start = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
        self._order_for(self.store, total=1000)
        b_order = self._order_for(self.store_b, total=1000)
        r = ReturnRequest.objects.create(
            user=self.customer, order=b_order, reason="damaged",
            status="refunded", refund_amount=Decimal("300"),
        )
        ReturnRequest.objects.filter(pk=r.pk).update(resolved_at=timezone.now())

        a = net_revenue(start, store=self.store.id, warehouse=self.wh.id)
        b = net_revenue(start, store=self.store_b.id, warehouse=self.wh_b.id)
        self.assertEqual(a["net"], 1000.0)   # untouched by Store B's refund
        self.assertEqual(b["net"], 700.0)

    def test_two_stores_do_not_report_identical_revenue(self):
        from storeops.services import store_dashboard

        self._order_for(self.store, total=500)
        self._order_for(self.store_b, total=900)
        a = store_dashboard(self.store)["kpis"]["todayRevenue"]
        b = store_dashboard(self.store_b)["kpis"]["todayRevenue"]
        self.assertEqual(a, 500.0)
        self.assertEqual(b, 900.0)

    def test_unscoped_revenue_still_sees_the_whole_platform(self):
        from core.financials import net_revenue

        start = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
        self._order_for(self.store, total=500)
        self._order_for(self.store_b, total=900)
        self.assertEqual(net_revenue(start)["net"], 1400.0)


class InvariantCheckerTests(AccountingBase):
    """`reconcile_finance` must scope stock by VARIANT, as the repair path already does.

    Comparing one variant's cache against the whole product's ledger makes every
    product with variants report a permanent false ERROR. Prod showed variant 5 at
    993/993 and the variant-NULL bucket at 0/0 — both correct — while the command
    reported "cache 0 != ledger 993". A check that is always red is one nobody reads.
    """

    def test_variant_buckets_do_not_report_false_drift(self):
        from django.core.management import call_command
        from catalog.models import ProductVariant

        variant = ProductVariant.objects.create(
            product=self.product, label="5kg", price_delta=Decimal("0"),
        )
        # Stock only the variant bucket; the variant-NULL bucket stays legitimately 0.
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10, unit_cost=Decimal("60"), variant=variant,
        )
        # Passes => exit 0 => no SystemExit. The old check raised SystemExit(1) here.
        call_command("reconcile_finance")

    def test_real_drift_is_still_detected(self):
        """Guards the guard: scoping must not silence genuine cache drift."""
        from django.core.management import call_command
        from inventory.models import StockItem

        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10, unit_cost=Decimal("60"),
        )
        StockItem.objects.filter(product=self.product, warehouse=self.wh).update(
            quantity=3
        )
        with self.assertRaises(SystemExit):
            call_command("reconcile_finance")
