"""The store-PRIVATE category tree behind the customer Categories tab.

Covers the two things that make it safe: it shows only the serving store's OWN
products (never another store's, never the company-wide catalog), and every rail
tile leads somewhere — a category is listed only when private products live under
it, with a count that matches what the leaf grid will actually return.
"""
from django.test import TestCase

from accounts.models import Role, User
from catalog.models import Category, Product
from storeops.tests import _seq, client_for, mk_store


def _customer():
    return User.objects.create(
        phone=f"+91{9700000000 + next(_seq)}", name="Cust", role=Role.CUSTOMER
    )


def _enable_scoping():
    """The transitional ``?store=`` resolver (how these tests pin a serving store,
    standing in for the device's lat/lng) only applies once store visibility is on."""
    from system.models import FeatureFlag

    FeatureFlag.objects.update_or_create(
        key="zone_store_visibility", defaults={"enabled": True}
    )


def _payload(response):
    """The list rows, whichever envelope the renderer used."""
    body = response.json()
    data = body.get("data", body) if isinstance(body, dict) else body
    if isinstance(data, dict):
        data = data.get("results", data.get("items", []))
    return data


class StoreCategoryTreeTests(TestCase):
    def setUp(self):
        _enable_scoping()
        self.store = mk_store()
        self.other = mk_store()
        self.cust = client_for(_customer())
        # Grocery ▸ Staples ▸ Flour, plus an empty Electronics department.
        self.grocery = Category.objects.create(
            name="Grocery", slug=f"grocery-{next(_seq)}"
        )
        self.staples = Category.objects.create(
            name="Staples", slug=f"staples-{next(_seq)}", parent=self.grocery
        )
        self.flour = Category.objects.create(
            name="Flour", slug=f"flour-{next(_seq)}", parent=self.staples
        )
        self.electronics = Category.objects.create(
            name="Electronics", slug=f"elec-{next(_seq)}"
        )

    def _product(self, name, category, store):
        p = Product.objects.create(
            name=name, price=50, mrp=60, category=category, origin_store=store
        )
        from stores.models import StoreProduct

        if store is not None:
            StoreProduct.objects.create(store=store, product=p, is_available=True)
        return p

    def _levels(self, parent=None):
        url = f"/api/v1/store-categories?store={self.store.id}"
        if parent is not None:
            url += f"&parent={parent}"
        r = self.client.get(url)
        self.assertEqual(r.status_code, 200, r.content[:400])
        return _payload(r)

    # ── the tree itself ──────────────────────────────────────────────

    def test_top_level_shows_only_departments_holding_private_products(self):
        self._product("Atta", self.flour, self.store)
        names = [c["name"] for c in self._levels()]
        # Grocery surfaces because a product sits three levels beneath it …
        self.assertEqual(names, ["Grocery"])
        # … and Electronics, which holds nothing, is not offered as a dead end.
        self.assertNotIn("Electronics", names)

    def test_drill_down_repeats_a_level_at_a_time(self):
        self._product("Atta", self.flour, self.store)
        [grocery] = self._levels()
        self.assertTrue(grocery["hasChildren"])

        [staples] = self._levels(parent=grocery["id"])
        self.assertEqual(staples["name"], "Staples")
        self.assertTrue(staples["hasChildren"])

        [flour] = self._levels(parent=staples["id"])
        self.assertEqual(flour["name"], "Flour")
        # Leaf: the app opens the product grid here instead of another rail.
        self.assertFalse(flour["hasChildren"])
        self.assertEqual(self._levels(parent=flour["id"]), [])

    def test_count_is_the_whole_subtree(self):
        self._product("Atta", self.flour, self.store)
        self._product("Rice", self.staples, self.store)
        [grocery] = self._levels()
        self.assertEqual(grocery["productCount"], 2)
        [staples] = self._levels(parent=grocery["id"])
        self.assertEqual(staples["productCount"], 2)
        [flour] = self._levels(parent=staples["id"])
        self.assertEqual(flour["productCount"], 1)

    # ── isolation ────────────────────────────────────────────────────

    def test_another_stores_private_products_are_invisible(self):
        self._product("Their Atta", self.flour, self.other)
        self.assertEqual(self._levels(), [])

    def test_company_wide_products_do_not_enter_the_private_tree(self):
        # origin_store NULL = a shared catalog product. The tab is store-private,
        # so it must not pull the company catalog in.
        self._product("Shared Salt", self.flour, None)
        self.assertEqual(self._levels(), [])

    def test_no_serving_store_yields_an_empty_tree_not_the_global_catalog(self):
        self._product("Atta", self.flour, self.store)
        r = self.client.get("/api/v1/store-categories")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(_payload(r), [])

    def test_category_borrows_a_product_photo_when_it_has_no_image(self):
        # Store-created categories rarely have artwork; every tile should still show
        # a real picture instead of a wall of identical fallback icons.
        p = self._product("Atta", self.flour, self.store)
        Product.objects.filter(pk=p.pk).update(image_url="https://cdn/atta.webp")
        [grocery] = self._levels()
        self.assertEqual(grocery["imageUrl"], "https://cdn/atta.webp")
        [staples] = self._levels(parent=grocery["id"])
        self.assertEqual(staples["imageUrl"], "https://cdn/atta.webp")

    def test_curated_category_image_beats_the_borrowed_one(self):
        p = self._product("Atta", self.flour, self.store)
        Product.objects.filter(pk=p.pk).update(image_url="https://cdn/atta.webp")
        Category.objects.filter(pk=self.grocery.pk).update(
            image_url="https://cdn/grocery.webp"
        )
        [grocery] = self._levels()
        self.assertEqual(grocery["imageUrl"], "https://cdn/grocery.webp")

    def test_hidden_product_leaves_no_phantom_category(self):
        from stores.models import StoreProduct

        p = self._product("Atta", self.flour, self.store)
        StoreProduct.objects.filter(store=self.store, product=p).update(
            is_available=False
        )
        self.assertEqual(self._levels(), [])


class PrivateProductScopeTests(TestCase):
    """``/products?scope=private`` — the leaf grid the tree drills into."""

    def setUp(self):
        self.store = mk_store()
        self.other = mk_store()
        self.cat = Category.objects.create(name="Flour", slug=f"f-{next(_seq)}")
        self.cust = client_for(_customer())

    def _product(self, name, store):
        p = Product.objects.create(
            name=name, price=50, mrp=60, category=self.cat, origin_store=store
        )
        if store is not None:
            from stores.models import StoreProduct

            StoreProduct.objects.create(store=store, product=p, is_available=True)
        return p

    def _names(self, url):
        r = self.client.get(url)
        self.assertEqual(r.status_code, 200, r.content[:400])
        return [p["name"] for p in _payload(r)]

    def test_returns_only_the_serving_stores_own_products(self):
        _enable_scoping()
        self._product("Mine", self.store)
        self._product("Theirs", self.other)
        self._product("Shared", None)
        names = self._names(f"/api/v1/products?scope=private&store={self.store.id}")
        self.assertEqual(names, ["Mine"])

    def test_without_scope_the_global_catalog_is_unchanged(self):
        # Regression guard: the private branch must not alter default browsing.
        self._product("Shared", None)
        self.assertIn("Shared", self._names("/api/v1/products"))

    def test_no_store_resolves_to_empty_not_the_global_catalog(self):
        self._product("Shared", None)
        self._product("Mine", self.store)
        self.assertEqual(self._names("/api/v1/products?scope=private"), [])


class ShareTokenInListPayloadTests(TestCase):
    """Every card that can be shared must carry the unguessable token, not just the
    detail screen — otherwise the share sheet falls back to the sequential id."""

    def test_list_rows_carry_share_token(self):
        cat = Category.objects.create(name="Flour", slug=f"f-{next(_seq)}")
        p = Product.objects.create(name="Atta", price=50, mrp=60, category=cat)
        rows = _payload(self.client.get("/api/v1/products"))
        row = next(r for r in rows if r["name"] == "Atta")
        self.assertEqual(row["shareToken"], p.share_token)
        self.assertTrue(p.share_token)

    def test_search_rows_carry_share_token(self):
        cat = Category.objects.create(name="Flour", slug=f"f-{next(_seq)}")
        Product.objects.create(name="Atta", price=50, mrp=60, category=cat)
        rows = _payload(self.client.get("/api/v1/products/search?q=Atta"))
        self.assertTrue(rows[0]["shareToken"])
