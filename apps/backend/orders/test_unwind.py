"""Stock and coupon unwind on the paths that aren't a plain cancellation."""
from decimal import Decimal

from django.test import TestCase

from accounts.models import Role, User
from catalog.models import Category, Product
from inventory.models import StockItem, Warehouse
from offers.models import Coupon, CouponRedemption
from offers.services import redeem_coupon
from orders.models import Order, OrderItem, OrderStatus
from orders.services import advance_status, cancel_order


def _user(phone="+919600013001"):
    return User.objects.create(phone=phone, name="Cust", role=Role.CUSTOMER)


class ReservationReleaseTests(TestCase):
    """A reservation must not survive an order that ends undelivered."""

    def setUp(self):
        self.user = _user()
        self.wh = Warehouse.objects.create(name="WH", code="WH-U", is_active=True)
        cat = Category.objects.create(name="Staples", slug="staples-unwind")
        self.product = Product.objects.create(
            name="Atta", price=Decimal("50"), mrp=Decimal("60"), category=cat,
            stock_count=100,
        )
        self.stock = StockItem.objects.create(
            product=self.product, warehouse=self.wh, quantity=100, reserved=5,
        )

    def _order(self, status):
        order = Order.objects.create(
            user=self.user, subtotal=Decimal("250"), total=Decimal("250"),
            status=status, stock_state=Order.StockState.RESERVED,
        )
        OrderItem.objects.create(
            order=order, product=self.product, name="Atta", price=Decimal("50"),
            mrp=Decimal("60"), quantity=5,
        )
        return order

    def _reserved(self):
        self.stock.refresh_from_db()
        return self.stock.reserved

    def test_failed_delivery_releases_the_hold(self):
        # Previously nothing released it and no later path could: cancel_order
        # refuses non-pending/confirmed, so the units were held forever.
        order = self._order(OrderStatus.OUT_FOR_DELIVERY)
        advance_status(order, OrderStatus.FAILED_DELIVERY)
        order.refresh_from_db()
        self.assertEqual(order.stock_state, Order.StockState.RELEASED)
        self.assertEqual(self._reserved(), 0)

    def test_rejected_releases_the_hold(self):
        order = self._order(OrderStatus.CONFIRMED)
        advance_status(order, OrderStatus.REJECTED)
        order.refresh_from_db()
        self.assertEqual(order.stock_state, Order.StockState.RELEASED)
        self.assertEqual(self._reserved(), 0)

    def test_release_is_idempotent_across_a_retried_delivery(self):
        order = self._order(OrderStatus.OUT_FOR_DELIVERY)
        advance_status(order, OrderStatus.FAILED_DELIVERY)
        # Re-attempt, fail again: the second release must not inflate stock.
        advance_status(order, OrderStatus.OUT_FOR_DELIVERY)
        advance_status(order, OrderStatus.FAILED_DELIVERY)
        self.assertEqual(self._reserved(), 0)

    def test_delivery_still_fulfils_rather_than_releasing(self):
        order = self._order(OrderStatus.OUT_FOR_DELIVERY)
        advance_status(order, OrderStatus.DELIVERED)
        order.refresh_from_db()
        self.assertEqual(order.stock_state, Order.StockState.FULFILLED)


class CouponReleaseTests(TestCase):
    def setUp(self):
        self.user = _user("+919600013002")
        self.coupon = Coupon.objects.create(
            code="SAVE10", is_active=True, usage_limit=1, per_user_limit=1,
            discount_type="flat", value=Decimal("10"),
        )

    def _order(self):
        return Order.objects.create(
            user=self.user, subtotal=Decimal("100"), total=Decimal("90"),
            status=OrderStatus.CONFIRMED,
        )

    def test_cancelling_gives_the_coupon_back(self):
        order = self._order()
        redeem_coupon("SAVE10", self.user, order_code=order.code, amount=Decimal("10"))
        self.assertEqual(CouponRedemption.objects.count(), 1)

        cancel_order(order)
        self.assertEqual(CouponRedemption.objects.count(), 0)

        # And it is genuinely usable again — previously "already used" forever.
        second = self._order()
        redeem_coupon("SAVE10", self.user, order_code=second.code,
                      amount=Decimal("10"))
        self.assertEqual(CouponRedemption.objects.count(), 1)

    def test_releasing_only_touches_that_order(self):
        keep = self._order()
        redeem_coupon("SAVE10", self.user, order_code=keep.code, amount=Decimal("10"))
        other = self._order()
        cancel_order(other)
        self.assertEqual(CouponRedemption.objects.count(), 1)
