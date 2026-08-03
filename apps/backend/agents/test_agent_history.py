"""Agent task history: the complement of the three active agent queues.

The invariants worth defending here are (a) an agent only ever sees their OWN
closed work, (b) a task appears in exactly one of {active queue, history} and
never both, and (c) counts/money totals describe the whole filtered set rather
than the page being viewed.
"""
from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from delivery.models import DeliveryTask
from orders.models import Order
from payments.models import CashCollection
from verification.models import VerificationTask

URL = "/api/v1/agents/history"


class AgentHistoryTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.agent = User.objects.create(
            phone="+919100000021", name="Ravi", role="agent", is_active=True)
        self.other = User.objects.create(
            phone="+919100000022", name="Sita", role="agent", is_active=True)
        self.customer = User.objects.create(
            phone="+919111111121", name="Anil", role="customer")
        self.client.force_authenticate(self.agent)

    # helpers ---------------------------------------------------------------

    def _order(self, code, total="250.00"):
        return Order.objects.create(
            user=self.customer, code=code, total=Decimal(total),
            address_snapshot={"name": "Anil", "formatted": "12 MG Road"},
        )

    def _delivery(self, code, status, agent=None):
        return DeliveryTask.objects.create(
            order=self._order(code), agent=agent or self.agent, status=status,
            delivered_at=timezone.now() if status == "delivered" else None,
        )

    def _collection(self, status, amount="500.00", collected="500.00", agent=None):
        return CashCollection.objects.create(
            user=self.customer, agent=agent or self.agent,
            amount=Decimal(amount), collected_amount=Decimal(collected),
            status=status,
            collected_at=timezone.now() if status != "cancelled" else None,
        )

    def _verification(self, status, agent=None):
        return VerificationTask.objects.create(
            customer=self.customer, agent=agent or self.agent,
            type="kyc", status=status, submitted_at=timezone.now(),
        )

    def _get(self, **params):
        return self.client.get(URL, params)

    # scoping ---------------------------------------------------------------

    def test_returns_only_closed_work(self):
        """Active tasks stay in the queue view; only terminal ones land here."""
        self._delivery("ORD-A", "delivered")
        self._delivery("ORD-B", "out_for_delivery")   # still active
        body = self._get().json()["data"]
        refs = [r["reference"] for r in body["items"]]
        self.assertEqual(refs, ["ORD-A"])
        self.assertEqual(body["counts"]["delivery"], 1)

    def test_does_not_leak_another_agents_history(self):
        self._delivery("ORD-MINE", "delivered")
        self._delivery("ORD-THEIRS", "delivered", agent=self.other)
        refs = [r["reference"] for r in self._get().json()["data"]["items"]]
        self.assertEqual(refs, ["ORD-MINE"])

    def test_requires_an_agent(self):
        self.client.force_authenticate(self.customer)
        self.assertEqual(self._get().status_code, 403)

    # merging + outcomes ----------------------------------------------------

    def test_merges_all_three_kinds(self):
        self._delivery("ORD-A", "delivered")
        self._collection("collected")
        self._verification("approved")
        body = self._get().json()["data"]
        self.assertEqual(body["total"], 3)
        self.assertEqual(
            {r["type"] for r in body["items"]},
            {"delivery", "collection", "verification"},
        )

    def test_type_filter_narrows_to_one_kind(self):
        self._delivery("ORD-A", "delivered")
        self._collection("collected")
        body = self._get(type="collection").json()["data"]
        self.assertEqual([r["type"] for r in body["items"]], ["collection"])
        self.assertNotIn("delivery", body["counts"])

    def test_partial_collection_is_flagged_partial(self):
        self._collection("partially_collected", amount="500.00", collected="200.00")
        row = self._get().json()["data"]["items"][0]
        self.assertEqual(row["outcome"], "partial")
        self.assertEqual(row["amount"], "200.00")
        self.assertEqual(row["amountDue"], "500.00")

    def test_rejected_delivery_is_flagged_failed(self):
        self._delivery("ORD-R", "rejected")
        self.assertEqual(self._get().json()["data"]["items"][0]["outcome"], "failed")

    def test_row_without_completion_stamp_still_sorts(self):
        """A cancelled collection never gets a collected_at — it must fall back
        to updated_at rather than blowing up on None."""
        self._collection("cancelled", collected="0.00")
        body = self._get().json()["data"]
        self.assertEqual(len(body["items"]), 1)
        self.assertTrue(body["items"][0]["closedAt"])

    # totals ----------------------------------------------------------------

    def test_collected_total_covers_whole_set_not_page(self):
        for _ in range(3):
            self._collection("collected", collected="100.00")
        body = self._get(limit=1).json()["data"]
        self.assertEqual(len(body["items"]), 1)      # page is one row
        self.assertEqual(body["collectedTotal"], "300.00")   # total is all three
        self.assertEqual(body["counts"]["collection"], 3)
        self.assertTrue(body["hasMore"])

    def test_pagination_walks_without_repeating(self):
        for i in range(5):
            self._delivery(f"ORD-{i}", "delivered")
        first = self._get(limit=2, offset=0).json()["data"]
        second = self._get(limit=2, offset=2).json()["data"]
        self.assertEqual(len(first["items"]), 2)
        self.assertEqual(len(second["items"]), 2)
        self.assertFalse(
            {r["id"] for r in first["items"]} & {r["id"] for r in second["items"]}
        )
        self.assertTrue(second["hasMore"])
        self.assertFalse(self._get(limit=2, offset=4).json()["data"]["hasMore"])

    # date window -----------------------------------------------------------

    def test_date_window_excludes_older_rows(self):
        old = self._delivery("ORD-OLD", "delivered")
        DeliveryTask.objects.filter(pk=old.pk).update(
            created_at=timezone.now() - timedelta(days=10))
        self._delivery("ORD-NEW", "delivered")
        today = timezone.localtime().date().isoformat()
        refs = [r["reference"] for r in self._get(**{"from": today}).json()["data"]["items"]]
        self.assertEqual(refs, ["ORD-NEW"])

    # validation ------------------------------------------------------------

    def test_rejects_bad_type(self):
        r = self._get(type="banana")
        self.assertEqual(r.json()["code"], "VALIDATION_ERROR")

    def test_rejects_bad_date(self):
        r = self._get(**{"from": "21-07-2026"})
        self.assertEqual(r.json()["code"], "VALIDATION_ERROR")

    def test_rejects_inverted_window(self):
        r = self._get(**{"from": "2026-07-20", "to": "2026-07-01"})
        self.assertEqual(r.json()["code"], "VALIDATION_ERROR")

    def test_rejects_oversized_limit(self):
        self.assertEqual(self._get(limit=5000).json()["code"], "VALIDATION_ERROR")
