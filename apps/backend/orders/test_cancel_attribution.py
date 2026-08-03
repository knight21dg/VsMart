"""A staff cancellation must be attributed to the staff member, with their reason.

The admin console's cancel path dropped both the actor and the note on the way
through `set_order_status`, and `cancel_order` then hardcoded the timeline entry
to "Cancelled by customer". Every admin cancellation — including "item out of
stock" and "customer unreachable" — was recorded as the customer's own decision,
which is exactly the trail an operator follows when investigating a complaint.
"""
from decimal import Decimal

from django.test import TestCase

from accounts.models import Role, User
from orders.admin_service import set_order_status
from orders.models import Order, OrderStatus, OrderStatusEvent
from orders.services import cancel_order


def _customer():
    return User.objects.create(phone="+919600020001", name="Cust", role=Role.CUSTOMER)


def _staff():
    return User.objects.create(phone="+919600020002", name="Ops Ravi", role=Role.ADMIN)


class CancelAttributionTests(TestCase):
    def setUp(self):
        self.customer = _customer()
        self.staff = _staff()

    def _order(self):
        return Order.objects.create(
            user=self.customer, subtotal=Decimal("500"), total=Decimal("500"),
            status=OrderStatus.CONFIRMED,
        )

    def _event(self, order):
        return OrderStatusEvent.objects.filter(
            order=order, status=OrderStatus.CANCELLED).latest("id")

    def test_customer_cancellation_is_still_attributed_to_the_customer(self):
        order = self._order()
        cancel_order(order)
        event = self._event(order)
        self.assertIsNone(event.by)
        self.assertEqual(event.note, "Cancelled by customer")

    def test_admin_cancellation_records_the_staff_member_and_their_reason(self):
        order = self._order()
        set_order_status(order, OrderStatus.CANCELLED, by=self.staff,
                         note="Exception: Item Out of Stock")
        order.refresh_from_db()
        event = self._event(order)

        self.assertEqual(order.status, OrderStatus.CANCELLED)
        self.assertEqual(event.by, self.staff)
        self.assertEqual(event.note, "Exception: Item Out of Stock")
        self.assertNotEqual(event.note, "Cancelled by customer")

    def test_staff_cancellation_without_a_note_still_says_staff_not_customer(self):
        order = self._order()
        set_order_status(order, OrderStatus.CANCELLED, by=self.staff, note="")
        event = self._event(order)
        self.assertEqual(event.by, self.staff)
        self.assertEqual(event.note, "Cancelled by staff")
