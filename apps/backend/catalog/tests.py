"""Tests for the ``rehost_catalog_images`` management command.

The command's network fetch is isolated in ``_fetch`` so these tests patch it
and never touch the real network. All media writes are routed to a throwaway
``MEDIA_ROOT``.
"""
import io
import tempfile
from decimal import Decimal
from unittest import mock

from django.core.management import call_command
from django.test import TestCase, override_settings
from PIL import Image

from catalog.models import Category, Product, ProductImage
from mediastore.models import MediaAsset

TMP_MEDIA = tempfile.mkdtemp(prefix="vsmart-rehost-")

PATCH_TARGET = "catalog.management.commands.rehost_catalog_images._fetch"


def _png_bytes(w=400, h=300, color=(10, 120, 200)):
    img = Image.new("RGB", (w, h), color)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class RehostCatalogImagesTests(TestCase):
    def setUp(self):
        self.category = Category.objects.create(
            name="Beverages",
            slug="beverages",
            image_url="https://cdn.dummyjson.com/product-images/groceries/juice/thumbnail.webp",
        )
        self.product = Product.objects.create(
            name="Orange Juice",
            price=Decimal("99.00"),
            mrp=Decimal("120.00"),
            category=self.category,
            image_url="https://cdn.dummyjson.com/product-images/groceries/juice/1.webp",
        )

    def test_product_external_image_is_rehosted(self):
        with mock.patch(PATCH_TARGET, return_value=_png_bytes()):
            call_command("rehost_catalog_images", "--model", "product")

        self.product.refresh_from_db()
        self.assertTrue(self.product.image_url.startswith("/api/v1/media/public/"))
        self.assertTrue(self.product.image_url.endswith("/medium"))
        # A public MediaAsset now exists for the rehosted catalog image.
        self.assertEqual(
            MediaAsset.objects.filter(category="catalog", visibility="public").count(),
            1,
        )

    def test_rerunning_is_idempotent(self):
        with mock.patch(PATCH_TARGET, return_value=_png_bytes()) as fetch:
            call_command("rehost_catalog_images", "--model", "product")
            first_url = Product.objects.get(pk=self.product.pk).image_url
            self.assertEqual(fetch.call_count, 1)

            # Second run: the row is now local, so nothing is fetched or created.
            call_command("rehost_catalog_images", "--model", "product")
            self.assertEqual(fetch.call_count, 1)

        self.product.refresh_from_db()
        self.assertEqual(self.product.image_url, first_url)
        self.assertEqual(MediaAsset.objects.count(), 1)

    def test_already_local_row_is_skipped(self):
        self.product.image_url = "/api/v1/media/public/abc-123/medium"
        self.product.save(update_fields=["image_url"])

        with mock.patch(PATCH_TARGET, return_value=_png_bytes()) as fetch:
            call_command("rehost_catalog_images", "--model", "product")

        fetch.assert_not_called()
        self.product.refresh_from_db()
        self.assertEqual(self.product.image_url, "/api/v1/media/public/abc-123/medium")
        self.assertEqual(MediaAsset.objects.count(), 0)

    def test_failed_fetch_is_skipped_and_counted(self):
        with mock.patch(PATCH_TARGET, side_effect=OSError("network down")):
            # Must not raise — the batch survives a per-item failure.
            call_command("rehost_catalog_images", "--model", "product")

        self.product.refresh_from_db()
        # Field untouched; no asset created.
        self.assertTrue(self.product.image_url.startswith("https://"))
        self.assertEqual(MediaAsset.objects.count(), 0)

    def test_dry_run_writes_nothing(self):
        original = self.product.image_url
        with mock.patch(PATCH_TARGET, return_value=_png_bytes()) as fetch:
            call_command("rehost_catalog_images", "--model", "product", "--dry-run")

        fetch.assert_not_called()
        self.product.refresh_from_db()
        self.assertEqual(self.product.image_url, original)
        self.assertEqual(MediaAsset.objects.count(), 0)

    def test_all_models_and_limit(self):
        ProductImage.objects.create(
            product=self.product,
            url="https://cdn.dummyjson.com/product-images/groceries/juice/2.webp",
        )
        # 3 external rows total (product, category, productimage); cap at 2.
        with mock.patch(PATCH_TARGET, return_value=_png_bytes()) as fetch:
            call_command("rehost_catalog_images", "--model", "all", "--limit", "2")

        self.assertEqual(fetch.call_count, 2)
        self.assertEqual(MediaAsset.objects.count(), 2)

    def test_category_uses_category_bucket(self):
        with mock.patch(PATCH_TARGET, return_value=_png_bytes()):
            call_command("rehost_catalog_images", "--model", "category")

        self.category.refresh_from_db()
        self.assertTrue(self.category.image_url.startswith("/api/v1/media/public/"))
        asset = MediaAsset.objects.get()
        self.assertEqual(asset.category, "category")
        self.assertEqual(asset.visibility, "public")


class ProductSearchAndSuggestTests(TestCase):
    """Full-text search relevance + the autocomplete suggest endpoint."""

    def setUp(self):
        self.dairy = Category.objects.create(name="Dairy", slug="dairy")
        self.bakery = Category.objects.create(name="Bakery", slug="bakery")

        def make(name, brand="", category=None, reviews=0, rating=0):
            return Product.objects.create(
                name=name,
                brand=brand,
                price=Decimal("50.00"),
                mrp=Decimal("60.00"),
                category=category or self.dairy,
                review_count=reviews,
                rating=Decimal(str(rating)),
            )

        # A prefix match ("Milk...") and a contains-only match ("... Milk").
        self.milk = make("Milk Full Cream", brand="Amul", reviews=500, rating=4.5)
        self.milkybar = make("Milkybar Chocolate", brand="Nestle", reviews=10)
        self.buttermilk = make("Spiced Buttermilk", brand="Amul", reviews=300)
        # A non-matching product to ensure filtering works.
        self.bread = make("Brown Bread", brand="Britannia", category=self.bakery)

    # ── search ───────────────────────────────────────────────
    def test_search_matches_name_and_brand(self):
        res = self.client.get("/api/v1/products/search", {"q": "milk"})
        self.assertEqual(res.status_code, 200)
        names = [p["name"] for p in res.data["data"]]
        self.assertIn("Milk Full Cream", names)
        self.assertIn("Milkybar Chocolate", names)
        self.assertIn("Spiced Buttermilk", names)
        self.assertNotIn("Brown Bread", names)

    def test_search_ranks_prefix_before_contains(self):
        res = self.client.get("/api/v1/products/search", {"q": "milk"})
        names = [p["name"] for p in res.data["data"]]
        # Name-prefix ("Milk...") outranks a contains-only match ("...milk").
        self.assertLess(
            names.index("Milk Full Cream"), names.index("Spiced Buttermilk")
        )

    def test_search_blank_query_returns_empty(self):
        res = self.client.get("/api/v1/products/search", {"q": "   "})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data["data"], [])

    # ── suggest ──────────────────────────────────────────────
    def test_suggest_returns_products_terms_and_categories(self):
        res = self.client.get("/api/v1/products/suggest", {"q": "milk"})
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data["success"])
        data = res.data["data"]

        product_names = [p["name"] for p in data["products"]]
        self.assertIn("Milk Full Cream", product_names)
        self.assertLessEqual(len(data["products"]), 6)

        # Completion terms are de-duplicated and all contain the query.
        self.assertTrue(data["terms"])
        lowered = [t.lower() for t in data["terms"]]
        self.assertEqual(len(lowered), len(set(lowered)))
        self.assertTrue(all("milk" in t for t in lowered))

    def test_suggest_matches_category_by_name(self):
        res = self.client.get("/api/v1/products/suggest", {"q": "dairy"})
        cat_names = [c["name"] for c in res.data["data"]["categories"]]
        self.assertIn("Dairy", cat_names)

    def test_suggest_blank_query_is_empty(self):
        res = self.client.get("/api/v1/products/suggest", {"q": ""})
        self.assertEqual(res.status_code, 200)
        data = res.data["data"]
        self.assertEqual(data["products"], [])
        self.assertEqual(data["terms"], [])
        self.assertEqual(data["categories"], [])

    def test_suggest_excludes_inactive_products(self):
        self.milk.is_active = False
        self.milk.save(update_fields=["is_active"])
        res = self.client.get("/api/v1/products/suggest", {"q": "milk full"})
        names = [p["name"] for p in res.data["data"]["products"]]
        self.assertNotIn("Milk Full Cream", names)


class ProductListSortAndPagingTests(TestCase):
    """Server-side sort options and the paginated envelope the app pages through."""

    def setUp(self):
        self.cat = Category.objects.create(name="Snacks", slug="snacks")

        def make(name, price, mrp, reviews=0):
            return Product.objects.create(
                name=name,
                price=Decimal(str(price)),
                mrp=Decimal(str(mrp)),
                category=self.cat,
                review_count=reviews,
            )

        # discount %: Half 50%, Deal 20%, Full 0%.
        self.half = make("Half Off", 50, 100, reviews=5)
        self.deal = make("Small Deal", 80, 100, reviews=50)
        self.full = make("Full Price", 100, 100, reviews=200)

    def test_sort_discount_orders_highest_discount_first(self):
        res = self.client.get("/api/v1/products", {"sort": "discount"})
        self.assertEqual(res.status_code, 200)
        names = [p["name"] for p in res.data["data"]]
        self.assertEqual(names[:3], ["Half Off", "Small Deal", "Full Price"])

    def test_sort_popular_orders_by_review_count(self):
        res = self.client.get("/api/v1/products", {"sort": "popular"})
        names = [p["name"] for p in res.data["data"]]
        self.assertEqual(names[:3], ["Full Price", "Small Deal", "Half Off"])

    def test_paginated_envelope_reports_meta_and_pages(self):
        # One item per page → three pages, and page 1 advertises more. Assert the
        # RENDERED (camelCased) body the app actually parses in _fetchPage.
        res = self.client.get("/api/v1/products", {"page": 1, "page_size": 1})
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(len(body["data"]), 1)
        meta = body["meta"]
        self.assertEqual(meta["page"], 1)
        self.assertEqual(meta["total"], 3)
        self.assertEqual(meta["totalPages"], 3)
        self.assertEqual(meta["pageSize"], 1)


class ProductListVariantStockTests(TestCase):
    """A listing card must know a product HAS packs, so the app's add-to-cart
    guard (`addToCartOrChoose`) routes to the detail page for pack selection
    instead of quick-adding straight from the card — which, for a product
    whose default/first pack is out of stock while another pack has stock,
    used to add the OUT-OF-STOCK one, because the list payload always sent
    `variants: []` regardless of whether the product actually had packs."""

    def setUp(self):
        from catalog.models import ProductVariant

        self.cat = Category.objects.create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Rice", price=Decimal("100"), mrp=Decimal("120"), category=self.cat,
        )
        self.out = ProductVariant.objects.create(
            product=self.product, label="1kg", price_delta=Decimal("0"),
            mrp=Decimal("120"), in_stock=False,
        )
        self.stocked = ProductVariant.objects.create(
            product=self.product, label="500g", price_delta=Decimal("-50"),
            mrp=Decimal("70"), in_stock=True,
        )
        self.plain = Product.objects.create(
            name="Salt", price=Decimal("20"), mrp=Decimal("25"), category=self.cat,
        )

    def _variants_for(self, body, product_id):
        row = next(p for p in body["data"] if p["id"] == str(product_id))
        return row["variants"]

    def test_listing_reports_each_packs_own_stock(self):
        res = self.client.get("/api/v1/products")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        variants = self._variants_for(body, self.product.id)
        by_label = {v["label"]: v for v in variants}
        self.assertEqual(len(variants), 2)
        self.assertFalse(by_label["1kg"]["inStock"])
        self.assertTrue(by_label["500g"]["inStock"])

    def test_listing_reports_no_variants_for_a_plain_product(self):
        res = self.client.get("/api/v1/products")
        body = res.json()
        self.assertEqual(self._variants_for(body, self.plain.id), [])

    def test_search_and_suggest_also_carry_variant_stock(self):
        res = self.client.get("/api/v1/products/search", {"q": "Rice"})
        variants = self._variants_for(res.json(), self.product.id)
        self.assertEqual({v["label"] for v in variants}, {"1kg", "500g"})

        res2 = self.client.get("/api/v1/products/suggest", {"q": "Rice"})
        row = next(p for p in res2.json()["data"]["products"]
                   if p["id"] == str(self.product.id))
        self.assertEqual({v["label"] for v in row["variants"]}, {"1kg", "500g"})

    def test_listing_page_does_not_n_plus_one_on_variants(self):
        """Locks in the batched query — a page of many variant-bearing products
        must cost a fixed number of queries, not one extra per product."""
        from catalog.models import ProductVariant

        for i in range(5):
            p = Product.objects.create(
                name=f"Extra {i}", price=Decimal("10"), mrp=Decimal("12"),
                category=self.cat,
            )
            ProductVariant.objects.create(product=p, label="A", in_stock=True)
            ProductVariant.objects.create(product=p, label="B", in_stock=False)

        with self.assertNumQueries(FuzzyInt(1, 8)):
            res = self.client.get("/api/v1/products", {"page_size": 20})
        self.assertEqual(res.status_code, 200)
        # Sanity: every variant-bearing product in the page actually got its packs.
        body = res.json()
        for row in body["data"]:
            if row["id"] == str(self.product.id):
                self.assertEqual(len(row["variants"]), 2)


class FuzzyInt(int):
    """An int that == any value within [lo, hi] — for assertNumQueries bounds
    where the exact count depends on things this test doesn't care about
    (pagination COUNT query, auth lookups) but an N+1 regression must still
    fail it loudly."""

    def __new__(cls, lo, hi):
        obj = super().__new__(cls, hi)
        obj.lo, obj.hi = lo, hi
        return obj

    def __eq__(self, other):
        return self.lo <= other <= self.hi

    def __repr__(self):
        return f"[{self.lo}..{self.hi}]"


class GstPercentageContractTests(TestCase):
    """GST has ONE unit rule: the API and storage speak percentages (18), only
    the pricing maths uses fractions (0.18).

    Before this the two were mixed. The admin form was labelled "GST rate (0–1)"
    so operators stored 0.18 on products, and `place_order` copied
    `PlatformConfig.gst_rate` (a fraction) straight into `OrderItem.gst_rate` — a
    column documented as a percentage. Every order line without an explicit
    product rate recorded 0.18% tax instead of 18%.
    """

    def setUp(self):
        from rest_framework.test import APIClient

        from accounts.models import User

        self.admin = User.objects.create(
            phone="+919000000601", name="Admin", role="admin"
        )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)
        self.category, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")

    def _create(self, gst):
        return self.client.post("/api/v1/admin/catalog/products", {
            "name": "Taxed Item", "brand": "VS", "unit": "1 kg",
            "price": "100", "mrp": "120",
            "categoryId": self.category.id, "gstRate": gst,
        }, format="json")

    def test_a_slab_percentage_is_accepted_and_stored_verbatim(self):
        r = self._create("18")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(Decimal(str(r.json()["data"]["gstRate"])), Decimal("18"))
        self.assertEqual(Product.objects.get(name="Taxed Item").gst_rate, Decimal("18"))

    def test_a_fraction_is_refused_and_the_error_names_the_fix(self):
        r = self._create("0.18")
        self.assertEqual(r.status_code, 400, r.content)
        detail = str(r.json())
        self.assertIn("standard slabs", detail)
        # The message spells out what they should have typed.
        self.assertIn("Enter 18 for 18%", detail)

    def test_an_off_slab_typo_is_refused(self):
        for typo in ("1.8", "180", "17"):
            self.assertEqual(self._create(typo).status_code, 400, typo)

    def test_null_gst_falls_back_to_the_platform_default(self):
        r = self._create(None)
        self.assertEqual(r.status_code, 201, r.content)
        self.assertIsNone(Product.objects.get(name="Taxed Item").gst_rate)

    def test_zero_rated_goods_are_allowed(self):
        self.assertEqual(self._create("0").status_code, 201)


class GstUnitHelperTests(TestCase):
    def test_round_trip(self):
        from core.pricing import gst_fraction_to_pct, gst_pct_to_fraction

        self.assertEqual(gst_pct_to_fraction(18), Decimal("0.1800"))
        self.assertEqual(gst_fraction_to_pct(Decimal("0.18")), Decimal("18.00"))
        self.assertEqual(gst_fraction_to_pct(gst_pct_to_fraction(5)), Decimal("5.00"))
        self.assertEqual(gst_pct_to_fraction(Decimal("0.25")), Decimal("0.0025"))


class OrderLineGstSnapshotTests(TestCase):
    """`OrderItem.gst_rate` must be the percentage its docstring promises."""

    def setUp(self):
        from addresses.models import Address
        from accounts.models import User
        from cart.services import get_cart, upsert_item
        from inventory.models import Warehouse

        Warehouse.objects.create(name="GstWh", code="GSTWH", is_default=True)
        self.category, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.user = User.objects.create(phone="+919000000602", name="GstCust")
        self.address = Address.objects.create(
            user=self.user, name="GstCust", phone="9000000602", line1="Rd",
            pincode="560001",
        )
        self.upsert_item, self.get_cart = upsert_item, get_cart

    def _place(self, product):
        from orders.models import Order
        from orders.services import place_order

        self.upsert_item(self.get_cart(self.user), product, None, 1)
        order = place_order(
            self.user, address=self.address, payment_method=Order.PaymentMethod.COD
        )
        return order.items.first()

    def test_explicit_product_rate_is_snapshotted_as_a_percentage(self):
        product = Product.objects.create(
            name="Rated", brand="VS", unit="1", price=Decimal("100"),
            mrp=Decimal("100"), category=self.category, stock_count=None,
            gst_rate=Decimal("5"),
        )
        self.assertEqual(self._place(product).gst_rate, Decimal("5.00"))

    def test_platform_fallback_is_converted_not_copied_raw(self):
        """PlatformConfig stores the fraction 0.18; the line must read 18.00,
        not 0.18 — which is what the old code wrote."""
        from siteconfig.models import PlatformConfig

        cfg = PlatformConfig.load()
        cfg.gst_rate = Decimal("0.18")
        cfg.save(update_fields=["gst_rate"])
        product = Product.objects.create(
            name="Unrated", brand="VS", unit="1", price=Decimal("100"),
            mrp=Decimal("100"), category=self.category, stock_count=None,
            gst_rate=None,
        )
        self.assertEqual(self._place(product).gst_rate, Decimal("18.00"))
