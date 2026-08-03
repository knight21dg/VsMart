from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product
from credit.models import CreditAccount
from inventory.models import InventoryLedger, Warehouse
from inventory.services import InventoryService
from orders.models import Order, OrderStatus
from payments.models import CashCollection
from reports.builders import BUILDERS
from stores.models import Store
from zones.models import Zone


class ReportsBaseData(TestCase):
    def setUp(self):
        self.cat = Category.objects.create(name="Grocery")
        self.wh = Warehouse.objects.create(code="W1", name="WH1", is_default=True)
        self.store = Store.objects.create(code="S1", name="Store 1", warehouse=self.wh)
        self.zone = Zone.objects.create(code="Z1", name="Zone 1", store=self.store)
        self.product = Product.objects.create(
            name="Rice", price=Decimal("100"), mrp=Decimal("120"), category=self.cat,
        )
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10,
        )
        self.customer = User.objects.create(
            phone="+919000000060", name="Cust", role="customer",
        )
        self.account = CreditAccount.objects.create(
            user=self.customer, credit_limit=Decimal("10000"),
            outstanding=Decimal("4000"),
        )
        self.order = Order.objects.create(
            user=self.customer, payment_method=Order.PaymentMethod.COD,
            status=OrderStatus.DELIVERED, store=self.store, zone=self.zone,
            total=Decimal("500"),
        )
        self.agent = User.objects.create(
            phone="+919777777060", name="Agent", role="agent",
        )
        self.collection = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("1500"),
            status="collected",
        )
        # collected_at set via update (no auto field).
        from django.utils import timezone

        CashCollection.objects.filter(pk=self.collection.pk).update(
            collected_at=timezone.now()
        )


class BuilderTests(ReportsBaseData):
    def test_dashboard_widgets(self):
        w = BUILDERS["dashboard"]({})["widgets"]
        self.assertEqual(w["revenueMtd"], 500.0)
        self.assertEqual(w["ordersMtd"], 1)
        self.assertEqual(w["outstandingCredit"], 4000.0)
        self.assertEqual(w["inventoryValue"], 1000.0)  # 10 * 100
        self.assertEqual(w["creditUtilization"], 40.0)

    def test_store_performance_ranks_revenue(self):
        rows = BUILDERS["store_performance"]({})["rows"]
        row = next(r for r in rows if r[0] == "Store 1")
        self.assertEqual(row[1], 500.0)        # revenue
        self.assertEqual(row[2], 1)            # orders
        self.assertEqual(row[7], 1000.0)       # inventory value

    def test_zone_performance(self):
        out = BUILDERS["zone_performance"]({})
        row = next(r for r in out["rows"] if r[0] == "Zone 1")
        self.assertEqual(row[1], 500.0)
        self.assertEqual(row[5], 4000.0)       # outstanding attributed via order zone
        self.assertEqual(row[6], 1500.0)       # collections
        self.assertTrue(out["charts"]["heatmap"])

    def test_credit_utilization_bands(self):
        out = BUILDERS["credit_utilization"]({})
        self.assertEqual(out["summary"]["totalCreditLimit"], 10000.0)
        self.assertEqual(out["summary"]["portfolioUtilization"], 40.0)
        self.assertEqual(out["charts"]["utilizationDistribution"]["25-50"], 1)

    def test_collection_efficiency(self):
        out = BUILDERS["collection_efficiency"]({})
        self.assertEqual(out["summary"]["completed"], 1)
        self.assertEqual(out["summary"]["successRate"], 100.0)

    def test_recovery_performance(self):
        out = BUILDERS["recovery_performance"]({})
        self.assertEqual(out["summary"]["collectedThisMonth"], 1500.0)
        self.assertIn("recoveryTrend", out["charts"])

    def test_customer_cohorts(self):
        rows = BUILDERS["customer_cohorts"]({})["rows"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][1], 1)        # cohort size


class ReportEndpointTests(ReportsBaseData):
    def setUp(self):
        super().setUp()
        self.admin = User.objects.create(phone="+919888888060", name="Admin", role="admin")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_dashboard_endpoint(self):
        r = self.client.get("/api/v1/reports/dashboard")
        self.assertEqual(r.status_code, 200)
        self.assertIn("widgets", r.json()["data"])

    def test_report_endpoint_with_pagination(self):
        r = self.client.get("/api/v1/reports/store_performance", {"page_size": 1, "page": 1})
        self.assertEqual(r.status_code, 200)
        self.assertIn("meta", r.json()["data"])

    def test_csv_export(self):
        r = self.client.get("/api/v1/reports/export", {"type": "store_performance", "fmt": "csv"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r["Content-Type"], "text/csv")

    def test_unknown_report_404(self):
        r = self.client.get("/api/v1/reports/nope")
        self.assertEqual(r.status_code, 404)

    def test_non_admin_forbidden(self):
        c = APIClient()
        c.force_authenticate(self.customer)
        r = c.get("/api/v1/reports/dashboard")
        self.assertIn(r.status_code, (401, 403))
