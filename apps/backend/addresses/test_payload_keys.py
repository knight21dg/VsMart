"""Address saving must survive the payload the app actually sends.

Two things bit this endpoint:

1. **GPS precision.** Devices report 7+ decimal places (16.9890751); the model
   stores 6. A plain DecimalField answered that with a 400 on *both* coordinates
   ("Ensure that there are no more than 6 decimal places"), so anyone who pinned
   a location could not save an address at all — while the identical address
   saved fine without coordinates. Extra precision is noise, not user error, so
   `CoordinateField` rounds it.

2. **Key mangling.** `djangorestframework_camel_case` inserts an underscore
   before trailing digits by default, turning `line1` into `line_1` — which,
   since `line1` is required, would 400 every save. The
   `JSON_CAMEL_CASE = {"JSON_UNDERSCOREIZE": {"no_underscore_before_number": True}}`
   setting prevents that. It is namespaced under `JSON_CAMEL_CASE` because that
   is the key the library reads; a top-level `JSON_UNDERSCOREIZE` does nothing.
"""
from decimal import Decimal

from django.conf import settings
from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User


class UnderscoreizeSettingTests(TestCase):
    def test_trailing_digits_stay_attached(self):
        from djangorestframework_camel_case.settings import api_settings
        from djangorestframework_camel_case.util import underscoreize

        opts = api_settings.JSON_UNDERSCOREIZE
        self.assertTrue(
            opts.get("no_underscore_before_number"),
            "Must be set under JSON_CAMEL_CASE — the library reads that key.",
        )
        out = underscoreize({"line1": "x", "isDefault": True}, **opts)
        self.assertIn("line1", out)
        self.assertNotIn("line_1", out)
        self.assertIn("is_default", out)  # real camelCase still converts

    def test_setting_lives_under_the_key_the_library_reads(self):
        self.assertIn("JSON_UNDERSCOREIZE", getattr(settings, "JSON_CAMEL_CASE", {}))


class AddressCreateTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000005001", name="Cust",
                                        role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    BODY = {
        "name": "Test User",
        "phone": "9494429963",
        "line1": "69-16-8, Vs Raju Nagar, Bank Colony",
        "area": "Vs Raju Nagar",
        "landmark": "knight 21",
        "district": "Ramanayyapeta",
        "state": "Andhra Pradesh",
        "pincode": "533005",
        "is_default": True,
    }

    def _post(self, **over):
        return self.client.post("/api/v1/addresses", {**self.BODY, **over},
                                format="json")

    def test_saves_the_payload_the_app_sends(self):
        r = self._post()
        self.assertEqual(r.status_code, 201, r.json())
        self.assertEqual(self.user.addresses.first().line1,
                         "69-16-8, Vs Raju Nagar, Bank Colony")

    def test_camelcase_body_also_works(self):
        body = {**self.BODY}
        body["isDefault"] = body.pop("is_default")
        r = self.client.post("/api/v1/addresses", body, format="json")
        self.assertEqual(r.status_code, 201, r.json())

    def test_line1_is_still_required(self):
        body = {**self.BODY}
        body.pop("line1")
        self.assertEqual(self.client.post("/api/v1/addresses", body,
                                          format="json").status_code, 400)

    # ── the real-world failure ──
    def test_raw_gps_precision_is_accepted_and_rounded(self):
        """A pinned location must not make the address unsaveable."""
        r = self._post(latitude=16.9890751, longitude=82.2474607)
        self.assertEqual(r.status_code, 201, r.json())
        addr = self.user.addresses.first()
        self.assertEqual(addr.latitude, Decimal("16.989075"))
        self.assertEqual(addr.longitude, Decimal("82.247461"))   # rounded half-up

    def test_extreme_precision_still_accepted(self):
        r = self._post(latitude=16.98907512345, longitude=-82.24746078901)
        self.assertEqual(r.status_code, 201, r.json())

    def test_coordinates_as_strings_are_handled(self):
        r = self._post(latitude="16.9890751", longitude="82.2474607")
        self.assertEqual(r.status_code, 201, r.json())

    def test_null_coordinates_are_fine(self):
        r = self._post(latitude=None, longitude=None)
        self.assertEqual(r.status_code, 201, r.json())
        self.assertIsNone(self.user.addresses.first().latitude)

    def test_out_of_range_coordinate_is_still_rejected(self):
        """Rounding must not turn a genuinely bogus value into a silent save —
        max_digits=9 still caps the magnitude."""
        self.assertEqual(self._post(latitude=12345.6789).status_code, 400)


class AddressCrudTests(TestCase):
    """Edit / delete / set-default — the operations beyond create.

    Verified against production too; these pin the behaviour so a regression
    shows up in CI rather than on a customer's phone.
    """

    def setUp(self):
        self.user = User.objects.create(phone="+919000005010", name="Cust",
                                        role="customer")
        self.other = User.objects.create(phone="+919000005011", name="Other",
                                         role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def _create(self, name="A", **over):
        body = {
            "name": name, "phone": "9494429963", "line1": f"{name} Street",
            "area": "Area", "district": "Kakinada", "state": "Andhra Pradesh",
            "pincode": "533005", **over,
        }
        r = self.client.post("/api/v1/addresses", body, format="json")
        self.assertEqual(r.status_code, 201, r.json())
        return r.json()["data"]["id"]

    # ── edit ──
    def test_edit_updates_the_address(self):
        aid = self._create("A")
        r = self.client.patch(f"/api/v1/addresses/{aid}",
                              {"name": "A EDITED", "line1": "New Street"},
                              format="json")
        self.assertEqual(r.status_code, 200, r.json())
        addr = self.user.addresses.get(pk=aid)
        self.assertEqual(addr.name, "A EDITED")
        self.assertEqual(addr.line1, "New Street")

    def test_edit_rounds_coordinates_too(self):
        """The app PATCHes the whole body on edit, coords included."""
        aid = self._create("A")
        r = self.client.patch(f"/api/v1/addresses/{aid}",
                              {"latitude": 17.1234567, "longitude": 81.7654321},
                              format="json")
        self.assertEqual(r.status_code, 200, r.json())
        addr = self.user.addresses.get(pk=aid)
        self.assertEqual(addr.latitude, Decimal("17.123457"))
        self.assertEqual(addr.longitude, Decimal("81.765432"))

    def test_cannot_edit_another_users_address(self):
        aid = self._create("Mine")
        thief = APIClient()
        thief.force_authenticate(self.other)
        r = thief.patch(f"/api/v1/addresses/{aid}", {"name": "Stolen"},
                        format="json")
        self.assertEqual(r.status_code, 404)
        self.assertEqual(self.user.addresses.get(pk=aid).name, "Mine")

    # ── delete ──
    def test_delete_removes_the_address(self):
        aid = self._create("A")
        r = self.client.delete(f"/api/v1/addresses/{aid}")
        self.assertEqual(r.status_code, 204)
        self.assertFalse(self.user.addresses.filter(pk=aid).exists())

    def test_cannot_delete_another_users_address(self):
        aid = self._create("Mine")
        thief = APIClient()
        thief.force_authenticate(self.other)
        self.assertEqual(
            thief.delete(f"/api/v1/addresses/{aid}").status_code, 404)
        self.assertTrue(self.user.addresses.filter(pk=aid).exists())

    # ── default ──
    def test_first_address_becomes_default_automatically(self):
        aid = self._create("A", is_default=False)
        self.assertTrue(self.user.addresses.get(pk=aid).is_default)

    def test_setting_a_default_clears_the_previous_one(self):
        """Exactly one default, or `getDefault()` in the app is ambiguous."""
        first = self._create("A")
        second = self._create("B")
        r = self.client.post(f"/api/v1/addresses/{second}/default", {},
                             format="json")
        self.assertEqual(r.status_code, 200, r.json())
        self.assertTrue(self.user.addresses.get(pk=second).is_default)
        self.assertFalse(self.user.addresses.get(pk=first).is_default)
        self.assertEqual(self.user.addresses.filter(is_default=True).count(), 1)

    def test_creating_with_is_default_demotes_the_old_one(self):
        first = self._create("A")
        self._create("B", is_default=True)
        self.assertFalse(self.user.addresses.get(pk=first).is_default)
        self.assertEqual(self.user.addresses.filter(is_default=True).count(), 1)

    def test_cannot_set_default_on_another_users_address(self):
        aid = self._create("Mine")
        thief = APIClient()
        thief.force_authenticate(self.other)
        self.assertEqual(
            thief.post(f"/api/v1/addresses/{aid}/default", {},
                       format="json").status_code, 404)

    # ── list scoping ──
    def test_list_only_returns_your_own_addresses(self):
        self._create("Mine")
        other_client = APIClient()
        other_client.force_authenticate(self.other)
        other_client.post("/api/v1/addresses", {
            "name": "Theirs", "phone": "9000000000", "line1": "X",
            "pincode": "533005",
        }, format="json")

        rows = self.client.get("/api/v1/addresses").json()["data"]
        self.assertEqual([a["name"] for a in rows], ["Mine"])
