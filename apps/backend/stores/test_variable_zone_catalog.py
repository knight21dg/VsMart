"""Variable-zone catalog scoping: a customer's SELECTED LOCATION resolves the
serving store from its zone polygon, and the catalog returns ONLY that store's
products — driven by location, and active even with the global
``zone_store_visibility`` flag OFF (it lights up per area as zones are drawn).

Also guards that areas with no zone drawn keep the global catalog (no blackout)
and that the transitional ``?store=`` param stays global while the flag is off.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Category, Product
from inventory.models import StockItem, Warehouse
from stores.models import Store
from system.models import FeatureFlag
from zones.models import Zone

# A square zone over central Bengaluru ([lng, lat] per GeoJSON).
SQUARE = {
    "type": "Polygon",
    "coordinates": [[
        [77.55, 12.95], [77.65, 12.95], [77.65, 13.00],
        [77.55, 13.00], [77.55, 12.95],
    ]],
}
# A point inside SQUARE, and one far outside it.
IN = {"lat": "12.97", "lng": "77.60"}
OUT = {"lat": "13.50", "lng": "78.50"}


class VariableZoneCatalogTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.cat = Category.objects.create(name="Grocery")
        # Store A (in-zone) with its own warehouse + one carried product.
        self.wh_a = Warehouse.objects.create(code="WA", name="WHA")
        self.store_a = Store.objects.create(
            code="SA", name="Central Store", warehouse=self.wh_a,
            status=Store.Status.ACTIVE,
        )
        self.zone = Zone.objects.create(
            code="ZA", name="Central", polygon_geojson=SQUARE, store=self.store_a,
            is_active=True, priority=5,
        )
        self.a_rice = self._product("Store A Rice")
        StockItem.objects.create(product=self.a_rice, warehouse=self.wh_a, quantity=20)

        # A different store's product (must NOT appear for an in-zone Store-A customer).
        self.wh_b = Warehouse.objects.create(code="WB", name="WHB")
        self.store_b = Store.objects.create(
            code="SB", name="Other Store", warehouse=self.wh_b,
            status=Store.Status.ACTIVE,
        )
        self.b_oil = self._product("Store B Oil")
        StockItem.objects.create(product=self.b_oil, warehouse=self.wh_b, quantity=20)

    def _product(self, name):
        return Product.objects.create(
            name=name, price=Decimal("50"), mrp=Decimal("60"), category=self.cat,
        )

    def _names(self, resp):
        data = resp.json()["data"]
        items = data["results"] if isinstance(data, dict) else data
        return {p["name"] for p in items}

    def test_in_zone_location_scopes_to_that_store_flag_off(self):
        # THE feature: selected location inside Store A's zone → only Store A's
        # catalog, with NO global flag set.
        self.assertFalse(FeatureFlag.objects.filter(key="zone_store_visibility").exists())
        names = self._names(self.client.get("/api/v1/products", IN))
        self.assertIn("Store A Rice", names)
        self.assertNotIn("Store B Oil", names)

    def test_in_zone_detail_of_other_store_product_is_404(self):
        det_a = self.client.get(f"/api/v1/products/{self.a_rice.id}", IN)
        self.assertEqual(det_a.status_code, 200)
        det_b = self.client.get(f"/api/v1/products/{self.b_oil.id}", IN)
        self.assertEqual(det_b.status_code, 404)

    def test_unzoned_location_keeps_global_catalog_flag_off(self):
        # Out-of-any-zone point, flag off → global catalog (NEVER blank).
        names = self._names(self.client.get("/api/v1/products", OUT))
        self.assertIn("Store A Rice", names)
        self.assertIn("Store B Oil", names)

    def test_no_location_keeps_global_catalog_flag_off(self):
        names = self._names(self.client.get("/api/v1/products"))
        self.assertEqual(names, {"Store A Rice", "Store B Oil"})

    def test_store_param_still_global_when_flag_off(self):
        # Back-compat: the transitional ?store= param does NOT scope while flag off.
        names = self._names(self.client.get("/api/v1/products", {"store": self.store_a.id}))
        self.assertIn("Store A Rice", names)
        self.assertIn("Store B Oil", names)

    def test_search_is_scoped_by_in_zone_location(self):
        names = self._names(
            self.client.get("/api/v1/products/search", {"q": "Store", **IN})
        )
        self.assertIn("Store A Rice", names)
        self.assertNotIn("Store B Oil", names)
