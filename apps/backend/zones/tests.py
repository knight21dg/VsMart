from decimal import Decimal

from django.test import TestCase

from stores.models import Store
from zones.models import Zone
from zones.serviceability import point_in_polygon, serviceability

# A square over central Bengaluru ([lng, lat] per GeoJSON).
SQUARE = {
    "type": "Polygon",
    "coordinates": [[
        [77.55, 12.95], [77.65, 12.95], [77.65, 13.00],
        [77.55, 13.00], [77.55, 12.95],
    ]],
}


class PointInPolygonTests(TestCase):
    def test_inside(self):
        self.assertTrue(point_in_polygon(77.60, 12.97, SQUARE))

    def test_outside(self):
        self.assertFalse(point_in_polygon(78.50, 13.50, SQUARE))

    def test_feature_wrapper(self):
        feature = {"type": "Feature", "properties": {}, "geometry": SQUARE}
        self.assertTrue(point_in_polygon(77.60, 12.97, feature))

    def test_hole_is_not_serviceable(self):
        with_hole = {
            "type": "Polygon",
            "coordinates": [
                SQUARE["coordinates"][0],
                # a small hole around (77.60, 12.975)
                [[77.595, 12.97], [77.605, 12.97], [77.605, 12.98],
                 [77.595, 12.98], [77.595, 12.97]],
            ],
        }
        self.assertFalse(point_in_polygon(77.60, 12.975, with_hole))
        self.assertTrue(point_in_polygon(77.56, 12.96, with_hole))


class ServiceabilityTests(TestCase):
    def setUp(self):
        self.store = Store.objects.create(
            code="S1", name="Central Store", status=Store.Status.ACTIVE,
        )
        self.zone = Zone.objects.create(
            code="Z1", name="Central", polygon_geojson=SQUARE, store=self.store,
            is_active=True, credit_enabled=True, estimated_delivery_minutes=18,
            priority=5, delivery_fee=Decimal("12.00"), min_order=Decimal("99.00"),
            free_delivery_threshold=Decimal("199.00"),
        )

    def test_serviceable_point_returns_zone_and_store(self):
        r = serviceability(lat=12.97, lng=77.60)
        self.assertTrue(r["serviceable"])
        self.assertEqual(r["zone_name"], "Central")
        self.assertEqual(r["store_name"], "Central Store")
        self.assertTrue(r["credit_available"])
        self.assertEqual(r["estimated_delivery_time"], 18)
        self.assertEqual(str(r["delivery_fee"]), "12.00")

    def test_unserviceable_point(self):
        r = serviceability(lat=13.50, lng=78.50)
        self.assertFalse(r["serviceable"])
        self.assertIsNone(r["store_id"])

    def test_credit_disabled_zone(self):
        self.zone.credit_enabled = False
        self.zone.save(update_fields=["credit_enabled"])
        r = serviceability(lat=12.97, lng=77.60)
        self.assertTrue(r["serviceable"])
        self.assertFalse(r["credit_available"])

    def test_inactive_store_makes_the_zone_unserviceable(self):
        """REVERSED (2026-07-21): this used to assert `serviceable: True` with a
        null store.

        That combination is not servable — no store means no catalog and no
        fulfilment. The app took `serviceable: True` as permission to unlock the
        storefront, then every catalog call resolved no store and returned an
        EMPTY set: a working-looking app with nothing in it and no explanation.
        Reporting it honestly routes the customer to the not-serviceable screen,
        which offers change-location and notify-me.
        """
        self.store.status = Store.Status.INACTIVE
        self.store.save(update_fields=["status"])
        r = serviceability(lat=12.97, lng=77.60)
        self.assertFalse(r["serviceable"])
        self.assertIsNone(r["store_id"])
        # The zone is still identified, so the UI can name the area.
        self.assertEqual(r["zone_name"], "Central")

    def test_serviceable_point_carries_the_stores_phone(self):
        self.store.phone = "+919876543210"
        self.store.save(update_fields=["phone"])
        r = serviceability(lat=12.97, lng=77.60)
        self.assertEqual(r["store_phone"], "+919876543210")

    def test_store_phone_is_none_when_store_has_none_set(self):
        r = serviceability(lat=12.97, lng=77.60)
        self.assertIsNone(r["store_phone"])

    def test_priority_breaks_overlap(self):
        # A second, lower-priority zone covering the same point.
        other_store = Store.objects.create(code="S2", name="Other Store")
        Zone.objects.create(
            code="Z2", name="Overlap", polygon_geojson=SQUARE, store=other_store,
            is_active=True, priority=1,
        )
        r = serviceability(lat=12.97, lng=77.60)
        self.assertEqual(r["zone_name"], "Central")  # priority 5 > 1


class AdminZoneOpsTests(TestCase):
    """Z4 backend — Store-Admin zone operations (agent assignment + density stats)."""

    def setUp(self):
        from rest_framework.test import APIClient

        from accounts.models import User
        from zones.models import Zone

        self.admin = User.objects.create(
            phone="+919888888001", name="Admin", role="admin",
        )
        self.agent = User.objects.create(
            phone="+919777777001", name="Agent", role="agent",
        )
        self.zone = Zone.objects.create(code="Z1", name="Central", is_active=True)
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_assign_and_list_agent(self):
        r = self.client.post(
            f"/api/v1/admin/zones/{self.zone.id}/agents",
            {"agentId": str(self.agent.id)}, format="json",
        )
        self.assertEqual(r.status_code, 201)
        from zones.models import ZoneAgent, ZoneEvent

        self.assertTrue(ZoneAgent.objects.filter(zone=self.zone, agent=self.agent).exists())
        self.assertTrue(ZoneEvent.objects.filter(type="agent_assigned").exists())

        listed = self.client.get(f"/api/v1/admin/zones/{self.zone.id}/agents")
        names = {a["name"] for a in listed.json()["data"]}
        self.assertIn("Agent", names)

    def test_unassign_agent(self):
        from zones.models import ZoneAgent

        ZoneAgent.objects.create(zone=self.zone, agent=self.agent)
        r = self.client.delete(
            f"/api/v1/admin/zones/{self.zone.id}/agents/{self.agent.id}"
        )
        self.assertEqual(r.status_code, 204)
        self.assertFalse(
            ZoneAgent.objects.filter(zone=self.zone, agent=self.agent).exists()
        )

    def test_zone_stats(self):
        r = self.client.get("/api/v1/admin/zones/stats")
        self.assertEqual(r.status_code, 200)
        rows = r.json()["data"]
        self.assertTrue(any(row["zoneName"] == "Central" for row in rows))


class AdminStoreCreateTests(TestCase):
    """Store onboarding: auto-provisions the backing warehouse (the store IS its own
    warehouse) and binds the serving zone passed from the store form."""

    def setUp(self):
        from rest_framework.test import APIClient

        from accounts.models import User
        from zones.models import Zone

        self.super = User.objects.create(phone="+919000000001", name="Super", role="superadmin")
        self.zone = Zone.objects.create(code="ZN1", name="North", is_active=True)
        self.client = APIClient()
        self.client.force_authenticate(self.super)

    def test_create_store_provisions_warehouse_and_links_zone(self):
        from zones.models import Zone, ZoneEvent

        r = self.client.post(
            "/api/v1/admin/stores",
            {"code": "S1", "name": "North Store", "zone": str(self.zone.id)},
            format="json",
        )
        self.assertEqual(r.status_code, 201, r.content)
        store_id = r.json()["data"]["id"]

        from stores.models import Store

        store = Store.objects.get(pk=store_id)
        # Store owns its inventory — a warehouse is auto-provisioned, no operator input.
        self.assertIsNotNone(store.warehouse_id)
        # The serving zone now routes to this store.
        self.zone.refresh_from_db()
        self.assertEqual(self.zone.store_id, store.id)
        self.assertTrue(ZoneEvent.objects.filter(type="store_assigned").exists())

    def test_create_store_without_zone_is_ok(self):
        r = self.client.post(
            "/api/v1/admin/stores",
            {"code": "S2", "name": "Lone Store"},
            format="json",
        )
        self.assertEqual(r.status_code, 201, r.content)
        from zones.models import Zone

        self.zone.refresh_from_db()
        self.assertIsNone(self.zone.store_id)


class ZoneStoreDeletionContractTests(TestCase):
    """Deleting a zone or a store.

    Two things were wrong here. The response was a bare ``204 No Content``, which
    the web console's fetch client could not read at all (a 204 is a null-body
    status, so ``res.json()`` rejected and a *successful* delete surfaced as
    "Empty response from server." with no cache invalidation). And the outcome is
    conditional — anything with trading history is deactivated, not deleted — so
    a 204 could not tell the operator which of the two they had just done.
    """

    def setUp(self):
        from rest_framework.test import APIClient

        from accounts.models import User

        self.super = User.objects.create(
            phone="+919000000501", name="Super", role="superadmin"
        )
        self.client = APIClient()
        self.client.force_authenticate(self.super)

    # ── zones ──
    def test_unused_zone_is_really_deleted_and_says_so(self):
        zone = Zone.objects.create(code="ZD1", name="Kakinada", is_active=True)
        r = self.client.delete(f"/api/v1/admin/zones/{zone.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertTrue(body["success"])
        self.assertEqual(body["code"], "RECORD_DELETED")
        self.assertIn("deleted", body["message"].lower())
        self.assertFalse(Zone.objects.filter(pk=zone.pk).exists())

    def test_zone_with_orders_is_deactivated_not_deleted(self):
        from accounts.models import User
        from orders.models import Order

        zone = Zone.objects.create(code="ZD2", name="Traded", is_active=True)
        customer = User.objects.create(
            phone="+919000000502", name="Cust", role="customer"
        )
        Order.objects.create(user=customer, zone=zone)

        r = self.client.delete(f"/api/v1/admin/zones/{zone.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["code"], "RECORD_DEACTIVATED")
        zone.refresh_from_db()
        self.assertFalse(zone.is_active)
        # The order keeps its zone attribution — that is the whole point.
        self.assertEqual(Order.objects.filter(zone=zone).count(), 1)

    def test_duplicate_zone_name_is_refused_with_a_readable_message(self):
        Zone.objects.create(code="ZK1", name="Kakinada", is_active=True)
        r = self.client.post(
            "/api/v1/admin/zones",
            {"name": "  kakinada ", "code": "ZK2"},
            format="json",
        )
        self.assertEqual(r.status_code, 400, r.content)
        detail = str(r.json())
        self.assertIn("already exists", detail)
        self.assertEqual(Zone.objects.filter(name__iexact="kakinada").count(), 1)

    def test_blank_zone_codes_do_not_collide(self):
        """`code` is unique+nullable; a blank string is a value and collided."""
        for name in ("Alpha", "Beta"):
            r = self.client.post(
                "/api/v1/admin/zones", {"name": name, "code": ""}, format="json"
            )
            self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(Zone.objects.filter(code__isnull=True).count(), 2)

    def test_codeless_zone_can_still_be_edited(self):
        """`code` is nullable, so a zone without one has to stay editable.

        The console used to disable Save until a code was typed, which made every
        zone created without one permanently uneditable.
        """
        zone = Zone.objects.create(name="No Code", code=None)
        r = self.client.patch(
            f"/api/v1/admin/zones/{zone.id}",
            {"name": "No Code", "code": None, "delivery_fee": "15.00"},
            format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        zone.refresh_from_db()
        self.assertIsNone(zone.code)
        self.assertEqual(str(zone.delivery_fee), "15.00")

    def test_not_null_numeric_fields_must_be_omitted_not_nulled(self):
        """radius_km / priority / estimated_delivery_minutes are NOT NULL with DB
        defaults. Posting an explicit null 400s — the console has to leave a blank
        input out of the payload instead, which is what this pins down."""
        zone = Zone.objects.create(name="Numeric", code="ZN1")
        rejected = self.client.patch(
            f"/api/v1/admin/zones/{zone.id}", {"radius_km": None}, format="json"
        )
        self.assertEqual(rejected.status_code, 400, rejected.content)

        omitted = self.client.patch(
            f"/api/v1/admin/zones/{zone.id}",
            {"name": "Numeric", "delivery_fee": None},
            format="json",
        )
        self.assertEqual(omitted.status_code, 200, omitted.content)
        zone.refresh_from_db()
        # The nullable fee override really is nulled; the NOT NULL radius survives.
        self.assertIsNone(zone.delivery_fee)
        self.assertIsNotNone(zone.radius_km)

    # ── stores ──
    def test_unused_store_is_really_deleted_and_says_so(self):
        store = Store.objects.create(code="SD1", name="Fresh Store")
        r = self.client.delete(f"/api/v1/admin/stores/{store.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["code"], "RECORD_DELETED")
        self.assertFalse(Store.objects.filter(pk=store.pk).exists())

    def test_store_with_orders_is_deactivated_and_reported_as_such(self):
        from accounts.models import User
        from orders.models import Order

        store = Store.objects.create(code="SD2", name="Busy Store")
        customer = User.objects.create(
            phone="+919000000503", name="Cust2", role="customer"
        )
        Order.objects.create(user=customer, store=store)

        r = self.client.delete(f"/api/v1/admin/stores/{store.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["code"], "RECORD_DEACTIVATED")
        self.assertIn("deactivated", body["message"].lower())
        store.refresh_from_db()
        self.assertEqual(store.status, Store.Status.INACTIVE)
        self.assertFalse(store.accepting_orders)

    def test_duplicate_store_code_names_the_owner(self):
        Store.objects.create(code="DUP", name="First Store")
        r = self.client.post(
            "/api/v1/admin/stores", {"code": "dup", "name": "Second"}, format="json"
        )
        self.assertEqual(r.status_code, 400, r.content)
        self.assertIn("First Store", str(r.json()))
