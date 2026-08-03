"""Referrals + loyalty admin APIs.

Neither programme had any console: real vouchers were minted on both sides of every
completed referral and nobody could see the tree, the conversion, or the cost.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from loyalty.services import post as points_post
from loyalty.models import PointsLedgerEntry
from offers.models import Coupon, CouponRedemption

from .models import Referral


class ReferralAdminTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919000950001", role="admin")
        self.alice = User.objects.create(
            phone="+919000950002", name="Alice", role="customer")
        self.bob = User.objects.create(
            phone="+919000950003", name="Bob", role="customer")
        self.carol = User.objects.create(
            phone="+919000950004", name="Carol", role="customer")

        # Alice invited two people; one converted.
        Referral.objects.create(
            referrer=self.alice, referee=self.bob, code="ALICE1",
            reward=Decimal("100"), status=Referral.Status.COMPLETED)
        Referral.objects.create(
            referrer=self.alice, referee=self.carol, code="ALICE2",
            reward=Decimal("100"), status=Referral.Status.PENDING)
        # Bob invited nobody who converted.
        Referral.objects.create(
            referrer=self.bob, code="BOB1",
            reward=Decimal("100"), status=Referral.Status.PENDING)

        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    # ── access ──
    def test_customer_cannot_read_the_referral_console(self):
        self.client.force_authenticate(self.alice)
        r = self.client.get("/api/v1/admin/referrers")
        self.assertIn(r.status_code, (401, 403))

    # ── the "who invited how many" view ──
    def test_referrer_list_counts_invites_and_conversions(self):
        r = self.client.get("/api/v1/admin/referrers")
        self.assertEqual(r.status_code, 200)
        rows = r.data["data"] if isinstance(r.data, dict) else r.data
        alice = next(row for row in rows if row["name"] == "Alice")
        self.assertEqual(alice["invited"], 2)
        self.assertEqual(alice["completed"], 1)
        self.assertEqual(alice["pending"], 1)

    def test_referrer_list_ranks_by_conversions_not_raw_invites(self):
        r = self.client.get("/api/v1/admin/referrers")
        rows = r.data["data"] if isinstance(r.data, dict) else r.data
        self.assertEqual(rows[0]["name"], "Alice")

    def test_referrer_detail_lists_who_they_invited(self):
        r = self.client.get(f"/api/v1/admin/referrers/{self.alice.id}")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["invited"], 2)
        names = {i["referee_name"] for i in r.data["invitees"]}
        self.assertEqual(names, {"Bob", "Carol"})

    def test_a_deleted_invitee_leaves_the_row_and_the_count_intact(self):
        """referee is SET_NULL — the referrer's history must not silently shrink."""
        self.carol.delete()
        r = self.client.get(f"/api/v1/admin/referrers/{self.alice.id}")
        self.assertEqual(r.data["invited"], 2)
        blank = [i for i in r.data["invitees"] if not i["referee_name"]]
        self.assertEqual(len(blank), 1)

    # ── summary ──
    def test_summary_reports_conversion_rate(self):
        r = self.client.get("/api/v1/admin/referrals/summary")
        self.assertEqual(r.data["total"], 3)
        self.assertEqual(r.data["completed"], 1)
        self.assertEqual(r.data["conversion_rate"], 33.3)

    def test_summary_counts_the_reward_for_BOTH_sides(self):
        """Referrer and referee each get a voucher, so a ₹100 referral costs ₹200."""
        r = self.client.get("/api/v1/admin/referrals/summary")
        self.assertEqual(Decimal(str(r.data["rewards_paid"])), Decimal("200"))

    def test_summary_survives_an_empty_programme(self):
        Referral.objects.all().delete()
        r = self.client.get("/api/v1/admin/referrals/summary")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["conversion_rate"], 0.0)

    # ── filtering ──
    def test_referral_list_filters_by_status(self):
        r = self.client.get("/api/v1/admin/referrals?status=completed")
        rows = r.data["data"] if isinstance(r.data, dict) else r.data
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["code"], "ALICE1")

    def test_referral_list_searches_by_invitee_phone(self):
        r = self.client.get(f"/api/v1/admin/referrals?search={self.carol.phone}")
        rows = r.data["data"] if isinstance(r.data, dict) else r.data
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["code"], "ALICE2")


class LoyaltyAdminTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919000960001", role="admin")
        self.user = User.objects.create(
            phone="+919000960002", name="Dave", role="customer")

        points_post(self.user, PointsLedgerEntry.Type.EARN, 500, note="Earned on VS1",
                    ref_type="order", ref_id="VS1")
        points_post(self.user, PointsLedgerEntry.Type.REDEEM, -200, note="Voucher")

        self.voucher = Coupon.objects.create(
            code="LOY1", owner=self.user,
            discount_type=Coupon.DiscountType.FLAT, value=Decimal("20"))
        self.unspent = Coupon.objects.create(
            code="LOY2", owner=self.user,
            discount_type=Coupon.DiscountType.FLAT, value=Decimal("30"))
        CouponRedemption.objects.create(
            coupon=self.voucher, user=self.user,
            order_code="VS2", amount=Decimal("20"))

        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_customer_cannot_read_the_loyalty_console(self):
        self.client.force_authenticate(self.user)
        r = self.client.get("/api/v1/admin/loyalty/summary")
        self.assertIn(r.status_code, (401, 403))

    def test_summary_reports_magnitudes_not_signed_points(self):
        r = self.client.get("/api/v1/admin/loyalty/summary")
        self.assertEqual(r.data["points_earned"], 500)
        self.assertEqual(r.data["points_redeemed"], 200)

    def test_outstanding_points_are_the_real_liability(self):
        r = self.client.get("/api/v1/admin/loyalty/summary")
        self.assertEqual(r.data["points_outstanding"], 300)

    def test_ledger_search_finds_by_order_reference(self):
        r = self.client.get("/api/v1/admin/loyalty/ledger?search=VS1")
        rows = r.data["data"] if isinstance(r.data, dict) else r.data
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["points"], 500)

    def test_top_members_carries_the_tier(self):
        r = self.client.get("/api/v1/admin/loyalty/members")
        self.assertEqual(r.data[0]["name"], "Dave")
        self.assertEqual(r.data[0]["lifetime_points"], 500)
        self.assertEqual(r.data[0]["tier"], "Bronze")

    def test_redemptions_list_flags_personal_vouchers(self):
        r = self.client.get("/api/v1/admin/redemptions")
        rows = r.data["data"] if isinstance(r.data, dict) else r.data
        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0]["is_personal"])
        self.assertEqual(rows[0]["order_code"], "VS2")

    def test_redemptions_filter_public_vs_personal(self):
        public = Coupon.objects.create(
            code="SALE10", discount_type=Coupon.DiscountType.FLAT, value=Decimal("10"))
        CouponRedemption.objects.create(
            coupon=public, user=self.user, order_code="VS3", amount=Decimal("10"))

        r = self.client.get("/api/v1/admin/redemptions?kind=public")
        rows = r.data["data"] if isinstance(r.data, dict) else r.data
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["coupon_code"], "SALE10")

    def test_outstanding_vouchers_separate_issued_from_spent(self):
        r = self.client.get("/api/v1/admin/redemptions/outstanding")
        self.assertEqual(r.data["issued"], 2)
        self.assertEqual(r.data["spent"], 1)
        self.assertEqual(r.data["outstanding"], 1)
        self.assertEqual(Decimal(str(r.data["outstanding_value"])), Decimal("30"))

    def test_percent_vouchers_are_excluded_from_outstanding_value(self):
        """A percent code's cost depends on the basket, so summing it invents a
        number."""
        Coupon.objects.create(
            code="LOY3", owner=self.user,
            discount_type=Coupon.DiscountType.PERCENT, value=Decimal("50"))
        r = self.client.get("/api/v1/admin/redemptions/outstanding")
        self.assertEqual(r.data["outstanding"], 2)
        self.assertEqual(Decimal(str(r.data["outstanding_value"])), Decimal("30"))
