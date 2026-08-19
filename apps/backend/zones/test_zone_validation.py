"""An active zone must be resolvable, or it silently serves nobody.

A zone could be saved with no polygon, no radius circle and no pincodes. It listed
normally in the admin console and answered every serviceability check with
`serviceable: false` — which reads to an operator as "the app is broken in that
area", not "this zone is empty". DRF also drops unknown keys silently, so sending
`polygon` instead of `polygonGeojson` produced the same dead zone with a 201.
"""
from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import Role, User
from zones.models import Zone

SQUARE = {
    "type": "Polygon",
    "coordinates": [[
        [82.20, 16.93], [82.30, 16.93], [82.30, 17.02],
        [82.20, 17.02], [82.20, 16.93],
    ]],
}


class ActiveZoneNeedsAServiceAreaTests(TestCase):
    def setUp(self):
        self.su = User.objects.create(phone="+919999000111", name="SA",
                                      role=Role.SUPERADMIN)
        self.c = APIClient()
        self.c.force_authenticate(self.su)

    def _post(self, **body):
        return self.c.post("/api/v1/admin/zones", body, format="json")

    def test_active_zone_with_no_service_area_is_refused(self):
        r = self._post(name="Kakinada", code="KKD1", isActive=True)
        self.assertEqual(r.status_code, 400, r.data)
        self.assertFalse(Zone.objects.filter(code="KKD1").exists())

    def test_misspelled_polygon_key_is_refused_not_silently_dropped(self):
        """`polygon` is not a field — DRF discards it. That must not yield a 201."""
        r = self._post(name="Kakinada", code="KKD2", isActive=True, polygon=SQUARE)
        self.assertEqual(r.status_code, 400, r.data)
        self.assertFalse(Zone.objects.filter(code="KKD2").exists())

    def test_polygon_zone_is_accepted(self):
        r = self._post(name="Kakinada", code="KKD3", isActive=True,
                       polygonGeojson=SQUARE)
        self.assertEqual(r.status_code, 201, r.data)
        self.assertTrue(Zone.objects.get(code="KKD3").polygon_geojson)

    def test_radius_zone_is_accepted(self):
        r = self._post(name="Kakinada Radius", code="KKD4", isActive=True,
                       centerLat="16.97", centerLng="82.25", radiusKm="5")
        self.assertEqual(r.status_code, 201, r.data)

    def test_pincode_zone_is_accepted(self):
        r = self._post(name="Kakinada Pins", code="KKD5", isActive=True,
                       pincodes=["533001", "533003"])
        self.assertEqual(r.status_code, 201, r.data)

    def test_inactive_zone_may_be_a_stub(self):
        """A zone being drafted isn't serving anyone yet, so it can be incomplete."""
        r = self._post(name="Draft", code="KKD6", isActive=False)
        self.assertEqual(r.status_code, 201, r.data)

    def test_cannot_activate_a_zone_that_has_no_service_area(self):
        zone = Zone.objects.create(code="KKD7", name="Draft", is_active=False)
        r = self.c.patch(f"/api/v1/admin/zones/{zone.id}",
                         {"isActive": True}, format="json")
        self.assertEqual(r.status_code, 400, r.data)
        zone.refresh_from_db()
        self.assertFalse(zone.is_active)
