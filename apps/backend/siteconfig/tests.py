from django.test import TestCase

from .models import PlatformConfig


class PublicSupportContactTests(TestCase):
    """GET /support/contact — the customer app's Help & Support fallback
    number/email when no store resolves for the caller. Public (no auth) and
    deliberately narrow: PlatformConfig also holds real business levers (fees,
    credit limits) that must never be exposed here."""

    URL = "/api/v1/support/contact"

    def test_public_no_auth_required(self):
        r = self.client.get(self.URL)
        self.assertEqual(r.status_code, 200)

    def test_returns_configured_contact_only(self):
        config = PlatformConfig.load()
        config.support_phone = "+911800266911"
        config.support_email = "help@thevsmart.com"
        config.save(update_fields=["support_phone", "support_email"])
        d = self.client.get(self.URL).json()["data"]
        self.assertEqual(d, {
            "supportPhone": "+911800266911",
            "supportEmail": "help@thevsmart.com",
        })

    def test_never_leaks_business_config(self):
        d = self.client.get(self.URL).json()["data"]
        self.assertNotIn("gstRate", d)
        self.assertNotIn("creditDefaultLimit", d)
        self.assertNotIn("deliveryFee", d)
