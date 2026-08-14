"""Product Master — super-admin catalog CRUD (spec §PRODUCT MASTER / M10).

The master catalog holds NO stock (stock lives per-store in inventory). These admin
endpoints let Super-Admin create/edit/archive products and manage categories.
"""
from decimal import Decimal

from rest_framework import serializers
from rest_framework.generics import (
    ListCreateAPIView,
    RetrieveUpdateDestroyAPIView,
    get_object_or_404,
)
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.permissions import IsAdmin

from .models import Category, Product


class AdminProductSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    category_id = serializers.PrimaryKeyRelatedField(
        source="category", queryset=Category.objects.all()
    )
    category_name = serializers.CharField(source="category.name", read_only=True)
    # Which store added this product, if any. Null = company-wide. Read-only:
    # ownership is set at creation and moving a product between owners is not a
    # field edit. Surfaced so a picker can label whose product it is.
    origin_store_name = serializers.CharField(
        source="origin_store.name", read_only=True, default=None
    )
    # A relative self-hosted media path (/api/v1/media/public/…) — CharField (not
    # URLField) so the picker's uploaded path validates, and blank clears the image.
    image_url = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    # "Where is this product?" — how many stores physically hold it (stock > 0).
    store_count = serializers.SerializerMethodField()

    class Meta:
        model = Product
        fields = [
            "id", "name", "brand", "unit", "sku", "hsn", "gst_rate",
            "price", "mrp", "credit_price", "category_id", "category_name",
            "image_url", "description", "in_stock", "stock_count", "store_count", "is_active",
            "origin_store_name",
            # Content translations. The admin console writes the raw columns —
            # unlike the customer API, which resolves them by request language.
            "name_te", "name_hi", "description_te", "description_hi",
        ]
        read_only_fields = ["id", "in_stock", "stock_count", "store_count",
                            "origin_store_name"]

    def get_store_count(self, obj):
        from inventory.models import StockItem

        return (
            StockItem.objects.filter(product=obj, quantity__gt=0)
            .values("warehouse_id")
            .distinct()
            .count()
        )

    def validate_gst_rate(self, value):
        """A GST rate is a PERCENTAGE on one of the statutory slabs.

        The form used to be labelled "GST rate (0–1)" and accepted any decimal,
        so operators entered 0.18 for 18% — and a stray 1.8 or 180 was accepted
        just as happily. Both are silent tax errors on every invoice the product
        appears on, so the API refuses anything that isn't a real slab.
        """
        if value is None:
            return None  # falls back to the platform default
        from core.pricing import GST_SLABS, gst_slab_error

        rate = Decimal(str(value))
        if rate not in GST_SLABS:
            raise serializers.ValidationError(gst_slab_error(rate))
        return rate


class AdminCategorySerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    parent_id = serializers.PrimaryKeyRelatedField(
        source="parent", queryset=Category.objects.all(), required=False, allow_null=True
    )
    # Accept a relative self-hosted media path from the image picker (see product note).
    image_url = serializers.CharField(required=False, allow_blank=True, allow_null=True)

    class Meta:
        model = Category
        fields = ["id", "name", "slug", "parent_id", "icon_name", "image_url",
                  "product_count", "sort_order", "is_active",
                  # Raw translation columns (resolved per-language on the customer API).
                  "name_te", "name_hi"]
        read_only_fields = ["id", "product_count"]


class AdminProductListCreateView(ListCreateAPIView):
    permission_classes = [IsAdmin]
    serializer_class = AdminProductSerializer

    def get_queryset(self):
        # The company master holds company-wide products only; store-private products
        # (origin_store set) belong to a single store and are managed from its panel.
        #
        # `?scope=all` opts out of that narrowing for surfaces that need to see
        # what a *customer* sees rather than what this page edits. The home-rail
        # picker is the case in point: `scope_catalog_queryset` puts store-added
        # products in the customer catalog too (deliberately — a store's product
        # is sellable before any zone is drawn), so the rails already display
        # them. Hiding them from the picker meant the console could not curate
        # the very products the rails were showing.
        qs = Product.objects.select_related("category", "origin_store").order_by("-id")
        if self.request.query_params.get("scope") != "all":
            qs = qs.filter(origin_store__isnull=True)
        q = self.request.query_params.get("q")
        if q:
            # Name alone was too narrow: an operator reaching for a product by the
            # code on the shelf label or by its brand got "no results" and had no
            # way to tell that from "it doesn't exist".
            from django.db.models import Q

            qs = qs.filter(
                Q(name__icontains=q) | Q(sku__icontains=q) | Q(brand__icontains=q)
            )
        category = self.request.query_params.get("category")
        if category:
            qs = qs.filter(category_id=category)
        active = self.request.query_params.get("active")
        if active in ("1", "true", "True"):
            qs = qs.filter(is_active=True)
        elif active in ("0", "false", "False"):
            qs = qs.filter(is_active=False)
        return qs

    def perform_create(self, serializer):
        from inventory.barcodes import ensure_product_barcodes

        product = serializer.save()
        # Mint a scannable code at birth. Without this, a product created here
        # had NO barcode and could never be rung up at a till — codes were only
        # ever generated on the store panel's create path.
        ensure_product_barcodes(product)
        record_audit(self.request.user, "product.create", target=product,
                     after={"name": product.name})


class AdminProductDetailView(RetrieveUpdateDestroyAPIView):
    permission_classes = [IsAdmin]
    serializer_class = AdminProductSerializer
    queryset = Product.objects.select_related("category").all()

    def perform_update(self, serializer):
        product = serializer.save()
        record_audit(self.request.user, "product.update", target=product,
                     after={"name": product.name})

    def perform_destroy(self, instance):
        # Archive, never hard-delete (orders/ledger reference products).
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])
        record_audit(self.request.user, "product.archive", target=instance,
                     after={"is_active": False})


class AdminCategoryListCreateView(ListCreateAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = AdminCategorySerializer
    queryset = Category.objects.all()


class AdminCategoryDetailView(RetrieveUpdateDestroyAPIView):
    """Category read/edit/delete.

    Deleting is refused while anything depends on the category. `Product.category`
    is PROTECT, so a DELETE on a category with products raised `ProtectedError` —
    not a DRF exception, so it escaped the handler as a **500 SYSTEM_ERROR**
    instead of telling the admin why. `Category.parent` is CASCADE, so deleting a
    parent would also silently take its children with it.
    """

    permission_classes = [IsAdmin]
    serializer_class = AdminCategorySerializer
    queryset = Category.objects.all()

    def perform_destroy(self, instance):
        from rest_framework.exceptions import ValidationError

        used = Product.objects.filter(category=instance).count()
        if used:
            raise ValidationError({"category": [
                f"'{instance.name}' still has {used} product(s). Move or archive "
                f"them first."
            ]})
        # `parent` is CASCADE — deleting a department would silently take its
        # sub-categories (and, through them, nothing that PROTECT would catch).
        # Make the operator clear the tree explicitly.
        kids = Category.objects.filter(parent=instance).count()
        if kids:
            raise ValidationError({"category": [
                f"'{instance.name}' still has {kids} sub-categor"
                f"{'y' if kids == 1 else 'ies'}. Delete those first."
            ]})
        record_audit(self.request.user, "category.delete", target=instance,
                     after={"name": instance.name})
        instance.delete()


class AdminProductVariantsView(APIView):
    """The packs a product is stocked as, with live counts.

    A variant is a separately-stocked SKU that happens to be grouped under a
    parent product — 1 kg and 5 kg Rice have their own stock, price and barcode.
    Nothing exposed that list to the console, so any screen that had to name a
    pack (stock transfer, most obviously) had no way to offer one, and operators
    were left moving "Rice" with no idea which pack they were touching.

    ``?warehouse=<id>`` adds each pack's availability at that warehouse, so a
    transfer form can show "1 kg — 20 available" rather than a bare label.
    """

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        from inventory.models import Warehouse
        from inventory.services import StockCalculationService

        product = get_object_or_404(Product, pk=pk)
        warehouse = None
        warehouse_id = request.query_params.get("warehouse")
        if warehouse_id:
            warehouse = Warehouse.objects.filter(pk=warehouse_id).first()

        rows = []
        for v in product.variants.all():
            row = {
                "id": str(v.id),
                "label": v.label,
                "sku": v.sku,
                "inStock": v.in_stock,
            }
            if warehouse is not None:
                row["available"] = StockCalculationService.available(
                    product, warehouse, v
                )
            rows.append(row)

        payload = {
            "productId": str(product.id),
            "productName": product.name,
            # False means "this product is a single SKU" — the caller can skip
            # the pack picker entirely rather than showing an empty dropdown.
            "hasVariants": bool(rows),
            "variants": rows,
        }
        if warehouse is not None:
            # Stock banked before the product had packs. It can't be sold or
            # moved until it's allocated to one, so the console has to be able
            # to see it.
            payload["unallocated"] = StockCalculationService.available(
                product, warehouse, None
            )
        return Response(payload)


class AdminImageUploadView(APIView):
    """Upload an image (product / category photo) to VS Mart's own media engine and
    return a public URL to store in an ``image_url`` field. Field name: ``file``.

    The picker uploads here first, then submits the returned URL with the entity's
    JSON save — so images live on the VPS and no external URL is ever entered."""

    permission_classes = [IsAdmin]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        from mediastore.pipeline import ingest_public_image

        upload = request.FILES.get("file") or request.FILES.get("image")
        if upload is None:
            raise serializers.ValidationError({"file": ["An image file is required."]})
        category = request.data.get("category") or "catalog"
        url = ingest_public_image(upload, owner=request.user, category=category)
        return Response({"url": url}, status=201)
