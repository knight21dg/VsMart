"""Rejecting an order.

Two defects met here. The store panel could accept an order but not refuse one:
"rejected" was missing from both the panel's status list and the backend's
`ALLOWED_STATUSES`, even though `can_transition` had always permitted it. And
the rejection path released stock but nothing else — a prepaid order the store
rejected kept the customer's money and burned their single-use coupon, while
`cancel_order` (the same unwind, different word) refunded and released both.
"""
from decimal import Decimal

from django.test import TestCase

from accounts.models import Role, User
from catalog.models import Category, Product
from inventory.models import InventoryLedger, Warehouse
from inventory.services import InventoryService, StockCalculationService
from orders.models import Order, OrderItem, OrderStatus
from orders.services import advance_status
from payments.models import Payment


class RejectUnwindTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="RejWh", code="REJWH", is_default=True)
        self.category, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Atta", brand="VS", unit="1 kg", price=Decimal("100"),
            mrp=Decimal("120"), category=self.category, stock_count=None,
        )
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh,
            type=InventoryLedger.Type.GRN, quantity=50,
        )
        self.user = User.objects.create(
            phone="+919600022001", name="Cust", role=Role.CUSTOMER
        )

    def _order(self, *, status=OrderStatus.CONFIRMED, paid=Decimal("0")):
        order = Order.objects.create(
            user=self.user, subtotal=Decimal("200"), total=Decimal("200"),
            status=status, stock_state=Order.StockState.RESERVED,
            payment_method=Order.PaymentMethod.UPI,
            payment_status=(
                Order.PaymentStatus.PAID if paid else Order.PaymentStatus.PENDING
            ),
        )
        OrderItem.objects.create(
            order=order, product=self.product, name="Atta", quantity=2,
            price=Decimal("100"), mrp=Decimal("120"),
        )
        InventoryService.reserve(product=self.product, quantity=2, warehouse=self.wh)
        if paid:
            Payment.objects.create(
                user=self.user, order=order, amount=paid,
                purpose=Payment.Purpose.ORDER, status=Payment.Status.SUCCESS,
            )
        return order

    def test_rejecting_releases_the_reservation(self):
        order = self._order()
        before = StockCalculationService.available(self.product, self.wh)
        advance_status(order, OrderStatus.REJECTED)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.REJECTED)
        self.assertEqual(
            StockCalculationService.available(self.product, self.wh), before + 2
        )

    def test_rejecting_a_prepaid_order_refunds_the_customer(self):
        """The store refused to fulfil — keeping the money is not an option."""
        order = self._order(paid=Decimal("200"))
        advance_status(order, OrderStatus.REJECTED)
        order.refresh_from_db()
        refunds = Payment.objects.filter(
            order=order, purpose=Payment.Purpose.REFUND, status=Payment.Status.SUCCESS
        )
        self.assertEqual(refunds.count(), 1)
        self.assertEqual(refunds.first().amount, Decimal("200"))
        self.assertEqual(order.payment_status, Order.PaymentStatus.REFUNDED)

    def test_rejecting_an_unpaid_order_creates_no_refund(self):
        order = self._order()
        advance_status(order, OrderStatus.REJECTED)
        self.assertFalse(
            Payment.objects.filter(order=order, purpose=Payment.Purpose.REFUND).exists()
        )

    def test_rejecting_releases_a_single_use_coupon(self):
        from offers.models import Coupon, CouponRedemption

        coupon = Coupon.objects.create(
            code="ONEUSE", discount_type="flat", value=Decimal("50"),
            is_active=True, usage_limit=1,
        )
        order = self._order()
        CouponRedemption.objects.create(
            coupon=coupon, user=self.user, order_code=order.code, amount=Decimal("50")
        )
        advance_status(order, OrderStatus.REJECTED)
        # The customer never received the goods, so the code must be usable again.
        self.assertFalse(
            CouponRedemption.objects.filter(order_code=order.code).exists()
        )

    def test_a_delivered_order_cannot_be_rejected(self):
        from orders.services import CheckoutError

        order = self._order(status=OrderStatus.DELIVERED)
        with self.assertRaises(CheckoutError):
            advance_status(order, OrderStatus.REJECTED)


class StoreRejectEndpointTests(TestCase):
    """The store panel's own path — it could accept but not refuse."""

    def setUp(self):
        from storeops.tests import client_for, mk_staff, mk_store

        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.user = User.objects.create(
            phone="+919600022002", name="Cust2", role=Role.CUSTOMER
        )

    def _order(self, status=OrderStatus.PLACED):
        return Order.objects.create(
            user=self.user, store=self.store, subtotal=Decimal("100"),
            total=Decimal("100"), status=status,
        )

    def test_store_can_reject_an_order(self):
        order = self._order()
        r = self.mgr.post(
            f"/api/v1/store/orders/{order.code}/status",
            {"status": "rejected"}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.REJECTED)

    def test_store_can_still_accept(self):
        order = self._order()
        r = self.mgr.post(
            f"/api/v1/store/orders/{order.code}/status",
            {"status": "confirmed"}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.CONFIRMED)

    def test_store_still_cannot_mark_an_order_delivered(self):
        """Rejection is now allowed, but the agent's half of the state machine
        (OTP + proof photo) must stay closed to the store."""
        order = self._order(status=OrderStatus.CONFIRMED)
        r = self.mgr.post(
            f"/api/v1/store/orders/{order.code}/status",
            {"status": "delivered"}, format="json",
        )
        self.assertEqual(r.status_code, 400, r.content)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.CONFIRMED)

    def test_rejecting_an_already_delivered_order_explains_why(self):
        """An illegal transition is the operator's mistake, not a server fault.

        `CheckoutError` was a plain Exception that each view had to catch and
        re-raise by hand; this endpoint never did, so the operator was shown a
        500 "We hit a temporary problem on our end" instead of the reason.
        """
        order = self._order(status=OrderStatus.DELIVERED)
        r = self.mgr.post(
            f"/api/v1/store/orders/{order.code}/status",
            {"status": "rejected"}, format="json",
        )
        # 409 CONFLICT — the record's state, not the request's shape, is wrong.
        self.assertEqual(r.status_code, 409, r.content)
        body = r.json()
        self.assertFalse(body["success"])
        self.assertEqual(body["code"], "ORDER_STATUS_INVALID")
        self.assertIn("delivered cannot become rejected", body["message"])
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.DELIVERED)
