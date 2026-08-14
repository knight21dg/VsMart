from decimal import Decimal

from django.conf import settings
from django.db import models

from catalog.models import Product
from core.models import TimeStampedModel

ZERO = Decimal("0.00")


# ── Masters ──────────────────────────────────────────────
class Brand(TimeStampedModel):
    name = models.CharField(max_length=120, unique=True)
    code = models.CharField(max_length=40, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Unit(TimeStampedModel):
    """Unit of measure master (e.g. Kilogram/kg, Piece/pc)."""

    name = models.CharField(max_length=60, unique=True)
    code = models.CharField(max_length=20, unique=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return f"{self.name} ({self.code})"


class Supplier(TimeStampedModel):
    name = models.CharField(max_length=160)
    gstin = models.CharField(max_length=20, blank=True)
    phone = models.CharField(max_length=15, blank=True)
    email = models.EmailField(blank=True)
    address = models.CharField(max_length=300, blank=True)
    is_active = models.BooleanField(default=True)
    # Store-scoped: each store keeps its own suppliers. Null = legacy/global supplier
    # visible to every store.
    store = models.ForeignKey(
        "stores.Store",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="suppliers",
    )

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Barcode(TimeStampedModel):
    """Product/variant ↔ barcode (unique), for POS scanning."""

    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="barcodes"
    )
    variant = models.ForeignKey(
        "catalog.ProductVariant",
        on_delete=models.CASCADE,
        related_name="barcodes",
        null=True,
        blank=True,
    )
    code = models.CharField(max_length=64, unique=True)
    symbology = models.CharField(max_length=20, default="EAN13")
    is_primary = models.BooleanField(default=False)

    class Meta:
        ordering = ["-is_primary", "code"]

    def __str__(self):
        return f"{self.code} → {self.product_id}"


# ── Warehouse / stock cache ──────────────────────────────
class Warehouse(TimeStampedModel):
    name = models.CharField(max_length=120)
    code = models.CharField(max_length=40, unique=True)
    is_active = models.BooleanField(default=True)
    is_default = models.BooleanField(default=False)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return f"{self.name} ({self.code})"

    def save(self, *args, **kwargs):
        # Enforce a single default warehouse — demote any other default first.
        # (App-level guarantee on every write path; a DB UniqueConstraint here is
        # avoided because DRF surfaces partial constraints as a hard 400 validator.)
        if self.is_default:
            Warehouse.objects.exclude(pk=self.pk).filter(is_default=True).update(
                is_default=False
            )
        super().save(*args, **kwargs)


class StockItem(TimeStampedModel):
    """Per product×variant×warehouse on-hand CACHE. `quantity` is derived from the
    InventoryLedger (Σ qty) and rebuilt by `reconcile()` — never written by
    callers directly; only `InventoryService.post_movement` updates it.

    ``variant=NULL`` is a real bucket, not "any variant":

    * for a product with NO variants it is *the* stock — unchanged behaviour;
    * for a product WITH variants it is the **unallocated pool** — stock received
      before the pack sizes existed. It is counted in the product total but is not
      sellable as any particular variant until a store allocates it, because
      nothing knows which pack those units are. Allocating posts a conserving
      adjustment pair (out of NULL, into the variant).

    Nullable rather than required because most groceries have no variants at all,
    and because a NULL bucket lets stock that predates a variant survive the
    change instead of being silently reassigned to a guessed pack.
    """

    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="stock_items"
    )
    variant = models.ForeignKey(
        "catalog.ProductVariant",
        on_delete=models.CASCADE,
        related_name="stock_items",
        null=True,
        blank=True,
    )
    warehouse = models.ForeignKey(
        Warehouse, on_delete=models.CASCADE, related_name="stock"
    )
    quantity = models.IntegerField(default=0)  # cache of Σ ledger.qty
    reserved = models.PositiveIntegerField(default=0)
    # Cumulative units written off as damaged/expired (segregated, unsellable) —
    # cache of Σ |qty| over DAMAGE/EXPIRY ledger rows, maintained by post_movement.
    damaged = models.PositiveIntegerField(default=0)
    low_stock_threshold = models.PositiveIntegerField(default=10)

    class Meta:
        # Two partial constraints rather than one unique_together: in SQL, NULL is
        # never equal to NULL, so a plain (product, variant, warehouse) unique
        # would let unlimited duplicate variant=NULL rows through — exactly the
        # bucket every non-variant product uses. Postgres 15+ could express this
        # as NULLS NOT DISTINCT, but partial constraints work on every backend.
        constraints = [
            models.UniqueConstraint(
                fields=["product", "warehouse"],
                condition=models.Q(variant__isnull=True),
                name="uniq_stockitem_product_warehouse_novariant",
            ),
            models.UniqueConstraint(
                fields=["product", "variant", "warehouse"],
                condition=models.Q(variant__isnull=False),
                name="uniq_stockitem_product_variant_warehouse",
            ),
        ]
        ordering = ["-created_at"]

    def __str__(self):
        label = f" · {self.variant.label}" if self.variant_id else ""
        return f"{self.product}{label} @ {self.warehouse}"

    @property
    def available(self):
        return self.quantity - self.reserved


class StockBatch(TimeStampedModel):
    """A received lot — drives FEFO picking and expiry management."""

    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="batches"
    )
    # A lot is received as a specific pack — 40×1kg and 40×500g arrive, and expire,
    # as separate lots. NULL = a lot of a product that has no variants.
    variant = models.ForeignKey(
        "catalog.ProductVariant",
        on_delete=models.CASCADE,
        related_name="batches",
        null=True,
        blank=True,
    )
    warehouse = models.ForeignKey(
        Warehouse, on_delete=models.CASCADE, related_name="batches"
    )
    batch_no = models.CharField(max_length=60)
    expiry_date = models.DateField(null=True, blank=True)
    quantity = models.IntegerField(default=0)  # remaining in this batch (cache)
    unit_cost = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)

    class Meta:
        ordering = ["expiry_date", "created_at"]  # FEFO order
        indexes = [
            models.Index(fields=["product", "warehouse", "expiry_date"]),
            models.Index(
                fields=["product", "variant", "warehouse", "expiry_date"],
                name="inv_batch_pvwe_idx",
            ),
        ]

    def __str__(self):
        label = f" · {self.variant.label}" if self.variant_id else ""
        return f"{self.product}{label} batch {self.batch_no}"


# ── The ledger (system of record) ────────────────────────
class InventoryLedger(models.Model):
    """Append-only stock movement ledger — the system of record for all stock.

    The one rule: never update stock directly. Every movement is a row here with a
    signed `quantity`; on-hand for a product×variant×warehouse is Σ quantity (the
    StockItem cache mirrors it). Never UPDATE/DELETE — corrections are new
    `adjustment` rows.
    """

    class Type(models.TextChoices):
        OPENING = "opening"            # adopt legacy / initial count (signed +)
        PURCHASE = "purchase"          # PO receipt (+)
        GRN = "grn"                    # goods receipt note (+)
        SALE = "sale"                  # POS sale (−)
        ORDER = "order"                # online order fulfilment (−)
        ORDER_CANCEL = "order_cancel"  # online order cancel (+)
        RETURN = "return"              # customer return (+)
        REFUND = "refund"             # refund restock (+)
        TRANSFER_IN = "transfer_in"    # into destination warehouse (+)
        TRANSFER_OUT = "transfer_out"  # out of source warehouse (−)
        ADJUSTMENT = "adjustment"      # manual correction (signed)
        DAMAGE = "damage"              # written off damaged (−)
        EXPIRY = "expiry"              # written off expired (−)

    product = models.ForeignKey(
        Product, on_delete=models.PROTECT, related_name="ledger_entries"
    )
    variant = models.ForeignKey(
        "catalog.ProductVariant",
        on_delete=models.SET_NULL,
        related_name="ledger_entries",
        null=True,
        blank=True,
    )
    warehouse = models.ForeignKey(
        Warehouse, on_delete=models.PROTECT, related_name="ledger_entries"
    )
    type = models.CharField(max_length=14, choices=Type.choices)
    quantity = models.IntegerField()  # signed
    # on-hand for this row's product×variant×warehouse bucket after the movement
    balance_after = models.IntegerField()
    batch = models.ForeignKey(
        StockBatch,
        on_delete=models.SET_NULL,
        related_name="movements",
        null=True,
        blank=True,
    )
    expiry_date = models.DateField(null=True, blank=True)
    unit_cost = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )  # for valuation (per-unit cost at this movement)
    ref_type = models.CharField(max_length=40, blank=True)  # e.g. "grn", "pos", "order"
    ref_id = models.CharField(max_length=64, blank=True)
    note = models.CharField(max_length=200, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["product", "warehouse", "created_at"]),
            models.Index(
                fields=["product", "variant", "warehouse", "created_at"],
                name="inv_ledger_pvwc_idx",
            ),
            models.Index(fields=["type", "created_at"]),
        ]

    def __str__(self):
        return f"{self.type} {self.quantity:+d} {self.product_id}@{self.warehouse_id}"

    def save(self, *args, **kwargs):
        # Append-only: ledger rows are immutable; corrections are new rows.
        if not self._state.adding:
            raise ValueError("InventoryLedger is append-only and cannot be modified.")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("InventoryLedger is append-only and cannot be deleted.")


class LowStockAlert(TimeStampedModel):
    class Status(models.TextChoices):
        ACTIVE = "active"
        CLEARED = "cleared"

    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="low_stock_alerts"
    )
    # Alerts are per pack: a shop out of 1kg needs telling even when the 500g shelf
    # is full, and a product-level alert would never fire. NULL = no variants.
    variant = models.ForeignKey(
        "catalog.ProductVariant",
        on_delete=models.CASCADE,
        related_name="low_stock_alerts",
        null=True,
        blank=True,
    )
    warehouse = models.ForeignKey(
        Warehouse, on_delete=models.CASCADE, related_name="low_stock_alerts"
    )
    threshold = models.PositiveIntegerField()
    available_at_raise = models.IntegerField()
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.ACTIVE
    )
    raised_at = models.DateTimeField(auto_now_add=True)
    cleared_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-raised_at"]

    def __str__(self):
        label = f" · {self.variant.label}" if self.variant_id else ""
        return f"low-stock {self.product_id}{label}@{self.warehouse_id} ({self.status})"


# ── Transfers ────────────────────────────────────────────
class StockTransfer(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "pending"
        COMPLETED = "completed"
        CANCELLED = "cancelled"

    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    #: Which pack is moving. Stock is held per product×variant×warehouse, so a
    #: transfer that doesn't name the pack can only ever move the `variant=NULL`
    #: unallocated pool — which is what this did: sending "10 Rice" between
    #: stores drew on unallocated units rather than the 1 kg packs the operator
    #: had chosen, and simply failed when there were none. NULL still means the
    #: unallocated pool, consistent with the rest of the inventory model.
    variant = models.ForeignKey(
        "catalog.ProductVariant", on_delete=models.SET_NULL,
        null=True, blank=True, related_name="transfers",
    )
    from_warehouse = models.ForeignKey(
        Warehouse, on_delete=models.CASCADE, related_name="transfers_out"
    )
    to_warehouse = models.ForeignKey(
        Warehouse, on_delete=models.CASCADE, related_name="transfers_in"
    )
    quantity = models.PositiveIntegerField()
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.PENDING
    )
    note = models.CharField(max_length=200, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )

    def __str__(self):
        return f"{self.product}: {self.from_warehouse} → {self.to_warehouse}"


# ── Procurement ──────────────────────────────────────────
class PurchaseOrder(TimeStampedModel):
    class Status(models.TextChoices):
        DRAFT = "draft"
        ORDERED = "ordered"
        PARTIAL = "partial"
        RECEIVED = "received"
        CANCELLED = "cancelled"

    supplier_name = models.CharField(max_length=160)  # kept for back-compat
    supplier = models.ForeignKey(
        Supplier, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="purchase_orders",
    )
    warehouse = models.ForeignKey(Warehouse, on_delete=models.CASCADE)
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.DRAFT
    )
    expected_at = models.DateField(null=True, blank=True)
    subtotal = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    tax = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    total = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    received_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True
    )

    def __str__(self):
        return f"PO {self.pk} — {self.supplier_name}"


class PurchaseOrderItem(models.Model):
    purchase_order = models.ForeignKey(
        PurchaseOrder, on_delete=models.CASCADE, related_name="items"
    )
    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    quantity = models.PositiveIntegerField()
    received_quantity = models.PositiveIntegerField(default=0)
    unit_cost = models.DecimalField(max_digits=12, decimal_places=2)


class GRN(TimeStampedModel):
    """Goods Receipt Note — receiving stock against (optionally) a PO. Posting a
    GRN writes one `grn` ledger row per line via InventoryService."""

    class Status(models.TextChoices):
        DRAFT = "draft"
        POSTED = "posted"

    purchase_order = models.ForeignKey(
        PurchaseOrder, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="grns",
    )
    supplier = models.ForeignKey(
        Supplier, on_delete=models.SET_NULL, null=True, blank=True
    )
    warehouse = models.ForeignKey(Warehouse, on_delete=models.PROTECT)
    reference = models.CharField(max_length=60, blank=True)  # supplier invoice no
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.DRAFT
    )
    total_cost = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    posted_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True
    )

    def __str__(self):
        return f"GRN {self.pk} ({self.status})"


class GRNItem(models.Model):
    grn = models.ForeignKey(GRN, on_delete=models.CASCADE, related_name="items")
    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    variant = models.ForeignKey(
        "catalog.ProductVariant", on_delete=models.SET_NULL, null=True, blank=True
    )
    quantity = models.PositiveIntegerField()
    unit_cost = models.DecimalField(max_digits=12, decimal_places=2)
    batch_no = models.CharField(max_length=60, blank=True)
    expiry_date = models.DateField(null=True, blank=True)


class PurchaseInvoice(TimeStampedModel):
    """A supplier's bill — what we actually OWE, as distinct from what we ordered
    (PurchaseOrder) or received (GRN).

    Without this the procurement loop had no closing end: stock could be received
    but the liability was never recorded, so there was no payables balance and no
    aging. `balance_due` is the running amount outstanding; it is derived from
    payments and never edited directly.
    """

    class Status(models.TextChoices):
        DRAFT = "draft"
        AWAITING = "awaiting"      # approved, unpaid
        PARTIAL = "partial"        # part-paid
        PAID = "paid"
        CANCELLED = "cancelled"

    supplier = models.ForeignKey(
        Supplier, on_delete=models.PROTECT, related_name="invoices"
    )
    # The receipt(s) this bill covers. Optional: a supplier may bill for
    # something received outside a formal GRN.
    grn = models.ForeignKey(
        GRN, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="invoices",
    )
    purchase_order = models.ForeignKey(
        PurchaseOrder, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="invoices",
    )
    store = models.ForeignKey(
        "stores.Store", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="purchase_invoices",
    )
    # The supplier's own invoice number. Unique per supplier so the same bill
    # can't be entered twice and paid twice.
    invoice_number = models.CharField(max_length=60)
    invoice_date = models.DateField()
    due_date = models.DateField(null=True, blank=True)

    subtotal = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    tax = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    total = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    # Cached: total - sum(payments). Maintained by inventory.ap_services.
    amount_paid = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)

    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.DRAFT, db_index=True
    )
    notes = models.CharField(max_length=300, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="purchase_invoices_created",
    )

    class Meta:
        ordering = ["-invoice_date", "-id"]
        constraints = [
            models.UniqueConstraint(
                fields=["supplier", "invoice_number"],
                name="uniq_supplier_invoice_number",
            ),
        ]
        indexes = [models.Index(fields=["status", "due_date"])]

    @property
    def balance_due(self):
        return max(self.total - self.amount_paid, ZERO)

    def __str__(self):
        return f"{self.supplier_id}/{self.invoice_number} {self.total}"


class VendorPayment(TimeStampedModel):
    """Money paid to a supplier against an invoice. Append-only: a correction is
    a new negative-effect row (a reversal), never an edit, so the payables trail
    matches the credit and inventory ledgers' discipline."""

    class Method(models.TextChoices):
        BANK = "bank"
        UPI = "upi"
        CASH = "cash"
        CHEQUE = "cheque"

    invoice = models.ForeignKey(
        PurchaseInvoice, on_delete=models.PROTECT, related_name="payments"
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    method = models.CharField(max_length=10, choices=Method.choices)
    paid_on = models.DateField()
    reference = models.CharField(max_length=80, blank=True)  # UTR / cheque no
    notes = models.CharField(max_length=300, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="vendor_payments_created",
    )

    class Meta:
        ordering = ["-paid_on", "-id"]

    def __str__(self):
        return f"Payment({self.invoice_id}) {self.amount}"
