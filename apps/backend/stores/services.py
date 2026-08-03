"""Store-based product visibility (spec §PRODUCT VISIBILITY / INVENTORY).

A customer should only see products carried by the store serving their zone.
This is gated behind the ``zone_store_visibility`` FeatureFlag and is **OFF by
default** — until the flag is enabled the catalog behaves globally exactly as
before, so turning zones on never silently empties the storefront.
"""

VISIBILITY_FLAG = "zone_store_visibility"
ENFORCEMENT_FLAG = "zone_enforcement"
PRICING_FLAG = "store_pricing"


def _flag_on(key: str) -> bool:
    from system.models import FeatureFlag

    return FeatureFlag.objects.filter(key=key, enabled=True).exists()


def store_visibility_enabled() -> bool:
    """True when the platform has opted into store-scoped catalog visibility."""
    return _flag_on(VISIBILITY_FLAG)


def zone_enforcement_enabled() -> bool:
    """True when checkout must reject addresses outside every serviceable zone."""
    return _flag_on(ENFORCEMENT_FLAG)


def store_pricing_enabled() -> bool:
    """True when per-store selling prices should be APPLIED to customers/POS. OFF by
    default — admins can still SET per-store prices; they only take effect once on."""
    return _flag_on(PRICING_FLAG)


def visible_product_ids(store):
    """Product ids the given store carries — a UNION model so a store can both stock
    shared products AND curate/override individual ones without one clobbering the
    other:

      carried = (on-hand > 0 in the store's warehouse)
                ∪ (StoreProduct.is_available=True — explicitly carried, incl. the
                   store's own private products)
                − (StoreProduct.is_available=False — explicitly hidden)

    Returns None when the store has no warehouse (callers then leave the queryset
    unfiltered)."""
    if store is None or store.warehouse_id is None:
        return None
    from inventory.models import StockItem

    from .models import StoreProduct

    stocked = set(
        StockItem.objects.filter(
            warehouse_id=store.warehouse_id, quantity__gt=0
        ).values_list("product_id", flat=True)
    )
    sp = StoreProduct.objects.filter(store=store)
    available = set(sp.filter(is_available=True).values_list("product_id", flat=True))
    hidden = set(sp.filter(is_available=False).values_list("product_id", flat=True))
    return (stocked | available) - hidden


def store_catalog_queryset(qs, store):
    """Restrict a ``Product`` queryset so store-PRIVATE products (``origin_store``
    set) of OTHER stores never appear. Company-wide products (``origin_store`` NULL)
    always pass; a store's own private products pass only for that store. ``store``
    may be None (→ only company-wide products pass — the safe global default)."""
    from django.db.models import Q

    owner = getattr(store, "id", None)
    return qs.filter(Q(origin_store__isnull=True) | Q(origin_store_id=owner))


def store_sellable_queryset(qs, store):
    """Products this store can actually SELL at its own counter.

    Stricter than :func:`store_catalog_queryset`, which only hides OTHER stores'
    private products and lets every company-wide product through — that made the
    POS offer the whole 25-product global catalog to a store carrying 3, and
    ringing one up died with a 409 at Charge because there was no stock.

    "Sellable" == :func:`visible_product_ids`: on-hand in this store's warehouse,
    or explicitly carried via StoreProduct, minus anything explicitly hidden. Same
    definition the customer-facing store catalog uses, so the till and the app
    agree on what this shop sells.

    NOT gated on the ``zone_store_visibility`` flag: that flag governs the CUSTOMER
    catalog. A till must always reflect its own shelf — selling stock you don't
    have isn't a display preference. (`store_view` bypasses its flag for the same
    reason.) Falls back to the looser scope when the store has no warehouse, so a
    mis-provisioned store degrades to today's behaviour instead of an empty POS.
    """
    qs = store_catalog_queryset(qs, store)
    ids = visible_product_ids(store)
    if ids is None:
        return qs
    return qs.filter(id__in=ids)


def store_entry(product, store):
    """The StoreProduct row for (store, product), or None."""
    if store is None:
        return None
    from .models import StoreProduct

    return StoreProduct.objects.filter(store=store, product=product).first()


def store_price(product, store):
    """Per-store selling price when store_pricing is ON and a StoreProduct price is
    set; otherwise the global Product.price. Contract-safe fallback."""
    if store is None or not store_pricing_enabled():
        return product.price
    sp = store_entry(product, store)
    if sp is not None and sp.selling_price is not None:
        return sp.selling_price
    return product.price


def store_mrp(product, store):
    if store is None or not store_pricing_enabled():
        return product.mrp
    sp = store_entry(product, store)
    if sp is not None and sp.mrp is not None:
        return sp.mrp
    return product.mrp


def store_view(product, store, sp="__lookup__"):
    """Resolved display + price for ``product`` AT ``store``, applying any per-store
    :class:`StoreProduct` override (name / brand / description / image / price / mrp)
    and falling back to the global ``Product`` for every unset field.

    Unlike :func:`store_price`, overrides here are NOT gated by the ``store_pricing``
    flag — they apply wherever a serving store is actually resolved (the store-scoped
    customer catalog and the store's own POS), which is the store manager's intent
    when they curate their storefront. ``store=None`` → the global product values.

    ``sp`` may be passed in (from a prefetched per-store override map) to avoid a
    per-product query; the sentinel triggers a lookup.
    """
    view = {
        "name": product.name,
        "brand": product.brand,
        "description": product.description,
        "image_url": product.image_url,
        "price": product.price,
        "mrp": product.mrp,
    }
    if store is None:
        return view
    if sp == "__lookup__":
        sp = store_entry(product, store)
    if sp is None:
        return view
    if sp.name:
        view["name"] = sp.name
    if sp.brand:
        view["brand"] = sp.brand
    if sp.description:
        view["description"] = sp.description
    if sp.image_url:
        view["image_url"] = sp.image_url
    if sp.selling_price is not None:
        view["price"] = sp.selling_price
    if sp.mrp is not None:
        view["mrp"] = sp.mrp
    return view


def resolve_store(store_id):
    """Fetch a Store by id (with warehouse), or None."""
    if not store_id:
        return None
    from .models import Store

    return Store.objects.filter(pk=store_id).select_related("warehouse").first()


def resolve_user_store(user):
    """Best-effort store serving the user's default address (None if unknown). Used
    by the cart so per-store pricing matches the customer's serving store."""
    if user is None or not getattr(user, "is_authenticated", False):
        return None
    from addresses.models import Address

    addr = (
        Address.objects.filter(user=user, is_default=True).first()
        or Address.objects.filter(user=user).first()
    )
    if addr is None:
        return None
    from zones.serviceability import resolve_serviceable_zone

    zone = resolve_serviceable_zone(
        lat=addr.latitude, lng=addr.longitude, pincode=addr.pincode or None
    )
    return getattr(zone, "store", None) if zone is not None else None


def warehouse_store(warehouse):
    """The Store linked to a warehouse (reverse OneToOne), or None."""
    return getattr(warehouse, "store", None) if warehouse is not None else None


def filter_products_by_store(qs, store_id):
    """Restrict a Product queryset to what the resolved store carries — but only
    when store visibility is enabled AND a valid store is supplied. Otherwise the
    queryset is returned untouched (the safe global default).

    DEPRECATED for the customer catalog — it trusts a client-supplied store id and
    leaks the global catalog when none is given. Use :func:`scope_catalog_queryset`,
    which resolves the store SERVER-SIDE from the user's location and returns an empty
    set (never the global catalog) when no serviceable store resolves. Kept only for
    any internal/admin callers that already hold a trusted store id."""
    if not store_id or not store_visibility_enabled():
        return qs
    from .models import Store

    store = (
        Store.objects.filter(pk=store_id)
        .select_related("warehouse")
        .first()
    )
    ids = visible_product_ids(store)
    if ids is None:
        return qs
    return qs.filter(id__in=ids)


def resolve_catalog_store(request):
    """Cached wrapper around :func:`_resolve_catalog_store` (one resolution per request
    — the queryset scope and the serializer pricing context both ask for it)."""
    cached = getattr(request, "_catalog_store_cache", None)
    if cached is not None:
        return cached
    result = _resolve_catalog_store(request)
    try:
        request._catalog_store_cache = result
    except Exception:  # pragma: no cover - request may be immutable in odd cases
        pass
    return result


def _resolve_catalog_store(request):
    """Resolve, **server-side**, the single store whose catalog this request may see.

    The store is NEVER taken from a client-supplied store id — a customer must not be
    able to choose (or omit) a store to widen what they see. Instead it is derived from
    the customer's actual location, in priority order:

      1. ``lat`` / ``lng`` / ``pincode`` query params — the device's current/selected
         delivery location (the app passes these);
      2. the authenticated user's selected/default saved address;
      3. (transitional) a ``store`` query param, accepted ONLY if it is a real active
         store — a single-store scope, never the global catalog — so older app builds
         that still send a store id keep working until they pass location instead.

    Returns ``(store_or_None, scoping_active)``. When ``scoping_active`` is True the
    caller scopes to the resolved store (or returns an EMPTY catalog if the store is
    None — out of area); when False the global catalog is returned unchanged.

    VARIABLE ZONE (location-driven): a genuine **selected location** (lat/lng/pincode)
    that falls inside a Zone polygon resolves that zone's store and scopes the catalog
    to it **on its own — even when the global ``zone_store_visibility`` flag is off**.
    This lets zone scoping "light up" per area as polygons are drawn, without a risky
    all-or-nothing flip: a customer whose selected location is inside a served zone sees
    only that store's catalog, while everyone else (no location, or an area with no zone
    drawn yet) keeps the global catalog. The global flag only additionally governs the
    weaker signals below (saved address + the transitional ``store`` param), which stay
    global while the flag is off so older app builds are unaffected."""
    from zones.serviceability import resolve_serviceable_zone

    qp = getattr(request, "query_params", None) or {}
    lat, lng, pincode = qp.get("lat"), qp.get("lng"), qp.get("pincode")

    # 1. VARIABLE ZONE — an explicit selected location, resolved against the zone
    #    polygons. Authoritative and flag-independent: when the point is inside a
    #    served zone WITH a store, scope to that store. A zone with no store (or no
    #    zone at all) is not a scope signal here — fall through so an unzoned area
    #    keeps the global catalog instead of going blank.
    if lat or lng or pincode:
        zone = resolve_serviceable_zone(lat=lat, lng=lng, pincode=pincode)
        store = getattr(zone, "store", None) if zone is not None else None
        if store is not None:
            return store, True

    # Beyond an explicit in-zone location, scoping only applies when the global flag
    # is on. Flag off → global catalog (back-compat: the transitional ?store= param
    # and saved-address stay global, as older builds expect).
    if not store_visibility_enabled():
        return None, False

    # 2. authenticated user's saved address
    user = getattr(request, "user", None)
    if user is not None and getattr(user, "is_authenticated", False):
        from addresses.models import Address

        addr = (
            Address.objects.filter(user=user, is_default=True).first()
            or Address.objects.filter(user=user).first()
        )
        if addr is not None:
            zone = resolve_serviceable_zone(
                lat=addr.latitude, lng=addr.longitude, pincode=addr.pincode or None
            )
            if zone is not None:
                return getattr(zone, "store", None), True

    # 3. transitional: a real active store id (still single-store, never the union)
    store_id = qp.get("store")
    if store_id:
        store = resolve_store(store_id)
        if store is not None and store.is_serviceable:
            return store, True

    return None, True


def scope_catalog_queryset(qs, request):
    """Scope a customer Product queryset to the request's serving store (server-side).

    * scoping inactive (global catalog) → the WHOLE catalog, INCLUDING store-added
      products, so a product added in the store panel is sellable immediately even
      before any zone is drawn (single-store / launch reality);
    * scoping active + store resolved → only that store's carried products (its own
      private products + company-wide), other stores' private products hidden;
    * scoping active + no serviceable store → EMPTY (out of area).

    Scoping goes "active" per the variable-zone rules in :func:`resolve_catalog_store`
    (an in-zone selected location, or the global ``zone_store_visibility`` flag)."""
    store, active = resolve_catalog_store(request)
    if not active:
        # Global catalog: show everything. A store's own products join the shared
        # storefront until zone scoping narrows the view to a single store.
        return qs
    if store is None:
        return qs.none()
    qs = store_catalog_queryset(qs, store)
    ids = visible_product_ids(store)
    if ids is None:
        return qs.none()
    return qs.filter(id__in=ids)
