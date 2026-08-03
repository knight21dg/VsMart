from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from credit.models import CreditAccount
from orders.models import Order, OrderItem
from returns.models import ReturnItem, ReturnRequest


class AdminReturnsTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919888888080", name="Admin", role="admin")
        self.customer = User.objects.create(phone="+919000000080", name="Cust", role="customer")
        self.account = CreditAccount.objects.create(
            user=self.customer, credit_limit=Decimal("10000"), outstanding=Decimal("500"),
        )
        self.order = Order.objects.create(
            user=self.customer, payment_method=Order.PaymentMethod.CREDIT,
            status="delivered", total=Decimal("500"), credit_used=Decimal("500"),
        )
        OrderItem.objects.create(order=self.order, product=None, name="Rice", quantity=2, price=Decimal("250"), mrp=Decimal("300"))
        self.ret = ReturnRequest.objects.create(
            user=self.customer, order=self.order, reason="Damaged",
            refund_amount=Decimal("500"),
        )
        ReturnItem.objects.create(return_request=self.ret, product_name="Rice", quantity=2, amount=Decimal("500"))
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def _status(self, status):
        return self.client.post(f"/api/v1/admin/returns/{self.ret.code}/status", {"status": status}, format="json")

    def test_list_and_detail(self):
        r = self.client.get("/api/v1/admin/returns")
        self.assertTrue(any(x["code"] == self.ret.code for x in r.json()["data"]))
        d = self.client.get(f"/api/v1/admin/returns/{self.ret.code}")
        self.assertEqual(d.json()["data"]["status"], "requested")
        self.assertEqual(len(d.json()["data"]["items"]), 1)

    def test_full_workflow_refunds_credit(self):
        self.assertEqual(self._status("approved").status_code, 200)
        self.assertEqual(self._status("picked").status_code, 200)
        self.assertEqual(self._status("refunded").status_code, 200)
        self.ret.refresh_from_db()
        self.order.refresh_from_db()
        self.account.refresh_from_db()
        self.assertEqual(self.ret.status, "refunded")
        self.assertIsNotNone(self.ret.resolved_at)
        self.assertEqual(self.order.payment_status, "refunded")
        self.assertEqual(self.order.status, "returned")  # full return (2 of 2 units)
        # Credit outstanding reversed by the refund.
        self.assertEqual(self.account.outstanding, Decimal("0"))

    def test_invalid_transition_rejected(self):
        # requested → refunded skips collecting the goods entirely.
        self.assertEqual(self._status("refunded").status_code, 400)

    def test_requested_to_picked_allowed_for_agent_pickup(self):
        # The field agent inspects and collects in one step at the customer's
        # door, so `requested → picked` is a valid jump (see pickup_services).
        self.assertEqual(self._status("picked").status_code, 200)
        self.ret.refresh_from_db()
        self.assertEqual(self.ret.status, "picked")

    def test_reject_sets_resolved(self):
        self.assertEqual(self._status("rejected").status_code, 200)
        self.ret.refresh_from_db()
        self.assertEqual(self.ret.status, "rejected")
        self.assertIsNotNone(self.ret.resolved_at)

    def test_double_refund_is_rejected_no_double_reversal(self):
        from credit.models import CreditLedgerEntry

        self._status("approved")
        self.assertEqual(self._status("refunded").status_code, 200)
        # A second refund (double-click / retry / concurrent admin) is rejected.
        self.assertEqual(self._status("refunded").status_code, 400)
        # Exactly ONE credit refund posted — never reversed twice.
        self.assertEqual(
            CreditLedgerEntry.objects.filter(
                order=self.order, type=CreditLedgerEntry.Type.REFUND).count(),
            1,
        )
        self.account.refresh_from_db()
        self.assertEqual(self.account.outstanding, Decimal("0"))

    def test_refund_posts_credit_refund_ledger_entry(self):
        from credit.models import CreditLedgerEntry

        self._status("approved")
        self._status("refunded")
        # Reversed via a NEW append-only refund entry, not by editing the purchase.
        self.assertTrue(CreditLedgerEntry.objects.filter(
            order=self.order, type=CreditLedgerEntry.Type.REFUND).exists())


class AdminReturnsPaginationTests(TestCase):
    """The admin returns queue used to return a hard `[:200]` slice with no offset,
    so return 201 onwards was unreachable with nothing signalling the cut-off."""

    def setUp(self):
        self.admin = User.objects.create(
            phone="+919888888081", name="Admin", role="admin"
        )
        self.customer = User.objects.create(
            phone="+919000000081", name="Cust", role="customer"
        )
        self.order = Order.objects.create(
            user=self.customer, payment_method=Order.PaymentMethod.CREDIT,
            status="delivered", total=Decimal("2500"),
        )
        for i in range(25):
            ReturnRequest.objects.create(
                user=self.customer, order=self.order, reason=f"Damaged {i}",
                refund_amount=Decimal("100"),
            )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_envelope_carries_pagination_meta(self):
        body = self.client.get("/api/v1/admin/returns").json()
        self.assertEqual(body["meta"]["total"], 25)
        self.assertEqual(body["meta"]["page"], 1)
        # `data` stays a bare row array, so existing callers keep working.
        self.assertIsInstance(body["data"], list)

    def test_default_page_size_preserves_the_old_visible_rows(self):
        # The console's returns page has no pager yet; it must not start showing
        # fewer rows than the 200 it did before pagination landed.
        body = self.client.get("/api/v1/admin/returns").json()
        self.assertEqual(len(body["data"]), 25)
        self.assertEqual(body["meta"]["totalPages"], 1)

    def test_every_return_is_reachable_by_paging(self):
        seen, page = set(), 1
        while True:
            body = self.client.get(
                "/api/v1/admin/returns", {"page": page, "page_size": 10}
            ).json()
            seen.update(r["code"] for r in body["data"])
            self.assertLessEqual(len(body["data"]), 10)
            if page >= body["meta"]["totalPages"]:
                break
            page += 1
        self.assertEqual(page, 3)
        self.assertEqual(len(seen), 25)

    def test_legacy_limit_still_returns_a_bare_list(self):
        body = self.client.get("/api/v1/admin/returns", {"limit": 5}).json()
        self.assertEqual(len(body["data"]), 5)
        self.assertNotIn("meta", body)
