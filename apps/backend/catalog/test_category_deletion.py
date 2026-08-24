"""Deleting a category.

`Product.category` is PROTECT and NOT NULL — a category with products can't be
row-deleted without either reassigning them first or leaving them orphaned, and
neither is what "delete this category" should silently do. It used to just
raise `ProtectedError`, which isn't a DRF exception, so it escaped as an
unexplained 500 instead of telling the operator why nothing happened. Now it
deactivates instead (same contract as zones/stores), and says so.
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

    def test_category_with_products_is_deactivated_not_deleted(self):
        cat = Category.objects.create(name="Beverages", slug="beverages-cd1")
        Product.objects.create(
            name="Cola", category=cat, price="20.00", mrp="25.00",
        )
        r = self.client.delete(f"/api/v1/admin/catalog/categories/{cat.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["code"], "RECORD_DEACTIVATED")
        cat.refresh_from_db()
        self.assertFalse(cat.is_active)
        # The product keeps its category — that is the whole point.
        self.assertEqual(Product.objects.filter(category=cat).count(), 1)

    def test_category_with_children_is_deactivated_not_deleted(self):
        parent = Category.objects.create(name="Dairy", slug="dairy-cd1")
        Category.objects.create(name="Milk", slug="milk-cd1", parent=parent)
        r = self.client.delete(f"/api/v1/admin/catalog/categories/{parent.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["code"], "RECORD_DEACTIVATED")
        parent.refresh_from_db()
        self.assertFalse(parent.is_active)
        self.assertTrue(Category.objects.filter(slug="milk-cd1").exists())

    def test_deactivating_a_category_never_500s_on_the_old_protected_error_path(self):
        """The exact old failure mode: a plain ORM delete on a category with
        products used to raise ProtectedError straight through as a 500."""
        cat = Category.objects.create(name="Frozen", slug="frozen-cd1")
        Product.objects.create(
            name="Ice Cream", category=cat, price="80.00", mrp="90.00",
        )
        r = self.client.delete(f"/api/v1/admin/catalog/categories/{cat.id}")
        self.assertNotEqual(r.status_code, 500, r.content)
        self.assertEqual(r.status_code, 200, r.content)
