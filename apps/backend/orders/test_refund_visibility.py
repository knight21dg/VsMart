"""The order detail must say whether the money came back.

`OrderDetailSerializer` exposed status and totals but nothing about money actually
moved, so a customer whose order was cancelled saw "Cancelled" and had no way to
tell whether they'd been refunded.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from payments.models import Payment

from .models import Order, OrderStatus


class OrderRefundVisibilityTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919001100001", role="customer")
        self.order = Order.objects.create(
            user=self.user, payment_method=Order.PaymentMethod.UPI,
            status=OrderStatus.PLACED, total=Decimal("500"))
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def _pay(self, amount, *, purpose=Payment.Purpose.ORDER,
             status=Payment.Status.SUCCESS):
        return Payment.objects.create(
            user=self.user, order=self.order, purpose=purpose,
            amount=Decimal(amount), method=Payment.Method.UPI, status=status)

    def _detail(self):
        r = self.client.get(f"/api/v1/orders/{self.order.code}")
        self.assertEqual(r.status_code, 200)
        return r.data

    def test_unpaid_order_reports_zero_on_both(self):
        data = self._detail()
        self.assertEqual(Decimal(str(data["amount_paid"])), Decimal("0"))
        self.assertEqual(Decimal(str(data["amount_refunded"])), Decimal("0"))

    def test_paid_order_reports_what_was_taken(self):
        self._pay("500")
        self.assertEqual(Decimal(str(self._detail()["amount_paid"])), Decimal("500"))

    def test_a_failed_attempt_is_not_counted_as_paid(self):
        self._pay("500", status=Payment.Status.FAILED)
        self.assertEqual(Decimal(str(self._detail()["amount_paid"])), Decimal("0"))

    def test_refund_is_reported_and_nets_off_the_paid_amount(self):
        self._pay("500")
        self._pay("500", purpose=Payment.Purpose.REFUND)

        data = self._detail()
        self.assertEqual(Decimal(str(data["amount_refunded"])), Decimal("500"))
        # Fully refunded → nothing still out of pocket.
        self.assertEqual(Decimal(str(data["amount_paid"])), Decimal("0"))

    def test_partial_refund_leaves_the_remainder_showing_as_paid(self):
        self._pay("500")
        self._pay("200", purpose=Payment.Purpose.REFUND)

        data = self._detail()
        self.assertEqual(Decimal(str(data["amount_refunded"])), Decimal("200"))
        self.assertEqual(Decimal(str(data["amount_paid"])), Decimal("300"))

    def test_a_pending_refund_is_not_reported_as_refunded(self):
        """The whole point: 'cancelled but not yet refunded' must be visible as
        NOT refunded, or the customer thinks they've been paid back."""
        self._pay("500")
        self._pay("500", purpose=Payment.Purpose.REFUND,
                  status=Payment.Status.PENDING)

        data = self._detail()
        self.assertEqual(Decimal(str(data["amount_refunded"])), Decimal("0"))
        self.assertEqual(Decimal(str(data["amount_paid"])), Decimal("500"))

    def test_credit_leg_is_not_reported_as_cash_paid(self):
        """A VS Credit purchase is reversed in the credit ledger, not refunded, so
        counting it here would promise a refund that never arrives."""
        self.order.payment_method = Order.PaymentMethod.CREDIT
        self.order.credit_used = Decimal("500")
        self.order.save(update_fields=["payment_method", "credit_used"])

        self.assertEqual(Decimal(str(self._detail()["amount_paid"])), Decimal("0"))

    def test_another_users_order_is_not_readable(self):
        other = User.objects.create(phone="+919001100002", role="customer")
        self.client.force_authenticate(other)
        r = self.client.get(f"/api/v1/orders/{self.order.code}")
        self.assertEqual(r.status_code, 404)
