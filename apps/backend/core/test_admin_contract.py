"""Guards for the failure modes the console can't show you.

Every bug these lock down was invisible: the page rendered, the request
returned 200, and the wrong thing happened quietly. They share one root — a
value that is *data* being used where a *name* belongs, then rewritten by the
camelCase renderer on its way out.
"""
from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import Role, User


class ResponseKeysAreNotDataTests(TestCase):
    """A response key that is derived from data must survive the renderer.

    ``EnvelopeJSONRenderer`` camelCases every key in the payload. It cannot tell
    a field name from a value used as a key, so ``today_deals`` shipped as
    ``todayDeals`` and the console — which looks rails up by their real code —
    read an empty list for two of its four home rails. These pin the wire names
    that clients actually index by.
    """

    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create(
            phone="+919000007001", name="Admin", role=Role.SUPERADMIN
        )
        self.client.force_authenticate(self.admin)

    def test_employee_summary_uses_the_key_the_console_reads(self):
        """The Store Staff tile read `store_staff` and the API sent `storeStaff`,
        so it displayed 0 no matter how many store staff existed."""
        User.objects.create(phone="+919000007002", name="S1", role=Role.STORE_STAFF)
        User.objects.create(phone="+919000007003", name="S2", role=Role.STORE_STAFF)

        summary = self.client.get("/api/v1/admin/employees").json()["data"]["summary"]

        self.assertEqual(summary["storeStaff"], 2)
        self.assertNotIn("store_staff", summary)
        # The role *value* is untouched by the renderer — the console filters and
        # badges on it, so it must stay snake.
        roles = {e["role"] for e in
                 self.client.get("/api/v1/admin/employees").json()["data"]["employees"]}
        self.assertIn("store_staff", roles)

    def test_feature_flag_names_are_stable_on_the_wire(self):
        """Flag keys are data. What the code emits and what ships must match, or
        a lookup by the flag's real name silently reads False."""
        from system.models import FeatureFlag

        FeatureFlag.objects.create(key="zone_store_visibility", enabled=True)
        body = self.client.get("/api/v1/app-config").json()["data"]

        self.assertEqual(body["featureFlags"], {"zoneStoreVisibility": True})

    def test_home_rail_codes_survive_the_renderer(self):
        """Regression for the original: rails keyed by section code."""
        rails = self.client.get(
            "/api/v1/admin/catalog/home-sections"
        ).json()["data"]
        codes = {row["section"] for row in rails}

        self.assertEqual(codes, {"today_deals", "popular", "recommended", "top_selling"})


class DestructiveOutcomesAreReportedTests(TestCase):
    """A "Delete" that archives instead must say so.

    Anything with trading history is deactivated, not erased — the row is still
    on screen afterwards. A hardcoded "Deleted." toast over that reads as a
    failed delete, which is exactly how the zones page was reported broken. Each
    of these endpoints must return the outcome in the body so the console can
    repeat it rather than guess.
    """

    def setUp(self):
        self.client = APIClient()
        self.client.force_authenticate(
            User.objects.create(phone="+919000007010", name="A", role=Role.SUPERADMIN)
        )

    def test_a_served_banner_is_archived_and_says_so(self):
        from offers.models import Offer

        served = Offer.objects.create(title="Served", type="banner", impressions=5)
        response = self.client.delete(f"/api/v1/admin/marketing/offers/{served.id}")

        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["code"], "RECORD_ARCHIVED")
        self.assertEqual(body["data"]["outcome"], "archived")
        self.assertIn("archived", body["message"].lower())
        served.refresh_from_db()
        self.assertFalse(served.is_active)

    def test_a_banner_archived_on_clicks_alone_is_still_reported(self):
        """The console used to word its toast off `impressions > 0` — its own
        copy of a rule the server owns, and already out of step with it."""
        from offers.models import Offer

        clicked = Offer.objects.create(
            title="Clicked", type="banner", impressions=0, clicks=3
        )
        body = self.client.delete(
            f"/api/v1/admin/marketing/offers/{clicked.id}"
        ).json()

        self.assertEqual(body["code"], "RECORD_ARCHIVED")

    def test_an_unserved_banner_is_really_deleted(self):
        from offers.models import Offer

        fresh = Offer.objects.create(title="Fresh", type="banner")
        body = self.client.delete(f"/api/v1/admin/marketing/offers/{fresh.id}").json()

        self.assertEqual(body["code"], "RECORD_DELETED")
        self.assertFalse(Offer.objects.filter(pk=fresh.pk).exists())


class MethodMismatchesAnswerCleanlyTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.client.force_authenticate(
            User.objects.create(phone="+919000007020", name="A", role=Role.SUPERADMIN)
        )

    def test_getting_the_unassign_url_is_405_not_500(self):
        """One APIView serves `…/agents` and `…/agents/<agent_id>`, so a GET on
        the second handed `get()` a kwarg it did not accept — a TypeError, i.e. a
        500 on a URL that should simply refuse the method."""
        from zones.models import Zone

        zone = Zone.objects.create(name="Agents Zone", code="ZAG")
        agent = User.objects.create(
            phone="+919000007021", name="Agent", role=Role.AGENT
        )

        response = self.client.get(f"/api/v1/admin/zones/{zone.id}/agents/{agent.id}")

        self.assertEqual(response.status_code, 405, response.content)

    def test_the_agent_list_still_works(self):
        from zones.models import Zone

        zone = Zone.objects.create(name="List Zone", code="ZLI")
        response = self.client.get(f"/api/v1/admin/zones/{zone.id}/agents")

        self.assertEqual(response.status_code, 200, response.content)
