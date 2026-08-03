"""Inventory ledger invariants — the integrity backbone of Phase 5.

The one rule under test: stock is never written directly; every movement is a signed
InventoryLedger row, and the StockItem cache always equals Σ ledger.qty.
"""
from decimal import Decimal

from django.test import TestCase

from catalog.models import Category, Product

from .models import InventoryLedger, LowStockAlert, StockItem, Warehouse
from .services import (
    InventoryError,
    InventoryService,
    StockCalculationService,
    default_warehouse,
    reconcile,
)

Type = InventoryLedger.Type


def make_product(stock_count=None, price="100.00"):
    cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
    return Product.objects.create(
        name="Test Rice 5kg", brand="VS", unit="5 kg", price=Decimal(price),
        mrp=Decimal("120.00"), category=cat, stock_count=stock_count,
    )


class LedgerInvariantTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.product = make_product()

    def _sum_ledger(self, product, warehouse):
        return sum(
            e.quantity
            for e in InventoryLedger.objects.filter(product=product, warehouse=warehouse)
        )

    def test_post_movement_writes_ledger_and_updates_cache(self):
        entry = InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=40,
        )
        self.assertEqual(entry.balance_after, 40)
        item = StockItem.objects.get(product=self.product, warehouse=self.wh)
        self.assertEqual(item.quantity, 40)
        self.assertEqual(item.quantity, self._sum_ledger(self.product, self.wh))

    def test_invariant_holds_across_many_movements(self):
        moves = [
            (Type.GRN, 100), (Type.SALE, -3), (Type.ORDER, -10), (Type.RETURN, 2),
            (Type.ADJUSTMENT, -5), (Type.GRN, 25), (Type.DAMAGE, -4),
        ]
        for mtype, qty in moves:
            InventoryService.post_movement(
                product=self.product, warehouse=self.wh, type=mtype, quantity=qty,
            )
        item = StockItem.objects.get(product=self.product, warehouse=self.wh)
        ledger_sum = self._sum_ledger(self.product, self.wh)
        on_hand = StockCalculationService.on_hand(self.product, self.wh)
        self.assertEqual(item.quantity, ledger_sum)          # cache == Σ ledger
        self.assertEqual(on_hand, ledger_sum)                # calc == Σ ledger
        self.assertEqual(on_hand, 100 - 3 - 10 + 2 - 5 + 25 - 4)  # == 105

    def test_balance_after_chains_correctly(self):
        for qty in (50, -20, 10):
            InventoryService.post_movement(
                product=self.product, warehouse=self.wh, type=Type.ADJUSTMENT,
                quantity=qty, allow_negative=True,
            )
        running = 0
        for e in InventoryLedger.objects.filter(
            product=self.product, warehouse=self.wh
        ).order_by("created_at", "id"):
            running += e.quantity
            self.assertEqual(e.balance_after, running)

    def test_zero_quantity_rejected(self):
        with self.assertRaises(InventoryError):
            InventoryService.post_movement(
                product=self.product, warehouse=self.wh, type=Type.ADJUSTMENT, quantity=0,
            )

    def test_oversell_blocked_without_flag(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=5,
        )
        with self.assertRaises(InventoryError):
            InventoryService.post_movement(
                product=self.product, warehouse=self.wh, type=Type.SALE, quantity=-10,
            )
        # On-hand unchanged after the failed (rolled-back) movement.
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), 5)

    def test_available_equals_on_hand_minus_reserved(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=30,
        )
        item = StockItem.objects.get(product=self.product, warehouse=self.wh)
        item.reserved = 12
        item.save(update_fields=["reserved"])
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 18)


class OpeningAdoptionTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)

    def test_legacy_stock_count_adopted_on_first_touch(self):
        product = make_product(stock_count=50)
        # First ledger movement should adopt the legacy 50 as an opening row.
        InventoryService.post_movement(
            product=product, warehouse=self.wh, type=Type.SALE, quantity=-1,
        )
        self.assertTrue(
            InventoryLedger.objects.filter(product=product, type=Type.OPENING).exists()
        )
        self.assertEqual(StockCalculationService.on_hand(product, self.wh), 49)
        product.refresh_from_db()
        self.assertEqual(product.stock_count, 49)

    def test_opening_seeded_only_once(self):
        product = make_product(stock_count=20)
        InventoryService.post_movement(
            product=product, warehouse=self.wh, type=Type.GRN, quantity=5,
        )
        InventoryService.post_movement(
            product=product, warehouse=self.wh, type=Type.GRN, quantity=5,
        )
        self.assertEqual(
            InventoryLedger.objects.filter(product=product, type=Type.OPENING).count(), 1
        )
        self.assertEqual(StockCalculationService.on_hand(product, self.wh), 30)


class TransferTests(TestCase):
    def setUp(self):
        self.a = Warehouse.objects.create(name="A", code="A", is_default=True)
        self.b = Warehouse.objects.create(name="B", code="B")
        self.product = make_product()
        InventoryService.post_movement(
            product=self.product, warehouse=self.a, type=Type.GRN, quantity=20,
        )

    def test_transfer_conserves_total_across_warehouses(self):
        InventoryService.transfer(
            self.product, from_warehouse=self.a, to_warehouse=self.b, quantity=8,
        )
        self.assertEqual(StockCalculationService.on_hand(self.product, self.a), 12)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.b), 8)
        # Network-wide total is conserved.
        self.assertEqual(StockCalculationService.on_hand(self.product), 20)

    def test_transfer_same_warehouse_rejected(self):
        with self.assertRaises(InventoryError):
            InventoryService.transfer(
                self.product, from_warehouse=self.a, to_warehouse=self.a, quantity=1,
            )


class ReconcileTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.product = make_product()

    def test_reconcile_detects_and_fixes_drift(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=40,
        )
        # Corrupt the cache behind the service's back.
        item = StockItem.objects.get(product=self.product, warehouse=self.wh)
        StockItem.objects.filter(pk=item.pk).update(quantity=999)
        fixes = reconcile(product=self.product)
        self.assertEqual(len(fixes), 1)
        item.refresh_from_db()
        self.assertEqual(item.quantity, 40)  # rebuilt from ledger

    def test_reconcile_noop_when_consistent(self):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=7,
        )
        self.assertEqual(reconcile(product=self.product), [])


class AdjustAndAlertTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.product = make_product()

    def test_adjust_set_targets_absolute_on_hand(self):
        InventoryService.adjust(self.product, set=75, warehouse=self.wh)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), 75)
        InventoryService.adjust(self.product, set=60, warehouse=self.wh)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), 60)

    def test_adjust_delta_applies_signed_change(self):
        InventoryService.adjust(self.product, delta=30, warehouse=self.wh)
        InventoryService.adjust(self.product, delta=-12, warehouse=self.wh)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), 18)

    def test_low_stock_alert_raised_and_cleared(self):
        item, _ = StockItem.objects.get_or_create(product=self.product, warehouse=self.wh)
        StockItem.objects.filter(pk=item.pk).update(low_stock_threshold=10)
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=5,
        )  # below threshold → alert
        self.assertTrue(
            LowStockAlert.objects.filter(
                product=self.product, status=LowStockAlert.Status.ACTIVE
            ).exists()
        )
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=50,
        )  # back above → cleared
        self.assertFalse(
            LowStockAlert.objects.filter(
                product=self.product, status=LowStockAlert.Status.ACTIVE
            ).exists()
        )


class DefaultWarehouseTests(TestCase):
    def test_default_warehouse_created_when_absent(self):
        self.assertFalse(Warehouse.objects.exists())
        wh = default_warehouse()
        self.assertTrue(wh.is_default)
        self.assertEqual(default_warehouse(), wh)  # idempotent

    def test_single_default_enforced(self):
        a = Warehouse.objects.create(name="A", code="A", is_default=True)
        b = Warehouse.objects.create(name="B", code="B", is_default=True)
        a.refresh_from_db()
        self.assertFalse(a.is_default)   # demoted
        self.assertTrue(b.is_default)
        self.assertEqual(Warehouse.objects.filter(is_default=True).count(), 1)


class ReservationTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.product = make_product()
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=20,
        )

    def test_reserve_drops_available_not_on_hand(self):
        InventoryService.reserve(self.product, quantity=5, warehouse=self.wh)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), 20)
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 15)

    def test_cannot_reserve_beyond_available(self):
        InventoryService.reserve(self.product, quantity=18, warehouse=self.wh)
        with self.assertRaises(InventoryError):
            InventoryService.reserve(self.product, quantity=5, warehouse=self.wh)

    def test_release_restores_availability(self):
        InventoryService.reserve(self.product, quantity=8, warehouse=self.wh)
        InventoryService.release(self.product, quantity=8, warehouse=self.wh)
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 20)


class OversellGuardTests(TestCase):
    """The last sellable unit can never be reserved twice. (The select_for_update
    row lock in reserve() serialises concurrent checkouts into these sequential
    cases; under the lock, the second contender sees the first's reservation.)"""

    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.product = make_product()

    def _stock(self, n):
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=n)

    def test_last_unit_cannot_be_reserved_twice(self):
        self._stock(1)
        InventoryService.reserve(self.product, quantity=1, warehouse=self.wh)
        with self.assertRaises(InventoryError):  # second checkout for the same unit
            InventoryService.reserve(self.product, quantity=1, warehouse=self.wh)
        # On-hand untouched; nothing oversold.
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 0)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), 1)

    def test_two_units_serve_two_then_reject_third(self):
        self._stock(2)
        InventoryService.reserve(self.product, quantity=1, warehouse=self.wh)
        InventoryService.reserve(self.product, quantity=1, warehouse=self.wh)
        with self.assertRaises(InventoryError):
            InventoryService.reserve(self.product, quantity=1, warehouse=self.wh)
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 0)

    def test_reserve_then_release_then_reserve_succeeds(self):
        self._stock(1)
        InventoryService.reserve(self.product, quantity=1, warehouse=self.wh)
        InventoryService.release(self.product, quantity=1, warehouse=self.wh)
        # Cancelled order freed the unit → next checkout can claim it.
        InventoryService.reserve(self.product, quantity=1, warehouse=self.wh)
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 0)


class AppendOnlyLedgerTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.product = make_product()

    def test_ledger_row_cannot_be_modified_or_deleted(self):
        entry = InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=Type.GRN, quantity=5,
        )
        entry.quantity = 999
        with self.assertRaises(ValueError):
            entry.save()
        with self.assertRaises(ValueError):
            entry.delete()
