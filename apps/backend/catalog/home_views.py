"""Home-screen rails — the customer read endpoint and the admin curation CRUD.

The rails ("Today's Deals", "Popular Products", "Recommended For You", "Top
Selling") were hardcoded in the Flutter app as `/products?sort=…` calls, so the
console had no way to influence what a customer sees on the front page. These
endpoints put that back under the merchandiser's control without taking away the
algorithmic default — see `catalog.home` for the one rule that governs it.
"""
from rest_framework import serializers
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.app_errors import AppError, ok
from core.authentication import OptionalJWTAuthentication
from core.permissions import IsAdmin
from stores.services import scope_catalog_queryset

from .home import (
    SECTION_FALLBACK_SORT,
    SECTION_LIMIT,
    active_product_queryset,
    curated_rows,
    section_products,
)
from .models import HomeFeature, Product
from .serializers import ProductListSerializer
from .views import _StoreContextMixin


def _section_or_400(value):
    section = (value or "").strip()
    if section not in SECTION_FALLBACK_SORT:
        raise serializers.ValidationError({"section": [
            f"Unknown home section. Valid sections: "
            f"{', '.join(SECTION_FALLBACK_SORT)}."
        ]})
    return section


# ── Customer ─────────────────────────────────────────────
class HomeSectionView(_StoreContextMixin, APIView):
    """GET /home/sections/<section> — the products for one home rail.

    Public (auth-optional) because the home screen renders before sign-in. The
    queryset is store-scoped exactly like `/products`, so curation can never
    surface a product the serving store doesn't carry.
    """

    permission_classes = [AllowAny]
    authentication_classes = [OptionalJWTAuthentication]

    def get(self, request, section):
        section = _section_or_400(section)
        base = scope_catalog_queryset(active_product_queryset(), request)
        products = section_products(section, base_queryset=base)
        data = ProductListSerializer(
            products, many=True, context=self.get_serializer_context()
        ).data
        return Response(ok("OK", data=data, meta={
            "section": section,
            "curated": HomeFeature.objects.filter(
                section=section, is_active=True
            ).exists(),
        }))

    def get_serializer_context(self):
        # APIView has no `get_serializer_context`; _StoreContextMixin calls
        # super(), so provide the base the generic views would have given it.
        return {"request": self.request, "view": self}


class HomeSectionCatalogView(APIView):
    """GET /home/sections — which rails exist, so a client renders the home
    screen from the server's list instead of a hardcoded one."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        return Response(ok("OK", data=[
            {
                "key": value,
                "label": label,
                "fallbackSort": SECTION_FALLBACK_SORT[value],
                "limit": SECTION_LIMIT,
            }
            for value, label in HomeFeature.Section.choices
        ]))


# ── Admin ────────────────────────────────────────────────
class AdminHomeFeatureSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    product_name = serializers.CharField(source="product.name", read_only=True)
    product_image_url = serializers.CharField(source="product.image_url", read_only=True)
    product_price = serializers.DecimalField(
        source="product.price", max_digits=12, decimal_places=2, read_only=True
    )
    product_is_active = serializers.BooleanField(
        source="product.is_active", read_only=True
    )
    # A store-added product is only in its own store's catalog, so a pin on one
    # reaches that store's customers and nobody else. The rail has to say so, or
    # a curator reads "pinned" as "on everyone's home screen".
    product_origin_store_name = serializers.CharField(
        source="product.origin_store.name", read_only=True, default=None
    )

    class Meta:
        model = HomeFeature
        fields = [
            "id", "section", "product_id", "product_name", "product_image_url",
            "product_price", "product_is_active", "product_origin_store_name",
            "sort_order", "is_active",
        ]
        # DRF auto-generates a UniqueTogetherValidator from the model constraint,
        # which fires first and reports "The fields section, product_id must make
        # a unique set." — accurate and useless to an operator. The view's own
        # check produces "<product> is already on this rail." and a 409, so the
        # auto validator is turned off to let it through. The DB constraint still
        # backstops a race.
        validators = []

    def validate_section(self, value):
        return _section_or_400(value)


class AdminHomeSectionView(APIView):
    """GET  /admin/catalog/home-sections?section=… → the rail's pins
    POST /admin/catalog/home-sections               → pin a product to a rail
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        section = request.query_params.get("section")
        if section:
            rows = curated_rows(_section_or_400(section))
            return Response(AdminHomeFeatureSerializer(rows, many=True).data)
        # No section → every rail at once, which is what the console's page needs
        # to render all four lists without four round trips.
        #
        # A LIST of {section, items}, not a dict keyed by section code. The
        # response goes through CamelCaseJSONRenderer, which rewrites *every* key
        # in the payload — including ones that are data rather than field names.
        # Keying by section code turned `today_deals` into `todayDeals` and
        # `top_selling` into `topSelling` on the wire, so the console's lookup by
        # section code missed those two rails entirely: whatever was pinned to
        # Today's Deals or Top Selling rendered as "Not curated", and could never
        # be reordered or removed. Section codes are values here, so they belong
        # in a value position where no key transform can touch them.
        return Response([
            {
                "section": value,
                "label": label,
                "items": AdminHomeFeatureSerializer(
                    curated_rows(value), many=True
                ).data,
            }
            for value, label in HomeFeature.Section.choices
        ])

    def post(self, request):
        serializer = AdminHomeFeatureSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        section = serializer.validated_data["section"]
        product = serializer.validated_data["product"]

        if HomeFeature.objects.filter(section=section, product=product).exists():
            raise AppError(
                "DUPLICATE_RECORD",
                message=f"{product.name} is already on this rail.",
            )
        if not product.is_active:
            # Pinning an archived product would put an unbuyable card on the home
            # screen — the unique failure mode of curation over an algorithm,
            # which can only ever surface live rows.
            raise AppError(
                "VALIDATION_ERROR",
                message=f"{product.name} is archived and can't be featured. "
                        f"Restore it first.",
            )
        # Append to the end of the rail unless the caller placed it explicitly.
        if not serializer.validated_data.get("sort_order"):
            last = (
                HomeFeature.objects.filter(section=section)
                .order_by("-sort_order")
                .values_list("sort_order", flat=True)
                .first()
            )
            serializer.validated_data["sort_order"] = (last or 0) + 1

        feature = serializer.save()
        record_audit(request.user, "home_section.pin", target=feature,
                     after={"section": section, "product": product.name})
        return Response(AdminHomeFeatureSerializer(feature).data, status=201)


class AdminHomeSectionDetailView(APIView):
    """PATCH → reorder / activate a pin. DELETE → unpin."""

    permission_classes = [IsAdmin]

    def _get(self, pk):
        feature = HomeFeature.objects.filter(pk=pk).select_related("product").first()
        if feature is None:
            raise AppError("NOT_FOUND", message="That featured product no longer exists.")
        return feature

    def patch(self, request, pk):
        feature = self._get(pk)
        # Only the pin's placement is editable. Re-pointing an existing pin at a
        # different product (or rail) is unpin + pin — allowing it here would slip
        # past the "already on this rail" and "not archived" checks that only the
        # create path applies.
        editable = {
            k: v for k, v in request.data.items()
            if k in ("sort_order", "sortOrder", "is_active", "isActive")
        }
        serializer = AdminHomeFeatureSerializer(feature, data=editable, partial=True)
        serializer.is_valid(raise_exception=True)
        feature = serializer.save()
        record_audit(request.user, "home_section.update", target=feature,
                     after={"sortOrder": feature.sort_order,
                            "isActive": feature.is_active})
        return Response(AdminHomeFeatureSerializer(feature).data)

    def delete(self, request, pk):
        feature = self._get(pk)
        name, section = feature.product.name, feature.get_section_display()
        record_audit(request.user, "home_section.unpin", target=feature,
                     after={"section": feature.section, "product": name})
        feature.delete()
        # 200 + a message, not a bare 204: the console needs to say what came off
        # which rail, and a 204 carries neither.
        return Response(ok(
            "RECORD_DELETED",
            message=f"{name} removed from {section}.",
            data={"id": str(pk), "outcome": "deleted"},
        ))


class AdminHomeSectionReorderView(APIView):
    """POST /admin/catalog/home-sections/reorder — set a rail's order in one call.

    Drag-and-drop produces a whole new ordering, and applying it as N separate
    PATCHes leaves the rail visibly scrambled if one of them fails partway.
    """

    permission_classes = [IsAdmin]

    def post(self, request):
        from django.db import transaction

        section = _section_or_400(request.data.get("section"))
        ids = request.data.get("ids") or request.data.get("featureIds") or []
        if not isinstance(ids, list):
            raise serializers.ValidationError({"ids": ["Send the ordered list of pin ids."]})

        rail = {f.id: f for f in HomeFeature.objects.filter(section=section)}
        unknown = [i for i in ids if int(i) not in rail]
        if unknown:
            raise serializers.ValidationError(
                {"ids": [f"Not on this rail: {', '.join(str(u) for u in unknown)}."]}
            )
        with transaction.atomic():
            for position, feature_id in enumerate(ids, start=1):
                feature = rail[int(feature_id)]
                feature.sort_order = position
                feature.save(update_fields=["sort_order", "updated_at"])
        record_audit(request.user, "home_section.reorder", after={
            "section": section, "count": len(ids)
        })
        return Response(
            AdminHomeFeatureSerializer(curated_rows(section), many=True).data
        )
