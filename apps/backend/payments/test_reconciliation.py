"""Recovery for payments the gateway captured but never reported.

Without this, an app killed after capture (with the webhook also lost) left the
payment PENDING and `release_expired_reservations` cancelled the order — while the
customer had been charged.
"""
from decimal import Decimal
from unittest import mock

from django.test import TestCase
from django.utils import timezone

from accounts.models import Role, User
from orders.models import Order, OrderStatus
from orders.services import release_expired_reservations
from payments.models import Payment
from payments.services import reconcile_pending_payments


def _user(phone="+919600012001"):
    return User.objects.create(phone=phone, name="Cust", role=Role.CUSTOMER)


class ReconcilePendingPaymentsTests(TestCase):
    def setUp(self):
        self.user = _user()
        self.order = Order.objects.create(
            user=self.user, subtotal=Decimal("500"), total=Decimal("500"),
            status=OrderStatus.PENDING,
        )
        self.payment = Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, amount=Decimal("500"),
            method=Payment.Method.UPI, order=self.order, gateway="razorpay",
            status=Payment.Status.PENDING, gateway_order_id="order_live",
        )
        self._age(self.payment, minutes=30)

    def _age(self, payment, *, minutes):
        Payment.objects.filter(pk=payment.pk).update(
            created_at=timezone.now() - timezone.timedelta(minutes=minutes)
        )

    def _gateway(self, info):
        gw = mock.Mock()
        gw.fetch_order_payment.return_value = info
        return mock.patch("payments.services.get_gateway", return_value=gw)

    def test_a_captured_payment_is_recovered_and_the_order_settles(self):
        with self._gateway({"gateway_payment_id": "pay_live",
                            "status": "captured", "amount": Decimal("500")}):
            summary = reconcile_pending_payments()
        self.assertEqual(summary["settled"], 1)
        self.payment.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual(self.payment.status, Payment.Status.SUCCESS)
        self.assertEqual(self.order.payment_status, Order.PaymentStatus.PAID)

    def test_a_failed_payment_is_marked_failed(self):
        with self._gateway({"gateway_payment_id": "pay_live",
                            "status": "failed", "amount": Decimal("500")}):
            summary = reconcile_pending_payments()
        self.assertEqual(summary["failed"], 1)
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.status, Payment.Status.FAILED)

    def test_a_still_in_flight_payment_is_left_alone(self):
        with self._gateway({"gateway_payment_id": "pay_live",
                            "status": "authorized", "amount": Decimal("500")}):
            summary = reconcile_pending_payments()
        self.assertEqual(summary["unresolved"], 1)
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.status, Payment.Status.PENDING)

    def test_a_short_capture_is_not_settled(self):
        with self._gateway({"gateway_payment_id": "pay_live",
                            "status": "captured", "amount": Decimal("1")}):
            summary = reconcile_pending_payments()
        self.assertEqual(summary["errors"], 1)
        self.order.refresh_from_db()
        self.assertNotEqual(self.order.payment_status, Order.PaymentStatus.PAID)

    def test_a_recent_payment_is_not_touched(self):
        # Never race a checkout still in progress.
        self._age(self.payment, minutes=1)
        with self._gateway({"gateway_payment_id": "p", "status": "captured",
                            "amount": Decimal("500")}) as _:
            summary = reconcile_pending_payments(older_than_minutes=10)
        self.assertEqual(summary["checked"], 0)

    def test_cash_payments_are_not_reconciled(self):
        Payment.objects.filter(pk=self.payment.pk).update(
            method=Payment.Method.CASH, gateway_order_id=""
        )
        with self._gateway(None):
            summary = reconcile_pending_payments()
        self.assertEqual(summary["checked"], 0)


class ExpiryJobTests(TestCase):
    """The expiry job must not cancel an order whose money may be captured."""

    def setUp(self):
        self.user = _user("+919600012002")
        self.order = Order.objects.create(
            user=self.user, subtotal=Decimal("500"), total=Decimal("500"),
            status=OrderStatus.PENDING, stock_state=Order.StockState.RESERVED,
        )
        Order.objects.filter(pk=self.order.pk).update(
            placed_at=timezone.now() - timezone.timedelta(hours=2)
        )

    def test_an_order_with_an_unresolved_gateway_payment_is_not_cancelled(self):
        payment = Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, amount=Decimal("500"),
            method=Payment.Method.UPI, order=self.order, gateway="razorpay",
            status=Payment.Status.PENDING, gateway_order_id="order_live",
        )
        Payment.objects.filter(pk=payment.pk).update(
            created_at=timezone.now() - timezone.timedelta(hours=2)
        )
        gw = mock.Mock()
        gw.fetch_order_payment.return_value = {
            "gateway_payment_id": "p", "status": "authorized",
            "amount": Decimal("500"),
        }
        with mock.patch("payments.services.get_gateway", return_value=gw):
            cancelled = release_expired_reservations()
        self.assertNotIn(self.order.code, cancelled)
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, OrderStatus.PENDING)

    def test_a_genuinely_abandoned_order_is_still_cancelled(self):
        cancelled = release_expired_reservations()
        self.assertIn(self.order.code, cancelled)
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, OrderStatus.CANCELLED)

    def test_reconciliation_settles_the_order_instead_of_cancelling_it(self):
        payment = Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, amount=Decimal("500"),
            method=Payment.Method.UPI, order=self.order, gateway="razorpay",
            status=Payment.Status.PENDING, gateway_order_id="order_live",
        )
        Payment.objects.filter(pk=payment.pk).update(
            created_at=timezone.now() - timezone.timedelta(hours=2)
        )
        gw = mock.Mock()
        gw.fetch_order_payment.return_value = {
            "gateway_payment_id": "pay_live", "status": "captured",
            "amount": Decimal("500"),
        }
        with mock.patch("payments.services.get_gateway", return_value=gw):
            cancelled = release_expired_reservations()
        self.assertNotIn(self.order.code, cancelled)
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, Order.PaymentStatus.PAID)
        self.assertNotEqual(self.order.status, OrderStatus.CANCELLED)
