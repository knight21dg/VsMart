"""Notification idempotency.

Nothing deduplicated notifications: every retry of an operation minted a fresh
inbox row and a fresh device push. An agent was re-alerted "New delivery
assigned" each time the 120-second dispatch loop touched a task already sitting
in their list, and a replayed checkout could ring the store counter twice for
one order. `notify(dedupe_key=…)` keys the send on the *event* rather than the
attempt.
"""
from decimal import Decimal
from unittest import mock

from django.test import TestCase

from accounts.models import Role, User
from notifications.models import Notification
from notifications.services import notify
from orders.models import Order, OrderStatus


class NotifyDedupeTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            phone="+919600033001", name="Cust", role=Role.CUSTOMER
        )

    def _count(self):
        return Notification.objects.filter(user=self.user).count()

    def test_a_keyed_notification_is_sent_once(self):
        for _ in range(3):
            notify(self.user, type="delivery", title="New delivery assigned",
                   dedupe_key="delivery_assigned:task:1:agent:9")
        self.assertEqual(self._count(), 1)

    def test_the_repeat_returns_the_original_row(self):
        first = notify(self.user, type="order", title="A", dedupe_key="k1")
        again = notify(self.user, type="order", title="B", dedupe_key="k1")
        self.assertEqual(first.pk, again.pk)
        # The first message wins — a repeat must not silently rewrite history.
        self.assertEqual(again.title, "A")

    def test_a_repeat_schedules_no_second_push(self):
        """The point isn't tidy rows, it's not buzzing someone's pocket twice.

        The push is deferred with `transaction.on_commit`, which never fires
        inside a TestCase's rolled-back transaction — `captureOnCommitCallbacks`
        runs them so the assertion is about real behaviour.
        """
        with mock.patch("notifications.services._push") as push:
            with self.captureOnCommitCallbacks(execute=True):
                notify(self.user, type="order", title="Once", dedupe_key="k2")
                notify(self.user, type="order", title="Once", dedupe_key="k2")
        self.assertEqual(push.call_count, 1)

    def test_different_keys_both_arrive(self):
        notify(self.user, type="order", title="A", dedupe_key="order_status:X:packed")
        notify(self.user, type="order", title="B", dedupe_key="order_status:X:delivered")
        self.assertEqual(self._count(), 2)

    def test_the_same_key_for_a_different_user_still_arrives(self):
        other = User.objects.create(
            phone="+919600033002", name="Other", role=Role.CUSTOMER
        )
        notify(self.user, type="order", title="A", dedupe_key="shared")
        notify(other, type="order", title="A", dedupe_key="shared")
        self.assertEqual(Notification.objects.filter(dedupe_key="shared").count(), 2)

    def test_unkeyed_notifications_are_still_repeatable(self):
        """A re-sent OTP or a marketing blast must be able to arrive twice."""
        for _ in range(3):
            notify(self.user, type="delivery", title="Delivery code")
        self.assertEqual(self._count(), 3)


class DeliveryAssignmentDedupeTests(TestCase):
    """The concrete duplicate the QA report describes."""

    def setUp(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask

        self.DeliveryTask = DeliveryTask
        self.customer = User.objects.create(
            phone="+919600033010", name="Cust", role=Role.CUSTOMER
        )
        self.agent = User.objects.create(
            phone="+919600033011", name="Rider", role=Role.AGENT
        )
        AgentProfile.objects.create(user=self.agent, code="AGDUP1")
        self.order = Order.objects.create(
            user=self.customer, subtotal=Decimal("100"), total=Decimal("100"),
            status=OrderStatus.READY_FOR_DISPATCH,
        )
        self.task = DeliveryTask.objects.create(
            order=self.order, agent=self.agent, status="assigned"
        )

    def test_repeated_dispatch_passes_alert_the_agent_once(self):
        from delivery.services import _notify_agent

        for _ in range(4):
            _notify_agent(self.task)
        self.assertEqual(
            Notification.objects.filter(
                user=self.agent, title="New delivery assigned"
            ).count(),
            1,
        )

    def test_reassigning_to_a_different_agent_does_notify_them(self):
        """Dedupe must not silence a real handover."""
        from accounts.models import AgentProfile
        from delivery.services import _notify_agent

        _notify_agent(self.task)
        new_agent = User.objects.create(
            phone="+919600033012", name="Rider2", role=Role.AGENT
        )
        AgentProfile.objects.create(user=new_agent, code="AGDUP2")
        self.task.agent = new_agent
        self.task.save(update_fields=["agent"])
        _notify_agent(self.task)
        self.assertEqual(
            Notification.objects.filter(title="New delivery assigned").count(), 2
        )
        self.assertTrue(
            Notification.objects.filter(
                user=new_agent, title="New delivery assigned"
            ).exists()
        )


class OrderStatusNotificationDedupeTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            phone="+919600033020", name="Cust", role=Role.CUSTOMER
        )

    def test_revisiting_a_status_does_not_re_announce_it(self):
        """A re-attempted delivery goes out_for_delivery → failed → out_for
        _delivery. The customer should not be told "Out For Delivery" twice."""
        from orders.services import advance_status

        order = Order.objects.create(
            user=self.user, subtotal=Decimal("100"), total=Decimal("100"),
            status=OrderStatus.CONFIRMED,
        )
        advance_status(order, OrderStatus.OUT_FOR_DELIVERY)
        advance_status(order, OrderStatus.FAILED_DELIVERY)
        advance_status(order, OrderStatus.OUT_FOR_DELIVERY)

        out_for_delivery = Notification.objects.filter(
            user=self.user, title="Order Out For Delivery"
        )
        self.assertEqual(out_for_delivery.count(), 1)
        # …but the failure itself was still announced.
        self.assertTrue(
            Notification.objects.filter(
                user=self.user, title="Order Failed Delivery"
            ).exists()
        )
