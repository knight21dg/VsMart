"""Store-scoped catalog management — the store panel's "add / manage items" surface.

A store can:
  * create a PRIVATE product (``Product.origin_store`` = its store) that only it sells
    — visible in its own POS and its zone's customer catalog, never elsewhere;
  * OVERRIDE a shared company product for its own storefront/POS — a different price,
    photo, name/brand/description — without touching the global product or any other
    store (persisted on the per-store ``StoreProduct`` row);
  * upload product photos to VS Mart's own media engine (no external URLs).

Everything is scoped to ``request.store`` from the caller's :class:`StoreStaff`
membership, so a store can never read or mutate another store's catalog.
"""
from django.db import transaction
from django.db.models import Q
from rest_framework import status as http
from rest_framework.exceptions import ValidationError
from rest_framework.generics import get_object_or_404
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit

from .io_utils import field, present
from .permissions import StoreScopedMixin


def _num(v):
    """Parse a money/number field, or None when blank."""
    if v in (None, ""):
        return None
    return v


def _money(v, key, *, allow_zero=True):
    """A non-negative money amount, or a 400 naming the field.

    The raw value used to go straight onto the model: ``price="abc"`` blew up as a
    500 (``decimal.InvalidOperation``) instead of a field error, and ``price=-10``
    saved cleanly — producing negative line totals in the cart and POS.
    """
    from decimal import Decimal, InvalidOperation

    try:
        amount = Decimal(str(v))
    except (InvalidOperation, TypeError, ValueError):
        raise ValidationError({key: ["Enter a valid amount."]})
    if amount < 0:
        raise ValidationError({key: ["Cannot be negative."]})
    if not allow_zero and amount == 0:
        raise ValidationError({key: ["Must be greater than zero."]})
    return amount


def _reorder_level(v, key="reorderLevel"):
    """A non-negative whole number, or a 400. ``int("abc")`` used to escape as a 500
    and ``-5`` was written straight to a PositiveIntegerField."""
    try:
        n = int(v)
    except (TypeError, ValueError):
        raise ValidationError({key: ["Enter a whole number."]})
    if n < 0:
        raise ValidationError({key: ["Cannot be negative."]})
    return n


def _sync_variants(product, variants):
    """Replace a product's variants with the given list — used for the store's OWN
    (private) products only. Each item:
    ``{id?, label, priceDelta, mrp?, imageUrl?, barcode?, openingStock?, reorderLevel?}``.
    Items without a matching id are created; matched ids are updated; existing variants
    absent from the list are deleted. Passing an empty list clears them.

    Returns ``(scanned, stock)``:

    * ``scanned`` — ``{variant_id: barcode}`` for the codes the caller sent, so
      :func:`_sync_barcodes` can attach them (new variants have no id at submit time,
      which is why the mapping is built here rather than guessed later);
    * ``stock`` — ``[(variant, openingStock|None, reorderLevel|None)]`` for the caller
      to post through the ledger. Stock is NOT written here: a variant is a row, but
      its stock is a movement, and movements only go through `InventoryService`."""
    from catalog.models import ProductVariant
    from inventory.services import StockCalculationService

    existing = {str(v.id): v for v in product.variants.all()}
    keep = set()
    scanned = {}
    stock = []
    for item in variants or []:
        label = (field(item, "label") or "").strip()
        if not label:
            continue
        delta = _num(field(item, "priceDelta")) or 0
        code = (field(item, "barcode") or "").strip()
        image = (field(item, "imageUrl") or "").strip()
        mrp = _num(field(item, "mrp"))
        vid = field(item, "id")
        if vid and str(vid) in existing:
            v = existing[str(vid)]
            v.label, v.price_delta, v.image_url, v.mrp = label, delta, image, mrp
            v.save(update_fields=["label", "price_delta", "image_url", "mrp"])
            keep.add(str(vid))
        else:
            v = ProductVariant.objects.create(
                product=product, label=label, price_delta=delta,
                image_url=image, mrp=mrp,
            )
        if code:
            scanned[v.id] = code
        # Each pack carries its own opening count and reorder point; the caller
        # posts them through the ledger once the variants exist.
        stock.append((v, _num(field(item, "openingStock")),
                      _num(field(item, "reorderLevel"))))
    for vid, v in existing.items():
        if vid in keep:
            continue
        # Refuse to drop a pack that still has stock. ProductVariant CASCADEs its
        # StockItem but only SET_NULLs its ledger rows, so deleting a stocked
        # variant would bin the cache while leaving the movements behind — the next
        # `reconcile` would resurrect those units in the unallocated pool, silently
        # and with no trace of which pack they were. Make the operator write the
        # stock off (or count it to zero) first, which is a real, auditable decision.
        on_hand = StockCalculationService.on_hand(product, variant=v)
        if on_hand:
            raise ValidationError({"variants": [
                f"'{v.label}' still has {on_hand} in stock. Write it off or count it "
                f"to zero before removing the pack."
            ]})
        v.delete()
    return scanned, stock


def _apply_stock(product, wh, *, d, variant_stock, by, reason):
    """Create the stock rows and post the opening counts for a product the store just
    added or edited. Returns the product's total on-hand.

    Branches on whether the PRODUCT has packs, not on whether this request sent a
    ``variants[]`` list — a shared company product can have variants the store still
    stocks without being allowed to edit them.

    A product with variants is stocked per PACK: its top-level ``openingStock`` is
    meaningless (which pack would those units be?) and is rejected rather than
    silently pooled where nothing can sell it. A product without variants keeps the
    single product-level count it has always had.
    """
    from catalog.models import ProductVariant
    from inventory.models import StockItem
    from inventory.services import InventoryService, StockCalculationService

    if wh is None:
        return 0
    # Query fresh, never `product.variants.all()`: the caller prefetched variants and
    # `_sync_variants` has since added/removed some, so the cache still lists deleted
    # packs — stocking one of those is an FK violation and a 500. (`_sync_barcodes`
    # re-queries for the same reason.)
    variants = list(ProductVariant.objects.filter(product=product))
    if variants:
        if _num(field(d, "openingStock")) is not None:
            raise ValidationError({"openingStock": [
                "This product is sold by pack — set the stock on each variant instead."
            ]})
        intents = {v.id: (opening, reorder) for v, opening, reorder in variant_stock}
        for v in variants:
            # Always create the row so every pack lists in inventory, even at 0.
            si, _ = StockItem.objects.get_or_create(
                product=product, variant=v, warehouse=wh
            )
            opening, reorder = intents.get(v.id, (None, None))
            if reorder is not None:
                si.low_stock_threshold = _reorder_level(reorder)
                si.save(update_fields=["low_stock_threshold"])
            if opening is not None:
                try:
                    InventoryService.adjust(
                        product, variant=v, set=int(opening), warehouse=wh,
                        reason=reason, created_by=by,
                    )
                except Exception as e:  # surface domain errors as 400
                    raise ValidationError({"variants": [f"{v.label}: {e}"]})
        return StockCalculationService.on_hand(product, wh)

    si, _ = StockItem.objects.get_or_create(product=product, warehouse=wh)
    reorder = _num(field(d, "reorderLevel"))
    if reorder is not None:
        si.low_stock_threshold = _reorder_level(reorder)
        si.save(update_fields=["low_stock_threshold"])
    opening = _num(field(d, "openingStock"))
    if opening is None:
        return StockCalculationService.on_hand(product, wh)
    try:
        return InventoryService.adjust(
            product, set=int(opening), warehouse=wh, reason=reason, created_by=by,
        )
    except Exception as e:  # surface domain errors as 400
        raise ValidationError({"openingStock": [str(e)]})


def _ean13(body12: str) -> str:
    """Append the EAN-13 check digit to a 12-digit body → a scannable 13-digit code."""
    s = sum((3 if i % 2 else 1) * int(d) for i, d in enumerate(body12))
    return body12 + str((10 - s % 10) % 10)


def barcode_owner(code, *, product=None, variant=None):
    """The existing Barcode row that would CLASH with `code`, or None.

    A code is free only if no other row holds it. The same product+variant's own row
    doesn't count as a clash (re-saving an unchanged code must be a no-op), but the
    SAME product's *other* variant does — every sellable unit needs its own code."""
    from inventory.models import Barcode

    if not code:
        return None
    qs = Barcode.objects.select_related("product", "variant").filter(code=code)
    for row in qs:
        if row.product_id == getattr(product, "id", None) and row.variant_id == (
            variant.id if variant else None
        ):
            continue  # its own row
        return row
    return None


def _assert_barcode_free(code, *, product=None, variant=None, key="barcode"):
    """Reject a scanned code already assigned elsewhere, naming the owner so the
    operator knows what they just scanned."""
    row = barcode_owner(code, product=product, variant=variant)
    if row is None:
        return
    where = row.product.name
    if row.variant_id:
        where += f" ({row.variant.label})"
    raise ValidationError(
        {key: [f"Barcode {code} is already assigned to '{where}'. "
               f"Every product/variant needs its own code."]}
    )


def _symbology(code):
    return "EAN13" if len(code) == 13 and code.isdigit() else "CODE128"


def _sync_barcodes(product, *, product_code=None, variant_codes=None):
    """Ensure the product AND every variant has a unique, scannable barcode.

    A SCANNED code (off the physical pack) always wins and becomes the unit's unique
    key — that's what stops the same item being added twice. When none is scanned we
    fall back to a deterministic in-store EAN-13 (GS1 restricted prefix ``2``):
    ``20`` + product id for the base product, ``21`` + variant id per variant, so
    every unit is still scannable. Idempotent; variant deletes cascade their codes."""
    from catalog.models import ProductVariant
    from inventory.models import Barcode

    codes = {str(k): v for k, v in (variant_codes or {}).items()}

    def apply(variant, scanned, auto_body):
        row = Barcode.objects.filter(product=product, variant=variant).first()
        code = (scanned or "").strip()
        if code:
            _assert_barcode_free(code, product=product, variant=variant)
            if row is None:
                Barcode.objects.create(product=product, variant=variant, code=code,
                                       symbology=_symbology(code), is_primary=True)
            elif row.code != code:
                row.code, row.symbology = code, _symbology(code)
                row.save(update_fields=["code", "symbology"])
            return
        if row is None:  # no scan → keep it scannable with a generated in-store code
            Barcode.objects.get_or_create(
                product=product, variant=variant,
                defaults={"code": _ean13(auto_body), "is_primary": True},
            )

    apply(None, product_code, f"20{product.id:010d}")
    # Query variants fresh (a prefetch cache on `product` may be stale after a sync).
    for v in ProductVariant.objects.filter(product=product):
        apply(v, codes.get(str(v.id)), f"21{v.id:010d}")


def _sync_images(product, urls):
    """Replace a product's gallery (ProductImage rows) with the given ordered list of
    image URLs — store-owned products only. Returns the first URL (for the single
    ``Product.image_url`` thumbnail) or "" when the gallery is cleared."""
    from catalog.models import ProductImage

    clean = [u for u in (urls or []) if u]
    product.gallery.all().delete()
    for i, u in enumerate(clean):
        ProductImage.objects.create(product=product, url=u, sort=i)
    return clean[0] if clean else ""


def _product_payload(product, store):
    """The store's resolved view of a product + the raw override values it may edit."""
    from inventory.models import StockItem
    from inventory.services import StockCalculationService
    from stores.services import store_entry, store_view

    sp = store_entry(product, store)
    view = store_view(product, store, sp=sp)
    owned = product.origin_store_id == store.id
    # Barcode per product/variant (for display + POS scanning).
    barcodes = {b.variant_id: b.code for b in product.barcodes.all()}
    # Each pack's own stock in THIS store's warehouse — the panel renders a stock
    # column per variant, not one number for the product.
    wh = store.warehouse if store is not None else None
    buckets = StockCalculationService.by_variant(product, wh) if wh else {}
    reorders = {}
    if wh is not None:
        reorders = {
            si.variant_id: si.low_stock_threshold
            for si in StockItem.objects.filter(product=product, warehouse=wh)
        }
    return {
        "productId": str(product.id),
        "private": owned,
        "categoryId": str(product.category_id) if product.category_id else None,
        "categoryName": product.category.name if product.category_id else None,
        "sku": product.sku or "",
        "hsn": product.hsn or "",
        "unit": product.unit or "",
        # Resolved (what this store shows) …
        "name": view["name"],
        "brand": view["brand"],
        "description": view["description"],
        "imageUrl": view["image_url"] or "",
        "images": [g.url for g in product.gallery.all()],
        "barcode": barcodes.get(None, ""),
        "price": float(view["price"] or 0),
        "mrp": float(view["mrp"] or 0),
        "isAvailable": sp.is_available if sp is not None else True,
        # … and the global product values, so the UI can show "overridden from".
        "globalName": product.name,
        "globalPrice": float(product.price or 0),
        "globalMrp": float(product.mrp or 0),
        # The RAW per-store override (null = "follow the company product"). The
        # editor must bind to these, not to the resolved `price`/`mrp` above —
        # echoing a resolved value back is what silently pinned an override.
        "overridePrice": (float(sp.selling_price) if sp is not None
                          and sp.selling_price is not None else None),
        "overrideMrp": (float(sp.mrp) if sp is not None
                        and sp.mrp is not None else None),
        # Variants are editable for the store's OWN products (global product variants
        # are read-only here). Always surfaced so the edit dialog can show them.
        "variants": [
            {"id": str(v.id), "label": v.label, "priceDelta": float(v.price_delta or 0),
             "price": float((view["price"] or 0) + (v.price_delta or 0)),
             "mrp": float(v.mrp) if v.mrp is not None else None,
             # Falls back to the product photo, so the UI never renders a blank tile
             # for a pack that simply looks the same.
             "imageUrl": v.image_url or view["image_url"] or "",
             "hasOwnImage": bool(v.image_url),
             "barcode": barcodes.get(v.id, ""),
             # This pack's own stock in this store.
             "onHand": (buckets.get(v.id) or {}).get("onHand", 0),
             "available": (buckets.get(v.id) or {}).get("available", 0),
             "reorderLevel": reorders.get(v.id, 0),
             "inStock": v.in_stock}
            for v in product.variants.all()
        ],
        # Stock received before this product had packs. Counted in the product total
        # but sellable as nothing until the store says which pack it is — surfaced so
        # it can't sit invisible.
        "unallocated": (buckets.get(None) or {}).get("onHand", 0)
        if product.variants.exists() else 0,
        "hasOverride": sp is not None and any(
            [sp.name, sp.brand, sp.description, sp.image_url,
             sp.selling_price is not None, sp.mrp is not None]
        ),
    }


class StoreCategoriesView(StoreScopedMixin, APIView):
    """Active categories for the store's product-add form. Returns `parentId` so the
    UI can present a department → sub-category cascade (top-level = parentId null)."""

    store_permission = "inventory.view"

    def get(self, request):
        from catalog.models import Category

        rows = (
            Category.objects.filter(is_active=True)
            .order_by("sort_order", "name")
            .values("id", "name", "parent_id")
        )
        return Response([
            {
                "id": str(r["id"]),
                "name": r["name"],
                "parentId": str(r["parent_id"]) if r["parent_id"] else None,
            }
            for r in rows
        ])


class StoreProductImageView(StoreScopedMixin, APIView):
    """Upload a product photo to VS Mart's media engine → returns a public URL to
    store in the product/override ``imageUrl``. Field name: ``file``."""

    store_permission = "inventory.manage"
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        from mediastore.pipeline import ingest_public_image

        upload = request.FILES.get("file") or request.FILES.get("image")
        if upload is None:
            raise ValidationError({"file": ["An image file is required."]})
        url = ingest_public_image(upload, owner=request.user, category="catalog")
        return Response({"url": url}, status=http.HTTP_201_CREATED)


class StoreCatalogCreateView(StoreScopedMixin, APIView):
    """POST → create a store-private product (belongs to this store only)."""

    store_permissions = {"read": "inventory.view", "write": "inventory.manage"}

    # ATOMIC: the product, its StoreProduct link, variants, gallery, barcodes and
    # the opening-stock ledger movement are ONE unit of work. Without this the
    # opening-stock step (which takes a `select_for_update` row lock, and so *needs*
    # a transaction) blew up and left a half-built, barcode-less orphan product
    # behind on every failed click.
    @transaction.atomic
    def post(self, request):
        from catalog.models import Category, Product
        from inventory.models import StockItem
        from inventory.services import InventoryService

        from stores.models import StoreProduct

        d = request.data
        name = (field(d, "name") or "").strip()
        if not name:
            raise ValidationError({"name": ["Product name is required."]})
        category_id = field(d, "categoryId")
        if not category_id:
            raise ValidationError({"categoryId": ["Choose a category."]})
        category = get_object_or_404(Category, pk=category_id)
        price = _num(field(d, "price"))
        if price is None:
            raise ValidationError({"price": ["A selling price is required."]})
        price = _money(price, "price", allow_zero=False)
        mrp = _num(field(d, "mrp"))
        if mrp is not None:
            mrp = _money(mrp, "mrp")
            # MRP is the printed ceiling — selling above it is illegal in India, and
            # an MRP below price silently made discount_percent read 0.
            if mrp < price:
                raise ValidationError(
                    {"mrp": ["MRP cannot be less than the selling price."]}
                )
        # A multi-image gallery (each pre-cropped 1:1 by the client) or a single image.
        images = field(d, "images")
        clean_images = [u for u in (images or []) if u]
        image_url = (clean_images[0] if clean_images else None) or (field(d, "imageUrl") or "")
        # Check the scanned code BEFORE creating anything: scanning a pack that's
        # already in the catalog must read as "this already exists", not create a
        # second copy of it. (The write is atomic anyway, but this gives the good
        # error instead of a constraint blow-up.)
        scanned_code = (field(d, "barcode") or "").strip()
        _assert_barcode_free(scanned_code)
        product = Product.objects.create(
            name=name,
            brand=field(d, "brand", "") or "",
            unit=field(d, "unit", "") or "Each",
            sku=field(d, "sku", "") or "",
            hsn=field(d, "hsn", "") or "",
            price=price,
            mrp=mrp if mrp is not None else price,
            category=category,
            description=field(d, "description", "") or "",
            image_url=image_url,
            origin_store=self.store,
        )
        # Mark the store as carrying it (so it shows in POS + the zone catalog).
        StoreProduct.objects.create(store=self.store, product=product, is_available=True)

        # Optional variants (label + price delta + image + their own scanned codes
        # and their own opening stock).
        variant_codes, variant_stock = _sync_variants(product, field(d, "variants"))
        if images is not None:
            _sync_images(product, clean_images)
        # A scannable barcode for the product + each variant (POS scan-to-cart).
        # A scanned code becomes the unit's unique key; otherwise one is generated.
        _sync_barcodes(product, product_code=scanned_code, variant_codes=variant_codes)

        wh = self.store.warehouse
        on_hand = _apply_stock(
            product, wh, d=d, variant_stock=variant_stock, by=request.user,
            reason="Opening stock (store product add)",
        )
        record_audit(request.user, "store_product.create", target=product,
                     after={"name": name, "onHand": on_hand})
        data = _product_payload(product, self.store)
        data["onHand"] = on_hand
        return Response(data, status=http.HTTP_201_CREATED)


class StoreProductOverrideView(StoreScopedMixin, APIView):
    """GET the store's view of a product; PATCH to override it for THIS store only.

    A store-owned private product is edited in place (the store owns it). A shared
    company product is never mutated — edits land on the per-store StoreProduct row.
    """

    store_permissions = {"read": "inventory.view", "write": "inventory.manage"}

    def _product(self, product_id):
        from catalog.models import Product

        return get_object_or_404(
            Product.objects.select_related("category")
            .prefetch_related("variants", "gallery", "barcodes")
            .filter(Q(origin_store__isnull=True) | Q(origin_store=self.store)),
            pk=product_id,
        )

    def get(self, request, product_id):
        return Response(_product_payload(self._product(product_id), self.store))

    # ATOMIC for the same reason as the create path: the stock adjustment takes a
    # row lock, and a partial edit (fields saved, stock rejected) must never stick.
    @transaction.atomic
    def patch(self, request, product_id):
        from stores.models import StoreProduct

        product = self._product(product_id)
        d = request.data
        owned = product.origin_store_id == self.store.id
        # A shared product's variants aren't editable here, but its stock still is —
        # so this stays empty and `_apply_stock` reads the packs off the product.
        variant_stock = []

        if owned:
            # Edit the private product directly.
            changed = []
            for src, attr in [("name", "name"), ("brand", "brand"),
                              ("description", "description"), ("sku", "sku"),
                              ("hsn", "hsn"), ("unit", "unit")]:
                v = field(d, src)
                if v is not None:
                    setattr(product, attr, v)
                    changed.append(attr)
            price = _num(field(d, "price"))
            if price is not None:
                product.price = price
                changed.append("price")
            mrp = _num(field(d, "mrp"))
            if mrp is not None:
                product.mrp = mrp
                changed.append("mrp")
            # A gallery (images[]) takes precedence; else a single imageUrl.
            if "images" in d:
                first = _sync_images(product, field(d, "images"))
                product.image_url = first
                changed.append("image_url")
            else:
                img = field(d, "imageUrl")
                if img is not None:
                    product.image_url = img
                    changed.append("image_url")
            if changed:
                product.save(update_fields=[*changed, "updated_at"])
            # Variant management is allowed only for the store's own product.
            variant_codes, variant_stock = {}, []
            if "variants" in d:
                variant_codes, variant_stock = _sync_variants(product, field(d, "variants"))
            # Keep barcodes in sync (new variants get one; deleted ones cascade away).
            # A re-scanned code replaces the generated one; conflicts are rejected.
            scanned_code = (field(d, "barcode") or "").strip()
            _sync_barcodes(product, product_code=scanned_code,
                           variant_codes=variant_codes)

        # Availability + shared-product overrides live on StoreProduct in both cases.
        sp, _ = StoreProduct.objects.get_or_create(store=self.store, product=product)
        sp_changed = []
        avail = field(d, "isAvailable")
        if avail is not None:
            sp.is_available = bool(avail)
            sp_changed.append("is_available")
        if not owned:
            # Shared product → capture display/price overrides on the store row.
            #
            # PRESENCE semantics, not `is not None`: an override is only written
            # when the client actually SENT the field, and a null/blank CLEARS it
            # (back to following the company product). The old `is not None` test
            # meant any payload that merely echoed the resolved values back — e.g.
            # toggling "Available for sale" — silently pinned a permanent price
            # override, so later company price changes never reached this store.
            for src, attr in [("name", "name"), ("brand", "brand"),
                              ("description", "description"),
                              ("imageUrl", "image_url")]:
                if present(d, src):
                    v = field(d, src)
                    setattr(sp, attr, "" if v in (None, "") else v)
                    sp_changed.append(attr)
            for src, attr in [("price", "selling_price"), ("mrp", "mrp")]:
                if present(d, src):
                    raw = field(d, src)
                    setattr(sp, attr, None if raw in (None, "") else _money(raw, src))
                    sp_changed.append(attr)
        if sp_changed:
            sp.save()

        # Optional per-store reorder level + opening/updated stock — per pack when the
        # product has variants, else on the single product-level row.
        _apply_stock(
            product, self.store.warehouse, d=d, variant_stock=variant_stock,
            by=request.user, reason="Stock set (store product edit)",
        )

        record_audit(request.user, "store_product.override", target=product,
                     after={"owned": owned})
        # Re-fetch so the payload reflects any variant add/remove (the prefetch cache
        # on `product` is stale after _sync_variants).
        return Response(_product_payload(self._product(product_id), self.store))


class StoreBarcodeLookupView(StoreScopedMixin, APIView):
    """GET /store/barcode?code=<scanned> → what (if anything) already owns this code.

    Lets the add-product form resolve a scanned pack BEFORE submitting: if the code
    is already in the catalog the operator gets "this is <product>" instead of
    creating a duplicate. `carried` says whether THIS store already sells it, so the
    UI can offer "edit it" vs "add it to my store".
    """

    store_permissions = {"read": "inventory.view", "write": "inventory.manage"}

    def get(self, request):
        from stores.models import StoreProduct

        code = (request.query_params.get("code") or "").strip()
        if not code:
            return Response({"found": False, "code": ""})
        row = barcode_owner(code)
        if row is None:
            return Response({"found": False, "code": code})
        product = row.product
        return Response({
            "found": True,
            "code": code,
            "productId": str(product.id),
            "productName": product.name,
            "variantLabel": row.variant.label if row.variant_id else None,
            # Is it already on THIS store's shelf, or another store's private item?
            "carried": StoreProduct.objects.filter(
                store=self.store, product=product, is_available=True
            ).exists(),
            "ownedByAnotherStore": bool(
                product.origin_store_id and product.origin_store_id != self.store.id
            ),
        })
