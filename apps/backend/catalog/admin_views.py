"""Product Master — super-admin catalog CRUD (spec §PRODUCT MASTER / M10).

The master catalog holds NO stock (stock lives per-store in inventory). These admin
endpoints let Super-Admin create/edit/archive products and manage categories.
"""
from rest_framework import serializers
from rest_framework.generics import ListCreateAPIView, RetrieveUpdateDestroyAPIView
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
            # Content translations. The admin console writes the raw columns —
            # unlike the customer API, which resolves them by request language.
            "name_te", "name_hi", "description_te", "description_hi",
        ]
        read_only_fields = ["id", "in_stock", "stock_count", "store_count"]

    def get_store_count(self, obj):
        from inventory.models import StockItem

        return (
            StockItem.objects.filter(product=obj, quantity__gt=0)
            .values("warehouse_id")
            .distinct()
            .count()
        )


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
        qs = Product.objects.select_related("category").filter(
            origin_store__isnull=True
        ).order_by("-id")
        q = self.request.query_params.get("q")
        if q:
            qs = qs.filter(name__icontains=q)
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
