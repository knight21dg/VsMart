"""Regression: a product added in the store panel is store-PRIVATE (origin_store),
so it reaches customers only through the store-scoped catalog path — visible to a
customer resolved to that store, hidden from other stores' customers, and (by
design) absent from the flag-off global catalog.

Guards the fix for the "product added in store panel 404s / doesn't show in the
app" report: the store panel and the customer catalog must agree on visibility
once zone_store_visibility is on.
"""
import json

from django.test import TestCase

from accounts.models import Role, User
from catalog.models import Category
from system.models import FeatureFlag

from .tests import _data, _seq, client_for, mk_staff, mk_store


def _customer():
    return User.objects.create(
        phone=f"+91{9600000000 + next(_seq)}", name="Cust", role=Role.CUSTOMER
    )


class StorePanelProductVisibilityTests(TestCase):
    def setUp(self):
        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, role="manager"))
        self.dept = Category.objects.create(name="Grocery", slug=f"grocery-{next(_seq)}")
        self.cust = client_for(_customer())

    def _add_product(self, name="Panel Atta"):
        body = {
            "categoryId": str(self.dept.id), "name": name, "brand": "B",
            "unit": "1 kg", "price": "55", "mrp": "60", "images": [],
            "barcode": "", "variants": [], "openingStock": "20", "reorderLevel": "5",
        }
        r = self.mgr.post("/api/v1/store/inventory/products", body, format="json")
        self.assertIn(r.status_code, (200, 201), r.content[:500])
        return _data(r)["productId"]

    def _enable_scoping(self):
        FeatureFlag.objects.update_or_create(
            key="zone_store_visibility", defaults={"enabled": True}
        )

    def test_store_panel_lists_its_own_new_product(self):
        self._add_product("Panel Atta")
        inv = self.mgr.get("/api/v1/store/inventory")
        self.assertEqual(inv.status_code, 200)
        self.assertIn("Panel Atta", json.dumps(inv.json(), default=str))

    def test_visible_in_global_catalog_when_unscoped(self):
        # No zone drawn / flag off (the launch reality): a store-added product is
        # visible in the global catalog and openable, so it works immediately.
        pid = self._add_product("Panel Atta")
        lst = self.cust.get("/api/v1/products")
        self.assertEqual(lst.status_code, 200)
        self.assertIn("Panel Atta", json.dumps(lst.json(), default=str))
        det = self.cust.get(f"/api/v1/products/{pid}")
        self.assertEqual(det.status_code, 200)

    def test_visible_to_customer_resolved_to_that_store(self):
        self._enable_scoping()
        pid = self._add_product("Panel Atta")
        # `?store=` is the transitional resolver for a real active store.
        lst = self.cust.get(f"/api/v1/products?store={self.store.id}")
        self.assertEqual(lst.status_code, 200)
        self.assertIn("Panel Atta", json.dumps(lst.json(), default=str))
        det = self.cust.get(f"/api/v1/products/{pid}?store={self.store.id}")
        self.assertEqual(det.status_code, 200)

    def test_hidden_from_a_different_stores_customer(self):
        self._enable_scoping()
        pid = self._add_product("Panel Atta")
        other = mk_store()
        lst = self.cust.get(f"/api/v1/products?store={other.id}")
        self.assertNotIn("Panel Atta", json.dumps(lst.json(), default=str))
        det = self.cust.get(f"/api/v1/products/{pid}?store={other.id}")
        self.assertEqual(det.status_code, 404)

    def test_store_product_id_is_not_guessable_but_token_shares(self):
        # Zone scoping on: a store-private product's SEQUENTIAL id can't be opened
        # without a resolved store (no enumeration) …
        from catalog.models import Product

        self._enable_scoping()
        pid = self._add_product("Panel Atta")
        by_id = self.cust.get(f"/api/v1/products/{pid}")
        self.assertEqual(by_id.status_code, 404)

        # … but the unguessable share_token opens it for anyone with the link.
        token = Product.objects.get(id=pid).share_token
        self.assertTrue(token)
        by_token = self.cust.get(f"/api/v1/products/{token}")
        self.assertEqual(by_token.status_code, 200)
        self.assertEqual(_data(by_token)["shareToken"], token)

    def test_detail_scoped_to_resolved_store_still_404s_cross_store(self):
        # And WHEN a store resolves, a cross-store deep link by id is still hidden.
        self._enable_scoping()
        pid = self._add_product("Panel Atta")
        other = mk_store()
        det = self.cust.get(f"/api/v1/products/{pid}?store={other.id}")
        self.assertEqual(det.status_code, 404)
