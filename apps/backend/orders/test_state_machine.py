"""The order status state machine.

`advance_status` used to assign whatever it was handed. The headline consequence:
an agent could mark a CANCELLED or never-paid order "delivered", which fulfilled
its stock and awarded loyalty points for goods nobody bought.
"""
from decimal import Decimal

from django.test import TestCase

from accounts.models import Role, User
from orders.models import Order, OrderStatus, can_transition
from orders.services import CheckoutError, advance_status


class TransitionRuleTests(TestCase):
    def test_forward_moves_including_skipped_rungs(self):
        # A store that dispatches immediately skips packed/ready — legitimate.
        self.assertTrue(can_transition("confirmed", "out_for_delivery"))
        self.assertTrue(can_transition("placed", "confirmed"))
        self.assertTrue(can_transition("packed", "ready_for_dispatch"))

    def test_backward_moves_are_refused(self):
        self.assertFalse(can_transition("out_for_delivery", "confirmed"))
        self.assertFalse(can_transition("packed", "placed"))

    def test_delivered_only_from_out_for_delivery(self):
        # The rule that matters most: it blocks marking an unpaid, unpacked or
        # cancelled order delivered.
        self.assertTrue(can_transition("out_for_delivery", "delivered"))
        for bad in ("pending", "placed", "confirmed", "packed",
                    "ready_for_dispatch", "cancelled"):
            self.assertFalse(can_transition(bad, "delivered"), bad)

    def test_nothing_leaves_a_terminal_state(self):
        for terminal in ("cancelled", "rejected", "returned", "partially_returned"):
            for target in ("confirmed", "delivered", "out_for_delivery"):
                self.assertFalse(can_transition(terminal, target), f"{terminal}->{target}")

    def test_delivered_may_only_move_to_a_return(self):
        self.assertTrue(can_transition("delivered", "returned"))
        self.assertTrue(can_transition("delivered", "partially_returned"))
        self.assertFalse(can_transition("delivered", "cancelled"))

    def test_cancellation_stops_once_a_rider_has_it(self):
        self.assertTrue(can_transition("confirmed", "cancelled"))
        self.assertTrue(can_transition("ready_for_dispatch", "cancelled"))
        self.assertFalse(can_transition("out_for_delivery", "cancelled"))

    def test_failed_delivery_only_from_out_for_delivery_and_can_be_retried(self):
        self.assertTrue(can_transition("out_for_delivery", "failed_delivery"))
        self.assertFalse(can_transition("confirmed", "failed_delivery"))
        self.assertTrue(can_transition("failed_delivery", "out_for_delivery"))
        self.assertTrue(can_transition("failed_delivery", "returned"))

    def test_a_no_op_is_allowed_so_retries_are_idempotent(self):
        self.assertTrue(can_transition("delivered", "delivered"))
        self.assertTrue(can_transition("cancelled", "cancelled"))

    def test_pending_is_treated_as_placed(self):
        self.assertTrue(can_transition("pending", "confirmed"))
        self.assertFalse(can_transition("confirmed", "pending"))


class AdvanceStatusTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            phone="+919600011001", name="Cust", role=Role.CUSTOMER
        )

    def _order(self, status):
        return Order.objects.create(
            user=self.user, subtotal=Decimal("100"), total=Decimal("100"),
            status=status,
        )

    def test_illegal_move_raises_and_changes_nothing(self):
        order = self._order(OrderStatus.CANCELLED)
        with self.assertRaises(CheckoutError) as ctx:
            advance_status(order, OrderStatus.DELIVERED)
        self.assertEqual(ctx.exception.code, "ORDER_STATUS_INVALID")
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.CANCELLED)

    def test_an_unpaid_pending_order_cannot_be_delivered(self):
        order = self._order(OrderStatus.PENDING)
        with self.assertRaises(CheckoutError):
            advance_status(order, OrderStatus.DELIVERED)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.PENDING)

    def test_a_legal_move_is_applied_and_recorded(self):
        order = self._order(OrderStatus.CONFIRMED)
        advance_status(order, OrderStatus.PACKED, note="Packed by store")
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.PACKED)
        self.assertTrue(
            order.timeline.filter(status=OrderStatus.PACKED).exists()
        )

    def test_repeating_the_same_status_is_a_no_op_not_an_error(self):
        order = self._order(OrderStatus.PACKED)
        advance_status(order, OrderStatus.PACKED)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.PACKED)
        # No duplicate timeline noise from a retried tap.
        self.assertEqual(order.timeline.filter(status=OrderStatus.PACKED).count(), 0)
