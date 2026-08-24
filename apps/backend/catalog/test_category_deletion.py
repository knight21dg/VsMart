"""Deleting a category.

`Product.category` is PROTECT and NOT NULL — a category with products can't be
row-deleted without either reassigning them first or leaving them orphaned.
It used to just raise `ProtectedError`, which isn't a DRF exception, so it
escaped as an unexplained 500 instead of telling the operator why nothing
happened. It then went through a deactivate-instead-of-delete phase (mirroring
zones/stores), but categories are a worse fit for that pattern: Product.category
has no null fallback, so "leave it deactivated until every product is manually
moved" was a dead end with no real second step. Delete is now a real, one-shot
delete: the category and its whole subtree go, and any product caught in it is
auto-reassigned to a catch-all 'Uncategorized' category rather than blocking
the delete or being destroyed with it.
"""
from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product


class CategoryDeletionContractTests(TestCase):
    def setUp(self):
        self.super = User.objects.create(
            phone="+919000000601", name="Super", role="superadmin"
        )
        self.client = APIClient()
        self.client.force_authenticate(self.super)

    def test_unused_category_is_really_deleted_and_says_so(self):
        cat = Category.objects.create(name="Snacks", slug="snacks-cd1")
        r = self.client.delete(f"/api/v1/admin/catalog/categories/{cat.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertTrue(body["success"])
        self.assertEqual(body["code"], "RECORD_DELETED")
        self.assertFalse(Category.objects.filter(pk=cat.pk).exists())

    def test_category_with_products_moves_them_to_uncategorized_and_deletes(self):
        cat = Category.objects.create(name="Beverages", slug="beverages-cd1")
        p = Product.objects.create(
            name="Cola", category=cat, price="20.00", mrp="25.00",
        )
        r = self.client.delete(f"/api/v1/admin/catalog/categories/{cat.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["code"], "RECORD_DELETED")
        self.assertEqual(body["data"]["productsMoved"], 1)
        self.assertFalse(Category.objects.filter(pk=cat.pk).exists())
        p.refresh_from_db()
        self.assertEqual(p.category.slug, "uncategorized")

    def test_deleting_a_parent_with_sub_categories_and_products_is_one_shot(self):
        """The exact real-world case this was built for: Beverage with 4
        sub-categories and 7 products across them, gone in a single call."""
        parent = Category.objects.create(name="Beverage", slug="beverage-cd1")
        subs = [
            Category.objects.create(name=n, slug=f"{n.lower()}-cd1", parent=parent)
            for n in ("Water", "Juices", "Tea", "Soft Drinks")
        ]
        products = [
            Product.objects.create(name=f"P{i}", category=subs[i % 4],
                                   price="10.00", mrp="12.00")
            for i in range(7)
        ]
        r = self.client.delete(f"/api/v1/admin/catalog/categories/{parent.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["code"], "RECORD_DELETED")
        self.assertEqual(body["data"]["descendantsRemoved"], 4)
        self.assertEqual(body["data"]["productsMoved"], 7)
        self.assertFalse(Category.objects.filter(pk=parent.pk).exists())
        for s in subs:
            self.assertFalse(Category.objects.filter(pk=s.pk).exists())
        for p in products:
            p.refresh_from_db()
            self.assertEqual(p.category.slug, "uncategorized")

    def test_uncategorized_is_reused_not_duplicated(self):
        cat1 = Category.objects.create(name="A", slug="a-cd1")
        Product.objects.create(name="P1", category=cat1, price="1.00", mrp="1.00")
        cat2 = Category.objects.create(name="B", slug="b-cd1")
        Product.objects.create(name="P2", category=cat2, price="1.00", mrp="1.00")

        self.client.delete(f"/api/v1/admin/catalog/categories/{cat1.id}")
        self.client.delete(f"/api/v1/admin/catalog/categories/{cat2.id}")

        self.assertEqual(Category.objects.filter(slug="uncategorized").count(), 1)
        self.assertEqual(
            Product.objects.filter(category__slug="uncategorized").count(), 2
        )

    def test_uncategorized_itself_cannot_be_deleted(self):
        cat = Category.objects.create(name="Junk", slug="junk-cd1")
        Product.objects.create(name="P", category=cat, price="1.00", mrp="1.00")
        self.client.delete(f"/api/v1/admin/catalog/categories/{cat.id}")  # creates it

        uncategorized = Category.objects.get(slug="uncategorized")
        r = self.client.delete(f"/api/v1/admin/catalog/categories/{uncategorized.id}")
        self.assertEqual(r.status_code, 400, r.content)
        self.assertTrue(Category.objects.filter(slug="uncategorized").exists())

    def test_deleting_a_category_never_500s_on_the_old_protected_error_path(self):
        """The exact old failure mode: a plain ORM delete on a category with
        products used to raise ProtectedError straight through as a 500."""
        cat = Category.objects.create(name="Frozen", slug="frozen-cd1")
        Product.objects.create(
            name="Ice Cream", category=cat, price="80.00", mrp="90.00",
        )
        r = self.client.delete(f"/api/v1/admin/catalog/categories/{cat.id}")
        self.assertNotEqual(r.status_code, 500, r.content)
        self.assertEqual(r.status_code, 200, r.content)
