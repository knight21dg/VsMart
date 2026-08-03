"""Failed-delivery → store handover, COD cash confirmation, and the earnings
single-source fix."""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product
from inventory.models import InventoryLedger, Warehouse
from inventory.services import InventoryService, StockCalculationService
from orders.models import Order, OrderItem, OrderStatus
from payments.models import CashCollection, Payment

from . import services
from .models import DeliveryTask
from .tests import DEST, _order


class ReturnHandoverTests(TestCase):
    """Agent initiates the return; the STORE confirms physical receipt — which is
    when stock restores and the order closes."""

    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Rice", brand="VS", unit="1 kg", price=Decimal("50"),
            mrp=Decimal("60"), category=cat, stock_count=100, available_count=100)
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh,
            type=InventoryLedger.Type.GRN, quantity=10)
        self.agent = User.objects.create(
            phone="+919777777500", name="Agent R", role="agent")
        self.customer = User.objects.create(
            phone="+919000000500", name="Cust R", role="customer")
        self.order = _order(self.customer, reserved=True)
        OrderItem.objects.create(
            order=self.order, product=self.product, name="Rice",
            quantity=2, price=Decimal("50"), mrp=Decimal("60"))
        InventoryService.reserve(product=self.product, quantity=2, warehouse=self.wh)
        self.task = services.auto_assign(self.order)
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        services.fail_delivery(
            self.task, self.agent,
            reason_code="FAILED_CUSTOMER_UNREACHABLE", note="No answer")
        self.client = APIClient()

    def test_agent_can_start_the_return(self):
        self.client.force_authenticate(self.agent)
        r = self.client.post(f"/api/v1/deliveries/{self.task.id}/return")
        self.assertEqual(r.status_code, 200, r.data)
        self.task.refresh_from_db()
        self.assertEqual(self.task.status, "return_initiated")

    def test_agent_initiation_does_NOT_restore_stock_yet(self):
        """Stock restores when the STORE has the goods, not when the rider says
        they're on the way back."""
        before = StockCalculationService.available(self.product, self.wh)
        self.client.force_authenticate(self.agent)
        self.client.post(f"/api/v1/deliveries/{self.task.id}/return")
        self.assertEqual(
            StockCalculationService.available(self.product, self.wh), before)

    def test_store_receipt_completes_the_return(self):
        # Stock was already freed the moment the delivery FAILED (the reservation
        # release hook) — the store receipt must close the loop WITHOUT releasing
        # a second time.
        services.initiate_return(self.task, self.agent)
        before = StockCalculationService.available(self.product, self.wh)
        services.return_to_store(self.task, by=self.customer)  # any staff actor
        self.task.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual(self.task.status, "returned_to_store")
        self.assertEqual(self.order.status, "cancelled")
        self.assertEqual(
            StockCalculationService.available(self.product, self.wh), before,
            "receipt double-released stock that fail already freed")

    def test_admin_shortcut_from_failed_still_works(self):
        services.return_to_store(self.task, by=self.customer)
        self.task.refresh_from_db()
        self.assertEqual(self.task.status, "returned_to_store")

    def test_the_failed_attempt_is_on_the_agents_record(self):
        """'He attempted' — the attempt row exists and counts."""
        self.assertTrue(self.task.attempts.exists())


class CodCashCollectionTests(TestCase):
    def setUp(self):
        self.agent = User.objects.create(
            phone="+919777777501", name="Agent C", role="agent")
        self.customer = User.objects.create(
            phone="+919000000501", name="Cust C", role="customer")
        self.order = _order(self.customer, total="649")
        self.task = services.auto_assign(self.order)
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        self.task.refresh_from_db()
        services.arrive(self.task, self.agent, DEST[0], DEST[1])
        services.verify_otp(self.task, self.agent, self.task.delivery_otp.code)
        services.add_evidence(self.task, self.agent, "pod/x.jpg",
                              lat=DEST[0], lng=DEST[1])
        services.complete_delivery(self.task, self.agent)
        self.client = APIClient()
        self.client.force_authenticate(self.agent)

    def _collect(self):
        return self.client.post(
            f"/api/v1/deliveries/{self.task.id}/collect-cash")

    def test_collecting_marks_the_order_paid_with_a_cash_payment(self):
        r = self._collect()
        self.assertEqual(r.status_code, 200, r.data)
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, "paid")
        payment = Payment.objects.get(order=self.order)
        self.assertEqual(payment.method, "cash")
        self.assertEqual(payment.status, Payment.Status.SUCCESS)
        self.assertEqual(payment.amount, Decimal("649"))

    def test_the_notes_enter_the_cash_book(self):
        self._collect()
        collection = CashCollection.objects.get(agent=self.agent)
        self.assertEqual(collection.status, CashCollection.Status.COLLECTED)
        self.assertEqual(collection.collected_amount, Decimal("649"))
        self.assertIsNone(collection.deposit_id)  # still in hand

    def test_in_hand_reflects_the_collection(self):
        self._collect()
        r = self.client.get("/api/v1/deliveries/cash-in-hand")
        self.assertEqual(Decimal(str(r.data["in_hand"])), Decimal("649"))
        self.assertEqual(r.data["collections"], 1)

    def test_double_tap_cannot_double_collect(self):
        self._collect()
        r = self._collect()
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(Payment.objects.filter(order=self.order).count(), 1)
        self.assertEqual(
            CashCollection.objects.filter(agent=self.agent).count(), 1)

    def test_collect_before_delivered_is_refused(self):
        other_order = _order(self.customer)
        task = services.auto_assign(other_order)
        services.accept(task, self.agent)
        r = self.client.post(f"/api/v1/deliveries/{task.id}/collect-cash")
        self.assertEqual(r.status_code, 409)

    def test_non_cod_order_is_refused(self):
        credit_order = _order(
            self.customer, method=Order.PaymentMethod.CREDIT)
        task = services.auto_assign(credit_order)
        services.accept(task, self.agent)
        services.pick_up(task, self.agent)
        services.out_for_delivery(task, self.agent)
        task.refresh_from_db()
        services.arrive(task, self.agent, DEST[0], DEST[1])
        services.verify_otp(task, self.agent, task.delivery_otp.code)
        services.add_evidence(task, self.agent, "pod/y.jpg",
                              lat=DEST[0], lng=DEST[1])
        services.complete_delivery(task, self.agent)
        r = self.client.post(f"/api/v1/deliveries/{task.id}/collect-cash")
        self.assertEqual(r.status_code, 409)


class EarningsSingleSourceTests(TestCase):
    """The dashboard figure must be the SAME earnings the completion screen shows
    (real per-task DeliveryEarnings), not a parallel flat rate."""

    def setUp(self):
        self.agent = User.objects.create(
            phone="+919777777502", name="Agent E", role="agent")
        self.customer = User.objects.create(
            phone="+919000000502", name="Cust E", role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.agent)

    def test_dashboard_base_equals_released_task_earnings(self):
        order = _order(self.customer, total="300")
        task = services.auto_assign(order)
        services.accept(task, self.agent)
        services.pick_up(task, self.agent)
        services.out_for_delivery(task, self.agent)
        task.refresh_from_db()
        services.arrive(task, self.agent, DEST[0], DEST[1])
        services.verify_otp(task, self.agent, task.delivery_otp.code)
        services.add_evidence(task, self.agent, "pod/z.jpg",
                              lat=DEST[0], lng=DEST[1])
        services.complete_delivery(task, self.agent)

        earned = task.earnings.total
        r = self.client.get("/api/v1/agents/earnings")
        self.assertEqual(Decimal(str(r.data["base"])), earned)
