"""Stock transfers move a PACK, not a vague product.

Stock is held per product x variant x warehouse — a 1 kg pack and a 5 kg pack
are separate SKUs with their own counts. `StockTransfer` had no `variant` field
and `_complete_transfer` never passed one, so every transfer drew on the
`variant=NULL` unallocated pool: choosing "10 Rice" in the console moved
unallocated units rather than the packs the operator meant, and failed outright
when there were none, while the packs sat full.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import Role, User
from catalog.models import Category, Product, ProductVariant
from inventory.models import InventoryLedger, StockTransfer, Warehouse
from inventory.services import InventoryService, StockCalculationService


class TransferVariantTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(
            phone="+919600111001", name="Admin", role=Role.ADMIN
        )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

        self.a = Warehouse.objects.create(name="A", code="WHA")
        self.b = Warehouse.objects.create(name="B", code="WHB")
        cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Rice", brand="VS", unit="kg", price=Decimal("50"),
            mrp=Decimal("60"), category=cat, stock_count=None,
        )
        self.one_kg = ProductVariant.objects.create(product=self.product, label="1 kg")
        self.five_kg = ProductVariant.objects.create(product=self.product, label="5 kg")

        # 20 of the 1 kg pack at A. Nothing unallocated, nothing of 5 kg.
        InventoryService.post_movement(
            product=self.product, variant=self.one_kg, warehouse=self.a,
            type=InventoryLedger.Type.GRN, quantity=20,
        )

    def _create(self, **body):
        payload = {
            "productId": self.product.id,
            "fromWarehouse": self.a.id,
            "toWarehouse": self.b.id,
            "quantity": 5,
        }
        payload.update(body)
        return self.client.post("/api/v1/inventory/transfer", payload, format="json")

    # ── the bug ──
    def test_a_variant_product_cannot_be_transferred_without_naming_the_pack(self):
        """This used to succeed and then silently move the unallocated pool."""
        r = self._create()
        self.assertEqual(r.status_code, 400, r.content)
        detail = str(r.json())
        self.assertIn("stocked per pack", detail)
        self.assertIn("1 kg", detail)  # the error lists the real choices

    def test_transferring_a_named_pack_moves_that_packs_stock(self):
        r = self._create(variantId=self.one_kg.id)
        self.assertEqual(r.status_code, 201, r.content)
        transfer_id = r.json()["data"]["id"]

        done = self.client.post(
            f"/api/v1/inventory/transfers/{transfer_id}/complete"
        )
        self.assertEqual(done.status_code, 200, done.content)

        # 5 of the 1 kg pack left A and arrived at B — as that pack.
        self.assertEqual(
            StockCalculationService.available(self.product, self.a, self.one_kg), 15
        )
        self.assertEqual(
            StockCalculationService.available(self.product, self.b, self.one_kg), 5
        )
        # And nothing leaked into the unallocated pool at either end.
        self.assertEqual(
            StockCalculationService.available(self.product, self.b, None), 0
        )

    def test_the_other_pack_is_untouched(self):
        r = self._create(variantId=self.one_kg.id)
        self.client.post(
            f"/api/v1/inventory/transfers/{r.json()['data']['id']}/complete"
        )
        self.assertEqual(
            StockCalculationService.available(self.product, self.a, self.five_kg), 0
        )
        self.assertEqual(
            StockCalculationService.available(self.product, self.b, self.five_kg), 0
        )

    # ── validation ──
    def test_a_pack_from_a_different_product_is_refused(self):
        cat = Category.objects.get(slug="grocery")
        other = Product.objects.create(
            name="Dal", brand="VS", unit="kg", price=Decimal("80"),
            mrp=Decimal("90"), category=cat, stock_count=None,
        )
        foreign = ProductVariant.objects.create(product=other, label="1 kg")
        r = self._create(variantId=foreign.id)
        self.assertEqual(r.status_code, 400, r.content)
        self.assertIn("doesn't belong to this product", str(r.json()))

    def test_transferring_more_than_the_pack_holds_is_refused_up_front(self):
        """It used to sit PENDING and only fail on completion — after the
        receiving store had been told it was coming."""
        r = self._create(variantId=self.one_kg.id, quantity=999)
        self.assertEqual(r.status_code, 400, r.content)
        self.assertIn("Only 20 of 1 kg available", str(r.json()))
        self.assertEqual(StockTransfer.objects.count(), 0)

    def test_the_source_check_is_per_pack_not_per_product(self):
        """20 units exist, but all of them are 1 kg — 5 kg has nothing."""
        r = self._create(variantId=self.five_kg.id, quantity=1)
        self.assertEqual(r.status_code, 400, r.content)
        self.assertIn("Only 0 of 5 kg available", str(r.json()))

    def test_unallocated_stock_must_be_allocated_before_it_can_move(self):
        """Unallocated stock is "assign me" stock. `post_movement` refuses a
        pack-less movement on a packed product, so a transfer of the pool could
        only ever fail downstream — it is refused up front, with the fix named."""
        cat = Category.objects.get(slug="grocery")
        pooled = Product.objects.create(
            name="Atta", brand="VS", unit="kg", price=Decimal("40"),
            mrp=Decimal("45"), category=cat, stock_count=None,
        )
        # Stock received BEFORE packs existed — the only way a pool arises.
        InventoryService.post_movement(
            product=pooled, variant=None, warehouse=self.a,
            type=InventoryLedger.Type.GRN, quantity=7,
        )
        ProductVariant.objects.create(product=pooled, label="1 kg")

        r = self._create(productId=pooled.id, quantity=7)
        self.assertEqual(r.status_code, 400, r.content)
        self.assertIn("allocated to a pack", str(r.json()))
        self.assertEqual(StockTransfer.objects.count(), 0)

    def test_a_product_with_no_packs_transfers_exactly_as_before(self):
        cat = Category.objects.get(slug="grocery")
        simple = Product.objects.create(
            name="Salt", brand="VS", unit="pack", price=Decimal("20"),
            mrp=Decimal("25"), category=cat, stock_count=None,
        )
        InventoryService.post_movement(
            product=simple, warehouse=self.a,
            type=InventoryLedger.Type.GRN, quantity=10,
        )
        r = self.client.post("/api/v1/inventory/transfer", {
            "productId": simple.id, "fromWarehouse": self.a.id,
            "toWarehouse": self.b.id, "quantity": 4,
        }, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        self.client.post(
            f"/api/v1/inventory/transfers/{r.json()['data']['id']}/complete"
        )
        self.assertEqual(StockCalculationService.available(simple, self.b, None), 4)

    # ── the board has to show which pack ──
    def test_the_transfer_row_names_the_pack(self):
        r = self._create(variantId=self.one_kg.id)
        row = r.json()["data"]
        self.assertEqual(row["variantLabel"], "1 kg")

