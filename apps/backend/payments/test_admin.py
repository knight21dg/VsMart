"""Admin payments ledger: search/filter, the event trail, and reconciliation
totals that describe exactly the rows on screen."""
from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User

from .models import Payment, PaymentEvent


def _data(resp):
    body = resp.json()["data"]
    return body["results"] if isinstance(body, dict) and "results" in body else body


class AdminPaymentsTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919000000800", name="Boss", role="admin")
        self.alice = User.objects.create(phone="+919000000801", name="Alice", role="customer")
        self.bob = User.objects.create(phone="+919000000802", name="Bob", role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

        self.paid = Payment.objects.create(
            user=self.alice, purpose=Payment.Purpose.ORDER, amount=Decimal("500"),
            method=Payment.Method.UPI, gateway=Payment.Gateway.RAZORPAY,
            status=Payment.Status.SUCCESS, gateway_payment_id="pay_ABC123",
        )
        Payment.objects.create(
            user=self.bob, purpose=Payment.Purpose.REPAYMENT, amount=Decimal("300"),
            method=Payment.Method.CASH, gateway=Payment.Gateway.MANUAL,
            status=Payment.Status.SUCCESS,
        )
        Payment.objects.create(
            user=self.bob, purpose=Payment.Purpose.ORDER, amount=Decimal("900"),
            method=Payment.Method.CARD, status=Payment.Status.FAILED,
        )
        Payment.objects.create(
            user=self.alice, purpose=Payment.Purpose.ORDER, amount=Decimal("120"),
            method=Payment.Method.UPI, status=Payment.Status.PENDING,
        )
        Payment.objects.create(
            user=self.alice, purpose=Payment.Purpose.REFUND, amount=Decimal("50"),
            method=Payment.Method.UPI, status=Payment.Status.SUCCESS,
            refund_of=self.paid,
        )

    def _list(self, **params):
        return _data(self.client.get("/api/v1/admin/payments", params))

    def _summary(self, **params):
        return _data(self.client.get("/api/v1/admin/payments/summary", params))

    # ── access ──
    def test_customer_cannot_read_the_ledger(self):
        c = APIClient()
        c.force_authenticate(self.alice)
        self.assertEqual(c.get("/api/v1/admin/payments").status_code, 403)
        self.assertEqual(c.get("/api/v1/admin/payments/summary").status_code, 403)

    # ── filters ──
    def test_lists_every_users_payments(self):
        self.assertEqual(len(self._list()), 5)

    def test_filter_by_status_and_method(self):
        self.assertEqual(len(self._list(status="failed")), 1)
        self.assertEqual(len(self._list(method="cash")), 1)
        self.assertEqual(len(self._list(purpose="refund")), 1)

    def test_search_by_customer_and_gateway_reference(self):
        self.assertEqual({p["customerName"] for p in self._list(q="Alice")}, {"Alice"})
        self.assertEqual(len(self._list(q="9000000802")), 2)
        rows = self._list(q="pay_ABC123")
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["gatewayPaymentId"], "pay_ABC123")

    def test_date_range_end_bound_covers_the_whole_day(self):
        """A finance user filtering 'to <today>' means through 23:59, not 00:00."""
        today = timezone.localdate().isoformat()
        self.assertEqual(len(self._list(**{"from": today, "to": today})), 5)

    def test_date_range_excludes_outside_rows(self):
        old = timezone.now() - timedelta(days=30)
        Payment.objects.filter(id=self.paid.id).update(created_at=old)
        today = timezone.localdate().isoformat()
        self.assertEqual(len(self._list(**{"from": today, "to": today})), 4)

    def test_bad_date_is_ignored_not_fatal(self):
        self.assertEqual(len(self._list(**{"from": "not-a-date"})), 5)

    # ── summary ──
    def test_summary_counts_only_successful_money_as_collected(self):
        s = self._summary()
        # 500 (order) + 300 (repayment). Pending/failed are intents, not receipts,
        # and the refund is reported separately rather than netted off.
        self.assertEqual(Decimal(str(s["collected"])), Decimal("800"))
        self.assertEqual(Decimal(str(s["refunded"])), Decimal("50"))
        self.assertEqual(s["failedCount"], 1)
        self.assertEqual(s["total"], 5)

    def test_summary_respects_the_same_filters_as_the_list(self):
        s = self._summary(q="Alice")
        # Alice: 500 success order + 120 pending + 50 refund → collected 500.
        self.assertEqual(Decimal(str(s["collected"])), Decimal("500"))
        self.assertEqual(Decimal(str(s["refunded"])), Decimal("50"))
        self.assertEqual(s["total"], 3)

    def test_summary_breakdowns(self):
        s = self._summary()
        by_status = {r["status"]: r["count"] for r in s["byStatus"]}
        self.assertEqual(by_status["success"], 3)
        self.assertEqual(by_status["failed"], 1)
        self.assertEqual(by_status["pending"], 1)
        # byMethod counts successful money only.
        by_method = {r["method"]: r["count"] for r in s["byMethod"]}
        self.assertEqual(by_method["cash"], 1)
        self.assertNotIn("card", by_method)   # the only card payment failed

    # ── detail ──
    def test_detail_returns_the_event_trail_in_order(self):
        PaymentEvent.objects.create(payment=self.paid, status="created", note="init")
        PaymentEvent.objects.create(payment=self.paid, status="success",
                                    note="captured", gateway_ref="evt_1")
        data = _data(self.client.get(f"/api/v1/admin/payments/{self.paid.id}"))
        self.assertEqual([e["status"] for e in data["events"]], ["created", "success"])
        self.assertEqual(data["customerName"], "Alice")

    def test_detail_exposes_the_refund_chain(self):
        data = _data(self.client.get(f"/api/v1/admin/payments/{self.paid.id}"))
        self.assertEqual(len(data["refunds"]), 1)
        self.assertEqual(Decimal(str(data["refunds"][0]["amount"])), Decimal("50"))

    def test_ledger_is_read_only(self):
        """Refunds must go through payments.services so the ledger and the
        gateway stay in step — the admin ledger never mutates a Payment."""
        for method in ("post", "patch", "delete"):
            r = getattr(self.client, method)(
                f"/api/v1/admin/payments/{self.paid.id}", {}, format="json")
            self.assertIn(r.status_code, (403, 405))
