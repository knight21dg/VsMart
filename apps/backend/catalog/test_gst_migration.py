"""Safety proofs for the GST data migrations.

These exercise the migration FUNCTIONS directly against real rows rather than
asserting on the migration file's text. The properties that matter before this
runs against production data:

  * a fraction is scaled to a percentage exactly once;
  * a value already correct is NOT touched (no double conversion);
  * `0` and `NULL` are left alone;
  * running it twice changes nothing the second time;
  * it is reversible;
  * nothing outside `gst_rate` is modified.
"""
from decimal import Decimal

import importlib

from django.apps import apps as global_apps
from django.test import TestCase

from catalog.models import Category, Product


def _migration_fn(module_path, name):
    """Load a function out of a migration module.

    `importlib` rather than a plain import because a migration module's name
    starts with a digit, which is not a legal identifier.
    """
    return getattr(importlib.import_module(module_path), name)


def _catalog_fn(name):
    return _migration_fn(
        "catalog.migrations.0010_product_gst_rate_as_percentage", name
    )


def _orders_fn(name):
    return _migration_fn(
        "orders.migrations.0012_orderitem_gst_rate_as_percentage", name
    )


class ProductGstMigrationTests(TestCase):
    """`catalog.0010` — the product master."""

    def setUp(self):
        self.category, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.to_percentage = _catalog_fn("to_percentage")
        self.to_fraction = _catalog_fn("to_fraction")

    def _product(self, name, gst):
        return Product.objects.create(
            name=name, brand="VS", unit="1", price=Decimal("100"),
            mrp=Decimal("120"), category=self.category, gst_rate=gst,
            description="untouched", stock_count=None,
        )

    def _run_forward(self):
        self.to_percentage(global_apps, None)

    def test_every_legacy_fraction_scales_to_its_slab(self):
        cases = {
            "zero": (Decimal("0"), Decimal("0")),            # left alone
            "three": (Decimal("0.03"), Decimal("3")),
            "five": (Decimal("0.05"), Decimal("5")),
            "twelve": (Decimal("0.12"), Decimal("12")),
            "eighteen": (Decimal("0.18"), Decimal("18")),
            "twentyeight": (Decimal("0.28"), Decimal("28")),
        }
        for name, (before, _) in cases.items():
            self._product(name, before)

        self._run_forward()

        for name, (_, expected) in cases.items():
            self.assertEqual(
                Product.objects.get(name=name).gst_rate, expected, name
            )

    def test_values_already_correct_are_not_converted_twice(self):
        """The whole point. A percentage must survive the migration unchanged."""
        for name, pct in [("p5", Decimal("5")), ("p18", Decimal("18")),
                          ("p28", Decimal("28"))]:
            self._product(name, pct)
        self._run_forward()
        self.assertEqual(Product.objects.get(name="p5").gst_rate, Decimal("5"))
        self.assertEqual(Product.objects.get(name="p18").gst_rate, Decimal("18"))
        self.assertEqual(Product.objects.get(name="p28").gst_rate, Decimal("28"))

    def test_running_it_twice_is_a_no_op_the_second_time(self):
        self._product("mixed", Decimal("0.18"))
        self._product("already", Decimal("12"))
        self._run_forward()
        first = {p.name: p.gst_rate for p in Product.objects.all()}
        self._run_forward()
        second = {p.name: p.gst_rate for p in Product.objects.all()}
        self.assertEqual(first, second)
        self.assertEqual(first["mixed"], Decimal("18"))

    def test_null_stays_null(self):
        """NULL means "use the platform default" — not zero, and not 0 %."""
        self._product("unset", None)
        self._run_forward()
        self.assertIsNone(Product.objects.get(name="unset").gst_rate)

    def test_zero_stays_zero(self):
        self._product("zerorated", Decimal("0"))
        self._run_forward()
        self.assertEqual(Product.objects.get(name="zerorated").gst_rate, Decimal("0"))

    def test_no_other_column_is_touched(self):
        p = self._product("intact", Decimal("0.18"))
        before = Product.objects.filter(pk=p.pk).values().get()
        self._run_forward()
        after = Product.objects.filter(pk=p.pk).values().get()
        changed = {k for k in before if before[k] != after[k]}
        # updated_at moves because the row was saved; nothing else may.
        self.assertLessEqual(changed, {"gst_rate", "updated_at"})
        self.assertEqual(after["price"], before["price"])
        self.assertEqual(after["description"], before["description"])

    def test_row_count_is_unchanged(self):
        for i in range(5):
            self._product(f"p{i}", Decimal("0.18"))
        before = Product.objects.count()
        self._run_forward()
        self.assertEqual(Product.objects.count(), before)

    def test_the_reverse_restores_the_fractions(self):
        self._product("rt", Decimal("0.18"))
        self._run_forward()
        self.assertEqual(Product.objects.get(name="rt").gst_rate, Decimal("18"))
        self.to_fraction(global_apps, None)
        self.assertEqual(Product.objects.get(name="rt").gst_rate, Decimal("0.18"))

    def test_the_migrated_value_is_accepted_by_the_api_validator(self):
        """A migrated value must be a legal slab, or the next edit of that
        product would fail validation on a field the operator never touched."""
        from core.pricing import GST_SLABS

        for frac in ["0.03", "0.05", "0.12", "0.18", "0.28"]:
            self._product(f"slab{frac}", Decimal(frac))
        self._run_forward()
        for p in Product.objects.exclude(gst_rate__isnull=True):
            self.assertIn(p.gst_rate, GST_SLABS, f"{p.name} → {p.gst_rate}")


class OrderItemGstMigrationTests(TestCase):
    """`orders.0012` — the historical order lines the bug already corrupted."""

    def setUp(self):
        from accounts.models import Role, User
        from orders.models import Order

        self.category, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.user = User.objects.create(
            phone="+919600088001", name="Cust", role=Role.CUSTOMER
        )
        self.order = Order.objects.create(
            user=self.user, subtotal=Decimal("100"), total=Decimal("118"),
            gst=Decimal("18"),
        )
        self.to_percentage = _orders_fn("to_percentage")
        self.to_fraction = _orders_fn("to_fraction")

    def _item(self, name, gst):
        from orders.models import OrderItem

        return OrderItem.objects.create(
            order=self.order, name=name, quantity=1,
            price=Decimal("100"), mrp=Decimal("120"), gst_rate=gst,
        )

    def _run_forward(self):
        self.to_percentage(global_apps, None)

    def test_the_bug_signature_is_repaired(self):
        from orders.models import OrderItem

        self._item("buggy", Decimal("0.18"))
        self._run_forward()
        self.assertEqual(OrderItem.objects.get(name="buggy").gst_rate, Decimal("18"))

    def test_correct_lines_are_left_alone(self):
        from orders.models import OrderItem

        self._item("good", Decimal("5"))
        self._run_forward()
        self.assertEqual(OrderItem.objects.get(name="good").gst_rate, Decimal("5"))

    def test_zero_rated_lines_are_left_alone(self):
        from orders.models import OrderItem

        self._item("zero", Decimal("0"))
        self._run_forward()
        self.assertEqual(OrderItem.objects.get(name="zero").gst_rate, Decimal("0"))

    def test_it_is_idempotent(self):
        from orders.models import OrderItem

        self._item("a", Decimal("0.18"))
        self._item("b", Decimal("0"))
        self._item("c", Decimal("12"))
        self._run_forward()
        first = {i.name: i.gst_rate for i in OrderItem.objects.all()}
        self._run_forward()
        self.assertEqual({i.name: i.gst_rate for i in OrderItem.objects.all()}, first)

    def test_the_money_on_the_order_is_never_touched(self):
        """The rate label was wrong; the amount charged was not. Repairing the
        label must not move a single rupee."""
        from orders.models import Order

        self._item("buggy", Decimal("0.18"))
        self._run_forward()
        self.order.refresh_from_db()
        self.assertEqual(self.order.total, Decimal("118"))
        self.assertEqual(self.order.gst, Decimal("18"))
        self.assertEqual(self.order.subtotal, Decimal("100"))

    def test_row_count_and_line_amounts_are_unchanged(self):
        from orders.models import OrderItem

        self._item("x", Decimal("0.18"))
        self._item("y", Decimal("0.18"))
        before = OrderItem.objects.count()
        self._run_forward()
        self.assertEqual(OrderItem.objects.count(), before)
        for item in OrderItem.objects.all():
            self.assertEqual(item.price, Decimal("100"))
            self.assertEqual(item.quantity, 1)

    def test_the_reverse_restores_the_fractions(self):
        from orders.models import OrderItem

        self._item("rt", Decimal("0.18"))
        self._run_forward()
        self.to_fraction(global_apps, None)
        self.assertEqual(OrderItem.objects.get(name="rt").gst_rate, Decimal("0.18"))
