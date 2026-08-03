"""Referrals must actually pay someone, and only for a real order.

The old flow marked a referral COMPLETED the moment a code was typed and
returned `{"reward": 100}` while crediting **nobody** — no coupon, no points,
nothing. It also completed before the referee had bought anything, so the
scheme could be farmed by creating accounts and typing codes at each other.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from offers.models import Coupon

from .models import Referral
from .services import apply_code, complete_for_order, my_referral


class _FakeOrder:
    """Just what `complete_for_order` reads."""

    def __init__(self, user):
        self.user = user
        self.code = "VSORD1"
        self.total = Decimal("500")


class ReferralCodeTests(TestCase):
    def setUp(self):
        self.alice = User.objects.create(phone="+919000008001", name="Alice",
                                         role="customer")
        self.bob = User.objects.create(phone="+919000008002", name="Bob",
                                       role="customer")

    def test_a_code_is_created_on_first_view_and_is_stable(self):
        first = my_referral(self.alice)
        self.assertTrue(first.code.startswith("VS"))
        self.assertEqual(my_referral(self.alice).id, first.id)

    def test_applying_links_but_does_not_complete(self):
        code = my_referral(self.alice).code
        referral = apply_code(self.bob, code)
        self.assertEqual(referral.referrer, self.alice)
        self.assertEqual(referral.referee, self.bob)
        self.assertEqual(referral.status, Referral.Status.PENDING)

    def test_applying_pays_nobody_yet(self):
        """The headline defect: typing a code used to claim a reward."""
        apply_code(self.bob, my_referral(self.alice).code)
        self.assertEqual(Coupon.objects.count(), 0)

    def test_you_cannot_refer_yourself(self):
        code = my_referral(self.alice).code
        with self.assertRaises(Exception):
            apply_code(self.alice, code)

    def test_a_code_can_only_be_applied_once_per_customer(self):
        apply_code(self.bob, my_referral(self.alice).code)
        with self.assertRaises(Exception):
            apply_code(self.bob, my_referral(self.alice).code)

    def test_an_unknown_code_is_refused(self):
        with self.assertRaises(Exception):
            apply_code(self.bob, "NOPE123")

    def test_a_blank_code_is_refused(self):
        for bad in ("", "   ", None):
            with self.assertRaises(Exception):
                apply_code(self.bob, bad)

    def test_several_people_can_use_one_code(self):
        carol = User.objects.create(phone="+919000008003", name="Carol",
                                    role="customer")
        code = my_referral(self.alice).code
        apply_code(self.bob, code)
        apply_code(carol, code)
        self.assertEqual(
            Referral.objects.filter(referrer=self.alice,
                                    referee__isnull=False).count(), 2)


class ReferralPayoutTests(TestCase):
    def setUp(self):
        self.alice = User.objects.create(phone="+919000008010", name="Alice",
                                         role="customer")
        self.bob = User.objects.create(phone="+919000008011", name="Bob",
                                       role="customer")
        apply_code(self.bob, my_referral(self.alice).code)

    def test_delivery_pays_both_sides_a_personal_voucher(self):
        complete_for_order(_FakeOrder(self.bob))

        self.assertEqual(Coupon.objects.filter(owner=self.alice).count(), 1)
        self.assertEqual(Coupon.objects.filter(owner=self.bob).count(), 1)
        for c in Coupon.objects.all():
            self.assertEqual(c.usage_limit, 1)
            self.assertEqual(c.per_user_limit, 1)
            self.assertIsNotNone(c.owner_id)   # personal: useless to a stranger
            self.assertTrue(c.is_active)

    def test_the_referral_is_marked_completed(self):
        complete_for_order(_FakeOrder(self.bob))
        self.assertEqual(
            Referral.objects.get(referee=self.bob).status,
            Referral.Status.COMPLETED,
        )

    def test_payout_is_idempotent(self):
        """A replayed delivery must not mint a second pair of vouchers."""
        complete_for_order(_FakeOrder(self.bob))
        complete_for_order(_FakeOrder(self.bob))
        complete_for_order(_FakeOrder(self.bob))
        self.assertEqual(Coupon.objects.count(), 2)

    def test_an_unreferred_customer_gets_nothing(self):
        stranger = User.objects.create(phone="+919000008012", name="S",
                                       role="customer")
        self.assertIsNone(complete_for_order(_FakeOrder(stranger)))
        self.assertEqual(Coupon.objects.filter(owner=stranger).count(), 0)

    def test_voucher_codes_are_unguessable(self):
        complete_for_order(_FakeOrder(self.bob))
        for c in Coupon.objects.all():
            self.assertTrue(c.code.startswith("REF"))
            self.assertGreaterEqual(len(c.code), 8)   # not a sequence


class ReferralApiTests(TestCase):
    def setUp(self):
        self.alice = User.objects.create(phone="+919000008020", name="Alice",
                                         role="customer")
        self.bob = User.objects.create(phone="+919000008021", name="Bob",
                                       role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.bob)

    def _data(self, r):
        return r.json().get("data", r.json())

    def test_get_returns_a_code_and_honest_counts(self):
        r = self.client.get("/api/v1/referrals")
        self.assertEqual(r.status_code, 200)
        data = self._data(r)
        self.assertTrue(data["code"])
        self.assertEqual(data["referredCount"], 0)
        self.assertEqual(data["completedCount"], 0)

    def test_apply_says_the_reward_is_pending_not_earned(self):
        code = my_referral(self.alice).code
        r = self.client.post("/api/v1/referrals/apply", {"code": code},
                             format="json")
        self.assertEqual(r.status_code, 200, r.json())
        data = self._data(r)
        self.assertEqual(data["rewardStatus"], Referral.Status.PENDING)
        self.assertIn("delivered", data["message"])

    def test_counts_separate_pending_from_paid(self):
        apply_code(self.bob, my_referral(self.alice).code)
        alice_client = APIClient()
        alice_client.force_authenticate(self.alice)

        data = self._data(alice_client.get("/api/v1/referrals"))
        self.assertEqual(data["referredCount"], 1)
        self.assertEqual(data["completedCount"], 0)
        self.assertEqual(data["pendingCount"], 1)

        complete_for_order(_FakeOrder(self.bob))
        data = self._data(alice_client.get("/api/v1/referrals"))
        self.assertEqual(data["completedCount"], 1)
        self.assertEqual(data["pendingCount"], 0)
