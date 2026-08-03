from django.http import Http404
from rest_framework import generics
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from core.app_errors import ok
from core.authentication import OptionalJWTAuthentication
from stores.services import resolve_catalog_store, scope_catalog_queryset

from .models import Category, Product
from .serializers import (
    CategorySerializer,
    ProductListSerializer,
    ProductSerializer,
    StoreCategorySerializer,
)
from .store_tree import (
    branch_ids,
    private_products_queryset,
    private_tree,
    representative_images,
    scoped_category_ids,
)


class _StoreContextMixin:
    """Inject the SERVER-resolved serving store into serializer context so price/mrp
    are store-aware (no-op when scoping off / store_pricing flag off → global values).
    The store is resolved from the customer's location, never a trusted client id."""

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        store, _ = resolve_catalog_store(self.request)
        ctx["store"] = store
        # Prefetch the store's per-product overrides once so the serializer applies
        # them without an N+1 lookup per product.
        if store is not None:
            from stores.models import StoreProduct

            ctx["store_overrides"] = {
                sp.product_id: sp
                for sp in StoreProduct.objects.filter(store=store)
            }
        return ctx


class _ScopedCategoryMixin:
    """Restrict a category listing to what the serving store can actually fill.

    These endpoints returned the whole company tree while `/products` was already
    store-scoped, so a customer saw departments their store carries nothing in,
    tapped one, and landed on an empty listing. Dead tiles.

    Optional auth (was `authentication_classes = []`) so a signed-in customer's
    saved address can resolve their store, exactly like the product endpoints —
    without it, location had to come from query params or scoping never applied.
    """

    permission_classes = [AllowAny]
    authentication_classes = [OptionalJWTAuthentication]
    pagination_class = None
    serializer_class = CategorySerializer

    def scoped(self, qs):
        ids = scoped_category_ids(self.request)
        # None = scoping inactive (global catalog): leave the tree untouched.
        return qs if ids is None else qs.filter(id__in=ids)


class CategoryListView(_ScopedCategoryMixin, generics.ListAPIView):
    """Top-level departments (parent is null), scoped to the serving store."""

    def get_queryset(self):
        return self.scoped(
            Category.objects.filter(is_active=True, parent__isnull=True)
        )


class SubCategoryListView(_ScopedCategoryMixin, generics.ListAPIView):
    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Category.objects.none()
        return self.scoped(
            Category.objects.filter(
                is_active=True, parent_id=self.kwargs["category_id"]
            )
        )


class StoreCategoryListView(generics.ListAPIView):
    """One level of the serving store's PRIVATE category tree.

    ``?parent=<id>`` returns that category's children; omitting it returns the top
    level. Only categories that actually hold the store's own products (directly or
    beneath them) are listed, so every tile leads somewhere.

    STRICTLY private: with no serving store resolved (out of area, or no location
    sent) the tree is EMPTY rather than falling back to the company-wide catalog —
    the app renders its "this store hasn't added products yet" state. Silently
    widening the scope here would put another store's departments in the rail.
    """

    permission_classes = [AllowAny]
    # Optional auth so a signed-in customer's saved address can resolve their store
    # without forcing sign-in to browse.
    authentication_classes = [OptionalJWTAuthentication]
    pagination_class = None
    serializer_class = StoreCategorySerializer

    def _tree(self):
        """Resolve the tree once per request — the queryset and the serializer
        context both need it."""
        cached = getattr(self, "_tree_cache", None)
        if cached is None:
            store, _ = resolve_catalog_store(self.request)
            visible, counts = private_tree(store)
            images = representative_images(store) if visible else {}
            cached = (visible, counts, branch_ids(visible), images)
            self._tree_cache = cached
        return cached

    def get_queryset(self):
        visible, _, _, _ = self._tree()
        if not visible:
            return Category.objects.none()
        qs = Category.objects.filter(is_active=True, id__in=visible)
        parent = self.request.query_params.get("parent") or None
        if parent:
            # A parent outside the visible set has no visible children anyway, so
            # this needs no extra guard — it simply returns nothing.
            return qs.filter(parent_id=parent)
        # Top level. Every visible category's ancestors are visible too (private_tree
        # walks the full chain), so the roots are exactly the parentless ones.
        return qs.filter(parent__isnull=True)

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        _, counts, branches, images = self._tree()
        ctx["private_counts"] = counts
        ctx["private_branches"] = branches
        ctx["private_images"] = images
        return ctx


class ProductListView(_StoreContextMixin, generics.ListAPIView):
    permission_classes = [AllowAny]
    # Optional auth: recognise a signed-in customer (to resolve their serving store from
    # their saved address) without forcing sign-in for public browse.
    authentication_classes = [OptionalJWTAuthentication]
    serializer_class = ProductListSerializer

    def _base_queryset(self):
        """The visibility-scoped starting set, before category/brand/sort.

        ``?scope=private`` is the leaf grid of the store-private Categories tab:
        ONLY the serving store's own products. It deliberately does NOT go through
        :func:`scope_catalog_queryset`, which returns the whole global catalog when
        scoping is inactive — that would quietly fill a "store products" grid with
        company-wide stock, and show nothing at all if no store resolves.
        """
        # Prefetched once for the whole page (not per-card) — ProductListSerializer
        # needs each product's actual variant rows to tell the app whether it has
        # packs at all, so quick-add-to-cart on a card can't bypass the pack picker.
        if self.request.query_params.get("scope") == "private":
            store, _ = resolve_catalog_store(self.request)
            return private_products_queryset(store).select_related(
                "category").prefetch_related("variants")
        qs = Product.objects.filter(is_active=True).select_related(
            "category").prefetch_related("variants")
        # Store-scoped visibility: the backend resolves the serving store from the
        # customer's location and returns ONLY that store's products — or an EMPTY set
        # when out of area. No-op (global catalog) when zone_store_visibility is off.
        return scope_catalog_queryset(qs, self.request)

    def get_queryset(self):
        qs = self._base_queryset()
        category = self.request.query_params.get("category")
        if category:
            # A department (parent) listing aggregates its subcategories' products;
            # a leaf subcategory listing returns just its own.
            child_ids = list(
                Category.objects.filter(parent_id=category).values_list(
                    "id", flat=True
                )
            )
            if child_ids:
                qs = qs.filter(category_id__in=[category, *child_ids])
            else:
                qs = qs.filter(category_id=category)
        brand = self.request.query_params.get("brand")
        if brand:
            qs = qs.filter(brand__iexact=brand)
        sort = self.request.query_params.get("sort")
        if sort == "price_low":
            qs = qs.order_by("price")
        elif sort == "price_high":
            qs = qs.order_by("-price")
        elif sort == "rating":
            qs = qs.order_by("-rating")
        elif sort == "popular":
            qs = qs.order_by("-review_count")
        elif sort == "discount":
            # Highest discount first (drives the home "best deals" rail).
            # `discount_percent` is a computed property (no stored column), so
            # annotate the ratio (mrp − price)/mrp and order by it. Cast to float
            # so the division isn't truncated on SQLite; NULLIF guards the mrp=0
            # edge and COALESCE keeps those rows last instead of first.
            from django.db.models import ExpressionWrapper, FloatField, Value
            from django.db.models.functions import Cast, Coalesce, NullIf

            discount_ratio = ExpressionWrapper(
                (Cast("mrp", FloatField()) - Cast("price", FloatField()))
                / NullIf(Cast("mrp", FloatField()), Value(0.0)),
                output_field=FloatField(),
            )
            qs = qs.annotate(
                discount_ratio=Coalesce(
                    discount_ratio, Value(0.0), output_field=FloatField()
                )
            ).order_by("-discount_ratio")
        return qs


class ProductDetailView(_StoreContextMixin, generics.RetrieveAPIView):
    permission_classes = [AllowAny]
    authentication_classes = [OptionalJWTAuthentication]
    serializer_class = ProductSerializer

    def _base_qs(self):
        return Product.objects.filter(is_active=True).prefetch_related(
            "gallery", "variants"
        )

    def get_queryset(self):
        # NUMERIC-id lookups are store-scoped so a store-private product's sequential
        # id can't be enumerated: in a resolved store you see its products (a
        # cross-store deep link 404s); with no serving store you see only company-wide
        # products. Store-private products are reached by their unguessable
        # share_token instead (see get_object).
        from stores.services import (
            resolve_catalog_store,
            store_catalog_queryset,
            visible_product_ids,
        )

        qs = self._base_qs()
        store, active = resolve_catalog_store(self.request)
        if active and store is not None:
            qs = store_catalog_queryset(qs, store)
            ids = visible_product_ids(store)
            if ids is not None:
                qs = qs.filter(id__in=ids)
            return qs
        if not active:
            # Global mode (no zone scoping configured): everything is openable, which
            # matches the global product list.
            return qs
        # Zone scoping on but no serving store (out of area / no location): company-wide
        # products only, so a store-private product's sequential id stays unguessable —
        # it is reached by its share_token instead.
        return store_catalog_queryset(qs, store)

    def get_object(self):
        key = str(self.kwargs.get("pk", ""))
        # 1. Unguessable share token → open the product for ANYONE with the link,
        #    regardless of store scoping. This is the shareable secret link; because
        #    the token has ~96 bits of entropy it cannot be guessed/enumerated.
        obj = self._base_qs().filter(share_token=key).first()
        if obj is not None:
            return obj
        # 2. Otherwise a numeric id, subject to store scoping above.
        if not key.isdigit():
            raise Http404("No Product matches the given query.")
        obj = self.get_queryset().filter(pk=int(key)).first()
        if obj is None:
            raise Http404("No Product matches the given query.")
        return obj


class ProductSearchView(_StoreContextMixin, generics.ListAPIView):
    permission_classes = [AllowAny]
    authentication_classes = [OptionalJWTAuthentication]
    serializer_class = ProductListSerializer

    def get_queryset(self):
        from django.db.models import (
            Case, IntegerField, Q, Value, When,
        )

        q = self.request.query_params.get("q", "").strip()
        if not q:
            return Product.objects.none()
        # Relevance: exact name > name-prefix > name-contains > brand > description;
        # ties broken by popularity (reviews) then rating.
        qs = (
            Product.objects.filter(is_active=True)
            # Match across LANGUAGES and keywords, not just English. A Telugu
            # shopper typing "బియ్యం" (or "biyyam") found nothing before, because
            # only the English name/brand/description were searched.
            .filter(
                Q(name__icontains=q)
                | Q(name_te__icontains=q)
                | Q(name_hi__icontains=q)
                | Q(brand__icontains=q)
                | Q(description__icontains=q)
                | Q(description_te__icontains=q)
                | Q(description_hi__icontains=q)
                | Q(search_keywords__icontains=q)
            )
            .annotate(
                relevance=Case(
                    When(name__iexact=q, then=Value(100)),
                    When(name_te__iexact=q, then=Value(100)),
                    When(name_hi__iexact=q, then=Value(100)),
                    When(name__istartswith=q, then=Value(80)),
                    When(name_te__istartswith=q, then=Value(80)),
                    When(name_hi__istartswith=q, then=Value(80)),
                    When(name__icontains=q, then=Value(60)),
                    When(name_te__icontains=q, then=Value(60)),
                    When(name_hi__icontains=q, then=Value(60)),
                    # A keyword hit is a deliberate curation, so rank it above
                    # an incidental description match.
                    When(search_keywords__icontains=q, then=Value(50)),
                    When(brand__icontains=q, then=Value(40)),
                    default=Value(20),
                    output_field=IntegerField(),
                )
            )
            .order_by("-relevance", "-review_count", "-rating", "-id")
            .select_related("category")
            .prefetch_related("variants")
        )
        # Server-resolved store scope (empty when out of area; global when flag off).
        return scope_catalog_queryset(qs, self.request)


class ProductSuggestView(_StoreContextMixin, generics.GenericAPIView):
    """As-you-type autocomplete. Returns a handful of matching products (with
    thumbnails), a short list of completion terms, and matching categories —
    deliberately lightweight so it can fire on every debounced keystroke without
    the cost of the full paginated search. Store-scoped exactly like search."""

    permission_classes = [AllowAny]
    authentication_classes = [OptionalJWTAuthentication]
    serializer_class = ProductListSerializer
    # Autocomplete is a single small slice, never paginated.
    pagination_class = None

    # Bounds — keep the payload small and predictable.
    _MAX_PRODUCTS = 6
    _MAX_TERMS = 8
    _MAX_CATEGORIES = 4
    # How many rows to scan when harvesting completion terms (popularity-ordered).
    _TERM_SCAN = 40

    def get(self, request, *args, **kwargs):
        from django.db.models import Case, IntegerField, Q, Value, When

        q = request.query_params.get("q", "").strip()
        if not q:
            return Response(
                ok(
                    "PRODUCT_SUGGESTIONS",
                    data={"products": [], "terms": [], "categories": []},
                )
            )

        # Matching active products (name or brand), store-scoped (empty out-of-area).
        base = scope_catalog_queryset(
            Product.objects.filter(is_active=True).filter(
                Q(name__icontains=q)
                | Q(name_te__icontains=q)
                | Q(name_hi__icontains=q)
                | Q(search_keywords__icontains=q)
                | Q(brand__icontains=q)
            ),
            request,
        )

        products_qs = (
            base.annotate(
                relevance=Case(
                    When(name__istartswith=q, then=Value(90)),
                    When(name__icontains=q, then=Value(70)),
                    When(brand__istartswith=q, then=Value(50)),
                    default=Value(30),
                    output_field=IntegerField(),
                )
            )
            .order_by("-relevance", "-review_count", "-rating", "-id")
            .select_related("category")
            .prefetch_related("variants")[: self._MAX_PRODUCTS]
        )
        products = self.get_serializer(products_qs, many=True).data

        # Completion terms: product names + brands that contain the query, most
        # popular first, de-duplicated case-insensitively and capped.
        terms = []
        seen = set()
        ql = q.lower()
        for name, brand in base.order_by("-review_count", "-rating").values_list(
            "name", "brand"
        )[: self._TERM_SCAN]:
            for candidate in (name, brand):
                candidate = (candidate or "").strip()
                key = candidate.lower()
                if candidate and ql in key and key not in seen:
                    seen.add(key)
                    terms.append(candidate)
            if len(terms) >= self._MAX_TERMS:
                break
        terms = terms[: self._MAX_TERMS]

        # Scoped like the products and terms above — this block wasn't, despite the
        # docstring, so typing "frozen" surfaced a chip for another store's tree
        # that opened an empty listing.
        category_qs = Category.objects.filter(is_active=True).filter(
            Q(name__icontains=q) | Q(name_te__icontains=q) | Q(name_hi__icontains=q)
        )
        visible = scoped_category_ids(request)
        if visible is not None:
            category_qs = category_qs.filter(id__in=visible)
        categories = CategorySerializer(
            category_qs[: self._MAX_CATEGORIES], many=True
        ).data

        return Response(
            ok(
                "PRODUCT_SUGGESTIONS",
                data={
                    "products": products,
                    "terms": terms,
                    "categories": categories,
                },
            )
        )
