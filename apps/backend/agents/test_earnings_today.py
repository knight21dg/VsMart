"""`GET /agents/earnings` must separate TODAY from LIFETIME.

The agent dashboard's tile is labelled "Earned today" but the endpoint only ever
returned lifetime figures, so the tile rendered a large number for a rider who
had earned nothing that day — and it never moved when they completed a drop.
"""
from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from agents.models import AgentIncentive
from delivery.models import DeliveryEarnings, DeliveryTask
from orders.models import Order
from payments.models import CashCollection

URL = "/api/v1/agents/earnings"


class EarningsTodayTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.agent = User.objects.create(
            phone="+919100000031", name="Ravi", role="agent", is_active=True)
        self.customer = User.objects.create(
            phone="+919100000032", name="Cust", role="customer")
        self.client.force_authenticate(self.agent)

    def _earning(self, amount, *, days_ago=0):
        order = Order.objects.create(user=self.customer, total=Decimal("100"))
        task = DeliveryTask.objects.create(order=order, agent=self.agent,
                                           status="delivered")
        e = DeliveryEarnings.objects.create(
            task=task, agent=self.agent, base=Decimal(amount),
            total=Decimal(amount), released=True, released_at=timezone.now())
        if days_ago:
            DeliveryEarnings.objects.filter(pk=e.pk).update(
                released_at=timezone.now() - timedelta(days=days_ago))
        return e

    def _get(self):
        r = self.client.get(URL)
        self.assertEqual(r.status_code, 200, r.data)
        return r.data

    def test_today_excludes_earlier_days(self):
        self._earning("50")                  # today
        self._earning("450", days_ago=5)     # last week

        d = self._get()
        self.assertEqual(Decimal(d["total"]), Decimal("500.00"))
        self.assertEqual(Decimal(d["today_total"]), Decimal("50.00"))
        self.assertEqual(d["today_deliveries"], 1)

    def test_today_is_zero_when_nothing_earned_today(self):
        """The exact bug: lifetime money, but nothing earned today."""
        self._earning("900", days_ago=2)

        d = self._get()
        self.assertEqual(Decimal(d["total"]), Decimal("900.00"))
        self.assertEqual(Decimal(d["today_total"]), Decimal("0.00"))
        self.assertEqual(d["today_deliveries"], 0)

    def test_lifetime_fields_are_unchanged(self):
        """The Earnings screen reads base/incentives/total — those stay lifetime."""
        self._earning("100", days_ago=10)
        self._earning("25")
        AgentIncentive.objects.create(
            agent=self.agent, amount=Decimal("75"), reason="weekend push")

        d = self._get()
        self.assertEqual(Decimal(d["base"]), Decimal("125.00"))
        self.assertEqual(Decimal(d["incentives"]), Decimal("75.00"))
        self.assertEqual(Decimal(d["total"]), Decimal("200.00"))

    def test_incentives_are_day_scoped_too(self):
        old = AgentIncentive.objects.create(
            agent=self.agent, amount=Decimal("500"), reason="last month")
        AgentIncentive.objects.filter(pk=old.pk).update(
            created_at=timezone.now() - timedelta(days=30))
        AgentIncentive.objects.create(
            agent=self.agent, amount=Decimal("60"), reason="today")

        d = self._get()
        self.assertEqual(Decimal(d["incentives"]), Decimal("560.00"))
        self.assertEqual(Decimal(d["today_incentives"]), Decimal("60.00"))
        self.assertEqual(Decimal(d["today_total"]), Decimal("60.00"))

    def test_collections_collected_today_count_toward_today(self):
        CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("1000"),
            collected_amount=Decimal("1000"), status="collected",
            collected_at=timezone.now())
        old = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("2000"),
            collected_amount=Decimal("2000"), status="collected",
            collected_at=timezone.now())
        CashCollection.objects.filter(pk=old.pk).update(
            collected_at=timezone.now() - timedelta(days=3))

        d = self._get()
        self.assertEqual(d["today_collections"], 1)
        # Two collections lifetime at the per-collection rate, one of them today.
        self.assertEqual(Decimal(d["today_base"]), Decimal(d["today_total"]))
        self.assertGreater(Decimal(d["base"]), Decimal(d["today_base"]))

    def test_another_agents_earnings_are_never_counted(self):
        other = User.objects.create(
            phone="+919100000033", name="Sita", role="agent", is_active=True)
        order = Order.objects.create(user=self.customer, total=Decimal("100"))
        task = DeliveryTask.objects.create(order=order, agent=other,
                                           status="delivered")
        DeliveryEarnings.objects.create(
            task=task, agent=other, base=Decimal("999"), total=Decimal("999"),
            released=True, released_at=timezone.now())

        d = self._get()
        self.assertEqual(Decimal(d["total"]), Decimal("0.00"))
        self.assertEqual(Decimal(d["today_total"]), Decimal("0.00"))
