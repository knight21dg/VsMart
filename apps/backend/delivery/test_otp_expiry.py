"""Delivery OTP expiry and lockout recovery.

`DeliveryOTP.generated_at` was written on every code and **never read**, so a
delivery OTP never expired: a delivery re-attempted the next day still accepted
yesterday's code, and a live handover credential sat in the customer's inbox
indefinitely. Separately, `manual_verification_required` was set on lockout and
never cleared, so a task that later verified cleanly stayed flagged.
"""
from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone

from accounts.models import AgentProfile, Role, User
from core.app_errors import AppError
from delivery import services
from delivery.models import DeliveryOTP, DeliveryTask
from orders.models import Order, OrderStatus


class DeliveryOtpExpiryTests(TestCase):
    def setUp(self):
        self.customer = User.objects.create(
            phone="+919600066001", name="Cust", role=Role.CUSTOMER
        )
        self.agent = User.objects.create(
            phone="+919600066002", name="Rider", role=Role.AGENT
        )
        AgentProfile.objects.create(user=self.agent, code="AGOTP1")
        self.order = Order.objects.create(
            user=self.customer, subtotal=Decimal("100"), total=Decimal("100"),
            status=OrderStatus.OUT_FOR_DELIVERY,
        )
        self.task = DeliveryTask.objects.create(
            order=self.order, agent=self.agent, status=DeliveryTask.Status.REACHED
        )
        self.otp = DeliveryOTP.objects.create(
            task=self.task, code="123456", generated_at=timezone.now()
        )

    def _age(self, minutes):
        self.otp.generated_at = timezone.now() - timedelta(minutes=minutes)
        self.otp.save(update_fields=["generated_at"])

    def test_a_fresh_code_verifies(self):
        services.verify_otp(self.task, self.agent, "123456")
        self.task.refresh_from_db()
        self.assertTrue(self.task.otp_verified)

    def test_a_code_just_inside_the_window_still_verifies(self):
        self._age(services.OTP_TTL_MINUTES - 1)
        services.verify_otp(self.task, self.agent, "123456")
        self.task.refresh_from_db()
        self.assertTrue(self.task.otp_verified)

    def test_an_expired_code_is_refused(self):
        self._age(services.OTP_TTL_MINUTES + 1)
        with self.assertRaises(AppError) as ctx:
            services.verify_otp(self.task, self.agent, "123456")
        self.assertEqual(ctx.exception.code, "DELIVERY_OTP_EXPIRED")
        self.task.refresh_from_db()
        self.assertFalse(self.task.otp_verified)

    def test_an_expired_code_does_not_burn_an_attempt(self):
        """Expiry is not a wrong guess. Counting it would let a slow customer
        lock the agent out through no fault of theirs."""
        self._age(services.OTP_TTL_MINUTES + 1)
        for _ in range(3):
            with self.assertRaises(AppError):
                services.verify_otp(self.task, self.agent, "123456")
        self.otp.refresh_from_db()
        self.assertEqual(self.otp.attempts, 0)
        self.assertFalse(self.otp.locked)

    def test_a_null_generated_at_is_not_treated_as_expired(self):
        """Rows written before the timestamp was enforced must not be
        invalidated retroactively under an agent standing at a door."""
        self.otp.generated_at = None
        self.otp.save(update_fields=["generated_at"])
        services.verify_otp(self.task, self.agent, "123456")
        self.task.refresh_from_db()
        self.assertTrue(self.task.otp_verified)

    def test_re_arriving_mints_a_fresh_unexpired_code(self):
        self._age(services.OTP_TTL_MINUTES + 5)
        services._generate_otp(self.task)
        self.otp.refresh_from_db()
        self.assertFalse(services.otp_is_expired(self.otp))
        self.assertEqual(self.otp.attempts, 0)
        self.assertFalse(self.otp.locked)

    # ── lockout ──
    def test_three_wrong_codes_lock_and_flag_for_manual_verification(self):
        for _ in range(3):
            with self.assertRaises(AppError):
                services.verify_otp(self.task, self.agent, "000000")
        self.otp.refresh_from_db()
        self.task.refresh_from_db()
        self.assertTrue(self.otp.locked)
        self.assertTrue(self.task.manual_verification_required)

    def test_a_later_clean_verify_clears_the_stale_manual_flag(self):
        """Re-arrival unlocks the OTP row but used to leave the task flagged, so
        a delivery that went on to verify normally stayed marked as needing
        manual verification in the board and every report reading it."""
        for _ in range(3):
            with self.assertRaises(AppError):
                services.verify_otp(self.task, self.agent, "000000")
        self.task.refresh_from_db()
        self.assertTrue(self.task.manual_verification_required)

        services._generate_otp(self.task)          # agent re-confirms arrival
        self.otp.refresh_from_db()
        services.verify_otp(self.task, self.agent, self.otp.code)

        self.task.refresh_from_db()
        self.assertTrue(self.task.otp_verified)
        self.assertFalse(self.task.manual_verification_required)

    def test_delivery_cannot_complete_on_an_expired_code(self):
        """The completion guard is the thing that must hold."""
        self._age(services.OTP_TTL_MINUTES + 1)
        with self.assertRaises(AppError):
            services.verify_otp(self.task, self.agent, "123456")
        with self.assertRaises(AppError) as ctx:
            services.complete_delivery(self.task, self.agent)
        self.assertEqual(ctx.exception.code, "DELIVERY_OTP_REQUIRED")


class ExpiredVersusInvalidTests(TestCase):
    """Expired and invalid must be distinguishable BY THE CLIENT, and must have
    different consequences. The agent app branches on the code to decide between
    a one-tap recovery panel and an attempts-left warning, so the codes and the
    attempt accounting are a contract, not cosmetics."""

    def setUp(self):
        from rest_framework.test import APIClient

        self.customer = User.objects.create(
            phone="+919600099001", name="Cust", role=Role.CUSTOMER
        )
        self.agent = User.objects.create(
            phone="+919600099002", name="Rider", role=Role.AGENT
        )
        AgentProfile.objects.create(user=self.agent, code="AGEXP1")
        self.order = Order.objects.create(
            user=self.customer, subtotal=Decimal("100"), total=Decimal("100"),
            status=OrderStatus.OUT_FOR_DELIVERY,
        )
        self.task = DeliveryTask.objects.create(
            order=self.order, agent=self.agent, status=DeliveryTask.Status.REACHED
        )
        self.otp = DeliveryOTP.objects.create(
            task=self.task, code="123456", generated_at=timezone.now()
        )
        self.client = APIClient()
        self.client.force_authenticate(self.agent)

    def _verify(self, code):
        return self.client.post(
            f"/api/v1/deliveries/{self.task.id}/otp", {"otp": code}, format="json"
        )

    def _expire(self):
        self.otp.generated_at = timezone.now() - timedelta(
            minutes=services.OTP_TTL_MINUTES + 1
        )
        self.otp.save(update_fields=["generated_at"])

    def test_the_two_failures_carry_different_codes(self):
        wrong = self._verify("000000")
        self.assertEqual(wrong.json()["code"], "INVALID_DELIVERY_OTP")

        self._expire()
        expired = self._verify("123456")
        self.assertEqual(expired.json()["code"], "DELIVERY_OTP_EXPIRED")
        self.assertNotEqual(wrong.json()["code"], expired.json()["code"])

    def test_the_two_failures_carry_different_messages(self):
        wrong = self._verify("000000").json()["message"]
        self._expire()
        expired = self._verify("123456").json()["message"]
        self.assertNotEqual(wrong, expired)
        self.assertIn("expired", expired.lower())

    def test_the_expired_response_tells_the_agent_how_to_recover(self):
        self._expire()
        body = self._verify("123456").json()
        self.assertTrue(body["nextStep"], "an expired code must say what to do")
        self.assertIn("arrival", body["nextStep"].lower())

    def test_expired_is_retryable_and_invalid_is_not_a_lockout_yet(self):
        self._expire()
        self.assertTrue(self._verify("123456").json()["retryable"])

    def test_a_wrong_code_consumes_an_attempt_and_expired_does_not(self):
        self._verify("000000")
        self.otp.refresh_from_db()
        self.assertEqual(self.otp.attempts, 1)

        self._expire()
        self._verify("123456")
        self.otp.refresh_from_db()
        self.assertEqual(self.otp.attempts, 1, "expiry must not burn an attempt")

    def test_the_lockout_rule_is_not_weakened_by_the_expiry_branch(self):
        """Three WRONG codes still lock, exactly as before."""
        for _ in range(3):
            self._verify("000000")
        self.otp.refresh_from_db()
        self.task.refresh_from_db()
        self.assertTrue(self.otp.locked)
        self.assertTrue(self.task.manual_verification_required)
        self.assertEqual(
            self._verify("123456").json()["code"], "MANUAL_VERIFICATION_REQUIRED"
        )

    def test_recovery_after_expiry_actually_works_end_to_end(self):
        """Expire → re-confirm arrival → the fresh code verifies. This is the
        exact sequence the app's "Send a new code" button performs."""
        self._expire()
        self.assertEqual(self._verify("123456").json()["code"], "DELIVERY_OTP_EXPIRED")

        services._generate_otp(self.task)
        self.otp.refresh_from_db()
        r = self._verify(self.otp.code)
        self.assertEqual(r.status_code, 200, r.content)
        self.task.refresh_from_db()
        self.assertTrue(self.task.otp_verified)
