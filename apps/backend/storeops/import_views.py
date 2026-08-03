"""Bulk catalog import for the store panel.

Typing products into a form one at a time is the single biggest cost of getting a
store live. This takes a spreadsheet and turns it into products + opening stock in
one pass.

Two guarantees shape the design:

* **Dry-run first.** The same validation runs with ``commit=false``, returning a
  per-row verdict, so the operator sees exactly what WILL happen (and what's
  wrong) before anything is written. No half-imported catalog to unpick.
* **All-or-nothing commit.** The write is one transaction. A bad row 40 must not
  leave rows 1-39 imported — the store would have no idea which half landed.

Rows are matched on **barcode**, the unique key for a sellable unit: a code that
already exists UPDATES that product, a new one CREATES. That makes re-importing a
corrected sheet safe and idempotent instead of duplicating the catalog.
"""
from django.db import transaction
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit

from .catalog_views import (
    _money,
    _reorder_level,
    _sync_barcodes,
    barcode_owner,
)
from .io_utils import field
from .permissions import StoreScopedMixin

# The importable columns. `name` + `price` are the minimum for a sellable product.
COLUMNS = [
    "name", "barcode", "category", "brand", "unit", "sku", "hsn",
    "price", "mrp", "openingstock", "reorderlevel",
]


def _clean(v):
    return (str(v).strip() if v is not None else "")


class StoreCatalogImportView(StoreScopedMixin, APIView):
    """POST /store/inventory/import — validate (and optionally commit) a sheet.

    Body: ``{"rows": [{name, barcode, category, ...}], "commit": bool}``
    Returns a per-row verdict plus a summary. With ``commit=true`` the import is
    refused outright if ANY row has an error — partial catalogs are worse than no
    catalog.
    """

    store_permissions = {"read": "inventory.view", "write": "inventory.manage"}

    def post(self, request):
        from catalog.models import Category, Product

        rows = field(request.data, "rows") or []
        commit = bool(field(request.data, "commit"))
        if not rows:
            raise ValidationError({"rows": ["Nothing to import."]})
        if len(rows) > 2000:
            raise ValidationError(
                {"rows": ["Import up to 2000 rows at a time — split the file."]})

        # Resolve categories BY NAME: an operator has a spreadsheet, not our ids.
        cats = {c.name.strip().lower(): c for c in Category.objects.all()}

        results = []
        seen_barcodes = {}
        for i, raw in enumerate(rows):
            errors = {}
            name = _clean(field(raw, "name"))
            barcode = _clean(field(raw, "barcode"))
            cat_name = _clean(field(raw, "category"))
            price_raw = _clean(field(raw, "price"))
            mrp_raw = _clean(field(raw, "mrp"))

            if not name:
                errors["name"] = "Required."
            category = cats.get(cat_name.lower()) if cat_name else None
            if not cat_name:
                errors["category"] = "Required."
            elif category is None:
                errors["category"] = f"No category named '{cat_name}'."

            price = mrp = None
            try:
                if not price_raw:
                    errors["price"] = "Required."
                else:
                    price = _money(price_raw, "price", allow_zero=False)
            except ValidationError as e:
                errors["price"] = e.detail["price"][0]
            try:
                if mrp_raw:
                    mrp = _money(mrp_raw, "mrp")
            except ValidationError as e:
                errors["mrp"] = e.detail["mrp"][0]
            if price is not None and mrp is not None and mrp < price:
                errors["mrp"] = "MRP cannot be less than the selling price."

            opening = _clean(field(raw, "openingStock")) or _clean(field(raw, "openingstock"))
            if opening:
                try:
                    if int(opening) < 0:
                        errors["openingStock"] = "Cannot be negative."
                except (TypeError, ValueError):
                    errors["openingStock"] = "Enter a whole number."
            reorder = _clean(field(raw, "reorderLevel")) or _clean(field(raw, "reorderlevel"))
            if reorder:
                try:
                    _reorder_level(reorder)
                except ValidationError as e:
                    errors["reorderLevel"] = e.detail["reorderLevel"][0]

            # Barcode decides create-vs-update, so it's the crux of the preview.
            action, existing = "create", None
            if barcode:
                # A sheet that lists the same code twice would silently collapse
                # into one product — catch it here, not after the write.
                if barcode in seen_barcodes:
                    errors["barcode"] = f"Duplicated in this file (row {seen_barcodes[barcode] + 1})."
                else:
                    seen_barcodes[barcode] = i
                owner = barcode_owner(barcode)
                if owner is not None:
                    p = owner.product
                    if p.origin_store_id and p.origin_store_id != self.store.id:
                        errors["barcode"] = "This barcode belongs to another store's product."
                    elif owner.variant_id:
                        errors["barcode"] = f"This code is a variant of '{p.name}'."
                    else:
                        action, existing = "update", p

            results.append({
                "index": i,
                "name": name,
                "barcode": barcode,
                "action": "error" if errors else action,
                "errors": errors,
                "existingId": str(existing.id) if existing else None,
            })

        summary = {
            "total": len(results),
            "create": sum(1 for r in results if r["action"] == "create"),
            "update": sum(1 for r in results if r["action"] == "update"),
            "errors": sum(1 for r in results if r["action"] == "error"),
        }
        if not commit or summary["errors"]:
            # Dry run, or a commit blocked by errors — nothing written either way.
            return Response({"committed": False, "summary": summary, "rows": results})

        self._commit(rows, results, cats)
        record_audit(request.user, "store_catalog.import", target=self.store,
                     after={"created": summary["create"], "updated": summary["update"]})
        return Response({"committed": True, "summary": summary, "rows": results})

    # ATOMIC: a sheet imports completely or not at all.
    @transaction.atomic
    def _commit(self, rows, results, cats):
        from catalog.models import Product
        from inventory.models import StockItem
        from inventory.services import InventoryError, InventoryService

        from stores.models import StoreProduct

        wh = self.store.warehouse
        for raw, verdict in zip(rows, results):
            name = _clean(field(raw, "name"))
            barcode = _clean(field(raw, "barcode"))
            category = cats.get(_clean(field(raw, "category")).lower())
            price = _money(_clean(field(raw, "price")), "price", allow_zero=False)
            mrp_raw = _clean(field(raw, "mrp"))
            mrp = _money(mrp_raw, "mrp") if mrp_raw else price

            if verdict["action"] == "update":
                product = Product.objects.get(pk=verdict["existingId"])
                product.name, product.price, product.mrp = name, price, mrp
                product.category = category
                for src, attr in [("brand", "brand"), ("unit", "unit"),
                                  ("sku", "sku"), ("hsn", "hsn")]:
                    v = _clean(field(raw, src))
                    if v:
                        setattr(product, attr, v)
                product.save()
            else:
                product = Product.objects.create(
                    name=name, price=price, mrp=mrp, category=category,
                    brand=_clean(field(raw, "brand")),
                    unit=_clean(field(raw, "unit")) or "Each",
                    sku=_clean(field(raw, "sku")), hsn=_clean(field(raw, "hsn")),
                    origin_store=self.store,
                )
            StoreProduct.objects.get_or_create(
                store=self.store, product=product, defaults={"is_available": True})
            # Scanned code wins; otherwise a scannable in-store code is generated.
            _sync_barcodes(product, product_code=barcode)

            if wh is None:
                continue
            si, _ = StockItem.objects.get_or_create(product=product, warehouse=wh)
            reorder = _clean(field(raw, "reorderLevel")) or _clean(field(raw, "reorderlevel"))
            if reorder:
                si.low_stock_threshold = _reorder_level(reorder)
                si.save(update_fields=["low_stock_threshold"])
            opening = _clean(field(raw, "openingStock")) or _clean(field(raw, "openingstock"))
            if opening:
                try:
                    InventoryService.adjust(
                        product, set=int(opening), warehouse=wh,
                        reason="Bulk import", created_by=self.request.user,
                    )
                except InventoryError as e:
                    # Inside the atomic block: surfacing this rolls the whole sheet
                    # back, which is the intended contract.
                    raise ValidationError({"openingStock": [f"{name}: {e}"]})
