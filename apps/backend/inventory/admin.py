from django.contrib import admin

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


@admin.register(Warehouse)
class WarehouseAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "is_active", "is_default", "created_at"]
    list_filter = ["is_active", "is_default"]
    search_fields = ["name", "code"]


@admin.register(Brand)
class BrandAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "is_active"]
    search_fields = ["name", "code"]


@admin.register(Unit)
class UnitAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "is_active"]
    search_fields = ["name", "code"]


@admin.register(Supplier)
class SupplierAdmin(admin.ModelAdmin):
    list_display = ["name", "gstin", "phone", "is_active"]
    list_filter = ["is_active"]
    search_fields = ["name", "gstin", "phone"]


@admin.register(Barcode)
class BarcodeAdmin(admin.ModelAdmin):
    list_display = ["code", "product", "symbology", "is_primary"]
    search_fields = ["code", "product__name"]


@admin.register(StockItem)
class StockItemAdmin(admin.ModelAdmin):
    list_display = ["product", "warehouse", "quantity", "reserved", "available",
                    "low_stock_threshold"]
    list_filter = ["warehouse"]
    search_fields = ["product__name"]


@admin.register(StockBatch)
class StockBatchAdmin(admin.ModelAdmin):
    list_display = ["product", "warehouse", "batch_no", "expiry_date", "quantity"]
    list_filter = ["warehouse"]
    search_fields = ["product__name", "batch_no"]


@admin.register(InventoryLedger)
class InventoryLedgerAdmin(admin.ModelAdmin):
    list_display = ["created_at", "product", "warehouse", "type", "quantity",
                    "balance_after", "ref_type", "ref_id"]
    list_filter = ["type", "warehouse"]
    search_fields = ["product__name", "ref_id"]
    readonly_fields = [f.name for f in InventoryLedger._meta.fields]


@admin.register(LowStockAlert)
class LowStockAlertAdmin(admin.ModelAdmin):
    list_display = ["product", "warehouse", "threshold", "available_at_raise",
                    "status", "raised_at"]
    list_filter = ["status", "warehouse"]


@admin.register(StockTransfer)
class StockTransferAdmin(admin.ModelAdmin):
    list_display = ["product", "from_warehouse", "to_warehouse", "quantity",
                    "status", "created_at"]
    list_filter = ["status"]


class PurchaseOrderItemInline(admin.TabularInline):
    model = PurchaseOrderItem
    extra = 0


@admin.register(PurchaseOrder)
class PurchaseOrderAdmin(admin.ModelAdmin):
    list_display = ["id", "supplier_name", "warehouse", "status", "expected_at",
                    "total", "created_by", "created_at"]
    list_filter = ["status", "warehouse"]
    search_fields = ["supplier_name"]
    inlines = [PurchaseOrderItemInline]


class GRNItemInline(admin.TabularInline):
    model = GRNItem
    extra = 0


@admin.register(GRN)
class GRNAdmin(admin.ModelAdmin):
    list_display = ["id", "warehouse", "supplier", "status", "total_cost",
                    "posted_at", "created_at"]
    list_filter = ["status", "warehouse"]
    inlines = [GRNItemInline]
