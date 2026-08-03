from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from core.app_errors import AppError
from credit.services import debit_purchase, ensure_account
from payments.models import CashCollection

from . import services


def _customer(phone, *, outstanding="1000"):
    u = User.objects.create(phone=phone, name="Cust", role="customer",
                            kyc_status="verified", credit_enabled=True)
    acct = ensure_account(u)
    debit_purchase(acct, Decimal(outstanding), note="seed")
    return u, acct


class CollectionLifecycleTests(TestCase):
    def setUp(self):
        self.agent = User.objects.create(phone="+919777700200", name="Agent C", role="agent")
        self.customer, self.acct = _customer("+919000000200", outstanding="1000")
        self.coll = CashCollection.objects.create(user=self.customer, amount=Decimal("1000"))

    def test_auto_assign(self):
        c = services.auto_assign(self.coll)
        self.assertEqual(c.agent_id, self.agent.id)
        self.assertEqual(c.status, "assigned")
        self.assertTrue(c.assignments.filter(action="auto_assigned").exists())

    def test_no_status_skipping(self):
        services.auto_assign(self.coll)
        with self.assertRaises(AppError) as ctx:
            services.en_route(self.coll, self.agent)  # ASSIGNED → EN_ROUTE not allowed
        self.assertEqual(ctx.exception.code, "INVALID_COLLECTION_TRANSITION")

    def test_otp_lockout(self):
        self._reach()
        services.request_collection_otp(self.coll, self.agent, Decimal("1000"))
        self.coll.refresh_from_db()
        for _ in range(2):
            with self.assertRaises(AppError) as ctx:
                services.verify_otp(self.coll, self.agent, "000000")
            self.assertEqual(ctx.exception.code, "INVALID_COLLECTION_OTP")
        with self.assertRaises(AppError) as ctx:
            services.verify_otp(self.coll, self.agent, "000000")
        self.assertEqual(ctx.exception.code, "COLLECTION_OTP_LOCKED")
        self.coll.refresh_from_db()
        self.assertTrue(self.coll.manual_verification_required)

    def test_collect_requires_otp(self):
        self._reach()
        with self.assertRaises(AppError) as ctx:
            services.collect(self.coll, self.agent)
        self.assertEqual(ctx.exception.code, "COLLECTION_OTP_REQUIRED")

    def test_partial_collection_posts_repayment(self):
        # OTP is bound to ₹400 → collect settles exactly that.
        self._reach_verified(Decimal("400"))
        services.collect(self.coll, self.agent)
        self.coll.refresh_from_db()
        self.acct.refresh_from_db()
        self.assertEqual(self.coll.status, "partially_collected")
        self.assertEqual(self.coll.collected_amount, Decimal("400.00"))
        self.assertEqual(self.coll.remaining, Decimal("600.00"))
        self.assertEqual(self.acct.outstanding, Decimal("600.00"))  # ledger updated
        self.assertTrue(self.coll.receipts.exists())

    def test_full_collection_closes_recovery(self):
        self._reach_verified()
        services.collect(self.coll, self.agent)  # full remaining
        self.coll.refresh_from_db()
        self.acct.refresh_from_db()
        self.assertEqual(self.coll.status, "collected")
        self.assertEqual(self.acct.outstanding, Decimal("0.00"))

    def test_over_collection_rejected_at_request(self):
        # Over-collection is caught when the amount-bound OTP is requested.
        self._reach()
        with self.assertRaises(AppError) as ctx:
            services.request_collection_otp(self.coll, self.agent, Decimal("5000"))
        self.assertEqual(ctx.exception.code, "COLLECTION_AMOUNT_INVALID")

    def test_sub_paise_amount_rejected_at_request(self):
        # Strict money precision — more than 2 decimal places is refused.
        self._reach()
        with self.assertRaises(AppError) as ctx:
            services.request_collection_otp(self.coll, self.agent, Decimal("100.999"))
        self.assertEqual(ctx.exception.code, "COLLECTION_AMOUNT_INVALID")

    def test_customer_sees_in_app_confirmation_otp(self):
        # The customer reads the OTP inside the app (never via SMS).
        self._reach()
        services.request_collection_otp(self.coll, self.agent, Decimal("700"))
        client = APIClient()
        client.force_authenticate(self.customer)
        r = client.get("/api/v1/collections/confirm")
        self.assertEqual(r.status_code, 200)
        pending = r.json()["data"]["pending"]
        self.assertEqual(pending["amount"], "700.00")
        self.assertEqual(len(pending["otp"]), 6)
        self.assertEqual(pending["agentName"], "Agent C")
        # once verified there's nothing left to confirm
        services.verify_otp(self.coll, self.agent, self.coll.collection_otp.code)
        r2 = client.get("/api/v1/collections/confirm")
        self.assertIsNone(r2.json()["data"]["pending"])

    def test_collect_settles_confirmed_otp_amount(self):
        # Agent can't collect a different figure than the customer confirmed.
        self._reach_verified(Decimal("300"))
        with self.assertRaises(AppError) as ctx:
            services.collect(self.coll, self.agent, amount=Decimal("900"))
        self.assertEqual(ctx.exception.code, "COLLECTION_AMOUNT_INVALID")
        # Collecting with no amount settles exactly the confirmed ₹300.
        services.collect(self.coll, self.agent)
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.collected_amount, Decimal("300.00"))
        self.assertEqual(self.coll.status, "partially_collected")

    def test_dispute(self):
        self._reach()
        services.dispute(self.coll, self.agent, note="Customer contests amount")
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.status, "disputed")
        self.assertTrue(self.coll.attempts.filter(outcome="disputed").exists())

    def test_failed_visit(self):
        services.auto_assign(self.coll)
        services.accept(self.coll, self.agent)
        services.en_route(self.coll, self.agent)
        services.fail(self.coll, self.agent, reason_code="CUSTOMER_NOT_AVAILABLE")
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.status, "failed")

    def _reach(self):
        services.auto_assign(self.coll)
        services.accept(self.coll, self.agent)
        services.en_route(self.coll, self.agent)
        services.reach(self.coll, self.agent)
        self.coll.refresh_from_db()

    def _reach_verified(self, amount=None):
        """Reach → request an amount-bound OTP → verify it. Defaults to the full
        remaining balance."""
        self._reach()
        services.request_collection_otp(
            self.coll, self.agent, amount or self.coll.remaining)
        self.coll.refresh_from_db()
        services.verify_otp(self.coll, self.agent, self.coll.collection_otp.code)
        self.coll.refresh_from_db()


class CollectionDunningTests(TestCase):
    def test_aging_and_dunning_escalation(self):
        cust, _ = _customer("+919000000201", outstanding="500")
        coll = CashCollection.objects.create(user=cust, amount=Decimal("500"))
        # Backdate 70 days → 61-90 bucket → escalates.
        CashCollection.objects.filter(pk=coll.pk).update(
            created_at=timezone.now() - timezone.timedelta(days=70))
        coll.refresh_from_db()
        self.assertEqual(services.aging_bucket(coll), "61-90")
        self.assertEqual(services.run_dunning(), 1)
        coll.refresh_from_db()
        self.assertTrue(coll.escalated)
        self.assertTrue(coll.is_priority)


class CollectionAdminApiTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919888800200", name="Admin", role="admin")
        self.agent = User.objects.create(phone="+919777700201", name="Agent D", role="agent")
        self.customer, _ = _customer("+919000000202", outstanding="800")
        self.coll = CashCollection.objects.create(user=self.customer, amount=Decimal("800"))
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_auto_assign_endpoint(self):
        r = self.client.post("/api/v1/admin/collections/auto-assign", {}, format="json")
        self.assertEqual(r.status_code, 200)
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.status, "assigned")

    def test_command_center(self):
        r = self.client.get("/api/v1/admin/collections/command-center")
        self.assertEqual(r.status_code, 200)
        body = r.json()["data"]
        self.assertIn("kpis", body)
        self.assertIn("aging", body)


class CollectionLocationSerializerTests(TestCase):
    """The agent-facing collection payload exposes the customer's location (their
    default address) so the app can map the visit — Z-maps agent parity."""

    def test_exposes_customer_default_address_location(self):
        from addresses.models import Address

        from .serializers import CollectionTaskSerializer

        cust, _ = _customer("+919000000750", outstanding="500")
        Address.objects.create(
            user=cust, name="Cust", phone=cust.phone, line1="12 MG Road",
            area="Indiranagar", city="Bengaluru",
            latitude=Decimal("12.971600"), longitude=Decimal("77.594600"),
            is_default=True,
        )
        coll = CashCollection.objects.create(user=cust, amount=Decimal("500"))
        data = CollectionTaskSerializer(coll).data
        self.assertAlmostEqual(data["customer_lat"], 12.9716, places=4)
        self.assertAlmostEqual(data["customer_lng"], 77.5946, places=4)
        self.assertIn("MG Road", data["address"])

    def test_no_address_yields_null_location(self):
        from .serializers import CollectionTaskSerializer

        cust, _ = _customer("+919000000751", outstanding="500")
        coll = CashCollection.objects.create(user=cust, amount=Decimal("500"))
        data = CollectionTaskSerializer(coll).data
        self.assertIsNone(data["customer_lat"])
        self.assertIsNone(data["customer_lng"])
        self.assertEqual(data["address"], "")


class AdminCollectionListPaginationTests(TestCase):
    """The recovery queue used to return a hard `[:300]` slice with no offset. The
    unseen tail is money nobody is chasing, so silent truncation is a money bug."""

    def setUp(self):
        self.admin = User.objects.create(
            phone="+919888888210", name="Admin", role="admin"
        )
        customer, _ = _customer("+919000000210", outstanding="1000")
        for _ in range(25):
            CashCollection.objects.create(user=customer, amount=Decimal("100"))
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_envelope_carries_pagination_meta(self):
        body = self.client.get("/api/v1/admin/collections").json()
        self.assertEqual(body["meta"]["total"], 25)
        self.assertEqual(body["meta"]["page"], 1)
        # `data` stays a bare row array, so existing callers keep working.
        self.assertIsInstance(body["data"], list)

    def test_default_page_size_preserves_the_old_visible_rows(self):
        # The console's collections page has no pager yet; it must not start
        # showing fewer rows than the 300 it did before pagination landed.
        body = self.client.get("/api/v1/admin/collections").json()
        self.assertEqual(len(body["data"]), 25)
        self.assertEqual(body["meta"]["totalPages"], 1)

    def test_every_collection_is_reachable_by_paging(self):
        seen, page = set(), 1
        while True:
            body = self.client.get(
                "/api/v1/admin/collections", {"page": page, "page_size": 10}
            ).json()
            seen.update(r["id"] for r in body["data"])
            self.assertLessEqual(len(body["data"]), 10)
            if page >= body["meta"]["totalPages"]:
                break
            page += 1
        self.assertEqual(page, 3)
        self.assertEqual(len(seen), 25)

    def test_legacy_limit_still_returns_a_bare_list(self):
        body = self.client.get("/api/v1/admin/collections", {"limit": 5}).json()
        self.assertEqual(len(body["data"]), 5)
        self.assertNotIn("meta", body)
