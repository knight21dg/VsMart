from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Category, Product
from inventory.models import StockItem, Warehouse
from stores.models import Store
from system.models import FeatureFlag


class StoreVisibilityTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.cat = Category.objects.create(name="Grocery")
        self.wh = Warehouse.objects.create(code="W1", name="WH1", is_default=True)
        self.store = Store.objects.create(
            code="S1", name="Store 1", warehouse=self.wh,
            status=Store.Status.ACTIVE,
        )
        self.carried = self._product("Stocked Rice")
        self.other = self._product("Unstocked Oil")
        # Only `carried` has on-hand in this store's warehouse.
        StockItem.objects.create(product=self.carried, warehouse=self.wh, quantity=10)
        StockItem.objects.create(product=self.other, warehouse=self.wh, quantity=0)

    def _product(self, name):
        return Product.objects.create(
            name=name, price=Decimal("50"), mrp=Decimal("60"), category=self.cat,
        )

    def _names(self, resp):
        data = resp.json()["data"]
        items = data["results"] if isinstance(data, dict) else data
        return {p["name"] for p in items}

    def test_flag_off_shows_all_products_even_with_store(self):
        # No flag → global catalog regardless of ?store=.
        resp = self.client.get("/api/v1/products", {"store": self.store.id})
        names = self._names(resp)
        self.assertIn("Stocked Rice", names)
        self.assertIn("Unstocked Oil", names)

    def test_flag_on_with_store_hides_unstocked(self):
        FeatureFlag.objects.create(key="zone_store_visibility", enabled=True)
        resp = self.client.get("/api/v1/products", {"store": self.store.id})
        names = self._names(resp)
        self.assertIn("Stocked Rice", names)
        self.assertNotIn("Unstocked Oil", names)

    def test_flag_on_without_resolvable_store_returns_empty(self):
        # Flag on + no location/address/store to resolve a serving store → EMPTY catalog
        # (NEVER the global list). A client must not be able to widen what it sees by
        # simply omitting the store, and an out-of-area customer sees nothing.
        FeatureFlag.objects.create(key="zone_store_visibility", enabled=True)
        resp = self.client.get("/api/v1/products")
        names = self._names(resp)
        self.assertEqual(names, set())

    def test_search_respects_store_visibility(self):
        FeatureFlag.objects.create(key="zone_store_visibility", enabled=True)
        resp = self.client.get(
            "/api/v1/products/search", {"q": "o", "store": self.store.id}
        )
        names = self._names(resp)
        self.assertNotIn("Unstocked Oil", names)


class StoreInventoryTests(TestCase):
    """E1 — damaged-stock tracking + the store-scoped inventory view."""

    def setUp(self):
        from inventory.models import InventoryLedger
        from inventory.services import InventoryService

        self.svc = InventoryService
        self.Type = InventoryLedger.Type
        self.cat = Category.objects.create(name="Grocery")
        self.wh = Warehouse.objects.create(code="W1", name="WH1", is_default=True)
        self.store = Store.objects.create(code="S1", name="Store 1", warehouse=self.wh)
        self.product = Product.objects.create(
            name="Milk", price=Decimal("30"), mrp=Decimal("35"), category=self.cat,
        )
        self.svc.post_movement(
            product=self.product, warehouse=self.wh, type=self.Type.GRN, quantity=50,
        )

    def test_damage_increments_damaged_bucket(self):
        self.svc.post_movement(
            product=self.product, warehouse=self.wh, type=self.Type.DAMAGE, quantity=-3,
        )
        item = StockItem.objects.get(product=self.product, warehouse=self.wh)
        self.assertEqual(item.damaged, 3)
        self.assertEqual(item.quantity, 47)  # on-hand reduced by the write-off

    def test_store_inventory_endpoint(self):
        from accounts.models import User

        self.svc.post_movement(
            product=self.product, warehouse=self.wh, type=self.Type.EXPIRY, quantity=-2,
        )
        admin = User.objects.create(phone="+919888888002", name="A", role="admin")
        client = APIClient()
        client.force_authenticate(admin)
        r = client.get(f"/api/v1/admin/stores/{self.store.id}/inventory")
        self.assertEqual(r.status_code, 200)
        rows = r.json()["data"]
        row = next(x for x in rows if x["name"] == "Milk")
        self.assertEqual(row["current"], 48)
        self.assertEqual(row["available"], 48)
        self.assertEqual(row["damaged"], 2)
