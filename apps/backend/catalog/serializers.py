from rest_framework import serializers

from core.i18n import pick, resolve_lang

from .models import Category, Product, ProductVariant


class CategorySerializer(serializers.ModelSerializer):
    # App casts ids as String — emit them as strings (renderer → camelCase keys).
    id = serializers.CharField(read_only=True)
    parent_id = serializers.CharField(read_only=True, allow_null=True)
    # Resolved for the request's language, emitted under the plain `name` key so
    # the client needs no change (see core.i18n).
    name = serializers.SerializerMethodField()

    class Meta:
        model = Category
        fields = ["id", "name", "icon_name", "image_url", "product_count", "parent_id"]

    def get_name(self, obj):
        return pick(obj, "name", resolve_lang(self.context.get("request")))


class StoreCategorySerializer(CategorySerializer):
    """A category as it appears in the serving store's PRIVATE tree.

    ``product_count`` is overridden to the store's own subtree count (the stored
    column counts the company-wide catalog and would over-report here), and
    ``has_children`` tells the app whether tapping this tile drills into another
    rail level or opens the leaf product grid. Both are read from context maps the
    view computes once for the whole page — never per row.
    """

    product_count = serializers.SerializerMethodField()
    has_children = serializers.SerializerMethodField()
    image_url = serializers.SerializerMethodField()

    class Meta(CategorySerializer.Meta):
        fields = CategorySerializer.Meta.fields + ["has_children"]

    def get_product_count(self, obj):
        return self.context.get("private_counts", {}).get(obj.id, 0)

    def get_image_url(self, obj):
        """The curated category image, else a photo borrowed from a product inside
        it — store-created categories rarely have artwork of their own, and a rail
        of identical fallback icons is unreadable."""
        return obj.image_url or self.context.get("private_images", {}).get(obj.id)

    def get_has_children(self, obj):
        return obj.id in self.context.get("private_branches", set())


class VariantSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = ProductVariant
        fields = ["id", "label", "price_delta", "in_stock", "image_url"]


class ProductSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    category_id = serializers.CharField(read_only=True)
    reviews = serializers.IntegerField(source="review_count", read_only=True)
    # Blinkit-style listing contract: sellable count + derived discount.
    available_quantity = serializers.IntegerField(source="available_count", read_only=True)
    # name/brand/description/image/price/mrp are store-aware: when a serving `store` is
    # in serializer context, that store's per-product override (StoreProduct) applies;
    # otherwise the global Product values (identical to legacy behaviour).
    name = serializers.SerializerMethodField()
    brand = serializers.SerializerMethodField()
    description = serializers.SerializerMethodField()
    image_url = serializers.SerializerMethodField()
    price = serializers.SerializerMethodField()
    mrp = serializers.SerializerMethodField()
    discount_percent = serializers.SerializerMethodField()
    discount_amount = serializers.SerializerMethodField()
    images = serializers.SerializerMethodField()
    variants = serializers.SerializerMethodField()

    def _view(self, obj):
        """The store-resolved view of this product (cached per instance)."""
        cache = getattr(obj, "_store_view_cache", None)
        if cache is not None:
            return cache
        from stores.services import store_view

        store = self.context.get("store")
        overrides = self.context.get("store_overrides")
        sp = overrides.get(obj.id) if overrides is not None else "__lookup__"
        view = store_view(obj, store, sp=sp)
        try:
            obj._store_view_cache = view
        except Exception:  # pragma: no cover - defensive
            pass
        return view

    @property
    def _lang(self):
        return resolve_lang(self.context.get("request"))

    def _localized(self, obj, field):
        """Store override first, then the language column, then English.

        A store-specific override is that store's own wording for their own
        product — translating it would mean overwriting text a human chose. Only
        the shared company-catalog text carries translations.
        """
        value = self._view(obj)[field]
        if value != getattr(obj, field, None):
            return value                      # store set its own wording
        return pick(obj, field, self._lang)

    def get_name(self, obj):
        return self._localized(obj, "name")

    def get_brand(self, obj):
        return self._view(obj)["brand"]

    def get_description(self, obj):
        return self._localized(obj, "description")

    def get_image_url(self, obj):
        return self._view(obj)["image_url"]

    def get_price(self, obj):
        return self._view(obj)["price"]

    def get_mrp(self, obj):
        return self._view(obj)["mrp"]

    def get_discount_percent(self, obj):
        v = self._view(obj)
        price, mrp = v["price"], v["mrp"]
        return round((mrp - price) / mrp * 100) if mrp and mrp > price else 0

    def get_discount_amount(self, obj):
        v = self._view(obj)
        price, mrp = v["price"], v["mrp"]
        return (mrp - price) if (mrp and mrp > price) else price * 0

    class Meta:
        model = Product
        fields = [
            "id",
            "share_token",
            "name",
            "brand",
            "unit",
            "price",
            "mrp",
            "credit_price",
            "discount_percent",
            "discount_amount",
            "category_id",
            "rating",
            "reviews",
            "image_url",
            "images",
            "in_stock",
            "stock_count",
            "available_quantity",
            "description",
            "specifications",
            "variants",
        ]

    def get_images(self, obj):
        urls = [g.url for g in obj.gallery.all()]
        if not urls:
            img = self._view(obj)["image_url"]
            if img:
                urls = [img]
        return urls

    def get_variants(self, obj):
        """Each pack with its OWN stock in the serving store, its own image (falling
        back to the product photo), and its resolved price (store base + delta). The
        `available` here is what the app gates add-to-cart on, per pack."""
        variants = list(obj.variants.all())
        if not variants:
            return []
        view = self._view(obj)
        base_price = view["price"] or 0
        store = self.context.get("store")
        buckets = {}
        if store is not None and store.warehouse_id is not None:
            from inventory.services import StockCalculationService

            buckets = StockCalculationService.by_variant(obj, store.warehouse)
        out = []
        for v in variants:
            avail = (buckets.get(v.id) or {}).get("available")
            # No serving store (global catalog) → fall back to the derived flag so the
            # payload is never emptier than before store scoping.
            in_stock = (avail > 0) if avail is not None else v.in_stock
            # snake_case keys — the response renderer camelizes them, same as every
            # other field, so the app sees priceDelta / imageUrl / inStock.
            out.append({
                "id": str(v.id),
                "label": v.label,
                "price_delta": v.price_delta,
                "price": base_price + (v.price_delta or 0),
                "mrp": v.mrp,
                "image_url": v.image_url or view["image_url"],
                "available": avail,
                "in_stock": in_stock,
            })
        return out


class ProductListSerializer(ProductSerializer):
    """Lighter payload for grids/rails (skips the gallery query, and computes
    variants from one BATCHED stock query for the whole page instead of the
    detail page's per-product query).

    Variants are NOT just extra detail here — the app's add-to-cart guard
    (`addToCartOrChoose`) checks `product.variants.isEmpty` to decide whether
    tapping a card's quick-add button is safe to act on directly, or must open
    the detail page for the customer to pick a pack. Before this, the list
    payload always sent `variants: []` regardless of whether the product
    actually had packs, so that guard never engaged: a card would show as
    in-stock (the product-level flag is true the moment ANY pack has stock)
    and quick-add would silently add whichever pack the base product record
    represents — even a 0-stock one — while opening the SAME card's detail
    page correctly steered you to a pack that's actually available.
    """

    class Meta(ProductSerializer.Meta):
        fields = [
            # share_token rides along in the LIST payload too: every grid/rail/search
            # card has a share button, and without the token those cards fell back to
            # the sequential id — which a store-private product must never leak.
            "id", "share_token", "name", "brand", "unit", "price", "mrp",
            "credit_price", "discount_percent", "discount_amount", "category_id",
            "rating", "reviews", "image_url", "in_stock", "stock_count",
            "available_quantity", "variants",
        ]

    def get_images(self, obj):  # not used in list
        return []

    def _bulk_variant_buckets(self):
        """Per-request cache of `{product_id: {variant_id: {...}}}` for every
        product on THIS page, fetched in one query on first access and reused
        by every sibling card — see `by_variant_bulk`."""
        cache = self.context.get("_bulk_variant_buckets")
        if cache is not None:
            return cache
        from inventory.services import StockCalculationService

        store = self.context.get("store")
        warehouse = store.warehouse if store and store.warehouse_id else None
        # `self.root` is the auto-created ListSerializer wrapping the whole
        # page; `.instance` is the page's product list, known up front because
        # DRF paginates before serializing.
        page = getattr(self.root, "instance", None) or []
        ids = [p.id for p in page]
        cache = StockCalculationService.by_variant_bulk(ids, warehouse)
        self.context["_bulk_variant_buckets"] = cache
        return cache

    def get_variants(self, obj):
        variants = list(obj.variants.all())  # prefetched — see the view's queryset
        if not variants:
            return []
        view = self._view(obj)
        base_price = view["price"] or 0
        store = self.context.get("store")
        buckets = self._bulk_variant_buckets().get(obj.id, {}) if store else {}
        out = []
        for v in variants:
            avail = (buckets.get(v.id) or {}).get("available")
            in_stock = (avail > 0) if avail is not None else v.in_stock
            out.append({
                "id": str(v.id),
                "label": v.label,
                "price_delta": v.price_delta,
                "price": base_price + (v.price_delta or 0),
                "mrp": v.mrp,
                "image_url": v.image_url or view["image_url"],
                "available": avail,
                "in_stock": in_stock,
            })
        return out
