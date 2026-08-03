from decimal import Decimal

from django.db import transaction
from django.db.models import Max, Sum
from rest_framework.exceptions import ValidationError
from rest_framework.generics import (
    ListAPIView,
    ListCreateAPIView,
    RetrieveUpdateDestroyAPIView,
    get_object_or_404,
)
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import Product
from core.pagination import CursorEnvelopePagination
from core.permissions import IsAdmin

from .models import (
    GRN,
    GRNItem,
    Barcode,
    Brand,
    InventoryLedger,
    LowStockAlert,
    PurchaseOrder,
    StockBatch,
    StockItem,
    StockTransfer,
    Supplier,
    Unit,
    Warehouse,
)
from .serializers import (
    AdjustmentInputSerializer,
    BarcodeSerializer,
    BrandSerializer,
    GRNCreateSerializer,
    GRNSerializer,
    InventoryLedgerSerializer,
    LowStockAlertSerializer,
    ProductStockSummarySerializer,
    PurchaseOrderCreateSerializer,
    PurchaseOrderSerializer,
    StockBatchSerializer,
    StockItemSerializer,
    StockTransferCreateSerializer,
    StockTransferSerializer,
    SupplierSerializer,
    UnitSerializer,
    ValuationRowSerializer,
    WarehouseSerializer,
)
from .services import (
    InventoryService,
    StockCalculationService,
    default_warehouse,
    post_grn,
    reconcile,
    set_reorder_level,
    stock_valuation,
    write_off,
)

Type = InventoryLedger.Type


# ── Warehouses ───────────────────────────────────────────
class WarehouseListView(ListCreateAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = WarehouseSerializer
    queryset = Warehouse.objects.all()


# ── Masters CRUD ─────────────────────────────────────────
class BrandListCreateView(ListCreateAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = BrandSerializer
    queryset = Brand.objects.all()


class BrandDetailView(RetrieveUpdateDestroyAPIView):
    permission_classes = [IsAdmin]
    serializer_class = BrandSerializer
    queryset = Brand.objects.all()


class UnitListCreateView(ListCreateAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = UnitSerializer
    queryset = Unit.objects.all()


class UnitDetailView(RetrieveUpdateDestroyAPIView):
    permission_classes = [IsAdmin]
    serializer_class = UnitSerializer
    queryset = Unit.objects.all()


class SupplierListCreateView(ListCreateAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = SupplierSerializer
    queryset = Supplier.objects.all()

    def get_queryset(self):
        qs = Supplier.objects.all()
        store = self.request.query_params.get("store")
        if store:
            # The store's own suppliers plus legacy/global (null-store) ones.
            from django.db.models import Q

            qs = qs.filter(Q(store_id=store) | Q(store__isnull=True))
        return qs


class SupplierDetailView(RetrieveUpdateDestroyAPIView):
    permission_classes = [IsAdmin]
    serializer_class = SupplierSerializer
    queryset = Supplier.objects.all()

    def perform_destroy(self, instance):
        """Deactivate, never hard-delete.

        `GRN.supplier` and `PurchaseOrder.supplier` are SET_NULL, so a real DELETE
        silently orphaned every historical receipt — the supplier column on past
        GRNs just became "—" and the product's supplier history collapsed. The
        model has carried `is_active` for exactly this; nothing used it. Same rule
        the product path already documents: archive, never destroy history.
        """
        if not instance.is_active:
            return
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])


class BarcodeListCreateView(ListCreateAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = BarcodeSerializer

    def get_queryset(self):
        qs = Barcode.objects.all()
        product = self.request.query_params.get("product")
        if product:
            qs = qs.filter(product_id=product)
        return qs


class BarcodeDetailView(RetrieveUpdateDestroyAPIView):
    permission_classes = [IsAdmin]
    serializer_class = BarcodeSerializer
    queryset = Barcode.objects.all()


# ── Stock views ──────────────────────────────────────────
class ProductStockSummaryView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        agg = {
            row["product_id"]: row
            for row in StockItem.objects.values("product_id").annotate(
                quantity=Sum("quantity"),
                reserved=Sum("reserved"),
                threshold=Max("low_stock_threshold"),
            )
        }
        products = Product.objects.all()
        q = request.query_params.get("q")
        if q:
            products = products.filter(name__icontains=q)

        low_stock = request.query_params.get("low_stock") in ("1", "true")
        rows = []
        for p in products:
            a = agg.get(p.id)
            # Fall back to the legacy product cache for not-yet-ledgered products.
            quantity = a["quantity"] if a else (p.stock_count or 0)
            reserved = a["reserved"] if a else 0
            available = quantity - reserved
            threshold = a["threshold"] if a else 0
            is_low = available < threshold
            if low_stock and not is_low:
                continue
            rows.append({
                "product_id": str(p.id),
                "name": p.name,
                "brand": p.brand,
                "quantity": quantity,
                "reserved": reserved,
                "available": available,
                "low_stock": is_low,
            })
        return Response(ProductStockSummarySerializer(rows, many=True).data)


class StockItemListView(ListAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = StockItemSerializer

    def get_queryset(self):
        qs = StockItem.objects.select_related("product", "warehouse")
        warehouse = self.request.query_params.get("warehouse")
        if warehouse:
            qs = qs.filter(warehouse_id=warehouse)
        product = self.request.query_params.get("product")
        if product:
            qs = qs.filter(product_id=product)
        return qs


class StockBatchListView(ListAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = StockBatchSerializer

    def get_queryset(self):
        qs = StockBatch.objects.all()
        product = self.request.query_params.get("product")
        if product:
            qs = qs.filter(product_id=product)
        if self.request.query_params.get("in_stock") in ("1", "true"):
            qs = qs.filter(quantity__gt=0)
        return qs


# ── Transfers ────────────────────────────────────────────
class StockTransferListCreateView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        transfers = StockTransfer.objects.all()
        return Response(StockTransferSerializer(transfers, many=True).data)

    def post(self, request):
        s = StockTransferCreateSerializer(data=request.data, context={"request": request})
        s.is_valid(raise_exception=True)
        transfer = s.save()
        # Auto-complete by default (moves stock); pass complete=false to leave pending.
        if request.data.get("complete", True) not in (False, "false", "0"):
            _complete_transfer(transfer, request.user)
        return Response(StockTransferSerializer(transfer).data, status=201)


class StockTransferCompleteView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        transfer = get_object_or_404(StockTransfer, pk=pk)
        if transfer.status == StockTransfer.Status.COMPLETED:
            return Response(StockTransferSerializer(transfer).data)
        _complete_transfer(transfer, request.user)
        return Response(StockTransferSerializer(transfer).data)


def _complete_transfer(transfer, user):
    InventoryService.transfer(
        transfer.product,
        from_warehouse=transfer.from_warehouse,
        to_warehouse=transfer.to_warehouse,
        quantity=transfer.quantity,
        created_by=user,
        note=transfer.note,
    )
    transfer.status = StockTransfer.Status.COMPLETED
    transfer.save(update_fields=["status", "updated_at"])


# ── Purchase Orders ──────────────────────────────────────
class PurchaseOrderListCreateView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        pos = PurchaseOrder.objects.prefetch_related("items").all()
        return Response(PurchaseOrderSerializer(pos, many=True).data)

    def post(self, request):
        s = PurchaseOrderCreateSerializer(data=request.data, context={"request": request})
        s.is_valid(raise_exception=True)
        po = s.save()
        return Response(PurchaseOrderSerializer(po).data, status=201)


# ── GRN ──────────────────────────────────────────────────
class GRNListCreateView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        grns = GRN.objects.prefetch_related("items").all()
        return Response(GRNSerializer(grns, many=True).data)

    # Atomic so a rejected line can't leave a phantom GRN header behind.
    @transaction.atomic
    def post(self, request):
        s = GRNCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        data = s.validated_data
        items = data["items"]
        grn = GRN.objects.create(
            warehouse=data["warehouse"],
            supplier=data.get("supplier"),
            purchase_order=data.get("purchase_order"),
            reference=data.get("reference", ""),
            created_by=request.user,
        )
        for idx, it in enumerate(items, start=1):
            product = it["product"]
            variant = it.get("variant")
            # Receiving a variant product without naming the pack drops the units
            # into the variant=NULL unallocated pool, where nothing can sell them
            # — the stock reads as received but every pack SKU stays at zero.
            # The store-panel purchase endpoint refuses this for the same reason.
            if variant is None and product.variants.exists():
                raise ValidationError({
                    "items": [f"Line {idx} ({product.name}): choose a pack to receive into."]
                })
            GRNItem.objects.create(
                grn=grn,
                product=product,
                variant=variant,
                quantity=it["quantity"],
                unit_cost=it["unit_cost"],
                batch_no=it.get("batch_no", ""),
                expiry_date=it.get("expiry_date"),
            )
        if data.get("post", True):
            post_grn(grn, by=request.user)
        grn = GRN.objects.prefetch_related("items").get(pk=grn.pk)
        return Response(GRNSerializer(grn).data, status=201)


class GRNPostView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        grn = get_object_or_404(GRN, pk=pk)
        post_grn(grn, by=request.user)
        grn = GRN.objects.prefetch_related("items").get(pk=grn.pk)
        return Response(GRNSerializer(grn).data)


# ── Ledger audit ─────────────────────────────────────────
class InventoryLedgerListView(ListAPIView):
    permission_classes = [IsAdmin]
    pagination_class = CursorEnvelopePagination
    serializer_class = InventoryLedgerSerializer

    def get_queryset(self):
        qs = InventoryLedger.objects.select_related("product", "warehouse")
        for field in ("product", "warehouse", "type"):
            val = self.request.query_params.get(field)
            if val:
                qs = qs.filter(**{f"{field}_id" if field != "type" else field: val})
        return qs


# ── Adjustments ──────────────────────────────────────────
class AdjustmentListCreateView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        qs = InventoryLedger.objects.filter(type=Type.ADJUSTMENT)
        product = request.query_params.get("product")
        if product:
            qs = qs.filter(product_id=product)
        return Response(InventoryLedgerSerializer(qs, many=True).data)

    def post(self, request):
        s = AdjustmentInputSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        warehouse = d.get("warehouse") or default_warehouse()
        new_on_hand = InventoryService.adjust(
            d["product"], set=d.get("set"), delta=d.get("delta"),
            warehouse=warehouse, reason=d.get("reason", ""), created_by=request.user,
        )
        return Response({
            "product_id": str(d["product"].id),
            "warehouse_id": str(warehouse.id),
            "on_hand": new_on_hand,
        }, status=201)


# ── Damage / Expiry write-offs ───────────────────────────
class DamageListCreateView(APIView):
    permission_classes = [IsAdmin]
    movement_type = Type.DAMAGE

    def get(self, request):
        qs = InventoryLedger.objects.filter(type=self.movement_type)
        product = request.query_params.get("product")
        if product:
            qs = qs.filter(product_id=product)
        return Response(InventoryLedgerSerializer(qs, many=True).data)

    def post(self, request):
        from .serializers import WriteOffInputSerializer

        s = WriteOffInputSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        entry = write_off(
            d["product"], type=self.movement_type, quantity=d["quantity"],
            warehouse=d.get("warehouse") or default_warehouse(),
            batch=d.get("batch"), reason=d.get("reason", ""), created_by=request.user,
        )
        return Response(InventoryLedgerSerializer(entry).data, status=201)


class ExpiryListCreateView(DamageListCreateView):
    movement_type = Type.EXPIRY


# ── Low stock + valuation ────────────────────────────────
class LowStockView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        alerts = LowStockAlert.objects.filter(
            status=LowStockAlert.Status.ACTIVE
        ).select_related("product")
        rows = []
        for a in alerts:
            item = StockItem.objects.filter(
                product=a.product, warehouse=a.warehouse
            ).first()
            rows.append({
                "id": str(a.id),
                "product_id": str(a.product_id),
                "name": a.product.name,
                "warehouse_id": str(a.warehouse_id),
                "threshold": a.threshold,
                "available": item.available if item else a.available_at_raise,
                "status": a.status,
                "raised_at": a.raised_at,
            })
        return Response(LowStockAlertSerializer(rows, many=True).data)


class ValuationView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        warehouse = request.query_params.get("warehouse")
        wh = Warehouse.objects.filter(pk=warehouse).first() if warehouse else None
        rows = stock_valuation(warehouse=wh)
        total = sum((r["value"] for r in rows), start=Decimal("0.00"))
        return Response({
            "rows": ValuationRowSerializer(rows, many=True).data,
            "total": total,
            "sku_count": len(rows),
        })


# ── Reorder level ────────────────────────────────────────
class ReorderLevelView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request):
        product = get_object_or_404(Product, pk=request.data.get("product"))
        warehouse = None
        if request.data.get("warehouse"):
            warehouse = Warehouse.objects.filter(pk=request.data["warehouse"]).first()
        threshold = int(request.data.get("threshold", 0))
        item = set_reorder_level(product, threshold=threshold, warehouse=warehouse)
        return Response({
            "product_id": str(product.id),
            "warehouse_id": str(item.warehouse_id),
            "low_stock_threshold": item.low_stock_threshold,
        })


# ── Integrity ────────────────────────────────────────────
class ReconcileView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request):
        product_id = request.data.get("product")
        product = Product.objects.filter(pk=product_id).first() if product_id else None
        fixes = reconcile(product=product)
        return Response({"checked": "ok", "fixed": fixes})
