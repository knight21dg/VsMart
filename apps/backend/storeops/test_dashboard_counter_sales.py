"""The store dashboard must count counter (POS) trade, not just online orders.

`POSTransaction` has no FK to `Order` and reaches a store through its session's
warehouse, so every dashboard figure — today's revenue, monthly revenue, the
14-day trend, top products — was built from `Order` alone. For a grocery store,
where most trade crosses the till, the headline number was reporting a minority
of the business while being labelled as the store's.
"""
from decimal import Decimal

from django.test import TestCase

from accounts.models import User
from catalog.models import Category, Product
from inventory.models import InventoryLedger, Warehouse
from inventory.services import InventoryService
from pos.services import checkout, open_session
from stores.models import Store
from storeops.services import store_dashboard


class DashboardCounterSalesTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN")
        self.store = Store.objects.create(
            code="ST-CS", name="Counter Store", status="active", warehouse=self.wh)
        self.cashier = User.objects.create(
            phone="+919600030001", name="Cashier", role="admin")
        cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Sugar 1kg", brand="VS", unit="1 kg", price=Decimal("100.00"),
            mrp=Decimal("120.00"), category=cat, stock_count=None,
        )
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh,
            type=InventoryLedger.Type.GRN, quantity=100,
        )
        self.session = open_session(
            cashier=self.cashier, warehouse=self.wh, opening_cash=Decimal("500"))

    def _sale(self, qty=2):
        return checkout(
            session=self.session,
            lines=[{"product": self.product, "qty": qty}],
            payments=[{"method": "cash", "amount": "1000.00"}],
            by=self.cashier,
        )

    def test_counter_sale_appears_in_todays_revenue(self):
        txn = self._sale(qty=2)
        kpis = store_dashboard(self.store)["kpis"]

        self.assertGreater(kpis["todayRevenue"], 0)
        self.assertAlmostEqual(kpis["todayCounterRevenue"], float(txn.total), places=2)
        self.assertEqual(kpis["todayCounterSales"], 1)
        # The store sold nothing online today, so all of it is counter trade.
        self.assertEqual(kpis["todayOnlineRevenue"], 0.0)

    def test_counter_sale_appears_in_monthly_revenue_and_the_trend(self):
        txn = self._sale(qty=2)
        d = store_dashboard(self.store)

        self.assertAlmostEqual(d["kpis"]["monthlyRevenue"], float(txn.total), places=2)
        # Last point of the 14-day window is today.
        self.assertAlmostEqual(d["salesTrend"][-1]["value"], float(txn.total), places=2)
        self.assertEqual(d["ordersTrend"][-1]["value"], 1)

    def test_counter_sale_appears_in_top_products(self):
        self._sale(qty=3)
        top = store_dashboard(self.store)["topProducts"]

        self.assertTrue(top, "counter sales must produce top-product rows")
        self.assertEqual(top[0]["name"], self.product.name)
        self.assertEqual(top[0]["quantity"], 3)

    def test_a_store_with_no_warehouse_does_not_blow_up(self):
        orphan = Store.objects.create(code="ST-NW", name="No WH", status="active")
        kpis = store_dashboard(orphan)["kpis"]
        self.assertEqual(kpis["todayCounterRevenue"], 0.0)
