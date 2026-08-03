from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product, ProductVariant


class CartValidateTests(TestCase):
    """The pre-checkout stock re-check. Full per-store stock is exercised live; here
    we cover the no-serving-store fallback (uses the product/variant in_stock flag)
    and the payload shape the app maps to checkout issues."""

    def setUp(self):
        self.user = User.objects.create(phone="+919000700001", role="customer")
        cat = Category.objects.create(name="Grocery")
        self.in_stock = Product.objects.create(
            name="Rice", price=100, mrp=120, category=cat, is_active=True, in_stock=True
        )
        self.oos = Product.objects.create(
            name="Dal", price=80, mrp=90, category=cat, is_active=True, in_stock=False
        )
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def _validate(self, items):
        return self.client.post("/api/v1/cart/validate", {"items": items}, format="json")

    def test_in_stock_product_passes(self):
        r = self._validate([{"product_id": str(self.in_stock.id), "quantity": 2}])
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data["ok"])
        self.assertTrue(r.data["items"][0]["inStock"])

    def test_out_of_stock_product_blocks(self):
        r = self._validate([{"product_id": str(self.oos.id), "quantity": 1}])
        self.assertFalse(r.data["ok"])
        line = r.data["items"][0]
        self.assertFalse(line["inStock"])
        self.assertEqual(line["productId"], str(self.oos.id))

    def test_out_of_stock_variant_blocks_even_when_product_in_stock(self):
        v = ProductVariant.objects.create(
            product=self.in_stock, label="5kg", price_delta=400, in_stock=False
        )
        r = self._validate([
            {"product_id": str(self.in_stock.id), "variant_id": str(v.id), "quantity": 1},
        ])
        # The product is in stock, but this PACK is not — the line must still block.
        self.assertFalse(r.data["ok"])
        self.assertFalse(r.data["items"][0]["inStock"])
        self.assertEqual(r.data["items"][0]["variantId"], str(v.id))


class CartGuestAccessTests(TestCase):
    """The stateless bill + stock-check endpoints must work WITHOUT a session so a
    not-yet-signed-in shopper viewing their cart never hits an authorization error.
    (Placing the order — /checkout, the server cart — stays authenticated.)"""

    def setUp(self):
        cat = Category.objects.create(name="Grocery")
        self.p = Product.objects.create(
            name="Rice", price=100, mrp=120, category=cat, is_active=True, in_stock=True
        )
        self.guest = APIClient()  # no force_authenticate → anonymous

    def test_quote_works_for_guest(self):
        r = self.guest.post(
            "/api/v1/cart/quote",
            {"items": [{"product_id": str(self.p.id), "quantity": 2}]},
            format="json",
        )
        self.assertEqual(r.status_code, 200, r.content[:300])
        self.assertEqual(r.data["bill"]["subtotal"], 200)

    def test_validate_works_for_guest(self):
        r = self.guest.post(
            "/api/v1/cart/validate",
            {"items": [{"product_id": str(self.p.id), "quantity": 1}]},
            format="json",
        )
        self.assertEqual(r.status_code, 200, r.content[:300])
        self.assertTrue(r.data["ok"])

    def test_server_cart_still_requires_auth(self):
        # The stateful cart is NOT guest-accessible.
        self.assertEqual(self.guest.get("/api/v1/cart").status_code, 401)


class CartReplaceTests(TestCase):
    """`PUT /cart` — the atomic, idempotent whole-cart sync used by checkout.

    The path it replaces (delete-every-line, then POST each item back against an
    ACCUMULATING endpoint) corrupted real baskets: any failure mid-loop left a
    partial cart, and the retry re-added what had already landed.
    """

    def setUp(self):
        self.user = User.objects.create(phone="+919000700055", role="customer")
        cat = Category.objects.create(name="Grocery")
        self.rice = Product.objects.create(
            name="Rice", price=100, mrp=120, category=cat, is_active=True, in_stock=True
        )
        self.dal = Product.objects.create(
            name="Dal", price=80, mrp=90, category=cat, is_active=True, in_stock=True
        )
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def _put(self, items):
        return self.client.put("/api/v1/cart", {"items": items}, format="json")

    def _quantities(self):
        r = self.client.get("/api/v1/cart")
        return {i["name"]: i["quantity"] for i in r.data["items"]}

    def test_replaces_cart_with_exact_lines(self):
        r = self._put([
            {"product_id": str(self.rice.id), "quantity": 2},
            {"product_id": str(self.dal.id), "quantity": 3},
        ])
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self._quantities(), {"Rice": 2, "Dal": 3})

    def test_replaying_the_same_put_does_not_double_quantities(self):
        """The regression this endpoint exists for. Under the old delete+POST sync a
        retry after a mid-flight failure re-added the already-synced lines."""
        payload = [{"product_id": str(self.rice.id), "quantity": 2}]
        self._put(payload)
        self._put(payload)
        self._put(payload)
        self.assertEqual(self._quantities(), {"Rice": 2})

    def test_drops_lines_absent_from_the_payload(self):
        self._put([
            {"product_id": str(self.rice.id), "quantity": 1},
            {"product_id": str(self.dal.id), "quantity": 1},
        ])
        self._put([{"product_id": str(self.rice.id), "quantity": 1}])
        self.assertEqual(self._quantities(), {"Rice": 1})

    def test_zero_quantity_line_is_a_drop_not_a_zero_line(self):
        self._put([{"product_id": str(self.rice.id), "quantity": 2}])
        self._put([{"product_id": str(self.rice.id), "quantity": 0}])
        self.assertEqual(self._quantities(), {})

    def test_empty_payload_clears_the_cart(self):
        self._put([{"product_id": str(self.rice.id), "quantity": 2}])
        r = self._put([])
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self._quantities(), {})

    def test_quantity_is_absolute_so_a_lower_value_lowers_the_line(self):
        self._put([{"product_id": str(self.rice.id), "quantity": 9}])
        self._put([{"product_id": str(self.rice.id), "quantity": 4}])
        self.assertEqual(self._quantities(), {"Rice": 4})

    def test_duplicate_lines_are_summed_and_clamped(self):
        self._put([
            {"product_id": str(self.rice.id), "quantity": 60},
            {"product_id": str(self.rice.id), "quantity": 60},
        ])
        # Merged total re-clamped to the per-line ceiling, not silently last-wins.
        self.assertEqual(self._quantities(), {"Rice": 99})

    def test_variant_must_belong_to_the_product(self):
        """The money guard from the POST path must hold on PUT too — otherwise the
        replace endpoint reopens the negative-delta underpricing hole."""
        foreign = ProductVariant.objects.create(
            product=self.dal, label="5kg", price_delta=-70, in_stock=True
        )
        r = self._put([
            {"product_id": str(self.rice.id),
             "variant_id": str(foreign.id), "quantity": 1},
        ])
        self.assertEqual(r.status_code, 400)

    def test_over_cap_quantity_is_rejected(self):
        r = self._put([{"product_id": str(self.rice.id), "quantity": 500}])
        self.assertEqual(r.status_code, 400)

    def test_rejects_an_invalid_product_without_touching_the_cart(self):
        """All-or-nothing: a bad line must not leave the previous cart half-replaced."""
        self._put([{"product_id": str(self.rice.id), "quantity": 2}])
        r = self._put([
            {"product_id": str(self.dal.id), "quantity": 1},
            {"product_id": "99999999", "quantity": 1},
        ])
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self._quantities(), {"Rice": 2})

    def test_requires_authentication(self):
        self.client.force_authenticate(None)
        r = self._put([{"product_id": str(self.rice.id), "quantity": 1}])
        self.assertIn(r.status_code, (401, 403))


class CartQuoteZoneTests(TestCase):
    """`/cart/quote` must price with the SAME zone fee overrides that checkout
    applies. It used to always pass zone=None, so a customer in a zone with its own
    delivery fee was quoted the platform default and then charged the zone rate —
    the total moved between the cart screen and the receipt."""

    def setUp(self):
        from addresses.models import Address
        from siteconfig.models import PlatformConfig
        from zones.models import Zone

        cfg = PlatformConfig.load()
        cfg.delivery_fee = Decimal("20")
        cfg.free_delivery_threshold = Decimal("500")
        cfg.save()

        self.user = User.objects.create(phone="+919000700077", role="customer")
        cat = Category.objects.create(name="Grocery")
        self.product = Product.objects.create(
            name="Rice", price=100, mrp=120, category=cat, is_active=True, in_stock=True
        )
        # A zone whose delivery fee differs from the platform default.
        self.zone = Zone.objects.create(
            name="Premium", code="PREM", is_active=True,
            center_lat=Decimal("12.970000"), center_lng=Decimal("77.600000"),
            radius_km=Decimal("10"), pincodes=["560038"],
            delivery_fee=Decimal("75"),
        )
        self.address = Address.objects.create(
            user=self.user, name="Home", phone="+919000700077",
            latitude=Decimal("12.970000"), longitude=Decimal("77.600000"),
            pincode="560038",
        )
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def _quote(self, **extra):
        body = {"items": [{"product_id": str(self.product.id), "quantity": 1}]}
        body.update(extra)
        return self.client.post("/api/v1/cart/quote", body, format="json")

    def test_quote_without_location_uses_platform_defaults(self):
        r = self._quote()
        self.assertEqual(r.status_code, 200)
        self.assertEqual(Decimal(str(r.data["bill"]["delivery_fee"])), Decimal("20.00"))

    def test_address_id_applies_the_zone_delivery_fee(self):
        r = self._quote(address_id=str(self.address.id))
        self.assertEqual(r.status_code, 200)
        self.assertEqual(Decimal(str(r.data["bill"]["delivery_fee"])), Decimal("75.00"))

    def test_explicit_coordinates_apply_the_zone_for_a_guest(self):
        self.client.force_authenticate(None)
        r = self._quote(latitude="12.970000", longitude="77.600000")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(Decimal(str(r.data["bill"]["delivery_fee"])), Decimal("75.00"))

    def test_another_users_address_is_ignored_not_honoured(self):
        """address_id is scoped to the caller — probing someone else's address must
        not resolve their zone (nor leak that it exists)."""
        from addresses.models import Address

        other = User.objects.create(phone="+919000700078", role="customer")
        theirs = Address.objects.create(
            user=other, name="Theirs", phone="+919000700078",
            latitude=Decimal("12.970000"), longitude=Decimal("77.600000"),
            pincode="560038",
        )
        r = self._quote(address_id=str(theirs.id))
        self.assertEqual(r.status_code, 200)
        # Falls back to platform defaults rather than applying their zone.
        self.assertEqual(Decimal(str(r.data["bill"]["delivery_fee"])), Decimal("20.00"))

    def test_unknown_address_id_degrades_to_defaults(self):
        r = self._quote(address_id="99999999")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(Decimal(str(r.data["bill"]["delivery_fee"])), Decimal("20.00"))

    def test_quoted_total_matches_the_engine_for_the_same_zone(self):
        """The real invariant: what the cart shows is what compute_bill produces
        for the zone checkout will resolve."""
        from core.pricing import compute_bill

        r = self._quote(address_id=str(self.address.id))
        expected = compute_bill(Decimal("100"), savings=Decimal("20"), zone=self.zone)
        self.assertEqual(
            Decimal(str(r.data["bill"]["total"])), expected["total"])
