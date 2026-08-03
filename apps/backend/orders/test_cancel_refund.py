"""Cancelling an order must return money that was actually collected.

`cancel_order` only ever reversed the VS Credit leg, so a customer who paid by UPI
and cancelled a confirmed order had the order cancelled and the money kept, with
`payment_status` still reading "paid".
"""
from decimal import Decimal

from django.test import TestCase

from accounts.models import Role, User
from orders.models import Order, OrderStatus
from orders.services import cancel_order, collected_amount
from payments.models import Payment


def _user(phone="+919600010001"):
    return User.objects.create(phone=phone, name="Cust", role=Role.CUSTOMER)


class CancelRefundTests(TestCase):
    def setUp(self):
        self.user = _user()

    def _paid_order(self, total="2000", method=Payment.Method.UPI):
        order = Order.objects.create(
            user=self.user, subtotal=Decimal(total), total=Decimal(total),
            status=OrderStatus.CONFIRMED,
            payment_status=Order.PaymentStatus.PAID,
        )
        Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, amount=Decimal(total),
            method=method, order=order, gateway="manual",
            status=Payment.Status.SUCCESS, gateway_payment_id="pay_x",
        )
        return order

    def test_cancelling_a_paid_order_creates_a_refund(self):
        order = self._paid_order("2000")
        cancel_order(order)
        order.refresh_from_db()

        refund = Payment.objects.get(order=order, purpose=Payment.Purpose.REFUND)
        self.assertEqual(refund.amount, Decimal("2000"))
        self.assertEqual(order.status, OrderStatus.CANCELLED)
        self.assertEqual(order.payment_status, Order.PaymentStatus.REFUNDED)

    def test_the_original_payment_is_marked_refunded_when_fully_returned(self):
        order = self._paid_order("2000")
        cancel_order(order)
        original = Payment.objects.get(order=order, purpose=Payment.Purpose.ORDER)
        self.assertEqual(original.status, Payment.Status.REFUNDED)

    def test_an_unpaid_order_produces_no_refund(self):
        order = Order.objects.create(
            user=self.user, subtotal=Decimal("500"), total=Decimal("500"),
            status=OrderStatus.PENDING,
        )
        cancel_order(order)
        self.assertFalse(
            Payment.objects.filter(order=order, purpose=Payment.Purpose.REFUND).exists()
        )
        order.refresh_from_db()
        self.assertEqual(order.payment_status, Order.PaymentStatus.PENDING)

    def test_refund_is_idempotent_across_repeated_cancels(self):
        # A concurrent customer+admin cancel, or a retry of the expiry cron, must
        # not send the money twice.
        order = self._paid_order("2000")
        cancel_order(order)
        with self.assertRaises(Exception):
            # Second cancel is rejected by the status guard …
            cancel_order(order)
        # … and even if it weren't, the idempotency key bounds it to one refund.
        self.assertEqual(
            Payment.objects.filter(order=order, purpose=Payment.Purpose.REFUND).count(),
            1,
        )

    def test_collected_amount_ignores_the_credit_leg(self):
        # A part-credit order must refund only what left a real instrument;
        # order.total would over-refund by the credit portion.
        order = Order.objects.create(
            user=self.user, subtotal=Decimal("2000"), total=Decimal("2000"),
            credit_used=Decimal("500"), status=OrderStatus.CONFIRMED,
            payment_status=Order.PaymentStatus.PAID,
        )
        Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, amount=Decimal("1500"),
            method=Payment.Method.UPI, order=order, gateway="manual",
            status=Payment.Status.SUCCESS, gateway_payment_id="pay_y",
        )
        self.assertEqual(collected_amount(order), Decimal("1500"))
        cancel_order(order)
        refund = Payment.objects.get(order=order, purpose=Payment.Purpose.REFUND)
        self.assertEqual(refund.amount, Decimal("1500"))

    def test_collected_amount_nets_off_an_earlier_partial_refund(self):
        order = self._paid_order("2000")
        original = Payment.objects.get(order=order, purpose=Payment.Purpose.ORDER)
        Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.REFUND, amount=Decimal("500"),
            method=Payment.Method.UPI, order=order, refund_of=original,
            gateway="manual", status=Payment.Status.SUCCESS,
        )
        self.assertEqual(collected_amount(order), Decimal("1500"))


class PartialRefundTests(TestCase):
    """A part refund must not retire the whole original payment."""

    def setUp(self):
        self.user = _user("+919600010002")
        self.order = Order.objects.create(
            user=self.user, subtotal=Decimal("2000"), total=Decimal("2000"),
            status=OrderStatus.DELIVERED, payment_status=Order.PaymentStatus.PAID,
        )
        self.original = Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, amount=Decimal("2000"),
            method=Payment.Method.UPI, order=self.order, gateway="manual",
            status=Payment.Status.SUCCESS, gateway_payment_id="pay_z",
        )

    def test_partial_refund_leaves_the_original_successful(self):
        from payments.services import refund_payment

        refund_payment(self.order, Decimal("200"), reason="one item returned",
                       idempotency_key="ret_1")
        self.original.refresh_from_db()
        # Previously flipped to REFUNDED, dropping the full ₹2,000 out of
        # collected revenue in the admin ledger for a ₹200 return.
        self.assertEqual(self.original.status, Payment.Status.SUCCESS)

    def test_refunds_accumulate_to_retire_the_original(self):
        from payments.services import refund_payment

        refund_payment(self.order, Decimal("200"), idempotency_key="ret_1")
        refund_payment(self.order, Decimal("1800"), idempotency_key="ret_2")
        self.original.refresh_from_db()
        self.assertEqual(self.original.status, Payment.Status.REFUNDED)
