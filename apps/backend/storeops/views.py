"""Store-Admin panel API — every endpoint is scoped to the caller's store via the
membership resolved in :class:`IsStoreStaff`. Most read/action endpoints reuse the
already-built admin services (orders, inventory, delivery, CRM) with the store
forced from membership, so behaviour matches the super-admin console exactly —
just narrowed to one store.
"""
from django.db import transaction
from django.db.models import Q
from rest_framework import status as http
from rest_framework.exceptions import ValidationError
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.app_errors import AppError

from .permissions import StoreScopedMixin
from .services import membership_payload, staff_activity, store_dashboard


def scoped_product(store, product_id):
    """A product THIS store may write to: a company-wide product, or its own
    private one — never another store's private product.

    Mirrors the read path in ``catalog_views.StoreProductOverrideView._product``.
    Write endpoints used to resolve products with a bare ``get_object_or_404``,
    which let one store post stock movements against another store's private item.
    """
    from catalog.models import Product

    return get_object_or_404(
        Product.objects.filter(Q(origin_store__isnull=True) | Q(origin_store=store)),
        pk=product_id,
    )


def resolve_variant(product, variant_id, *, key="variantId"):
    """The ProductVariant for this product, or None. Rejects a foreign id rather
    than silently touching the wrong (or product-level) bucket.

    Shared by every store write path that moves stock for a specific pack
    (inventory adjust/allocate and purchase receiving) — a variant is its own SKU,
    so resolving one loosely is how units end up in an unsellable bucket.
    """
    if not variant_id:
        return None
    from catalog.models import ProductVariant

    v = ProductVariant.objects.filter(pk=variant_id, product=product).first()
    if v is None:
        raise ValidationError({key: ["Not a variant of this product."]})
    return v


def _positive_int(value, key):
    """A whole number > 0, or a 400 naming the field. Free-text numeric input must
    never reach the DB via a silent ``int(x or 0)``."""
    try:
        n = int(value)
    except (TypeError, ValueError):
        raise ValidationError({key: ["Enter a whole number."]})
    if n <= 0:
        raise ValidationError({key: ["Must be greater than zero."]})
    return n


def _money(value, key, *, allow_zero=True):
    """A non-negative money amount, or a 400 naming the field."""
    from decimal import Decimal, InvalidOperation

    if value in (None, ""):
        raise ValidationError({key: ["This is required."]})
    try:
        amount = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        raise ValidationError({key: ["Enter a valid amount."]})
    if amount < 0 or (not allow_zero and amount == 0):
        raise ValidationError({key: ["Must be a positive amount."]})
    return amount


def scoped_supplier(store, supplier_id):
    """A supplier this store may use: its own, or a legacy/global one (store NULL).
    Matches the scoping the supplier LIST endpoint already applies."""
    from inventory.models import Supplier

    return Supplier.objects.filter(
        Q(store=store) | Q(store__isnull=True)
    ).filter(pk=supplier_id).first()


# ── Identity / dashboard ─────────────────────────────────
class StoreMeView(StoreScopedMixin, APIView):
    """Who am I + which store + what may I do (drives the panel's nav/gating)."""

    def get(self, request):
        return Response(membership_payload(self.membership))


class StoreDashboardView(StoreScopedMixin, APIView):
    store_permission = "dashboard.view"

    def get(self, request):
        return Response(store_dashboard(self.store))


# ── Staff / permissions (People) ─────────────────────────
class StorePermissionCatalogView(StoreScopedMixin, APIView):
    store_permission = "employees.view"

    def get(self, request):
        from .staff_service import permission_catalog

        return Response(permission_catalog())


class StoreStaffListView(StoreScopedMixin, APIView):
    store_permissions = {"read": "employees.view", "write": "employees.manage"}

    def get(self, request):
        from .staff_service import list_staff

        return Response(list_staff(self.store))

    def post(self, request):
        from .io_utils import field
        from .staff_service import create_staff, staff_row

        d = request.data
        staff = create_staff(
            self.store, actor=request.user,
            phone=field(d, "phone"), name=field(d, "name", "") or "",
            staff_role=field(d, "staffRole") or "cashier",
            permissions=d.get("permissions"),
            title=field(d, "title", "") or "",
            employee_code=field(d, "employeeCode", "") or "",
            # Sign-in credentials. The panel is an email+password login, so
            # without these the staff row exists but the person can never get in.
            email=field(d, "email", "") or "",
            password=field(d, "password", "") or "",
        )
        return Response(staff_row(staff), status=http.HTTP_201_CREATED)


class StoreStaffDetailView(StoreScopedMixin, APIView):
    store_permissions = {"read": "employees.view", "write": "employees.manage"}

    def _get(self, request, staff_id):
        from .models import StoreStaff

        return get_object_or_404(StoreStaff, pk=staff_id, store=self.store)

    def get(self, request, staff_id):
        from .staff_service import staff_row

        return Response(staff_row(self._get(request, staff_id)))

    def patch(self, request, staff_id):
        from .io_utils import field
        from .staff_service import staff_row, update_staff

        staff = self._get(request, staff_id)
        # Read via io_utils.field — the camelCase parser snake-cases the body, so a
        # direct request.data.get("isActive") would always be None (guard/update dead).
        is_active = field(request.data, "isActive")
        if staff.is_manager and staff.user_id == request.user.id and is_active is False:
            raise ValidationError({"isActive": ["You can't deactivate your own manager account."]})
        d = request.data
        update_staff(
            staff, actor=request.user,
            staff_role=field(d, "staffRole"),
            permissions=d.get("permissions") if "permissions" in d else None,
            title=field(d, "title"),
            employee_code=field(d, "employeeCode"),
            is_active=is_active,
            name=field(d, "name"),
        )
        return Response(staff_row(staff))


class StoreAttendanceView(StoreScopedMixin, APIView):
    store_permission = "employees.view"

    def get(self, request):
        from .staff_service import attendance_roster

        return Response(attendance_roster(self.store))


class StoreAttendanceActionView(StoreScopedMixin, APIView):
    """A staff member clocks themselves in/out (their own membership)."""

    def post(self, request, action):
        from .staff_service import check_in, check_out

        if action == "check-in":
            att = check_in(self.membership)
        elif action == "check-out":
            att = check_out(self.membership)
        else:
            raise ValidationError({"action": ["Unknown action."]})
        return Response({
            "date": att.date, "checkInAt": att.check_in_at, "checkOutAt": att.check_out_at,
        })


# ── Orders ───────────────────────────────────────────────
class StoreOrderListView(StoreScopedMixin, APIView):
    store_permission = "orders.view"

    def get(self, request):
        from orders.admin_service import search_orders

        params = {k: v for k, v in request.query_params.items()}
        params["store"] = str(self.store.id)  # force store scope
        return Response(search_orders(params))


class StoreOrderQueuesView(StoreScopedMixin, APIView):
    store_permission = "orders.view"

    def get(self, request):
        from orders.admin_service import order_queues

        # The store board is what a packer works from, so it carries the lines.
        return Response(order_queues(store_id=self.store.id, with_items=True))


class StoreOrderDetailView(StoreScopedMixin, APIView):
    store_permission = "orders.view"

    def _order(self, code):
        from orders.models import Order

        return get_object_or_404(
            Order.objects.select_related("user", "store", "zone", "delivery", "delivery__agent")
            .prefetch_related("items", "timeline"),
            code=code, store=self.store,
        )

    def get(self, request, code):
        from orders.admin_service import order_detail

        return Response(order_detail(self._order(code)))


class StoreOrderInvoiceView(StoreScopedMixin, APIView):
    """The branded PDF invoice for one of THIS store's online orders.

    Store staff previously had no way to pull an online order's invoice — only the
    customer and a super-admin could. The order is looked up with ``store=self.store``
    so one store can never fetch another's invoice by guessing an order code.

    Defaults to ``attachment`` (staff are printing/filing it); ``?inline=1`` renders
    it in the browser, matching the admin console's endpoint.
    """

    store_permission = "orders.view"

    def get(self, request, code):
        from django.http import HttpResponse

        from orders.invoice import build_invoice_pdf
        from orders.models import Order

        order = get_object_or_404(
            Order.objects.select_related("store", "user", "zone").prefetch_related(
                "items__product"
            ),
            code=code,
            store=self.store,
        )
        pdf = build_invoice_pdf(order)
        disposition = "inline" if request.query_params.get("inline") else "attachment"
        resp = HttpResponse(pdf, content_type="application/pdf")
        resp["Content-Disposition"] = (
            f'{disposition}; filename="invoice-{order.code}.pdf"'
        )
        return resp


class StoreOrderStatusView(StoreScopedMixin, APIView):
    """A store can only prepare an order — from confirmation through to it
    being staged for pickup. Everything from there on (out for delivery,
    reached, delivered) is the assigned agent's own state machine, gated
    behind the delivery-OTP + mandatory-photo completion guard — a store
    can't shortcut that by posting a status here."""

    store_permission = "orders.manage"

    ALLOWED_STATUSES = {"confirmed", "packed", "ready_for_dispatch", "cancelled"}

    def post(self, request, code):
        from orders.admin_service import order_detail, set_order_status
        from orders.models import Order

        order = get_object_or_404(Order, code=code, store=self.store)
        new_status = request.data.get("status")
        if not new_status:
            raise ValidationError({"status": ["status is required."]})
        if new_status not in self.ALLOWED_STATUSES:
            raise ValidationError({"status": [
                "Once an order is ready for dispatch, only the assigned "
                "delivery agent can advance it further."
            ]})
        set_order_status(order, new_status, by=request.user, note=request.data.get("note", ""))
        record_audit(request.user, "store_order.status", target=order, after={"status": new_status})
        order.refresh_from_db()
        return Response(order_detail(order))


class StoreOrderBulkStatusView(StoreScopedMixin, APIView):
    """Advance many orders at once — the morning confirm/pack sweep.

    Each order is committed on its own: a store confirming 30 orders must not
    lose the other 29 because one was already dispatched. The response reports
    per-order outcomes so the UI can say "27 confirmed, 3 skipped" instead of a
    single opaque success or failure.
    """

    store_permission = "orders.manage"

    def post(self, request):
        from django.db import transaction

        from orders.admin_service import set_order_status
        from orders.models import Order

        from .io_utils import field

        new_status = field(request.data, "status")
        codes = field(request.data, "codes") or []
        if not new_status:
            raise ValidationError({"status": ["status is required."]})
        if new_status not in StoreOrderStatusView.ALLOWED_STATUSES:
            raise ValidationError({"status": [
                "Once an order is ready for dispatch, only the assigned "
                "delivery agent can advance it further."
            ]})
        if not isinstance(codes, list) or not codes:
            raise ValidationError({"codes": ["Select at least one order."]})
        # Guard against a runaway select-all on a huge queue.
        if len(codes) > 200:
            raise ValidationError({"codes": ["Too many orders — select 200 or fewer."]})

        note = field(request.data, "note", "") or ""
        updated, failed = [], []
        orders = {
            o.code: o for o in Order.objects.filter(code__in=codes, store=self.store)
        }
        for code in codes:
            order = orders.get(code)
            if order is None:
                failed.append({"code": code, "error": "Not found at this store."})
                continue
            try:
                with transaction.atomic():
                    set_order_status(order, new_status, by=request.user, note=note)
            except Exception as exc:  # noqa: BLE001 — one bad order must not stop the sweep
                failed.append({"code": code, "error": str(exc)})
                continue
            updated.append(code)

        if updated:
            record_audit(request.user, "store_order.bulk_status", target=self.store,
                         after={"status": new_status, "count": len(updated),
                                "codes": updated[:50]})
        return Response({
            "status": new_status,
            "updated": updated,
            "failed": failed,
            "updatedCount": len(updated),
            "failedCount": len(failed),
        })


### StoreOrderAssignAgentView removed: it had no caller anywhere in the
# store-admin frontend, and it was a landmine — orders.admin_service.
# assign_agent() writes to the legacy DeliveryAssignment relation (not the
# real DeliveryTask the agent app reads), and get_or_create() silently
# no-ops if a task already exists in ANY status while still reporting
# success. Real store dispatch happens through storeops/dispatch_views.py's
# assignment engine (auto-assign) and manual-assign endpoints instead.


# ── Inventory ────────────────────────────────────────────
class StoreInventoryView(StoreScopedMixin, APIView):
    store_permission = "inventory.view"

    def get(self, request):
        from inventory.models import StockBatch, StockItem

        wh = self.warehouse_id
        if not wh:
            return Response([])
        low_only = request.query_params.get("low") in ("1", "true", "True")
        q = (request.query_params.get("q") or "").strip().lower()
        # Per-store display/price overrides (one query, no N+1).
        from stores.models import StoreProduct
        from stores.services import store_view

        overrides = {sp.product_id: sp for sp in StoreProduct.objects.filter(store=self.store)}
        # Earliest expiry per product (for the inventory table's Expiry column).
        exp = {}
        for b in StockBatch.objects.filter(warehouse_id=wh, quantity__gt=0,
                                           expiry_date__isnull=False).order_by("expiry_date"):
            exp.setdefault(b.product_id, b.expiry_date)
        rows = []
        # One row per STOCK BUCKET (product×variant). A variant product yields a row
        # per pack, each labelled and separately adjustable; the `variant=NULL` row of
        # a variant product is the unallocated pool, flagged so it reads as "assign me"
        # rather than as sellable stock.
        for it in (
            StockItem.objects.filter(warehouse_id=wh)
            .select_related("product", "variant")
        ):
            p = it.product
            view = store_view(p, self.store, sp=overrides.get(p.id))
            base = view["name"]
            is_pool = it.variant_id is None and p.variants.exists()
            if it.variant_id:
                name = f"{base} · {it.variant.label}"
            elif is_pool:
                name = f"{base} · Unallocated"
            else:
                name = base
            if q and q not in (name or "").lower() and q not in (p.sku or "").lower():
                continue
            available = it.quantity - it.reserved
            # The pool is never "low" — it isn't sellable, so a low badge would be noise.
            is_low = (not is_pool) and available <= it.low_stock_threshold
            if low_only and not is_low:
                continue
            unit_price = float(view["price"] or 0)
            if it.variant_id and it.variant.price_delta:
                unit_price += float(it.variant.price_delta)
            rows.append({
                "productId": str(p.id),
                "variantId": str(it.variant_id) if it.variant_id else None,
                "variantLabel": it.variant.label if it.variant_id else None,
                "unallocated": is_pool,
                "name": name,
                "sku": getattr(p, "sku", "") or "",
                "brand": view["brand"],
                "private": p.origin_store_id == self.store.id,
                "current": it.quantity,
                "reserved": it.reserved,
                "available": available,
                "damaged": it.damaged,
                "reorderLevel": it.low_stock_threshold,
                "sellingPrice": unit_price,
                "expiryDate": exp.get(p.id),
                "lowStock": is_low,
            })
        rows.sort(key=lambda r: r["available"])
        return Response(rows)


class StoreExpiryView(StoreScopedMixin, APIView):
    store_permission = "inventory.view"

    def get(self, request):
        from .services import _expiry_rows

        wh = self.warehouse_id
        if not wh:
            return Response([])
        within = int(request.query_params.get("days") or 30)
        return Response(_expiry_rows(wh, within_days=within))


class StoreInventoryAdjustView(StoreScopedMixin, APIView):
    store_permission = "inventory.manage"

    def post(self, request, product_id):
        from inventory.models import InventoryLedger
        from inventory.services import (
            ANY_VARIANT, InventoryService, StockCalculationService, write_off,
        )

        # Scoped: a bare pk lookup let this store post movements against another
        # store's private product.
        product = scoped_product(self.store, product_id)
        wh = self.store.warehouse
        if wh is None:
            raise ValidationError({"warehouse": ["This store has no warehouse."]})
        # Which pack this adjustment/write-off/allocation targets. A variant product
        # is counted per pack, so the caller must say which one (the inventory table
        # sends the row's variantId); a plain product sends none.
        variant = resolve_variant(product, request.data.get("variantId"))
        mode = request.data.get("mode") or "adjust"  # adjust | waste | expiry | allocate
        reason = request.data.get("reason", "")
        try:
            if mode == "adjust":
                set_to = request.data.get("set")
                delta = request.data.get("delta")
                if set_to is None and delta is None:
                    raise ValidationError({"set": ["Provide `set` or `delta`."]})
                InventoryService.adjust(
                    product, variant=variant, set=set_to, delta=delta, warehouse=wh,
                    reason=reason or "Store adjustment", created_by=request.user,
                )
            elif mode == "allocate":
                # Move units out of the unallocated pool into a real pack.
                if variant is None:
                    raise ValidationError({"variantId": ["Choose a pack to allocate to."]})
                qty = int(request.data.get("quantity") or 0)
                if qty <= 0:
                    raise ValidationError({"quantity": ["A positive quantity is required."]})
                InventoryService.allocate(
                    product, variant=variant, quantity=qty, warehouse=wh,
                    created_by=request.user,
                )
            elif mode in ("waste", "expiry"):
                qty = int(request.data.get("quantity") or 0)
                if qty <= 0:
                    raise ValidationError({"quantity": ["A positive quantity is required."]})
                write_off(
                    product, variant=variant,
                    type=(InventoryLedger.Type.EXPIRY if mode == "expiry"
                          else InventoryLedger.Type.DAMAGE),
                    quantity=qty, warehouse=wh, reason=reason or f"Marked {mode}",
                    created_by=request.user,
                )
            else:
                raise ValidationError({"mode": ["Unknown mode."]})
            # Report the affected bucket's on-hand (product total when no pack given).
            new_qty = StockCalculationService.on_hand(
                product, wh, variant if variant is not None else ANY_VARIANT
            )
        except ValidationError:
            raise
        except Exception as e:  # surface inventory domain errors as 400
            raise ValidationError({"detail": [str(e)]})
        record_audit(request.user, f"store_inventory.{mode}", target=product,
                     after={"reason": reason, "variant": getattr(variant, "id", None)})
        return Response({
            "productId": str(product.id),
            "variantId": str(variant.id) if variant else None,
            "onHand": new_qty,
        })


# ── Procurement ──────────────────────────────────────────
class StoreSupplierListView(StoreScopedMixin, APIView):
    store_permissions = {"read": "procurement.view", "write": "procurement.manage"}

    def get(self, request):
        from django.db.models import Q

        from inventory.models import Supplier

        # The store's own suppliers + legacy/global (null store) ones.
        qs = Supplier.objects.filter(Q(store=self.store) | Q(store__isnull=True))
        return Response([
            {
                "id": str(s.id), "name": s.name, "gstin": s.gstin, "phone": s.phone,
                "email": s.email, "address": s.address, "isActive": s.is_active,
                "shared": s.store_id is None,
            }
            for s in qs
        ])

    def post(self, request):
        from inventory.models import Supplier

        d = request.data
        name = (d.get("name") or "").strip()
        if not name:
            raise ValidationError({"name": ["Supplier name is required."]})
        s = Supplier.objects.create(
            store=self.store, name=name, gstin=d.get("gstin", ""),
            phone=d.get("phone", ""), email=d.get("email", ""), address=d.get("address", ""),
        )
        record_audit(request.user, "store_supplier.create", target=s, after={"name": name})
        return Response({"id": str(s.id), "name": s.name}, status=http.HTTP_201_CREATED)


class StorePurchaseListView(StoreScopedMixin, APIView):
    store_permissions = {"read": "procurement.view", "write": "procurement.manage"}

    def get(self, request):
        from inventory.models import GRN

        wh = self.warehouse_id
        if not wh:
            return Response([])
        qs = GRN.objects.filter(warehouse_id=wh).select_related("supplier").order_by("-created_at")[:200]
        return Response([
            {
                "id": str(g.id),
                "reference": g.reference,
                "supplier": g.supplier.name if g.supplier else None,
                "status": g.status,
                "totalCost": float(g.total_cost or 0),
                "postedAt": g.posted_at,
                "createdAt": g.created_at,
                "lines": g.items.count(),
            }
            for g in qs
        ])

    # ATOMIC: the GRN, its lines and the stock posting are one unit of work.
    # Without this a bad line (blank qty on line 3) still COMMITTED the GRN + the
    # earlier lines — leaving an un-postable, un-deletable ₹0 "draft" phantom in
    # the purchases list forever.
    @transaction.atomic
    def post(self, request):
        """Record a supplier purchase invoice → a posted GRN that increases stock.
        This is the store's primary inventory-intake path (spec §PROCUREMENT)."""
        from inventory.models import GRN, GRNItem
        from inventory.services import InventoryError, post_grn

        from .io_utils import field

        wh = self.store.warehouse
        if wh is None:
            raise ValidationError({"warehouse": ["This store has no warehouse."]})
        items = field(request.data, "items") or []
        if not items:
            raise ValidationError({"items": ["Add at least one product line."]})
        supplier = None
        supplier_id = field(request.data, "supplierId")
        if supplier_id:
            supplier = scoped_supplier(self.store, supplier_id)
            if supplier is None:
                raise ValidationError({"supplierId": ["Unknown supplier."]})
        grn = GRN.objects.create(
            warehouse=wh, supplier=supplier, reference=field(request.data, "invoiceNumber", "") or "",
            created_by=request.user,
        )
        for idx, it in enumerate(items):
            product = scoped_product(self.store, field(it, "productId"))
            qty = _positive_int(field(it, "quantity"), "quantity")
            # Cost drives COGS, weighted-average cost and the valuation report, and
            # the ledger is append-only — a silent 0 from `unitCost or 0` (which is
            # what a NaN/None arrives as) permanently poisons those numbers.
            unit_cost = _money(field(it, "unitCost"), "unitCost")
            # Which pack these units are. A variant is its OWN stock-keeping unit,
            # so receiving without one dumps them into the variant=NULL unallocated
            # pool — where POS can't sell them and every pack still reads zero.
            # Receiving is the only place that stock enters, so getting this wrong
            # is silent and permanent (the ledger is append-only); refuse the
            # ambiguity the way the inventory-allocate path already does.
            variant = resolve_variant(product, field(it, "variantId"))
            if variant is None and product.variants.exists():
                raise ValidationError({"items": [
                    f"Line {idx + 1} ({product.name}): choose a pack to receive into."
                ]})
            GRNItem.objects.create(
                grn=grn, product=product, variant=variant, quantity=qty,
                unit_cost=unit_cost, batch_no=field(it, "batchNo", "") or "",
                expiry_date=field(it, "expiryDate") or None,
            )
        try:
            post_grn(grn, by=request.user)
        except InventoryError as e:
            raise ValidationError({"detail": [str(e)]})
        record_audit(request.user, "store_purchase.create", target=grn,
                     after={"reference": grn.reference, "lines": len(items)})
        return Response({
            "id": str(grn.id), "reference": grn.reference,
            "totalCost": float(grn.total_cost or 0), "status": grn.status,
        }, status=http.HTTP_201_CREATED)


def _purchase_variant_rows(product, warehouse=None):
    """Every pack of a product (``[]`` when it has none), with its own on-hand.

    Mirrors ``pos_views._variant_rows`` but carries the goods-inward fields (sku /
    scannable barcode) instead of the till's pricing ones."""
    from inventory.services import StockCalculationService

    variants = list(product.variants.all())
    if not variants:
        return []
    buckets = (
        StockCalculationService.by_variant(product, warehouse) if warehouse else {}
    )
    rows = []
    for v in variants:
        codes = [b.code for b in v.barcodes.all()]  # primary first (Barcode.Meta)
        rows.append({
            "id": str(v.id),
            "label": v.label,
            "sku": v.sku or "",
            "barcode": codes[0] if codes else "",
            "onHand": (buckets.get(v.id) or {}).get("available", 0),
        })
    return rows


class StoreProductSearchView(StoreScopedMixin, APIView):
    """Catalog search for purchase-entry / lookups — any active product, with this
    store's on-hand shown. Used when recording a supplier invoice."""

    store_permission = "procurement.view"

    def get(self, request):
        from django.db.models import Q

        from catalog.models import Product
        from inventory.services import StockCalculationService

        from stores.services import store_catalog_queryset, store_view

        q = (request.query_params.get("q") or "").strip()
        # Company products + this store's own private ones; never another store's.
        products = store_catalog_queryset(
            Product.objects.filter(is_active=True), self.store
        ).prefetch_related("variants__barcodes", "barcodes")
        if q:
            # Barcode too: goods-inward is a scanning desk, and matching only
            # name/sku meant a scanned code found nothing. Matches a product's own
            # barcode or any of its variants' — same product↔code table POS scan
            # resolves against (inventory.Barcode).
            products = products.filter(
                Q(name__icontains=q)
                | Q(sku__icontains=q)
                | Q(barcodes__code__icontains=q)
                | Q(variants__sku__icontains=q)
            ).distinct()
        wh = self.store.warehouse
        rows = []
        for p in products[:30]:
            view = store_view(p, self.store)
            rows.append({
                "productId": str(p.id), "name": view["name"], "sku": getattr(p, "sku", "") or "",
                "brand": view["brand"], "price": float(view["price"] or 0),
                "onHand": StockCalculationService.available(p, wh) if wh else 0,
                # Packs are separately-stocked SKUs, so the clerk must say WHICH one
                # a line receives into. Without this the panel had no variant ids to
                # send and every receipt landed in the unallocated pool.
                "variants": _purchase_variant_rows(p, wh),
            })
        return Response(rows)


# ── Customers ────────────────────────────────────────────
def _store_customer_ids(store):
    """Customer ids this store may act on: anyone who ORDERED here plus anyone who
    RESIDES in the store's zone. The zone residents were missing, so a store couldn't
    see (or review the KYC / collections of) an area customer until their first order.
    Used both for the customer directory and as an authorization gate."""
    from orders.models import Order

    from crm.services import zone_resident_customer_ids

    ordered = set(
        Order.objects.filter(store=store).values_list("user_id", flat=True).distinct()
    )
    return list(ordered | zone_resident_customer_ids(store_id=store.id))


class StoreCustomerListView(StoreScopedMixin, APIView):
    store_permission = "customers.view"

    def get(self, request):
        from crm.services import search_customers

        rows = search_customers(
            request.query_params.get("q", ""),
            store=str(self.store.id),
            kyc=request.query_params.get("kyc"),
            credit=request.query_params.get("credit"),
            status=request.query_params.get("status"),
            risk=request.query_params.get("risk"),
            sort=request.query_params.get("sort", "newest"),
        )
        return Response(rows)


class StoreCustomerDetailView(StoreScopedMixin, APIView):
    store_permission = "customers.view"

    def get(self, request, customer_id):
        from accounts.models import User
        from crm.services import customer_360

        user = get_object_or_404(User, pk=customer_id)
        if user.id not in _store_customer_ids(self.store):
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        return Response(customer_360(user))


# ── Credit ───────────────────────────────────────────────
class StoreCreditListView(StoreScopedMixin, APIView):
    store_permission = "credit.view"

    def get(self, request):
        from credit.models import CreditAccount

        ids = _store_customer_ids(self.store)
        qs = CreditAccount.objects.filter(user_id__in=ids).select_related("user")
        status_f = request.query_params.get("status")
        if status_f:
            qs = qs.filter(status=status_f)
        rows = [
            {
                "customerId": str(a.user_id),
                "name": a.user.name or a.user.phone,
                "phone": a.user.phone,
                "creditLimit": float(a.credit_limit),
                "outstanding": float(a.outstanding),
                "available": float(a.available),
                "vsScore": a.vs_score,
                "status": a.status,
            }
            for a in qs
        ]
        rows.sort(key=lambda r: r["outstanding"], reverse=True)
        return Response(rows)


class StoreCreditActionView(StoreScopedMixin, APIView):
    store_permission = "credit.manage"

    def post(self, request, customer_id):
        from credit.models import CreditAccount

        if int(customer_id) not in _store_customer_ids(self.store):
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        acc = get_object_or_404(CreditAccount, user_id=customer_id)
        before = {"creditLimit": float(acc.credit_limit), "status": acc.status}
        fields = []
        if "creditLimit" in request.data or "credit_limit" in request.data:
            acc.credit_limit = request.data.get("creditLimit", request.data.get("credit_limit"))
            fields.append("credit_limit")
        if "status" in request.data:
            new = request.data["status"]
            if new not in {c.value for c in CreditAccount.Status}:
                raise ValidationError({"status": ["Invalid credit status."]})
            acc.status = new
            fields.append("status")
        if not fields:
            raise ValidationError({"detail": ["Nothing to update."]})
        acc.save(update_fields=fields)
        record_audit(request.user, "store_credit.update", target=acc, before=before,
                     after={"creditLimit": float(acc.credit_limit), "status": acc.status})
        return Response({
            "customerId": str(acc.user_id), "creditLimit": float(acc.credit_limit),
            "outstanding": float(acc.outstanding), "available": float(acc.available),
            "status": acc.status,
        })


def _bureau_camel(report):
    """Serialize a CreditBureauReport for the store panel (camelCase), or None."""
    if report is None:
        return None
    return {
        "id": str(report.id),
        "status": report.status,
        "score": report.score,
        "band": report.band,
        "nameOnBureau": report.name_on_bureau,
        "pan": report.pan,
        "mobile": report.mobile,
        "provider": report.provider,
        "source": report.source,
        "checkedAt": report.created_at,
    }


class StoreCibilView(StoreScopedMixin, APIView):
    """Store panel: view a customer's stored CIBIL score, and refresh (re-pull).

    Refresh reuses the mobile + consent from the customer's own last check —
    staff cannot originate a bureau pull without prior customer consent."""

    store_permission = "credit.view"

    def _guard(self, customer_id):
        from accounts.models import User

        if int(customer_id) not in _store_customer_ids(self.store):
            return None
        return get_object_or_404(User, pk=customer_id)

    def get(self, request, customer_id):
        from credit.services import latest_bureau_report

        customer = self._guard(customer_id)
        if customer is None:
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        return Response({"report": _bureau_camel(latest_bureau_report(customer))})

    def post(self, request, customer_id):
        from core.app_errors import AppError
        from credit.models import CreditBureauReport
        from credit.services import fetch_bureau_score, latest_bureau_report

        customer = self._guard(customer_id)
        if customer is None:
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        prior = latest_bureau_report(customer)
        if prior is None or not prior.consent:
            raise AppError(
                "CIBIL_CONSENT_REQUIRED",
                message="This customer hasn't consented to a credit-score check yet. "
                        "They must run it once from the app before it can be refreshed.",
            )
        report = fetch_bureau_score(
            customer, mobile=prior.mobile or getattr(customer, "phone", ""),
            consent=True, source=CreditBureauReport.Source.STORE,
            requested_by=request.user, force=True,
        )
        return Response({"report": _bureau_camel(report)})


# ── Verification (KYC queue — read; decision wired next) ─
class StoreVerificationQueueView(StoreScopedMixin, APIView):
    store_permission = "verification.view"

    def get(self, request):
        from kyc.models import KycApplication

        ids = _store_customer_ids(self.store)
        status_f = request.query_params.get("status") or "pending"
        qs = KycApplication.objects.filter(user_id__in=ids).select_related("user")
        if status_f != "all":
            qs = qs.filter(status=status_f)
        return Response([
            {
                "id": str(a.id),
                "customerId": str(a.user_id),
                "name": a.user.name or a.user.phone,
                "phone": a.user.phone,
                "status": a.status,
                "submittedAt": a.created_at,
            }
            for a in qs.order_by("-created_at")[:200]
        ])


# ── Delivery (Operations) ────────────────────────────────
class StoreDeliveryListView(StoreScopedMixin, APIView):
    store_permission = "delivery.view"

    def get(self, request):
        from delivery.admin_service import delivery_list

        params = {k: v for k, v in request.query_params.items()}
        params["store"] = str(self.store.id)
        return Response(delivery_list(params))


class StoreDeliveryAgentsView(StoreScopedMixin, APIView):
    store_permission = "delivery.view"

    def get(self, request):
        from delivery.admin_service import agent_load

        # Store-scoped: this list populates the delivery AND collections
        # reassign pickers, so an unscoped pool let a store hand work to another
        # store's agent.
        return Response(agent_load(store=self.store))


class StoreDeliveryStatusView(StoreScopedMixin, APIView):
    """A delivery's status, from out-for-delivery onward, is the assigned
    agent's own state machine — gated behind the OTP + mandatory-photo
    completion guard in ``delivery.services``. This endpoint used to let a
    store push a task straight to "delivered" via ``delivery.admin_service.
    set_status``, which wrote ``order.status`` directly and skipped that
    guard entirely (no OTP, no proof photo needed). It no longer accepts
    writes; a store can still see status (GET /store/delivery) and reassign
    the agent, but can't move the status itself."""

    store_permission = "delivery.manage"

    def post(self, request, task_id):
        raise AppError(
            "VALIDATION_ERROR",
            message="Delivery status is set by the assigned agent, not the store.",
        )


class StoreDeliveryReassignView(StoreScopedMixin, APIView):
    """Was calling `delivery.admin_service.reassign()` — a bare `task.agent =
    agent` write that never notified the new agent, never recorded a
    DeliveryAssignmentHistory row (silently corrupting `agent_performance()`'s
    acceptance-rate scoring), and force-jumped a rejected/failed task straight
    to "accepted" — skipping the Accept/Reject prompt the new agent should
    see. `delivery.services.reassign()` is the real one: it closes the
    current task out properly and opens a fresh one for the new agent,
    exactly like the reattempt/reassign flow already uses."""

    store_permission = "delivery.manage"

    def post(self, request, task_id):
        from accounts.models import User
        from delivery.models import DeliveryTask
        from delivery.services import manual_assign

        from agents.candidates import eligible_for_store

        task = get_object_or_404(
            DeliveryTask.objects.select_related("order"), pk=task_id, order__store=self.store
        )
        agent = get_object_or_404(User, pk=request.data.get("agentId") or request.data.get("agent_id"),
                                  role="agent", is_active=True)
        # The picker is store-scoped, but the endpoint is the actual control:
        # handing this task to another store's agent would drop it off this
        # store's board and onto a rider who can't physically do it.
        if not eligible_for_store(agent, self.store):
            raise AppError(
                "VALIDATION_ERROR",
                message="That agent belongs to another store.",
                fields={"agentId": ["Pick one of your store's agents."]},
            )
        # `manual_assign`, not `reassign`: reassign refuses a TERMINAL task, and
        # `rejected` is terminal. An agent turning a job down auto-reassigns it,
        # but when nobody else is eligible the order sits with a rejected task
        # and no live one — nobody is delivering it, and the store had no way to
        # act. manual_assign hands over the live task when there is one and
        # otherwise opens the next attempt for the order.
        new_task = manual_assign(task.order, agent, by=request.user,
                                 reason=request.data.get("reason", "Reassigned by store"))
        record_audit(request.user, "store_delivery.reassign", target=task,
                     after={"agentId": str(agent.id)})
        return Response({"id": new_task.id, "agent": agent.name or agent.phone})


# ── Audit log ────────────────────────────────────────────
class StoreAuditView(StoreScopedMixin, APIView):
    store_permission = "audit.view"

    def get(self, request):
        from datetime import date

        def _d(v):
            try:
                return date.fromisoformat(v) if v else None
            except (TypeError, ValueError):
                return None

        p = request.query_params
        return Response(staff_activity(
            self.store,
            limit=500,
            action=(p.get("action") or "").strip(),
            actor=(p.get("actor") or "").strip(),
            date_from=_d(p.get("from")),
            date_to=_d(p.get("to")),
        ))


# ── Settings ─────────────────────────────────────────────
class StoreSettingsView(StoreScopedMixin, APIView):
    store_permissions = {"read": "dashboard.view", "write": "settings.manage"}

    def get(self, request):
        s = self.store
        from siteconfig.models import PlatformConfig

        cfg = PlatformConfig.load()

        def hhmm(t):
            return t.strftime("%H:%M") if t else None

        return Response({
            "store": {
                "id": str(s.id), "code": s.code, "name": s.name, "address": s.address,
                "phone": s.phone, "latitude": float(s.latitude) if s.latitude else None,
                "longitude": float(s.longitude) if s.longitude else None, "status": s.status,
                # Operating window & capacity (store-admin controllable).
                "acceptingOrders": s.accepting_orders,
                "opensAt": hhmm(s.opens_at),
                "closesAt": hhmm(s.closes_at),
                "dailyOrderCapacity": s.daily_order_capacity,
                "isOpenNow": s.is_open_now(),
                "ordersToday": s.orders_today(),
            },
            "platform": {
                "gstRate": float(getattr(cfg, "gst_rate", 0) or 0),
                # The till MUST know which way tax runs. It computes the totals the
                # cashier collects against, while `pos.services.checkout` computes
                # what is actually charged — and checkout branches on this flag. The
                # POS previously hardcoded "exclusive", so flipping this admin-facing
                # config silently made every till overcharge by the GST rate.
                "posPriceTaxInclusive": bool(
                    getattr(cfg, "pos_price_tax_inclusive", False)
                ),
                "deliveryFee": float(getattr(cfg, "delivery_fee", 0) or 0),
                "freeDeliveryThreshold": float(getattr(cfg, "free_delivery_threshold", 0) or 0),
                "creditDefaultLimit": float(getattr(cfg, "credit_default_limit", 0) or 0),
            },
        })

    def patch(self, request):
        from datetime import datetime

        from .io_utils import field

        s = self.store
        before = {"name": s.name, "address": s.address, "phone": s.phone,
                  "acceptingOrders": s.accepting_orders}
        fields = []
        for src, attr in [("name", "name"), ("address", "address"), ("phone", "phone")]:
            if src in request.data:
                setattr(s, attr, request.data[src])
                fields.append(attr)

        # Operating window + capacity (accept either casing via io_utils.field).
        def _has(key):
            return field(request.data, key, "__missing__") != "__missing__"

        def _time(v):
            if v in (None, ""):
                return None
            return datetime.strptime(str(v), "%H:%M").time()

        if _has("acceptingOrders"):
            s.accepting_orders = bool(field(request.data, "acceptingOrders"))
            fields.append("accepting_orders")
        if _has("opensAt"):
            s.opens_at = _time(field(request.data, "opensAt"))
            fields.append("opens_at")
        if _has("closesAt"):
            s.closes_at = _time(field(request.data, "closesAt"))
            fields.append("closes_at")
        if _has("dailyOrderCapacity"):
            cap = field(request.data, "dailyOrderCapacity")
            s.daily_order_capacity = int(cap) if cap not in (None, "") else None
            fields.append("daily_order_capacity")

        if fields:
            s.save(update_fields=fields)
        record_audit(request.user, "store_settings.update", target=s, before=before,
                     after={f: getattr(s, f) for f in fields})
        return Response({"id": str(s.id), "name": s.name, "acceptingOrders": s.accepting_orders,
                         "isOpenNow": s.is_open_now()})
