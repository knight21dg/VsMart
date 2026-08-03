"""System app tests — currently the Google-backed geo endpoints.

No live Google key is configured in tests, so these assert the graceful
degradation contract the app relies on (stable shape + a `source` flag) rather
than hitting Google. Routing + auth are exercised too.
"""
from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import Role, User


def _client():
    u = User.objects.create(phone="+919800000001", name="Geo Tester", role=Role.CUSTOMER)
    c = APIClient()
    c.force_authenticate(u)
    return c


class GeoPlacesTests(TestCase):
    def setUp(self):
        self.c = _client()

    def test_autocomplete_requires_auth(self):
        self.assertEqual(APIClient().get("/api/v1/geo/places/autocomplete?q=koramangala").status_code, 401)

    def test_autocomplete_short_query(self):
        r = self.c.get("/api/v1/geo/places/autocomplete?q=k")
        self.assertEqual(r.status_code, 200)
        body = r.json().get("data", r.json())
        self.assertEqual(body["predictions"], [])
        self.assertEqual(body["source"], "short")

    def test_autocomplete_no_key_degrades(self):
        # No google_maps_key configured in tests → empty list, no_key flag.
        r = self.c.get("/api/v1/geo/places/autocomplete?q=koramangala")
        self.assertEqual(r.status_code, 200)
        body = r.json().get("data", r.json())
        self.assertEqual(body["predictions"], [])
        self.assertEqual(body["source"], "no_key")

    def test_detail_missing_place_id(self):
        r = self.c.get("/api/v1/geo/places/detail")
        self.assertEqual(r.status_code, 200)
        body = r.json().get("data", r.json())
        self.assertIsNone(body["lat"])
        self.assertEqual(body["source"], "none")

    def test_detail_no_key_degrades(self):
        r = self.c.get("/api/v1/geo/places/detail?placeId=ChIJ_test")
        self.assertEqual(r.status_code, 200)
        body = r.json().get("data", r.json())
        self.assertIsNone(body["lat"])
        self.assertEqual(body["source"], "no_key")


class MapsServicesTests(TestCase):
    """Routing / ETA / address-validation / geolocate / roads proxies — assert the
    graceful-degradation contract (no live key in tests) + routing + auth."""

    def setUp(self):
        self.c = _client()

    def test_route_requires_auth(self):
        r = APIClient().get("/api/v1/geo/route?origin=12.9,77.6&dest=12.8,77.5")
        self.assertEqual(r.status_code, 401)

    def test_route_bad_args(self):
        body = self.c.get("/api/v1/geo/route?origin=abc").json()
        body = body.get("data", body)
        self.assertEqual(body["source"], "bad_args")

    def test_route_no_key_degrades(self):
        body = self.c.get("/api/v1/geo/route?origin=12.9,77.6&dest=12.8,77.5").json()
        body = body.get("data", body)
        self.assertEqual(body["source"], "no_key")
        self.assertEqual(body["encodedPolyline"], "")

    def test_distance_matrix_no_key(self):
        body = self.c.post("/api/v1/geo/distance-matrix",
                           {"origins": ["12.9,77.6"], "destinations": ["12.8,77.5"]},
                           format="json").json()
        body = body.get("data", body)
        self.assertEqual(body["source"], "no_key")

    def test_validate_address_no_key(self):
        body = self.c.post("/api/v1/geo/validate-address",
                           {"addressLines": ["12 MG Road"], "pincode": "560001"},
                           format="json").json()
        body = body.get("data", body)
        self.assertEqual(body["source"], "no_key")

    def test_geolocate_no_key(self):
        body = self.c.post("/api/v1/geo/geolocate", {}, format="json").json()
        body = body.get("data", body)
        self.assertEqual(body["source"], "no_key")

    def test_snap_to_roads_bad_args(self):
        body = self.c.post("/api/v1/geo/snap-to-roads", {"path": ["12.9,77.6"]},
                           format="json").json()
        body = body.get("data", body)
        self.assertEqual(body["source"], "bad_args")


class GlobalSearchTests(TestCase):
    """Multi-entity global search. Admins get navigable cross-entity rows; a
    customer must only ever see the product catalog."""

    def setUp(self):
        from catalog.models import Category, Product
        from orders.models import Order
        from stores.models import Store

        self.admin = User.objects.create(
            phone="+919800000010", name="Ops Admin", role=Role.ADMIN
        )
        self.customer = User.objects.create(
            phone="+919812345678", name="Ramesh Kumar", role=Role.CUSTOMER
        )
        cat = Category.objects.create(name="Staples")
        self.product = Product.objects.create(
            name="Sona Masoori Rice", sku="RICE-5KG", price=250, mrp=300, category=cat
        )
        self.store = Store.objects.create(code="BLR01", name="Koramangala Store")
        self.order = Order.objects.create(
            user=self.customer, payment_method=Order.PaymentMethod.COD, total=499
        )

        self.ac = APIClient()
        self.ac.force_authenticate(self.admin)
        self.cc = APIClient()
        self.cc.force_authenticate(self.customer)

    def _search(self, client, q):
        r = client.get("/api/v1/search/global", {"q": q})
        self.assertEqual(r.status_code, 200)
        body = r.json()
        return body.get("data", body)

    def test_requires_auth(self):
        self.assertEqual(
            APIClient().get("/api/v1/search/global?q=rice").status_code, 401
        )

    def test_rows_carry_navigable_href(self):
        rows = self._search(self.ac, "rice")["results"]
        self.assertTrue(rows)
        for row in rows:
            for key in ("type", "id", "label", "sublabel", "href"):
                self.assertIn(key, row)
            self.assertTrue(row["href"].startswith("/"))

    def test_finds_order_by_bare_code(self):
        rows = self._search(self.ac, self.order.code)["results"]
        orders = [r for r in rows if r["type"] == "order"]
        self.assertEqual(len(orders), 1)
        self.assertEqual(orders[0]["href"], f"/orders/{self.order.code}")

    def test_finds_customer_by_name_and_phone(self):
        by_name = self._search(self.ac, "ramesh")["results"]
        self.assertIn(
            f"/customers/{self.customer.id}", [r["href"] for r in by_name]
        )
        by_phone = self._search(self.ac, "9812345678")["results"]
        self.assertIn(
            f"/customers/{self.customer.id}", [r["href"] for r in by_phone]
        )

    def test_finds_product_and_store(self):
        rows = self._search(self.ac, "Sona")["results"]
        self.assertIn(f"/inventory/product/{self.product.id}", [r["href"] for r in rows])
        rows = self._search(self.ac, "Koramangala")["results"]
        self.assertIn(f"/stores/{self.store.id}/edit", [r["href"] for r in rows])

    def test_short_query_returns_nothing(self):
        self.assertEqual(self._search(self.ac, "r")["results"], [])

    def test_customer_gets_no_cross_entity_rows(self):
        body = self._search(self.cc, "ramesh")
        self.assertEqual(body["results"], [])
        # …but the legacy product search still works for them.
        self.assertEqual(self._search(self.cc, "Sona")["products"][0]["name"],
                         "Sona Masoori Rice")

    def test_short_digit_query_skips_phone_scan(self):
        # A 3-digit query must not `icontains`-match every phone number.
        rows = self._search(self.ac, "981")["results"]
        self.assertEqual([r for r in rows if r["type"] == "customer"], [])
