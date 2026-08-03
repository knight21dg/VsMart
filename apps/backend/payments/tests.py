"""Payment money-path integrity (Sprint 1 / C-05): one order → one payment record
→ settled exactly once, even under duplicate webhooks / callbacks / retries."""
from decimal import Decimal

from django.db import IntegrityError, transaction
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from accounts.models import User
from orders.models import Order, OrderStatus

from .models import Payment, PaymentWebhookEvent
from .services import finalize_payment, start_payment

WEBHOOK_URL = "/api/v1/webhooks/razorpay"


@override_settings(DEBUG=False)  # no dev auto-settle — keep payments deterministic
class PaymentIntegrityTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000000300", name="Pay")
        self.order = Order.objects.create(
            user=self.user, payment_method=Order.PaymentMethod.UPI,
            status=OrderStatus.PENDING, total=Decimal("100"),
        )

    def _payment(self, *, key="", order=None, gateway_order_id=""):
        return Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, order=order,
            amount=Decimal("100"), method=Payment.Method.UPI,
            gateway_order_id=gateway_order_id, idempotency_key=key,
            status=Payment.Status.PENDING,
        )

    # ── finalize is idempotent (duplicate webhook / callback both fire) ──
    def test_finalize_settles_exactly_once(self):
        p = self._payment(order=self.order, gateway_order_id="go_1")
        finalize_payment(p, success=True, gateway_payment_id="pay_1")
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, Order.PaymentStatus.PAID)

        # A second finalize (duplicate callback) must NOT re-settle or overwrite.
        finalize_payment(Payment.objects.get(pk=p.pk),
                         success=True, gateway_payment_id="pay_DUP")
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.SUCCESS)
        self.assertEqual(p.gateway_payment_id, "pay_1")

    # ── start_payment idempotency (retry with same key) ──
    def test_start_payment_idempotent_on_key(self):
        p1 = start_payment(self.user, purpose=Payment.Purpose.ORDER,
                           amount=Decimal("100"), method=Payment.Method.UPI,
                           order=self.order, idempotency_key="k1")
        p2 = start_payment(self.user, purpose=Payment.Purpose.ORDER,
                           amount=Decimal("100"), method=Payment.Method.UPI,
                           order=self.order, idempotency_key="k1")
        self.assertEqual(p1.id, p2.id)
        self.assertEqual(Payment.objects.filter(idempotency_key="k1").count(), 1)

    # ── DB constraint blocks the concurrent-race duplicate ──
    def test_duplicate_payment_key_rejected(self):
        self._payment(key="k2")
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                self._payment(key="k2")

    def test_blank_keys_not_constrained(self):
        self._payment(key="")
        self._payment(key="")
        self.assertEqual(Payment.objects.filter(idempotency_key="").count(), 2)

    # ── duplicate webhook → one settlement, one event ──
    def test_duplicate_webhook_finalizes_once(self):
        self._payment(order=self.order, gateway_order_id="go_X")
        client = APIClient()
        body = {"event_id": "evt_1", "gateway_order_id": "go_X",
                "status": "success", "gateway_payment_id": "pay_X"}
        r1 = client.post(WEBHOOK_URL, body, format="json")
        self.assertEqual(r1.status_code, 200)
        r2 = client.post(WEBHOOK_URL, body, format="json")
        self.assertEqual(r2.json()["data"]["status"], "already_processed")

        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, Order.PaymentStatus.PAID)
        self.assertEqual(
            PaymentWebhookEvent.objects.filter(event_id="evt_1").count(), 1)
        self.assertEqual(
            Payment.objects.filter(gateway_order_id="go_X",
                                   status=Payment.Status.SUCCESS).count(), 1)

    # ── a failed payment is recorded as failed, order stays unpaid ──
    def test_failed_webhook_marks_failed_not_paid(self):
        self._payment(order=self.order, gateway_order_id="go_F")
        client = APIClient()
        client.post(WEBHOOK_URL, {"event_id": "evt_F", "gateway_order_id": "go_F",
                                  "status": "failed"}, format="json")
        self.order.refresh_from_db()
        self.assertNotEqual(self.order.payment_status, Order.PaymentStatus.PAID)
        self.assertEqual(
            Payment.objects.get(gateway_order_id="go_F").status,
            Payment.Status.FAILED)


@override_settings(DEBUG=False)
class RefundAndAuditTests(TestCase):
    """Gateway refunds, refund Payment records, and the PaymentEvent audit trail."""

    def setUp(self):
        from .models import PaymentEvent
        self.PaymentEvent = PaymentEvent
        self.user = User.objects.create(phone="+919000000400", name="Refund")
        self.order = Order.objects.create(
            user=self.user, payment_method=Order.PaymentMethod.UPI,
            status=OrderStatus.CONFIRMED, payment_status=Order.PaymentStatus.PAID,
            total=Decimal("500"),
        )
        # A settled online order payment to refund against.
        self.paid = Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, order=self.order,
            amount=Decimal("500"), method=Payment.Method.UPI,
            gateway="razorpay", gateway_order_id="go_r", gateway_payment_id="pay_r",
            status=Payment.Status.SUCCESS,
        )

    def test_finalize_logs_payment_event(self):
        p = Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, order=self.order,
            amount=Decimal("500"), method=Payment.Method.UPI,
            status=Payment.Status.PENDING,
        )
        finalize_payment(p, success=True, gateway_payment_id="pay_ok")
        ev = self.PaymentEvent.objects.filter(payment=p, status=Payment.Status.SUCCESS)
        self.assertTrue(ev.exists())
        self.assertEqual(ev.first().gateway_ref, "pay_ok")

    def test_refund_payment_creates_refund_and_marks_original(self):
        from .services import refund_payment

        refund = refund_payment(self.order, Decimal("500"),
                                reason="Return RET1", idempotency_key="refund_RET1")
        self.assertIsNotNone(refund)
        self.assertEqual(refund.purpose, Payment.Purpose.REFUND)
        self.assertEqual(refund.status, Payment.Status.SUCCESS)
        self.assertTrue(refund.gateway_refund_id)      # mock gateway issued one
        self.assertEqual(refund.refund_of_id, self.paid.id)
        self.paid.refresh_from_db()
        self.assertEqual(self.paid.status, Payment.Status.REFUNDED)

    def test_refund_payment_idempotent(self):
        from .services import refund_payment

        r1 = refund_payment(self.order, Decimal("500"), idempotency_key="refund_RET2")
        r2 = refund_payment(self.order, Decimal("500"), idempotency_key="refund_RET2")
        self.assertEqual(r1.id, r2.id)
        self.assertEqual(
            Payment.objects.filter(order=self.order,
                                   purpose=Payment.Purpose.REFUND).count(), 1)

    def test_refund_zero_amount_noop(self):
        from .services import refund_payment
        self.assertIsNone(refund_payment(self.order, Decimal("0")))


class CashCollectionIdempotencyTests(TestCase):
    """A timed-out retry of POST /credit/cash-collection with a stable
    Idempotency-Key must NOT create a duplicate pickup request."""

    URL = "/api/v1/credit/cash-collection"

    def setUp(self):
        from .models import CashCollection
        self.CashCollection = CashCollection
        self.user = User.objects.create(phone="+919000000500", name="Cash")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def test_same_key_twice_creates_one(self):
        h = {"HTTP_IDEMPOTENCY_KEY": "cc_k1"}
        r1 = self.client.post(self.URL, {"amount": "250"}, format="json", **h)
        r2 = self.client.post(self.URL, {"amount": "250"}, format="json", **h)
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 200)  # retry returns the existing one
        self.assertEqual(
            self.CashCollection.objects.filter(user=self.user).count(), 1)

    def test_different_keys_create_two(self):
        self.client.post(self.URL, {"amount": "250"}, format="json",
                         HTTP_IDEMPOTENCY_KEY="cc_a")
        self.client.post(self.URL, {"amount": "250"}, format="json",
                         HTTP_IDEMPOTENCY_KEY="cc_b")
        self.assertEqual(
            self.CashCollection.objects.filter(user=self.user).count(), 2)

    def test_no_key_creates_legacy(self):
        r1 = self.client.post(self.URL, {"amount": "250"}, format="json")
        r2 = self.client.post(self.URL, {"amount": "250"}, format="json")
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 201)
        self.assertEqual(
            self.CashCollection.objects.filter(user=self.user).count(), 2)


class CashCollectionAutoAssignOnRequestTests(TestCase):
    """A raised pickup request used to just sit in REQUESTED until someone
    noticed and assigned it by hand — nothing ever picked it up on its own."""

    URL = "/api/v1/credit/cash-collection"

    def setUp(self):
        self.user = User.objects.create(phone="+919000000600", name="Cash")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def test_request_auto_assigns_to_a_free_agent(self):
        from accounts.models import AgentProfile

        agent = User.objects.create(phone="+919000000601", name="Rider", role="agent")
        AgentProfile.objects.create(user=agent, code="AG601", is_available=True)

        r = self.client.post(self.URL, {"amount": "250"}, format="json")
        self.assertEqual(r.status_code, 201)
        from .models import CashCollection

        c = CashCollection.objects.get(pk=r.json()["data"]["id"])
        self.assertEqual(c.agent_id, agent.id)
        self.assertEqual(c.status, "assigned")
        self.assertIsNotNone(c.assigned_at)

    def test_request_stays_unassigned_with_no_agents_available(self):
        r = self.client.post(self.URL, {"amount": "250"}, format="json")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.json()["data"]["status"], "requested")
