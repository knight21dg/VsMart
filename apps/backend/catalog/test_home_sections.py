"""Admin-curated home rails, with the algorithmic ordering as a fallback.

"Today's Deals" and "Popular Products" were hardcoded `/products?sort=…` calls
in the Flutter app, so nothing in the console could influence the customer front
page. Curation is deliberately *additive*: an uncurated rail must behave exactly
as it did before, or every existing install changes the day this ships.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, HomeFeature, Product


class HomeSectionTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(
            phone="+919000000801", name="Admin", role="admin"
        )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)
        self.public = APIClient()
        self.category, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")

        # review_count drives the "popular" fallback ordering.
        self.top = self._product("Top Reviewed", reviews=500)
        self.mid = self._product("Mid Reviewed", reviews=50)
        self.low = self._product("Low Reviewed", reviews=1)

    def _product(self, name, *, reviews=0, price="100", mrp="120", active=True):
        return Product.objects.create(
            name=name, brand="VS", unit="1", price=Decimal(price), mrp=Decimal(mrp),
            category=self.category, review_count=reviews, is_active=active,
            stock_count=None,
        )

    def _rail(self, section="popular"):
        r = self.public.get(f"/api/v1/home/sections/{section}")
        self.assertEqual(r.status_code, 200, r.content)
        return r.json()

    # ── fallback behaviour ──
    def test_uncurated_rail_keeps_the_algorithmic_order(self):
        body = self._rail("popular")
        names = [p["name"] for p in body["data"]]
        self.assertEqual(names[:3], ["Top Reviewed", "Mid Reviewed", "Low Reviewed"])
        self.assertFalse(body["meta"]["curated"])

    def test_archived_products_never_reach_a_rail(self):
        self._product("Archived", reviews=9999, active=False)
        names = [p["name"] for p in self._rail("popular")["data"]]
        self.assertNotIn("Archived", names)

    def test_todays_deals_falls_back_to_biggest_markdown(self):
        self._product("Half Price", price="50", mrp="100")
        names = [p["name"] for p in self._rail("today_deals")["data"]]
        self.assertEqual(names[0], "Half Price")

    def test_unknown_section_is_a_400_not_a_500(self):
        self.assertEqual(
            self.public.get("/api/v1/home/sections/nonsense").status_code, 400
        )

    def test_section_catalogue_lists_every_rail(self):
        r = self.public.get("/api/v1/home/sections")
        self.assertEqual(r.status_code, 200)
        keys = {s["key"] for s in r.json()["data"]}
        self.assertEqual(keys, {"today_deals", "popular", "recommended", "top_selling"})

    # ── curation ──
    def test_a_pin_outranks_the_algorithm(self):
        HomeFeature.objects.create(section="popular", product=self.low, sort_order=1)
        body = self._rail("popular")
        self.assertEqual(body["data"][0]["name"], "Low Reviewed")
        self.assertTrue(body["meta"]["curated"])

    def test_pins_keep_the_curator_order(self):
        HomeFeature.objects.create(section="popular", product=self.mid, sort_order=1)
        HomeFeature.objects.create(section="popular", product=self.top, sort_order=2)
        names = [p["name"] for p in self._rail("popular")["data"]]
        self.assertEqual(names[:2], ["Mid Reviewed", "Top Reviewed"])

    def test_a_thin_rail_tops_up_from_the_algorithm(self):
        """One pin must not collapse the rail to a single card."""
        HomeFeature.objects.create(section="popular", product=self.low, sort_order=1)
        names = [p["name"] for p in self._rail("popular")["data"]]
        self.assertEqual(names[0], "Low Reviewed")
        self.assertIn("Top Reviewed", names)
        self.assertEqual(len(names), len(set(names)))  # the pin isn't repeated

    def test_an_inactive_pin_is_ignored(self):
        HomeFeature.objects.create(
            section="popular", product=self.low, sort_order=1, is_active=False
        )
        body = self._rail("popular")
        self.assertFalse(body["meta"]["curated"])
        self.assertEqual(body["data"][0]["name"], "Top Reviewed")

    def test_pinning_one_rail_does_not_affect_another(self):
        HomeFeature.objects.create(section="popular", product=self.low, sort_order=1)
        self.assertEqual(
            self._rail("recommended")["meta"]["curated"], False
        )

    # ── admin CRUD ──
    def _pin(self, section, product):
        return self.client.post(
            "/api/v1/admin/catalog/home-sections",
            {"section": section, "productId": product.id},
            format="json",
        )

    def test_admin_can_pin_reorder_and_unpin(self):
        first = self._pin("today_deals", self.top)
        second = self._pin("today_deals", self.mid)
        self.assertEqual(first.status_code, 201, first.content)
        self.assertEqual(second.status_code, 201, second.content)
        a, b = first.json()["data"]["id"], second.json()["data"]["id"]

        # Appended in click order without the caller supplying sortOrder.
        self.assertEqual(
            [p["name"] for p in self._rail("today_deals")["data"]][:2],
            ["Top Reviewed", "Mid Reviewed"],
        )

        reorder = self.client.post(
            "/api/v1/admin/catalog/home-sections/reorder",
            {"section": "today_deals", "ids": [b, a]},
            format="json",
        )
        self.assertEqual(reorder.status_code, 200, reorder.content)
        self.assertEqual(
            [row["productName"] for row in reorder.json()["data"]],
            ["Mid Reviewed", "Top Reviewed"],
        )
        self.assertEqual(
            [p["name"] for p in self._rail("today_deals")["data"]][:2],
            ["Mid Reviewed", "Top Reviewed"],
        )

        gone = self.client.delete(f"/api/v1/admin/catalog/home-sections/{a}")
        self.assertEqual(gone.status_code, 200, gone.content)
        self.assertEqual(gone.json()["code"], "RECORD_DELETED")
        self.assertIn("Top Reviewed", gone.json()["message"])
        self.assertEqual(HomeFeature.objects.filter(section="today_deals").count(), 1)

    def test_admin_get_returns_every_rail_in_one_call(self):
        self._pin("popular", self.top)
        r = self.client.get("/api/v1/admin/catalog/home-sections")
        self.assertEqual(r.status_code, 200, r.content)
        rails = {row["section"]: row["items"] for row in r.json()["data"]}
        self.assertEqual(len(rails["popular"]), 1)
        self.assertEqual(rails["recommended"], [])

    def test_multi_word_section_codes_survive_the_camelcase_renderer(self):
        """Section codes are DATA, so they must not be dict keys.

        Keyed by section, `today_deals`/`top_selling` came off the renderer as
        `todayDeals`/`topSelling`. The console looks rails up by their code (from
        /home/sections, where the code sits in a value and is untouched), so those
        two rails always read as empty — whatever was pinned to Today's Deals was
        invisible and could not be reordered or removed. Single-word codes like
        `popular` came through unchanged, which is why this hid for so long.
        """
        self._pin("today_deals", self.top)
        self._pin("top_selling", self.mid)
        r = self.client.get("/api/v1/admin/catalog/home-sections")
        rails = {row["section"]: row["items"] for row in r.json()["data"]}

        self.assertIn("today_deals", rails)
        self.assertIn("top_selling", rails)
        self.assertNotIn("todayDeals", rails)
        self.assertNotIn("topSelling", rails)
        self.assertEqual([i["productName"] for i in rails["today_deals"]], ["Top Reviewed"])
        self.assertEqual([i["productName"] for i in rails["top_selling"]], ["Mid Reviewed"])
        # Every rail is present so the console can render all four cards.
        self.assertEqual(len(rails), 4)

    def test_the_picker_search_matches_name_brand_and_sku(self):
        """The picker searches this endpoint. Name-only matching meant a product
        the operator could see in Catalog was unfindable by its shelf code."""
        needle = self._product("Sharbati Wheat Flour")
        needle.brand = "Aashirvaad"
        needle.sku = "ATTA-5KG"
        needle.save(update_fields=["brand", "sku"])

        for term in ("wheat", "aashirvaad", "ATTA-5KG", "atta"):
            r = self.client.get("/api/v1/admin/catalog/products", {"q": term})
            self.assertEqual(r.status_code, 200, r.content)
            names = [p["name"] for p in r.json()["data"]]
            self.assertIn("Sharbati Wheat Flour", names, f"q={term!r} found {names}")

    def test_the_picker_can_reach_store_added_products(self):
        """Store-added products are in the customer catalog (see
        `scope_catalog_queryset` — a store's product is sellable before any zone
        is drawn), so the rails already display them and the console has to be
        able to curate them. Default scope still shows the company master only,
        which is what the Catalog page edits."""
        from inventory.models import Warehouse
        from stores.models import Store

        warehouse = Warehouse.objects.create(name="W", code="W-HS", is_active=True)
        store = Store.objects.create(
            code="S-HS", name="VS Velangi", status="active",
            warehouse=warehouse, address="x", phone="1",
        )
        owned = self._product("Velangi Atta")
        owned.origin_store = store
        owned.save(update_fields=["origin_store"])

        default = self.client.get("/api/v1/admin/catalog/products", {"q": "Velangi"})
        self.assertEqual([p["name"] for p in default.json()["data"]], [])

        widened = self.client.get(
            "/api/v1/admin/catalog/products", {"q": "Velangi", "scope": "all"}
        )
        rows = widened.json()["data"]
        self.assertEqual([p["name"] for p in rows], ["Velangi Atta"])
        # Labelled with its owner so the curator knows the pin is store-limited.
        self.assertEqual(rows[0]["originStoreName"], "VS Velangi")

        pinned = self._pin("today_deals", owned)
        self.assertEqual(pinned.status_code, 201, pinned.content)
        self.assertEqual(
            pinned.json()["data"]["productOriginStoreName"], "VS Velangi"
        )

    def test_a_store_owned_pin_cannot_widen_another_store_rail(self):
        """Curation must never widen the caller's visibility. `section_products`
        intersects the pins with the already-scoped base, so a pin on a product
        the serving store doesn't carry is dropped rather than shown-unbuyable."""
        from catalog.home import section_products

        outsider = self._product("Someone Elses Stock")
        HomeFeature.objects.create(
            section="today_deals", product=outsider, sort_order=1
        )
        base = Product.objects.filter(is_active=True).exclude(pk=outsider.pk)
        self.assertNotIn(
            outsider, section_products("today_deals", base_queryset=base)
        )

    def test_the_picker_can_see_archived_products_so_it_can_explain_them(self):
        """Unfiltered search returns archived rows too — the console renders them
        blocked with the reason rather than dead-ending on "no results"."""
        self._product("Ghost Item", active=False)
        r = self.client.get("/api/v1/admin/catalog/products", {"q": "Ghost"})
        rows = r.json()["data"]
        self.assertEqual([p["name"] for p in rows], ["Ghost Item"])
        self.assertFalse(rows[0]["isActive"])
        # …and the API still refuses to feature it, which is what the UI mirrors.
        blocked = self._pin("popular", Product.objects.get(name="Ghost Item"))
        self.assertEqual(blocked.status_code, 400, blocked.content)

    def test_the_same_product_cannot_be_pinned_twice(self):
        self.assertEqual(self._pin("popular", self.top).status_code, 201)
        clash = self._pin("popular", self.top)
        self.assertEqual(clash.status_code, 409, clash.content)
        self.assertIn("already on this rail", clash.json()["message"])

    def test_an_archived_product_cannot_be_featured(self):
        dead = self._product("Dead", active=False)
        r = self._pin("popular", dead)
        self.assertEqual(r.status_code, 400, r.content)
        self.assertIn("archived", r.json()["message"].lower())

    def test_reorder_rejects_a_pin_from_another_rail(self):
        other = HomeFeature.objects.create(
            section="recommended", product=self.top, sort_order=1
        )
        r = self.client.post(
            "/api/v1/admin/catalog/home-sections/reorder",
            {"section": "popular", "ids": [other.id]},
            format="json",
        )
        self.assertEqual(r.status_code, 400, r.content)

    def test_curation_is_admin_only(self):
        shopper = APIClient()
        shopper.force_authenticate(
            User.objects.create(phone="+919000000802", name="Cust", role="customer")
        )
        r = shopper.post(
            "/api/v1/admin/catalog/home-sections",
            {"section": "popular", "productId": self.top.id},
            format="json",
        )
        self.assertEqual(r.status_code, 403, r.content)
