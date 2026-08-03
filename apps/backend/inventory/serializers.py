from rest_framework import serializers

from catalog.models import Product, ProductVariant
from stores.models import Store

from .models import (
    GRN,
    GRNItem,
    Barcode,
    Brand,
    InventoryLedger,
    LowStockAlert,
    PurchaseOrder,
    PurchaseOrderItem,
    StockBatch,
    StockItem,
    StockTransfer,
    Supplier,
    Unit,
    Warehouse,
)


# ── Warehouses & stock cache ─────────────────────────────
class WarehouseSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Warehouse
        fields = ["id", "name", "code", "is_active", "is_default"]


class StockItemSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)
    warehouse_id = serializers.CharField(read_only=True)
    # Human-readable labels so the UI shows names, not raw ids.
    product_name = serializers.CharField(source="product.name", read_only=True)
    warehouse_name = serializers.CharField(source="warehouse.name", read_only=True)
    available = serializers.IntegerField(read_only=True)

    class Meta:
        model = StockItem
        fields = [
            "id", "product_id", "product_name", "warehouse_id", "warehouse_name",
            "quantity", "reserved", "low_stock_threshold", "available",
        ]


class ProductStockSummarySerializer(serializers.Serializer):
    """Per-product stock aggregated across all warehouses."""

    product_id = serializers.CharField(read_only=True)
    name = serializers.CharField(read_only=True)
    brand = serializers.CharField(read_only=True)
    quantity = serializers.IntegerField(read_only=True)
    reserved = serializers.IntegerField(read_only=True)
    available = serializers.IntegerField(read_only=True)
    low_stock = serializers.BooleanField(read_only=True)


# ── Masters ──────────────────────────────────────────────
class BrandSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Brand
        fields = ["id", "name", "code", "is_active"]


class UnitSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Unit
        fields = ["id", "name", "code", "is_active"]


class SupplierSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    store = serializers.PrimaryKeyRelatedField(
        queryset=Store.objects.all(), required=False, allow_null=True
    )

    class Meta:
        model = Supplier
        fields = ["id", "name", "gstin", "phone", "email", "address", "is_active", "store"]


class BarcodeSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    variant_id = serializers.PrimaryKeyRelatedField(
        source="variant", queryset=ProductVariant.objects.all(),
        required=False, allow_null=True,
    )

    class Meta:
        model = Barcode
        fields = ["id", "product_id", "variant_id", "code", "symbology", "is_primary"]


class StockBatchSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)
    warehouse_id = serializers.CharField(read_only=True)

    class Meta:
        model = StockBatch
        fields = [
            "id", "product_id", "warehouse_id", "batch_no", "expiry_date",
            "quantity", "unit_cost",
        ]


# ── Transfers ────────────────────────────────────────────
class StockTransferSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)
    from_warehouse_id = serializers.CharField(read_only=True)
    to_warehouse_id = serializers.CharField(read_only=True)

    class Meta:
        model = StockTransfer
        fields = [
            "id", "product_id", "from_warehouse_id", "to_warehouse_id",
            "quantity", "status", "note",
        ]


class StockTransferCreateSerializer(serializers.Serializer):
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    from_warehouse = serializers.PrimaryKeyRelatedField(
        queryset=Warehouse.objects.all()
    )
    to_warehouse = serializers.PrimaryKeyRelatedField(queryset=Warehouse.objects.all())
    quantity = serializers.IntegerField(min_value=1)
    note = serializers.CharField(required=False, allow_blank=True)

    def validate(self, data):
        if data["from_warehouse"] == data["to_warehouse"]:
            raise serializers.ValidationError(
                "Source and destination warehouses must differ."
            )
        return data

    def create(self, validated_data):
        return StockTransfer.objects.create(
            product=validated_data["product"],
            from_warehouse=validated_data["from_warehouse"],
            to_warehouse=validated_data["to_warehouse"],
            quantity=validated_data["quantity"],
            note=validated_data.get("note", ""),
            status=StockTransfer.Status.PENDING,
            created_by=self.context["request"].user,
        )


# ── Procurement: Purchase Orders ─────────────────────────
class PurchaseOrderItemSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)

    class Meta:
        model = PurchaseOrderItem
        fields = ["id", "product_id", "quantity", "received_quantity", "unit_cost"]


class PurchaseOrderSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    warehouse_id = serializers.CharField(read_only=True)
    supplier_id = serializers.CharField(read_only=True, allow_null=True)
    created_by_id = serializers.CharField(read_only=True, allow_null=True)
    items = PurchaseOrderItemSerializer(many=True, read_only=True)

    class Meta:
        model = PurchaseOrder
        fields = [
            "id", "supplier_name", "supplier_id", "warehouse_id", "status",
            "expected_at", "subtotal", "tax", "total", "received_at",
            "created_by_id", "items",
        ]


class PurchaseOrderItemInputSerializer(serializers.Serializer):
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    quantity = serializers.IntegerField(min_value=1)
    unit_cost = serializers.DecimalField(max_digits=12, decimal_places=2)


class PurchaseOrderCreateSerializer(serializers.Serializer):
    supplier_name = serializers.CharField(required=False, allow_blank=True)
    supplier_id = serializers.PrimaryKeyRelatedField(
        source="supplier", queryset=Supplier.objects.all(),
        required=False, allow_null=True,
    )
    warehouse = serializers.PrimaryKeyRelatedField(queryset=Warehouse.objects.all())
    expected_at = serializers.DateField(required=False, allow_null=True)
    items = PurchaseOrderItemInputSerializer(many=True)

    def create(self, validated_data):
        items = validated_data.pop("items")
        supplier = validated_data.get("supplier")
        subtotal = sum(it["quantity"] * it["unit_cost"] for it in items)
        po = PurchaseOrder.objects.create(
            supplier_name=validated_data.get("supplier_name")
            or (supplier.name if supplier else ""),
            supplier=supplier,
            warehouse=validated_data["warehouse"],
            expected_at=validated_data.get("expected_at"),
            status=PurchaseOrder.Status.ORDERED,
            subtotal=subtotal,
            total=subtotal,
            created_by=self.context["request"].user,
        )
        for item in items:
            PurchaseOrderItem.objects.create(
                purchase_order=po,
                product=item["product"],
                quantity=item["quantity"],
                unit_cost=item["unit_cost"],
            )
        return po


# ── Procurement: GRN ─────────────────────────────────────
class GRNItemSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)

    class Meta:
        model = GRNItem
        fields = [
            "id", "product_id", "quantity", "unit_cost", "batch_no", "expiry_date",
        ]


class GRNSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    warehouse_id = serializers.CharField(read_only=True)
    supplier_id = serializers.CharField(read_only=True, allow_null=True)
    purchase_order_id = serializers.CharField(read_only=True, allow_null=True)
    items = GRNItemSerializer(many=True, read_only=True)

    class Meta:
        model = GRN
        fields = [
            "id", "purchase_order_id", "supplier_id", "warehouse_id", "reference",
            "status", "total_cost", "posted_at", "items", "created_at",
        ]


class GRNItemInputSerializer(serializers.Serializer):
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    variant_id = serializers.PrimaryKeyRelatedField(
        source="variant", queryset=ProductVariant.objects.all(),
        required=False, allow_null=True,
    )
    quantity = serializers.IntegerField(min_value=1)
    unit_cost = serializers.DecimalField(max_digits=12, decimal_places=2)
    batch_no = serializers.CharField(required=False, allow_blank=True)
    expiry_date = serializers.DateField(required=False, allow_null=True)


class GRNCreateSerializer(serializers.Serializer):
    warehouse = serializers.PrimaryKeyRelatedField(queryset=Warehouse.objects.all())
    supplier_id = serializers.PrimaryKeyRelatedField(
        source="supplier", queryset=Supplier.objects.all(),
        required=False, allow_null=True,
    )
    purchase_order_id = serializers.PrimaryKeyRelatedField(
        source="purchase_order", queryset=PurchaseOrder.objects.all(),
        required=False, allow_null=True,
    )
    reference = serializers.CharField(required=False, allow_blank=True)
    post = serializers.BooleanField(default=True)
    items = GRNItemInputSerializer(many=True)


# ── Ledger (audit), adjustments, write-offs ──────────────
class InventoryLedgerSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)
    product_name = serializers.CharField(source="product.name", read_only=True)
    variant_id = serializers.CharField(read_only=True, allow_null=True)
    warehouse_id = serializers.CharField(read_only=True)
    warehouse_name = serializers.CharField(source="warehouse.name", read_only=True)
    batch_id = serializers.CharField(read_only=True, allow_null=True)

    class Meta:
        model = InventoryLedger
        fields = [
            "id", "product_id", "product_name", "variant_id", "warehouse_id",
            "warehouse_name", "type", "quantity", "balance_after", "batch_id",
            "expiry_date", "unit_cost", "ref_type", "ref_id", "note", "created_at",
        ]


class AdjustmentInputSerializer(serializers.Serializer):
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    warehouse = serializers.PrimaryKeyRelatedField(
        queryset=Warehouse.objects.all(), required=False
    )
    set = serializers.IntegerField(required=False)
    delta = serializers.IntegerField(required=False)
    reason = serializers.CharField(required=False, allow_blank=True)

    def validate(self, data):
        if data.get("set") is None and data.get("delta") is None:
            raise serializers.ValidationError("Provide either `set` or `delta`.")
        return data


class WriteOffInputSerializer(serializers.Serializer):
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    warehouse = serializers.PrimaryKeyRelatedField(
        queryset=Warehouse.objects.all(), required=False
    )
    batch_id = serializers.PrimaryKeyRelatedField(
        source="batch", queryset=StockBatch.objects.all(),
        required=False, allow_null=True,
    )
    quantity = serializers.IntegerField(min_value=1)
    reason = serializers.CharField(required=False, allow_blank=True)


# ── Alerts & valuation ───────────────────────────────────
class LowStockAlertSerializer(serializers.Serializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)
    name = serializers.CharField(read_only=True)
    warehouse_id = serializers.CharField(read_only=True)
    threshold = serializers.IntegerField(read_only=True)
    available = serializers.IntegerField(read_only=True)
    status = serializers.CharField(read_only=True)
    raised_at = serializers.DateTimeField(read_only=True)


class ValuationRowSerializer(serializers.Serializer):
    product_id = serializers.CharField(read_only=True)
    name = serializers.CharField(read_only=True)
    warehouse_id = serializers.CharField(read_only=True)
    warehouse_name = serializers.CharField(read_only=True)
    quantity = serializers.IntegerField(read_only=True)
    unit_cost = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    value = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
