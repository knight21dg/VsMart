"""Repayment must never charge more than the customer owes.

`apply_repayment` clamps a negative outstanding to zero, so an overpayment used to
be CHARGED in full at the gateway and then silently dropped: the customer paid
₹5,000 against a ₹500 balance and ₹4,500 vanished — no credit balance holds it and
nothing refunds it. RepayView now rejects it before the money moves.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from credit.models import CreditAccount


class RepayOverpaymentTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919002200001", role="customer")
        self.account = CreditAccount.objects.create(
            user=self.user, credit_limit=Decimal("10000"),
            outstanding=Decimal("500"))
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def _repay(self, amount):
        return self.client.post(
            "/api/v1/credit/repay", {"amount": amount, "method": "upi"},
            format="json")

    def test_repaying_the_exact_balance_is_allowed(self):
        r = self._repay("500")
        self.assertEqual(r.status_code, 201)

    def test_partial_repayment_is_allowed(self):
        r = self._repay("200")
        self.assertEqual(r.status_code, 201)

    def test_overpayment_is_rejected_before_any_charge(self):
        from payments.models import Payment

        r = self._repay("5000")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.data["error"]["code"], "CREDIT_OVERPAYMENT")
        # No payment was created — the gateway was never touched.
        self.assertFalse(
            Payment.objects.filter(user=self.user, purpose="repayment").exists())

    def test_overpayment_error_surfaces_the_real_balance(self):
        r = self._repay("5000")
        # The customer is told what they actually owe so they can correct it.
        self.assertIn("500", r.data["error"]["message"])

    def test_repaying_with_a_clear_balance_is_rejected(self):
        self.account.outstanding = Decimal("0")
        self.account.save(update_fields=["outstanding"])
        r = self._repay("100")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.data["error"]["code"], "CREDIT_NO_DUES")

    def test_a_penny_over_is_still_rejected(self):
        r = self._repay("500.01")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.data["error"]["code"], "CREDIT_OVERPAYMENT")
