"""Everything the customer sees must belong to the store serving their location.

The product endpoints were already scoped; the CATEGORY endpoints were not — so a
customer saw departments their store carries nothing in, tapped one, and got an
empty listing. Dead tiles.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import Role, User
from catalog.models import Category, Product
from inventory.models import Warehouse
from stores.models import Store, StoreProduct
from system.models import FeatureFlag


def _rows(response):
    body = response.json()
    data = body.get("data", body) if isinstance(body, dict) else body
    if isinstance(data, dict):
        data = data.get("results", data.get("items", []))
    return data


class CategoryScopingTests(TestCase):
    def setUp(self):
        FeatureFlag.objects.update_or_create(
            key="zone_store_visibility", defaults={"enabled": True}
        )
        self.client_ = APIClient()
        self.grocery = Category.objects.create(name="Grocery", slug="g-zs")
        self.staples = Category.objects.create(
            name="Staples", slug="st-zs", parent=self.grocery
        )
        self.electronics = Category.objects.create(name="Electronics", slug="e-zs")
        self.tvs = Category.objects.create(
            name="TVs", slug="tv-zs", parent=self.electronics
        )
        self.store_a = self._store("A")
        self.store_b = self._store("B")
        # Store A sells groceries; Store B sells electronics.
        self._stock(self.store_a, "Atta", self.staples)
        self._stock(self.store_b, "Smart TV", self.tvs)

    def _store(self, tag):
        wh = Warehouse.objects.create(name=f"W{tag}", code=f"W-{tag}", is_active=True)
        return Store.objects.create(
            code=f"S-{tag}", name=f"Store {tag}", status="active", warehouse=wh,
            address="x", phone="1",
        )

    def _stock(self, store, name, category):
        p = Product.objects.create(
            name=name, price=Decimal("50"), mrp=Decimal("60"), category=category
        )
        StoreProduct.objects.create(store=store, product=p, is_available=True)
        return p

    def _departments(self, store=None):
        url = "/api/v1/categories"
        if store is not None:
            url += f"?store={store.id}"
        return sorted(c["name"] for c in _rows(self.client_.get(url)))

    def test_departments_are_limited_to_what_the_store_can_fill(self):
        self.assertEqual(self._departments(self.store_a), ["Grocery"])
        self.assertEqual(self._departments(self.store_b), ["Electronics"])

    def test_subcategories_are_scoped_too(self):
        rows = _rows(
            self.client_.get(
                f"/api/v1/categories/{self.grocery.id}/sub-categories"
                f"?store={self.store_b.id}"
            )
        )
        # Store B sells no groceries, so it must not advertise Staples.
        self.assertEqual(rows, [])

    def test_no_serving_store_shows_nothing_rather_than_everything(self):
        # Scoping active but out of area: an empty tree is honest; the whole
        # company tree would be a screen of tiles that all open empty.
        self.assertEqual(self._departments(), [])

    def test_search_suggestions_do_not_offer_another_stores_category(self):
        data = self.client_.get(
            f"/api/v1/products/suggest?q=TV&store={self.store_a.id}"
        ).json()
        payload = data.get("data", data)
        self.assertEqual(payload.get("categories"), [])

    def test_global_mode_is_unchanged(self):
        # Flag off and no location: a single-store deployment keeps the full tree.
        FeatureFlag.objects.filter(key="zone_store_visibility").update(enabled=False)
        self.assertEqual(self._departments(), ["Electronics", "Grocery"])


class CouponWalletTests(TestCase):
    """A wallet shows YOUR coupons — not everyone's."""

    def setUp(self):
        from offers.models import Coupon

        self.me = User.objects.create(
            phone="+919600015001", name="Me", role=Role.CUSTOMER
        )
        self.someone_else = User.objects.create(
            phone="+919600015002", name="Them", role=Role.CUSTOMER
        )
        self.client_ = APIClient()
        self.client_.force_authenticate(user=self.me)

        Coupon.objects.create(code="PUBLIC10", is_active=True,
                              discount_type="flat", value=Decimal("10"))
        Coupon.objects.create(code="MINE", is_active=True, owner=self.me,
                              discount_type="flat", value=Decimal("50"))
        Coupon.objects.create(code="THEIRS", is_active=True,
                              owner=self.someone_else,
                              discount_type="flat", value=Decimal("99"))

    def _codes(self):
        return sorted(c["code"] for c in _rows(self.client_.get("/api/v1/coupons/wallet")))

    def test_another_users_personal_coupon_is_not_disclosed(self):
        codes = self._codes()
        self.assertIn("PUBLIC10", codes)
        self.assertIn("MINE", codes)
        self.assertNotIn("THEIRS", codes)

    def test_expired_coupons_are_not_offered(self):
        from datetime import timedelta

        from django.utils import timezone

        from offers.models import Coupon

        Coupon.objects.create(
            code="OLD", is_active=True, discount_type="flat", value=Decimal("5"),
            valid_to=timezone.now().date() - timedelta(days=1),
        )
        self.assertNotIn("OLD", self._codes())


class ServiceabilityTests(TestCase):
    """A zone we can't actually serve must say so."""

    def test_a_zone_with_no_store_is_not_serviceable(self):
        from zones.models import Zone
        from zones.serviceability import serviceability

        Zone.objects.create(
            name="Uncovered", pincodes="500001", is_active=True, store=None,
        )
        result = serviceability(pincode="500001")
        # Used to answer serviceable=True with store_id=None, so the app unlocked
        # into a guaranteed-empty catalog with no explanation.
        self.assertFalse(result["serviceable"])
        self.assertIsNone(result["store_id"])
        # We still know WHERE they are — the UI can name the area.
        self.assertEqual(result["zone_name"], "Uncovered")

    def test_a_zone_with_a_live_store_is_serviceable(self):
        from zones.models import Zone
        from zones.serviceability import serviceability

        wh = Warehouse.objects.create(name="W", code="W-SV", is_active=True)
        store = Store.objects.create(
            code="S-SV", name="Live", status="active", warehouse=wh,
            address="x", phone="1",
        )
        Zone.objects.create(
            name="Covered", pincodes="500002", is_active=True, store=store,
        )
        result = serviceability(pincode="500002")
        self.assertTrue(result["serviceable"])
        self.assertEqual(result["store_id"], str(store.id))
