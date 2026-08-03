"""Money-integrity guards on the payment path.

Every test here corresponds to a way the system could previously be made to take
the wrong amount of money, or to believe money had arrived when it had not.
"""
from datetime import date
from decimal import Decimal
from unittest import mock

from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from accounts.models import Role, User
from core.app_errors import AppError
from credit.models import CreditAccount, Statement
from orders.models import Order
from payments.gateway import MockGateway, get_gateway
from payments.models import Payment, PaymentWebhookEvent
from payments.services import finalize_payment, start_payment
from payments.views import parse_webhook


def _user(phone="+919600001111"):
    return User.objects.create(phone=phone, name="Cust", role=Role.CUSTOMER)


def _client(user):
    c = APIClient()
    c.force_authenticate(user=user)
    return c


class OrderPaymentAmountTests(TestCase):
    """The amount charged for an order is the ORDER's, never the client's."""

    def setUp(self):
        self.user = _user()
        self.client_ = _client(self.user)
        self.order = Order.objects.create(
            user=self.user, subtotal=Decimal("5000"), total=Decimal("5000")
        )

    def test_client_cannot_choose_a_smaller_amount(self):
        # Previously: this created a real ₹1 gateway order for a ₹5,000 basket and
        # finalize_payment then marked the order fully PAID.
        r = self.client_.post(
            "/api/v1/payments",
            {"purpose": "order", "order_id": self.order.code, "amount": "1.00",
             "method": "upi"},
            format="json",
        )
        self.assertIn(r.status_code, (200, 201), r.content[:300])
        payment = Payment.objects.get(order=self.order)
        self.assertEqual(payment.amount, Decimal("5000"))

    def test_zero_and_negative_amounts_are_rejected_outright(self):
        for bad in ("0", "-100"):
            r = self.client_.post(
                "/api/v1/payments",
                {"purpose": "order", "order_id": self.order.code, "amount": bad,
                 "method": "upi"},
                format="json",
            )
            self.assertEqual(r.status_code, 400, f"{bad} -> {r.status_code}")

    def test_paying_an_already_paid_order_is_refused(self):
        self.order.payment_status = Order.PaymentStatus.PAID
        self.order.save(update_fields=["payment_status"])
        r = self.client_.post(
            "/api/v1/payments",
            {"purpose": "order", "order_id": self.order.code, "amount": "5000",
             "method": "upi"},
            format="json",
        )
        self.assertEqual(r.status_code, 409, r.content[:300])

    def test_another_users_order_is_not_payable(self):
        stranger = _client(_user("+919600002222"))
        r = stranger.post(
            "/api/v1/payments",
            {"purpose": "order", "order_id": self.order.code, "amount": "5000",
             "method": "upi"},
            format="json",
        )
        self.assertEqual(r.status_code, 404)


class SettlementAmountTests(TestCase):
    """A short capture must never mark an order fully paid."""

    def setUp(self):
        self.user = _user("+919600003333")
        self.order = Order.objects.create(
            user=self.user, subtotal=Decimal("5000"), total=Decimal("5000")
        )
        self.payment = Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, amount=Decimal("5000"),
            method=Payment.Method.UPI, order=self.order, gateway="razorpay",
            status=Payment.Status.PENDING, gateway_order_id="order_live_1",
        )

    def test_short_settlement_is_rejected_and_leaves_the_order_unpaid(self):
        with self.assertRaises(AppError):
            finalize_payment(self.payment, success=True, gateway_payment_id="pay_1",
                             settled_amount=Decimal("1"))
        self.payment.refresh_from_db()
        self.order.refresh_from_db()
        # PENDING, not FAILED: real money may have moved and needs reconciling.
        self.assertEqual(self.payment.status, Payment.Status.PENDING)
        self.assertNotEqual(self.order.payment_status, Order.PaymentStatus.PAID)

    def test_exact_settlement_marks_the_order_paid(self):
        finalize_payment(self.payment, success=True, gateway_payment_id="pay_1",
                         settled_amount=Decimal("5000"))
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, Order.PaymentStatus.PAID)
        self.assertEqual(self.order.status, "confirmed")

    def test_settlement_without_a_reported_amount_still_works(self):
        # The dev auto-settle path has no gateway amount to assert against.
        finalize_payment(self.payment, success=True, gateway_payment_id="pay_1")
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, Order.PaymentStatus.PAID)


class WebhookParsingTests(TestCase):
    """The handler must understand what Razorpay actually sends."""

    def test_real_razorpay_shape_is_parsed(self):
        headers = {"X-Razorpay-Event-Id": "evt_abc"}
        body = {
            "event": "payment.captured",
            "payload": {"payment": {"entity": {
                "id": "pay_xyz", "order_id": "order_xyz",
                "status": "captured", "amount": 500000,
            }}},
        }
        event_id, order_id, payment_id, ok, amount = parse_webhook(headers, body)
        self.assertEqual(event_id, "evt_abc")
        self.assertEqual(order_id, "order_xyz")
        self.assertEqual(payment_id, "pay_xyz")
        self.assertTrue(ok)
        self.assertEqual(amount, Decimal("5000"))  # paise → rupees

    def test_flat_mock_shape_still_parses(self):
        event_id, order_id, payment_id, ok, amount = parse_webhook(
            {},
            {"event_id": "e1", "gateway_order_id": "o1", "status": "success",
             "gateway_payment_id": "p1"},
        )
        self.assertEqual((event_id, order_id, payment_id, ok), ("e1", "o1", "p1", True))
        self.assertIsNone(amount)

    def test_a_failed_event_is_not_treated_as_success(self):
        _, _, _, ok, _ = parse_webhook(
            {"X-Razorpay-Event-Id": "evt_f"},
            {"event": "payment.failed",
             "payload": {"payment": {"entity": {"id": "p", "order_id": "o",
                                                "status": "failed"}}}},
        )
        self.assertFalse(ok)

    @override_settings(DEBUG=True)
    def test_unidentifiable_event_is_rejected_not_stored_under_a_blank_id(self):
        # event_id is unique: storing one blank event would make every later
        # webhook answer "already_processed" forever.
        r = APIClient().post("/api/v1/webhooks/razorpay", {"foo": "bar"}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertFalse(PaymentWebhookEvent.objects.filter(event_id="").exists())

    @override_settings(DEBUG=True)
    def test_blank_gateway_order_id_does_not_match_a_cash_payment(self):
        user = _user("+919600004444")
        cash = Payment.objects.create(
            user=user, purpose=Payment.Purpose.ORDER, amount=Decimal("100"),
            method=Payment.Method.CASH, gateway="manual",
            status=Payment.Status.PENDING,  # no gateway_order_id
        )
        r = APIClient().post(
            "/api/v1/webhooks/razorpay",
            {"event_id": "evt_1", "status": "failed"},
            format="json",
        )
        self.assertEqual(r.status_code, 200)
        cash.refresh_from_db()
        self.assertEqual(cash.status, Payment.Status.PENDING)


class GatewaySelectionTests(TestCase):
    """Configured keys must never silently degrade to a trusting mock."""

    def test_no_keys_gives_the_mock(self):
        self.assertIsInstance(get_gateway(), MockGateway)

    def test_configured_keys_that_fail_to_construct_raise(self):
        with mock.patch("payments.gateway.runtime.cfg", side_effect=lambda k: "set"), \
             mock.patch("payments.gateway.RazorpayGateway.__init__",
                        side_effect=ImportError("no razorpay sdk")):
            with self.assertRaises(ImportError):
                get_gateway()

    @override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=False)
    def test_mock_does_not_trust_signatures_in_production(self):
        # prod.py sets this False. Without the guard, the unauthenticated webhook
        # endpoint would accept anything and mark arbitrary orders paid.
        gw = MockGateway()
        self.assertFalse(gw.verify_webhook(b"{}", "anything"))
        self.assertFalse(gw.verify_checkout_signature("o", "p", "s"))

    @override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=None)
    def test_an_undeclared_flag_is_treated_as_production(self):
        # A settings module that never opts in must not get blanket trust.
        self.assertFalse(MockGateway().verify_webhook(b"{}", "x"))

    @override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=True)
    def test_mock_trusts_in_dev_so_keyless_flows_run(self):
        gw = MockGateway()
        self.assertTrue(gw.verify_webhook(b"{}", "anything"))


class ConfirmPaymentTests(TestCase):
    """The app's checkout callback is only trusted once its signature verifies."""

    def setUp(self):
        self.user = _user("+919600006666")
        self.client_ = _client(self.user)
        self.order = Order.objects.create(
            user=self.user, subtotal=Decimal("500"), total=Decimal("500")
        )
        self.payment = Payment.objects.create(
            user=self.user, purpose=Payment.Purpose.ORDER, amount=Decimal("500"),
            method=Payment.Method.UPI, order=self.order, gateway="manual",
            status=Payment.Status.PENDING, gateway_order_id="order_ok",
        )

    def _confirm(self, **over):
        body = {
            "razorpay_order_id": "order_ok",
            "razorpay_payment_id": "pay_ok",
            "razorpay_signature": "sig",
        }
        body.update(over)
        return self.client_.post(
            f"/api/v1/payments/{self.payment.id}/confirm", body, format="json"
        )

    @override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=True)
    def test_a_verified_callback_settles_the_order(self):
        r = self._confirm()
        self.assertEqual(r.status_code, 200, r.content[:300])
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, Order.PaymentStatus.PAID)

    @override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=False)
    def test_an_unverifiable_signature_does_not_settle(self):
        r = self._confirm()
        self.assertGreaterEqual(r.status_code, 400)
        self.order.refresh_from_db()
        self.assertNotEqual(self.order.payment_status, Order.PaymentStatus.PAID)

    @override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=True)
    def test_a_signature_for_a_different_order_is_refused(self):
        # Otherwise a valid triple from any other Razorpay order of ours could be
        # replayed to settle this payment for free.
        r = self._confirm(razorpay_order_id="order_somebody_elses")
        self.assertGreaterEqual(r.status_code, 400)
        self.order.refresh_from_db()
        self.assertNotEqual(self.order.payment_status, Order.PaymentStatus.PAID)

    @override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=True)
    def test_another_users_payment_cannot_be_confirmed(self):
        stranger = _client(_user("+919600006667"))
        r = stranger.post(
            f"/api/v1/payments/{self.payment.id}/confirm",
            {"razorpay_order_id": "order_ok", "razorpay_payment_id": "p",
             "razorpay_signature": "s"},
            format="json",
        )
        self.assertEqual(r.status_code, 404)

    @override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=True)
    def test_confirming_twice_settles_once(self):
        self.assertEqual(self._confirm().status_code, 200)
        self.assertEqual(self._confirm().status_code, 200)
        self.assertEqual(
            Payment.objects.filter(order=self.order,
                                   purpose=Payment.Purpose.ORDER).count(), 1)


class StatementRepaymentTests(TestCase):
    """A part-payment is not a settlement."""

    def setUp(self):
        self.user = _user("+919600005555")
        self.account = CreditAccount.objects.create(
            user=self.user, credit_limit=Decimal("10000")
        )
        today = date(2026, 7, 1)
        self.statement = Statement.objects.create(
            account=self.account, closing_balance=Decimal("8000"),
            period_start=today, period_end=date(2026, 7, 31),
            due_date=date(2026, 8, 10),
        )

    def _repay(self, amount):
        payment = start_payment(
            self.user, purpose="repayment", amount=Decimal(amount), method="upi",
            statement=self.statement,
        )
        payment.refresh_from_db()
        if payment.status != Payment.Status.SUCCESS:
            finalize_payment(payment, success=True, gateway_payment_id="p")
        self.statement.refresh_from_db()

    def test_partial_payment_does_not_mark_the_statement_paid(self):
        # ₹1 against ₹8,000 used to fabricate a full ₹8,000 receipt and stop dunning.
        self._repay("1")
        self.assertEqual(self.statement.payments, Decimal("1"))
        self.assertNotEqual(self.statement.status, Statement.Status.PAID)

    def test_payments_accumulate_and_settle_once_covered(self):
        self._repay("3000")
        self.assertNotEqual(self.statement.status, Statement.Status.PAID)
        self._repay("5000")
        self.assertEqual(self.statement.payments, Decimal("8000"))
        self.assertEqual(self.statement.status, Statement.Status.PAID)
