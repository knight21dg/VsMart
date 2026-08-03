"""Loyalty redemption must produce something spendable.

Redemption previously burned the points and created nothing — the ledger note
said "Redeemed to wallet" but no wallet exists, so the balance vanished for no
value and could not be restored (the ledger is append-only).
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from offers.models import Coupon
from offers.services import resolve_coupon

from .models import PointsLedgerEntry
from .services import MIN_REDEEM_POINTS, POINTS_PER_RUPEE, _balance, post


def _data(resp):
    return resp.json()["data"]


class LoyaltyRedeemTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000000900", name="Rita",
                                        role="customer")
        self.other = User.objects.create(phone="+919000000901", name="Sam",
                                         role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.user)
        post(self.user, type=PointsLedgerEntry.Type.EARN, points=1000,
             note="seed")

    def _redeem(self, points):
        return self.client.post("/api/v1/loyalty/redeem", {"points": points},
                                format="json")

    def test_redeeming_issues_a_real_voucher(self):
        r = self._redeem(500)
        self.assertEqual(r.status_code, 200, r.json())
        voucher = _data(r)["voucher"]
        coupon = Coupon.objects.get(code=voucher["code"])
        self.assertEqual(coupon.value, Decimal(500 // POINTS_PER_RUPEE))
        self.assertEqual(coupon.owner_id, self.user.id)
        self.assertEqual(coupon.usage_limit, 1)
        self.assertTrue(coupon.is_active)

    def test_points_are_actually_deducted(self):
        self._redeem(500)
        self.assertEqual(_balance(self.user), 500)

    def test_the_voucher_actually_discounts_a_cart(self):
        """The whole point: the customer can spend what they redeemed."""
        code = _data(self._redeem(500))["voucher"]["code"]
        coupon, discount, _ = resolve_coupon(code, Decimal("300"),
                                             user=self.user)
        self.assertIsNotNone(coupon)
        self.assertEqual(discount, Decimal("50.00"))

    def test_a_personal_voucher_is_worthless_to_anyone_else(self):
        code = _data(self._redeem(500))["voucher"]["code"]
        coupon, discount, message = resolve_coupon(code, Decimal("300"),
                                                   user=self.other)
        self.assertIsNone(coupon)
        self.assertEqual(discount, Decimal("0.00"))
        # Reported as invalid, not "not yours" — the code can't be probed.
        self.assertEqual(message, "Invalid coupon code")

    def test_an_anonymous_caller_cannot_use_a_personal_voucher(self):
        code = _data(self._redeem(500))["voucher"]["code"]
        self.assertIsNone(resolve_coupon(code, Decimal("300"))[0])

    def test_public_campaign_coupons_still_work_for_everyone(self):
        Coupon.objects.create(code="PUBLIC10", discount_type="flat",
                              value=Decimal("10"), is_active=True)
        for user in (self.user, self.other, None):
            coupon, _, _ = resolve_coupon("PUBLIC10", Decimal("300"), user=user)
            self.assertIsNotNone(coupon)

    def test_cannot_redeem_more_than_the_balance(self):
        r = self._redeem(5000)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(_balance(self.user), 1000)
        self.assertFalse(Coupon.objects.filter(owner=self.user).exists())

    def test_below_the_minimum_is_refused(self):
        r = self._redeem(MIN_REDEEM_POINTS - 1)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(_balance(self.user), 1000)

    def test_a_remainder_stays_on_the_balance_instead_of_evaporating(self):
        """105 points at 10/₹ is ₹10 — the leftover 5 must not be burned."""
        self._redeem(105)
        self.assertEqual(_balance(self.user), 900)
        self.assertEqual(
            Coupon.objects.get(owner=self.user).value, Decimal("10")
        )

    def test_nothing_is_burned_when_issuing_fails(self):
        """Points and voucher are one transaction — never one without the other."""
        before = _balance(self.user)
        with self.assertRaises(Exception):
            from unittest.mock import patch

            with patch("offers.models.Coupon.objects.create",
                       side_effect=RuntimeError("db down")):
                from .services import redeem_to_voucher

                redeem_to_voucher(self.user, 500)
        self.assertEqual(_balance(self.user), before)

    def test_each_redemption_mints_a_distinct_code(self):
        a = _data(self._redeem(200))["voucher"]["code"]
        b = _data(self._redeem(200))["voucher"]["code"]
        self.assertNotEqual(a, b)
