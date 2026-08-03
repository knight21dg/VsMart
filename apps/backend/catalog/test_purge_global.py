"""`purge_global_products` — a destructive command, so its safety rails are tested.

The two that matter: it must not change anything without --apply, and it must not
blow up (deleting nothing) on products the POS holds under PROTECT.
"""
from decimal import Decimal
from io import StringIO

from django.core.management import call_command
from django.test import TestCase

from accounts.models import Role, User
from catalog.models import Category, Product
from inventory.models import Warehouse
from orders.models import Order, OrderItem
from stores.models import Store, StoreProduct


def _run(**opts):
    out = StringIO()
    call_command("purge_global_products", stdout=out, **opts)
    return out.getvalue()


class PurgeGlobalProductsTests(TestCase):
    def setUp(self):
        self.cat = Category.objects.create(name="Staples", slug="staples-purge")
        wh = Warehouse.objects.create(name="W", code="W-P", is_active=True)
        self.store = Store.objects.create(
            code="S-P", name="Store", status="active", warehouse=wh,
            address="x", phone="1",
        )
        self.global_a = Product.objects.create(
            name="Shared Rice", price=Decimal("50"), mrp=Decimal("60"),
            category=self.cat,
        )
        self.global_b = Product.objects.create(
            name="Shared Dal", price=Decimal("70"), mrp=Decimal("80"),
            category=self.cat,
        )
        self.owned = Product.objects.create(
            name="Store Atta", price=Decimal("55"), mrp=Decimal("60"),
            category=self.cat, origin_store=self.store,
        )
        StoreProduct.objects.create(
            store=self.store, product=self.global_a, is_available=True
        )

    def test_dry_run_changes_nothing(self):
        out = _run()
        self.assertIn("DRY RUN", out)
        self.assertEqual(Product.objects.filter(origin_store__isnull=True).count(), 2)

    def test_apply_deletes_globals_and_keeps_store_owned(self):
        _run(apply=True)
        self.assertEqual(Product.objects.filter(origin_store__isnull=True).count(), 0)
        self.assertTrue(Product.objects.filter(pk=self.owned.pk).exists())

    def test_cascades_take_the_store_link_with_them(self):
        _run(apply=True)
        self.assertFalse(
            StoreProduct.objects.filter(product_id=self.global_a.pk).exists()
        )

    def test_past_order_lines_survive_with_their_snapshot(self):
        user = User.objects.create(
            phone="+919600014001", name="Cust", role=Role.CUSTOMER
        )
        order = Order.objects.create(
            user=user, subtotal=Decimal("50"), total=Decimal("50")
        )
        item = OrderItem.objects.create(
            order=order, product=self.global_a, name="Shared Rice",
            price=Decimal("50"), mrp=Decimal("60"), quantity=1,
        )
        _run(apply=True)
        item.refresh_from_db()
        # SET_NULL: the history is intact, only the link is gone.
        self.assertIsNone(item.product_id)
        self.assertEqual(item.name, "Shared Rice")
        self.assertEqual(item.price, Decimal("50"))

    def _pos_sale(self, product, code):
        """A till sale referencing `product` — the PROTECT that blocks deletion."""
        from pos.models import POSSession, POSTransaction, POSTransactionItem

        cashier = User.objects.create(
            phone=f"+9196000149{code[-2:]}", name="Cashier", role=Role.CUSTOMER
        )
        session = POSSession.objects.create(
            cashier=cashier, warehouse=self.store.warehouse,
        )
        txn = POSTransaction.objects.create(
            session=session, code=code, subtotal=Decimal("70"),
            tax=Decimal("0"), total=Decimal("70"),
        )
        POSTransactionItem.objects.create(
            transaction=txn, product=product, name=product.name,
            quantity=1, unit_price=Decimal("70"), line_total=Decimal("70"),
        )
        return txn

    def test_pos_protected_products_are_skipped_not_fatal(self):
        # POSTransactionItem.product is PROTECT. Without skipping these, the whole
        # delete raises ProtectedError inside one transaction and NOTHING is
        # removed — the command would silently accomplish nothing.
        self._pos_sale(self.global_b, "POS01")

        from pos.models import POSTransactionItem

        out = _run(apply=True)
        self.assertIn("BLOCKED by PROTECT", out)
        # The unprotected one went…
        self.assertFalse(Product.objects.filter(pk=self.global_a.pk).exists())
        # …the protected one stayed, and the POS history is intact.
        self.assertTrue(Product.objects.filter(pk=self.global_b.pk).exists())
        self.assertEqual(POSTransactionItem.objects.count(), 1)

    def test_deactivate_protected_hides_what_cannot_be_deleted(self):
        self._pos_sale(self.global_b, "POS02")

        _run(apply=True, deactivate_protected=True)
        self.global_b.refresh_from_db()
        self.assertFalse(self.global_b.is_active)
