"""Loyalty earning resolves the SERVING ZONE's rate.

The rate was hardcoded (`order_total // 10`), so every area earned identically and
a launch promo in a new zone needed a deploy. Zone overrides now resolve exactly
like the fee overrides: zone value wins, null falls back to PlatformConfig.
"""
from decimal import Decimal

from django.test import TestCase

from accounts.models import User
from siteconfig.models import PlatformConfig
from zones.models import Zone

from .services import earn_for_order, points_rate


class ZoneLoyaltyRateTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000900001", role="customer")
        self.default_zone = Zone.objects.create(name="Standard", code="STD")
        self.promo_zone = Zone.objects.create(
            name="Velangi", code="VLG", loyalty_points_per_100=20)

    # ── rate resolution ──
    def test_default_rate_reproduces_the_old_hardcoded_rule(self):
        """1 point per ₹10 spent — existing earning must not shift under anyone."""
        self.assertEqual(points_rate(None), 10)

    def test_zone_without_an_override_falls_back_to_platform(self):
        self.assertEqual(points_rate(self.default_zone), 10)

    def test_zone_override_wins(self):
        self.assertEqual(points_rate(self.promo_zone), 20)

    def test_platform_default_is_configurable(self):
        cfg = PlatformConfig.load()
        cfg.loyalty_points_per_100 = 15
        cfg.save()
        self.assertEqual(points_rate(None), 15)
        # …but a zone override still beats it.
        self.assertEqual(points_rate(self.promo_zone), 20)

    # ── earning ──
    def test_earning_is_unchanged_for_a_zoneless_order(self):
        entry = earn_for_order(self.user, Decimal("800"), "VS1")
        self.assertEqual(entry.points, 80)

    def test_promo_zone_earns_at_its_own_rate(self):
        entry = earn_for_order(self.user, Decimal("800"), "VS2", zone=self.promo_zone)
        self.assertEqual(entry.points, 160)

    def test_points_are_floored_never_rounded_up(self):
        """₹95 at 10/100 is 9.5 points — the customer gets 9, not 10."""
        entry = earn_for_order(self.user, Decimal("95"), "VS3")
        self.assertEqual(entry.points, 9)

    def test_small_basket_can_earn_zero_rather_than_a_free_point(self):
        entry = earn_for_order(self.user, Decimal("5"), "VS4")
        self.assertEqual(entry.points, 0)

    def test_zone_rate_is_noted_on_the_ledger_row(self):
        """An auditor reading the ledger should see WHY the amount differed."""
        entry = earn_for_order(self.user, Decimal("800"), "VS5", zone=self.promo_zone)
        self.assertIn("Velangi", entry.note)

    def test_a_zero_rate_zone_earns_nothing(self):
        zone = Zone.objects.create(name="NoPoints", code="NOP", loyalty_points_per_100=0)
        # 0 is a real setting, NOT "unset" — it must not fall back to the default.
        self.assertEqual(points_rate(zone), 0)
        self.assertEqual(
            earn_for_order(self.user, Decimal("800"), "VS6", zone=zone).points, 0)

    def test_balance_accumulates_across_zones(self):
        earn_for_order(self.user, Decimal("800"), "VS7")
        entry = earn_for_order(self.user, Decimal("800"), "VS8", zone=self.promo_zone)
        self.assertEqual(entry.balance_after, 240)
