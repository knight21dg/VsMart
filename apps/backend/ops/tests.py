from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import AuditLog, User


class AuditLogListTests(TestCase):
    """The audit trail used to return a hard `[:200]` slice with no pagination, so
    anything older than the most recent 200 entries was unreachable — and the
    "Filter by actor…" box matched only `actor__phone`, while the row rendered
    `actor.name`, so typing the name you could see always returned zero rows."""

    def setUp(self):
        self.admin = User.objects.create(
            phone="+919888888080", name="Admin", role="admin"
        )
        self.actor = User.objects.create(
            phone="+919000000811", name="Priya Sharma", role="agent"
        )
        self.other = User.objects.create(
            phone="+919000000812", name="Rahul Verma", role="agent"
        )
        for i in range(12):
            AuditLog.objects.create(actor=self.actor, action=f"credit.freeze.{i}")
        for i in range(3):
            AuditLog.objects.create(actor=self.other, action=f"order.cancel.{i}")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_envelope_carries_cursor_meta(self):
        r = self.client.get("/api/v1/audit/logs")
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertIsInstance(body["data"], list)
        self.assertIn("nextCursor", body["meta"])
        self.assertIn("previousCursor", body["meta"])

    def test_pages_through_every_entry(self):
        seen, url = set(), "/api/v1/audit/logs?page_size=5"
        for _ in range(10):  # guard against a cursor loop
            body = self.client.get(url).json()
            seen.update(row["id"] for row in body["data"])
            nxt = body["meta"]["nextCursor"]
            if not nxt:
                break
            url = nxt
        self.assertEqual(len(seen), 15)

    def test_actor_filter_matches_name(self):
        body = self.client.get("/api/v1/audit/logs", {"actor": "Priya"}).json()
        self.assertTrue(body["data"])
        self.assertTrue(all(r["actor"] == "Priya Sharma" for r in body["data"]))

    def test_actor_filter_still_matches_phone(self):
        body = self.client.get("/api/v1/audit/logs", {"actor": "9000000812"}).json()
        self.assertTrue(body["data"])
        self.assertTrue(all(r["actor"] == "Rahul Verma" for r in body["data"]))

    def test_actor_filter_excludes_non_matches(self):
        body = self.client.get("/api/v1/audit/logs", {"actor": "Priya"}).json()
        self.assertFalse(any(r["actor"] == "Rahul Verma" for r in body["data"]))
