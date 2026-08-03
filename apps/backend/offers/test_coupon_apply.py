"""Coupon apply: the preview must tell the truth, and the discount must be ours.

Two defects this locks down:

1. **Preview lied about spent coupons.** `resolve_coupon` (the validate/preview
   endpoint) checked expiry, min-order and ownership but NOT the usage caps that
   `redeem_coupon` enforces at checkout. So a used-up code previewed as
   "Applied — ₹100 off" and the customer only discovered it was dead when
   placing the order failed.

2. **The discount was client-supplied.** `place_order` fed the request's
   `coupon_discount` straight into the bill, so a crafted checkout could pair a
   real ₹50 code with a ₹99,999 discount and buy an order for nothing.
"""
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product

from .models import Coupon, CouponRedemption
from .services import CouponError, redeem_coupon, resolve_coupon


class CouponPreviewTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000007001", name="A",
                                        role="customer")
        self.other = User.objects.create(phone="+919000007002", name="B",
                                         role="customer")

    def _coupon(self, **kw):
        kw.setdefault("code", "SAVE50")
        kw.setdefault("discount_type", Coupon.DiscountType.FLAT)
        kw.setdefault("value", Decimal("50"))
        kw.setdefault("is_active", True)
        return Coupon.objects.create(**kw)

    # ── the basics still work ──
    def test_a_valid_coupon_previews_with_its_discount(self):
        self._coupon()
        coupon, discount, msg = resolve_coupon("SAVE50", "500", user=self.user)
        self.assertIsNotNone(coupon)
        self.assertEqual(discount, Decimal("50.00"))

    def test_code_match_is_case_insensitive(self):
        self._coupon()
        coupon, _, _ = resolve_coupon("save50", "500", user=self.user)
        self.assertIsNotNone(coupon)

    def test_percent_coupon_respects_its_cap(self):
        self._coupon(code="PCT", discount_type=Coupon.DiscountType.PERCENT,
                     value=Decimal("20"), max_discount=Decimal("30"))
        _, discount, _ = resolve_coupon("PCT", "1000", user=self.user)
        self.assertEqual(discount, Decimal("30.00"))  # 200 capped to 30

    def test_discount_never_exceeds_the_cart(self):
        self._coupon(value=Decimal("500"))
        _, discount, _ = resolve_coupon("SAVE50", "100", user=self.user)
        self.assertEqual(discount, Decimal("100.00"))

    def test_min_order_is_enforced(self):
        self._coupon(min_order=Decimal("300"))
        coupon, discount, msg = resolve_coupon("SAVE50", "100", user=self.user)
        self.assertIsNone(coupon)
        self.assertIn("Minimum order", msg)

    def test_expired_coupon_is_refused(self):
        self._coupon(valid_to=timezone.localdate() - timezone.timedelta(days=1))
        coupon, _, msg = resolve_coupon("SAVE50", "500", user=self.user)
        self.assertIsNone(coupon)
        self.assertIn("expired", msg.lower())

    def test_inactive_coupon_is_refused(self):
        self._coupon(is_active=False)
        self.assertIsNone(resolve_coupon("SAVE50", "500", user=self.user)[0])

    # ── personal coupons ──
    def test_a_personal_coupon_is_refused_for_everyone_else(self):
        self._coupon(owner=self.user)
        coupon, _, msg = resolve_coupon("SAVE50", "500", user=self.other)
        self.assertIsNone(coupon)
        # Reported as invalid, not "not yours" — the code must not be probeable.
        self.assertEqual(msg, "Invalid coupon code")

    def test_a_personal_coupon_works_for_its_owner(self):
        self._coupon(owner=self.user)
        self.assertIsNotNone(resolve_coupon("SAVE50", "500", user=self.user)[0])

    def test_a_personal_coupon_cannot_be_redeemed_by_a_stranger(self):
        """Even skipping the preview entirely."""
        self._coupon(owner=self.user)
        with self.assertRaises(CouponError):
            redeem_coupon("SAVE50", self.other, order_code="X1",
                          amount=Decimal("50"))

    # ── the preview/redeem agreement ──
    def test_preview_reports_a_globally_exhausted_coupon(self):
        c = self._coupon(usage_limit=1)
        CouponRedemption.objects.create(coupon=c, user=self.other,
                                        order_code="OLD", amount=Decimal("50"))
        coupon, discount, msg = resolve_coupon("SAVE50", "500", user=self.user)
        self.assertIsNone(coupon, "a spent coupon must not preview as valid")
        self.assertEqual(discount, Decimal("0"))
        self.assertIn("usage limit", msg.lower())

    def test_preview_reports_a_coupon_this_user_already_used(self):
        c = self._coupon(per_user_limit=1)
        CouponRedemption.objects.create(coupon=c, user=self.user,
                                        order_code="OLD", amount=Decimal("50"))
        coupon, _, msg = resolve_coupon("SAVE50", "500", user=self.user)
        self.assertIsNone(coupon)
        self.assertIn("already used", msg.lower())

    def test_another_users_redemption_does_not_block_a_per_user_cap(self):
        c = self._coupon(per_user_limit=1)
        CouponRedemption.objects.create(coupon=c, user=self.other,
                                        order_code="OLD", amount=Decimal("50"))
        self.assertIsNotNone(resolve_coupon("SAVE50", "500", user=self.user)[0])

    def test_whatever_previews_valid_can_actually_be_redeemed(self):
        """The invariant: preview and redeem must never disagree."""
        self._coupon(usage_limit=2, per_user_limit=1)
        coupon, _, _ = resolve_coupon("SAVE50", "500", user=self.user)
        self.assertIsNotNone(coupon)
        redeem_coupon("SAVE50", self.user, order_code="O1", amount=Decimal("50"))

        # Now spent for this user — preview must say so rather than promising it.
        self.assertIsNone(resolve_coupon("SAVE50", "500", user=self.user)[0])
        with self.assertRaises(CouponError):
            redeem_coupon("SAVE50", self.user, order_code="O2",
                          amount=Decimal("50"))


class CouponCheckoutIntegrityTests(TestCase):
    """The discount that reaches the bill must be computed by us."""

    def setUp(self):
        self.user = User.objects.create(phone="+919000007010", name="A",
                                        role="customer", kyc_status="verified")
        cat = Category.objects.create(name="Grocery")
        self.product = Product.objects.create(
            name="Rice", category=cat, price=Decimal("500"), mrp=Decimal("600"),
            in_stock=True,
        )
        Coupon.objects.create(code="SAVE50", discount_type=Coupon.DiscountType.FLAT,
                              value=Decimal("50"), is_active=True)

    def _cart(self):
        from cart.models import Cart, CartItem

        cart, _ = Cart.objects.get_or_create(user=self.user)
        CartItem.objects.create(cart=cart, product=self.product, quantity=1,
                                price_snapshot=self.product.price)
        return cart

    def test_an_inflated_client_discount_is_ignored(self):
        """The headline defect: a real code + a made-up amount must not pay off."""
        from addresses.models import Address
        from orders.services import place_order

        self._cart()
        addr = Address.objects.create(
            user=self.user, name="A", phone="9", line1="L", pincode="533005",
        )
        order = place_order(
            self.user, address=addr, payment_method="cod",
            coupon_code="SAVE50", coupon_discount=Decimal("99999"),
        )
        # Server recomputed it: the coupon is worth 50, not 99,999.
        self.assertEqual(order.discount, Decimal("50.00"))
        self.assertGreater(order.total, Decimal("0"))

    def test_a_discount_with_no_code_is_ignored(self):
        from addresses.models import Address
        from orders.services import place_order

        self._cart()
        addr = Address.objects.create(
            user=self.user, name="A", phone="9", line1="L", pincode="533005",
        )
        order = place_order(
            self.user, address=addr, payment_method="cod",
            coupon_code="", coupon_discount=Decimal("400"),
        )
        self.assertEqual(order.discount, Decimal("0.00"))

    def test_a_bogus_code_REFUSES_the_order_not_silently_full_price(self):
        # This used to pass the order through with discount 0 — the customer who
        # attached the code believed a discount applied and the gateway charged
        # full price (VSNEW100 → ₹649 instead of ₹549, live). Fail loud instead.
        from addresses.models import Address
        from orders.services import CheckoutError, place_order

        self._cart()
        addr = Address.objects.create(
            user=self.user, name="A", phone="9", line1="L", pincode="533005",
        )
        with self.assertRaises(CheckoutError) as ctx:
            place_order(
                self.user, address=addr, payment_method="cod",
                coupon_code="NOPE", coupon_discount=Decimal("50"),
            )
        self.assertEqual(ctx.exception.code, "COUPON_INVALID")


class CouponApiTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000007020", name="A",
                                        role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.user)
        Coupon.objects.create(code="SAVE50", discount_type=Coupon.DiscountType.FLAT,
                              value=Decimal("50"), is_active=True)

    def test_validate_returns_the_discount(self):
        r = self.client.post("/api/v1/coupons/validate",
                             {"code": "SAVE50", "cart_total": "500"},
                             format="json")
        self.assertEqual(r.status_code, 200)
        data = r.json().get("data", r.json())
        self.assertTrue(data["valid"])
        self.assertEqual(data["discount"], 50.0)

    def test_validate_rejects_an_exhausted_coupon(self):
        c = Coupon.objects.get(code="SAVE50")
        c.usage_limit = 1
        c.save(update_fields=["usage_limit"])
        CouponRedemption.objects.create(coupon=c, user=self.user,
                                        order_code="OLD", amount=Decimal("50"))
        r = self.client.post("/api/v1/coupons/validate",
                             {"code": "SAVE50", "cart_total": "500"},
                             format="json")
        data = r.json().get("data", r.json())
        self.assertFalse(data["valid"])
        self.assertEqual(data["discount"], 0.0)
