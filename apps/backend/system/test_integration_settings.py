"""The super-admin integration-settings panel must expose EVERY setting.

Two failures this file exists for:

1. **A setting existed in the backend with nowhere in the UI to put it.** The
   Payon credit-bureau key sat in the model and in `SEED` for weeks while the
   admin page enumerated its fields by hand and simply didn't list it — so the
   only way to configure a live integration was a shell on the server. The API
   contract is now "every `SEED` field, every time", and the client renders
   whatever it is sent.

2. **Secrets were write-only**, returned as a `<field>_set` boolean. The owner
   reversed that (2026-08-11) so the platform can be handed over with credentials
   visible and verifiable. These tests pin the new behaviour deliberately, so that
   re-hiding them is a conscious decision with a failing test attached rather than
   an accident.
"""
from accounts.models import Role, User
from core import runtime_settings as rt
from django.test import TestCase
from rest_framework.test import APIClient

URL = "/api/v1/admin/settings/integrations"


def _data(resp):
    body = resp.json()
    return body.get("data", body)


class IntegrationSettingsAccessTests(TestCase):
    def test_only_a_super_admin_may_read_credentials(self):
        for role in (Role.CUSTOMER, Role.AGENT, Role.ADMIN):
            with self.subTest(role=role):
                u = User.objects.create(phone=f"+9198000010{role[:2]}", role=role)
                c = APIClient()
                c.force_authenticate(u)
                self.assertIn(c.get(URL).status_code, (401, 403))

    def test_anonymous_is_rejected(self):
        self.assertIn(APIClient().get(URL).status_code, (401, 403))


class IntegrationSettingsContentTests(TestCase):
    def setUp(self):
        self.su = User.objects.create(phone="+919800000099", role=Role.SUPERADMIN)
        self.c = APIClient()
        self.c.force_authenticate(self.su)

    def test_every_seeded_setting_is_returned(self):
        """The whole point: no field may be backend-only."""
        got = _data(self.c.get(URL))
        # The envelope renderer camelCases keys, so compare on that basis.
        camel = {f.replace("_", " ").title().replace(" ", "") for f in rt.SEED}
        camel = {c[0].lower() + c[1:] for c in camel}
        missing = camel - set(got)
        self.assertEqual(
            missing, set(),
            f"settings exist in SEED but are not exposed to the panel: {missing}")

    def test_secret_values_are_returned_in_clear_text(self):
        rt.get_obj()  # create the singleton
        self.c.patch(URL, {"creditBureauApiKey": "live-key-123"}, format="json")
        got = _data(self.c.get(URL))
        self.assertEqual(got["creditBureauApiKey"], "live-key-123")
        # The old boolean is still sent, so a client can badge "Configured".
        self.assertIs(got["creditBureauApiKeySet"], True)

    def test_the_client_is_told_which_fields_are_sensitive(self):
        """So the page never keeps its own copy of the list to drift from."""
        got = _data(self.c.get(URL))
        self.assertEqual(set(got["secretFields"]), set(rt.SECRET_FIELDS))

    def test_a_value_only_present_in_env_is_reported_as_effective(self):
        """`cfg()` falls back to settings; showing the raw column read 'Not set'
        for a key that was in fact live."""
        with self.settings(CREDIT_BUREAU_BASE_URL="https://reseller.example/api"):
            rt.invalidate()
            got = _data(self.c.get(URL))
        rt.invalidate()
        self.assertEqual(got["creditBureauBaseUrl"], "https://reseller.example/api")


class IntegrationSettingsWriteTests(TestCase):
    def setUp(self):
        self.su = User.objects.create(phone="+919800000098", role=Role.SUPERADMIN)
        self.c = APIClient()
        self.c.force_authenticate(self.su)
        rt.get_obj()

    def tearDown(self):
        rt.invalidate()

    def test_a_secret_can_be_cleared(self):
        """Blank used to mean 'keep', which would leave a credential the operator
        believes they deleted still live."""
        self.c.patch(URL, {"razorpayKeySecret": "sekret"}, format="json")
        self.assertEqual(_data(self.c.get(URL))["razorpayKeySecret"], "sekret")

        self.c.patch(URL, {"razorpayKeySecret": ""}, format="json")
        rt.invalidate()
        self.assertEqual(_data(self.c.get(URL))["razorpayKeySecret"], "")

    def test_a_field_absent_from_the_body_is_untouched(self):
        self.c.patch(URL, {"razorpayKeyId": "rzp_live_x"}, format="json")
        self.c.patch(URL, {"emailFrom": "a@b.test"}, format="json")
        rt.invalidate()
        got = _data(self.c.get(URL))
        self.assertEqual(got["razorpayKeyId"], "rzp_live_x")
        self.assertEqual(got["emailFrom"], "a@b.test")

    def test_a_null_does_not_break_a_non_null_column(self):
        resp = self.c.patch(URL, {"signzyApiKey": None}, format="json")
        self.assertEqual(resp.status_code, 200)
        rt.invalidate()
        self.assertEqual(_data(self.c.get(URL))["signzyApiKey"], "")

    def test_saving_takes_effect_without_a_redeploy(self):
        """The panel's whole purpose — `cfg()` must see the new value at once."""
        self.c.patch(URL, {"creditBureauApiKey": "rotated-key"}, format="json")
        self.assertEqual(rt.cfg("credit_bureau_api_key"), "rotated-key")
