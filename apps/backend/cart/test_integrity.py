"""Cart line integrity — a line's price and quantity must not be attacker-chosen."""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import Role, User
from cart.models import CartItem
from cart.serializers import MAX_LINE_QUANTITY
from catalog.models import Category, Product, ProductVariant


def _client(user):
    c = APIClient()
    c.force_authenticate(user=user)
    return c


class CartVariantScopingTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            phone="+919600007777", name="Cust", role=Role.CUSTOMER
        )
        self.client_ = _client(self.user)
        cat = Category.objects.create(name="Staples", slug="staples-cart")
        self.expensive = Product.objects.create(
            name="Dry Fruits", price=Decimal("2000"), mrp=Decimal("2200"), category=cat
        )
        self.cheap = Product.objects.create(
            name="Salt", price=Decimal("20"), mrp=Decimal("25"), category=cat
        )
        # A steep negative delta on the CHEAP product — harmless there, ruinous if
        # it can be attached to the expensive one.
        self.cheap_variant = ProductVariant.objects.create(
            product=self.cheap, label="Small", price_delta=Decimal("-1900")
        )
        self.own_variant = ProductVariant.objects.create(
            product=self.expensive, label="500g", price_delta=Decimal("-500")
        )

    def _add(self, product, variant=None, quantity=1):
        body = {"product_id": str(product.id), "quantity": quantity}
        if variant is not None:
            body["variant_id"] = str(variant.id)
        return self.client_.post("/api/v1/cart/items", body, format="json")

    def test_another_products_variant_is_rejected(self):
        # Previously priced the line at 2000 + (-1900) = ₹100 and place_order
        # charged it — while /cart/quote and /cart/validate, which DO scope the
        # variant, kept showing the honest ₹2,000 bill.
        r = self._add(self.expensive, self.cheap_variant)
        self.assertEqual(r.status_code, 400, r.content[:300])
        self.assertFalse(CartItem.objects.filter(cart__user=self.user).exists())

    def test_the_products_own_variant_is_accepted_and_priced_correctly(self):
        r = self._add(self.expensive, self.own_variant)
        self.assertIn(r.status_code, (200, 201), r.content[:300])
        item = CartItem.objects.get(cart__user=self.user)
        self.assertEqual(item.price_snapshot, Decimal("1500"))

    def test_a_line_without_a_variant_still_works(self):
        r = self._add(self.cheap)
        self.assertIn(r.status_code, (200, 201))
        self.assertEqual(
            CartItem.objects.get(cart__user=self.user).price_snapshot, Decimal("20")
        )


class CartQuantityBoundTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            phone="+919600008888", name="Cust", role=Role.CUSTOMER
        )
        self.client_ = _client(self.user)
        cat = Category.objects.create(name="Staples", slug="staples-qty")
        self.product = Product.objects.create(
            name="Atta", price=Decimal("50"), mrp=Decimal("60"), category=cat
        )

    def _add(self, quantity):
        return self.client_.post(
            "/api/v1/cart/items",
            {"product_id": str(self.product.id), "quantity": quantity},
            format="json",
        )

    def test_a_single_oversized_request_is_rejected(self):
        self.assertEqual(self._add(MAX_LINE_QUANTITY + 1).status_code, 400)

    def test_repeated_adds_cannot_climb_past_the_cap(self):
        # POST accumulates, so a per-request cap alone wouldn't bound the line —
        # each request stays legal while the total runs away.
        for _ in range(5):
            self.assertIn(self._add(MAX_LINE_QUANTITY).status_code, (200, 201))
        item = CartItem.objects.get(cart__user=self.user)
        self.assertEqual(item.quantity, MAX_LINE_QUANTITY)

    def test_patch_cannot_exceed_the_cap(self):
        self._add(1)
        item = CartItem.objects.get(cart__user=self.user)
        r = self.client_.patch(
            f"/api/v1/cart/items/{item.id}",
            {"quantity": MAX_LINE_QUANTITY + 50},
            format="json",
        )
        self.assertEqual(r.status_code, 400)
