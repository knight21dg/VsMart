"""Reorder must put back what was actually bought.

The old view called ``upsert_item(cart, item.product, None, item.quantity)`` — the
variant was hardcoded to None. Reordering a 5 kg pack therefore added the BASE
product: a different SKU, at a different price, drawn from a different stock pool
(variants are separately stocked). It also skipped delisted products in silence, so
a five-item reorder could quietly become a two-item cart.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product, ProductVariant

from .models import Order, OrderItem, OrderStatus
from .services import reorder_into_cart, reorder_plan


class ReorderTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000800001", role="customer")
        cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.rice = Product.objects.create(
            name="Rice", brand="VS", unit="1 kg", price=Decimal("100"),
            mrp=Decimal("120"), category=cat, is_active=True, in_stock=True)
        self.pack5kg = ProductVariant.objects.create(
            product=self.rice, label="5kg", price_delta=Decimal("400"), in_stock=True)
        self.dal = Product.objects.create(
            name="Dal", brand="VS", unit="1 kg", price=Decimal("80"),
            mrp=Decimal("90"), category=cat, is_active=True, in_stock=True)

        self.order = Order.objects.create(
            user=self.user, payment_method=Order.PaymentMethod.COD,
            status=OrderStatus.DELIVERED, total=Decimal("580"))
        OrderItem.objects.create(
            order=self.order, product=self.rice, variant=self.pack5kg,
            name="Rice", quantity=1, price=Decimal("500"), mrp=Decimal("520"))
        OrderItem.objects.create(
            order=self.order, product=self.dal, name="Dal",
            quantity=2, price=Decimal("80"), mrp=Decimal("90"))

        self.client = APIClient()
        self.client.force_authenticate(self.user)

    # ── the variant bug ──
    def test_reorder_keeps_the_original_pack(self):
        cart, _ = reorder_into_cart(self.order, self.user)
        line = cart.items.get(product=self.rice)
        self.assertEqual(
            line.variant_id, self.pack5kg.id,
            "reorder swapped the 5kg pack for the base product")

    def test_reordered_pack_is_priced_as_the_pack(self):
        cart, _ = reorder_into_cart(self.order, self.user)
        line = cart.items.get(product=self.rice)
        # base 100 + 5kg delta 400
        self.assertEqual(line.price_snapshot, Decimal("500"))

    def test_line_without_a_variant_stays_variantless(self):
        cart, _ = reorder_into_cart(self.order, self.user)
        self.assertIsNone(cart.items.get(product=self.dal).variant_id)

    def test_quantities_are_carried_over(self):
        cart, _ = reorder_into_cart(self.order, self.user)
        self.assertEqual(cart.items.get(product=self.dal).quantity, 2)

    # ── unavailable lines are reported, not silently dropped ──
    def test_delisted_product_is_reported_as_unavailable(self):
        self.dal.is_active = False
        self.dal.save(update_fields=["is_active"])

        _, lines = reorder_into_cart(self.order, self.user)
        dropped = [line for line in lines if not line["available"]]
        self.assertEqual(len(dropped), 1)
        self.assertEqual(dropped[0]["reason"], "discontinued")

    def test_delisted_product_is_not_added_to_the_cart(self):
        self.dal.is_active = False
        self.dal.save(update_fields=["is_active"])

        cart, _ = reorder_into_cart(self.order, self.user)
        self.assertFalse(cart.items.filter(product=self.dal).exists())
        self.assertTrue(cart.items.filter(product=self.rice).exists())

    def test_out_of_stock_pack_is_reported_separately_from_delisted(self):
        """'Sold out' and 'we no longer sell this' are different messages."""
        self.pack5kg.in_stock = False
        self.pack5kg.save(update_fields=["in_stock"])

        lines = reorder_plan(self.order, self.user)
        rice_line = next(line for line in lines if line["name"].startswith("Rice"))
        self.assertFalse(rice_line["available"])
        self.assertEqual(rice_line["reason"], "out_of_stock")

    # ── accumulation ──
    def test_reordering_twice_accumulates_and_stays_within_the_cap(self):
        reorder_into_cart(self.order, self.user)
        cart, _ = reorder_into_cart(self.order, self.user)
        self.assertEqual(cart.items.get(product=self.dal).quantity, 4)

    def test_merged_quantity_is_clamped_to_the_line_ceiling(self):
        for _ in range(60):
            reorder_into_cart(self.order, self.user)
        self.assertEqual(cart_qty(self.user, self.dal), 99)

    # ── preview endpoint ──
    def test_preview_lists_lines_without_touching_the_cart(self):
        from cart.models import CartItem

        r = self.client.get(f"/api/v1/orders/{self.order.code}/reorder/preview")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.data["items"]), 2)
        self.assertEqual(r.data["available_count"], 2)
        self.assertFalse(CartItem.objects.filter(cart__user=self.user).exists())

    def test_preview_prices_live_not_historical(self):
        """A past line's price is history; showing it would promise a total the cart
        won't honour."""
        self.rice.price = Decimal("150")
        self.rice.save(update_fields=["price"])

        r = self.client.get(f"/api/v1/orders/{self.order.code}/reorder/preview")
        rice = next(i for i in r.data["items"] if i["name"].startswith("Rice"))
        self.assertEqual(Decimal(str(rice["price"])), Decimal("550"))  # 150 + 400

    def test_preview_carries_the_variant_id(self):
        r = self.client.get(f"/api/v1/orders/{self.order.code}/reorder/preview")
        rice = next(i for i in r.data["items"] if i["name"].startswith("Rice"))
        self.assertEqual(rice["variant_id"], str(self.pack5kg.id))

    def test_commit_reports_what_it_skipped(self):
        self.dal.is_active = False
        self.dal.save(update_fields=["is_active"])

        r = self.client.post(f"/api/v1/orders/{self.order.code}/reorder")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.data["added_count"], 1)
        self.assertEqual(len(r.data["skipped"]), 1)
        self.assertEqual(r.data["skipped"][0]["reason"], "discontinued")

    def test_another_users_order_cannot_be_reordered(self):
        other = User.objects.create(phone="+919000800002", role="customer")
        self.client.force_authenticate(other)
        r = self.client.post(f"/api/v1/orders/{self.order.code}/reorder")
        self.assertEqual(r.status_code, 404)


def cart_qty(user, product):
    from cart.models import CartItem

    return CartItem.objects.get(cart__user=user, product=product).quantity
