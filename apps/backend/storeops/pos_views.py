"""Store-scoped POS (billing counter) — wraps pos/services.py with the cashier's
store warehouse. Gated by the ``pos.operate`` permission. Every sale posts the
inventory ledger + (for credit tender) the credit ledger, exactly like the
network POS, but the till's warehouse is always this store's.
"""
from decimal import Decimal, InvalidOperation

from rest_framework import status as http
from rest_framework.exceptions import ValidationError
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from .permissions import StoreScopedMixin


def _f(v):
    return float(v or 0)


def _variant_rows(product, base_price, warehouse=None):
    """Per-store priced variant options for a product (empty when it has none).

    Carries each pack's OWN available count so the till can gate the quantity against
    the pack the cashier actually rang up, not the product total."""
    from decimal import Decimal

    from inventory.services import StockCalculationService

    buckets = (
        StockCalculationService.by_variant(product, warehouse) if warehouse else {}
    )
    out = []
    for v in product.variants.all():
        delta = v.price_delta or Decimal("0")
        avail = (buckets.get(v.id) or {}).get("available", 0)
        out.append({
            "id": str(v.id),
            "label": v.label,
            "priceDelta": _f(delta),
            "price": _f((base_price or Decimal("0")) + delta),
            "available": avail,
            "inStock": avail > 0,
            "imageUrl": v.image_url or "",
        })
    return out


def session_payload(session, drawer=None):
    if session is None:
        return {"session": None}
    data = {
        "id": session.id,
        "status": session.status,
        "openingCash": _f(session.opening_cash),
        "openedAt": session.opened_at,
        "cashier": session.cashier.name or session.cashier.phone if session.cashier else None,
    }
    if drawer is not None:
        data["drawer"] = {k: _f(v) for k, v in drawer.items()}
    return {"session": data}


def txn_payload(txn):
    return {
        "code": txn.code,
        "type": txn.type,
        "subtotal": _f(txn.subtotal),
        "tax": _f(txn.tax),
        "discount": _f(txn.discount),
        "total": _f(txn.total),
        "creditUsed": _f(txn.credit_used),
        "changeDue": _f(txn.change_due),
        "paymentStatus": txn.payment_status,
        "createdAt": txn.created_at,
        "customerName": (txn.customer.name or txn.customer.phone) if txn.customer_id else None,
        "customerPhone": txn.customer.phone if txn.customer_id else None,
        "primaryMethod": txn.payments.all()[0].method if txn.payments.all() else None,
        "items": [
            # productId/variantId are what a RETURN posts back
            # (`/store/pos/transactions/<code>/return` takes items:[{productId, qty}]).
            # Without them the sales UI literally could not build a return payload,
            # which is why the return endpoint sat unreachable.
            {"productId": str(i.product_id), "name": i.name, "quantity": i.quantity,
             "variantId": str(i.variant_id) if i.variant_id else None,
             "unitPrice": _f(i.unit_price),
             "discount": _f(i.discount), "lineTotal": _f(i.line_total)}
            for i in txn.items.all()
        ],
        "payments": [
            {"method": p.method, "amount": _f(p.amount), "reference": p.reference}
            for p in txn.payments.all()
        ],
    }


# ── Session ──────────────────────────────────────────────
class StorePOSSessionView(StoreScopedMixin, APIView):
    store_permission = "pos.operate"

    def get(self, request):
        from pos.services import current_session, drawer_summary

        session = current_session(request.user)
        return Response(session_payload(session, drawer_summary(session) if session else None))

    def post(self, request):
        from pos.services import POSError, open_session

        wh = self.store.warehouse
        if wh is None:
            raise ValidationError({"warehouse": ["This store has no warehouse / till."]})
        try:
            session = open_session(
                cashier=request.user, warehouse=wh,
                opening_cash=request.data.get("openingCash") or request.data.get("opening_cash") or 0,
            )
        except POSError as e:
            raise ValidationError({"detail": [str(e)]})
        return Response(session_payload(session), status=http.HTTP_201_CREATED)


class StorePOSSessionCloseView(StoreScopedMixin, APIView):
    store_permission = "pos.operate"

    def post(self, request):
        from pos.services import POSError, close_session, current_session

        session = current_session(request.user)
        if session is None:
            raise ValidationError({"session": ["No open session to close."]})
        try:
            closing = close_session(
                session=session,
                counted_cash=request.data.get("countedCash", request.data.get("counted_cash")),
                notes=request.data.get("notes", ""), by=request.user,
            )
        except POSError as e:
            raise ValidationError({"detail": [str(e)]})
        return Response({
            "expectedCash": _f(closing.expected_cash),
            "countedCash": _f(closing.counted_cash),
            "variance": _f(closing.variance),
            "totalSales": _f(closing.total_sales),
            "cashSales": _f(closing.cash_sales),
            "upiSales": _f(closing.upi_sales),
            "cardSales": _f(closing.card_sales),
            "creditSales": _f(closing.credit_sales),
            "transactionCount": closing.transaction_count,
        }, status=http.HTTP_201_CREATED)


# ── Catalog lookups ──────────────────────────────────────
class StorePOSScanView(StoreScopedMixin, APIView):
    store_permission = "pos.operate"

    def get(self, request):
        from inventory.models import Barcode
        from inventory.services import StockCalculationService

        code = request.query_params.get("code") or request.query_params.get("barcode")
        if not code:
            raise ValidationError({"code": ["A barcode is required."]})
        bc = Barcode.objects.select_related("product", "variant").filter(code=code).first()
        # A barcode that maps to another store's private product is "unknown" here.
        if bc is None or (
            bc.product.origin_store_id is not None
            and bc.product.origin_store_id != self.store.id
        ):
            return Response(
                {"error": {"code": "not_found", "message": "Unknown barcode.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        from decimal import Decimal

        from stores.services import store_view

        p = bc.product
        view = store_view(p, self.store)
        # A variant barcode resolves to that variant + its price (base + delta).
        variant = bc.variant
        price = view["price"] or Decimal("0")
        name = view["name"]
        if variant is not None:
            price = price + (variant.price_delta or Decimal("0"))
            name = f"{name} · {variant.label}"
        return Response({
            "productId": str(p.id),
            "variantId": str(variant.id) if variant else None,
            "variantLabel": variant.label if variant else None,
            "name": name,
            "price": _f(price), "mrp": _f(view["mrp"]),
            "available": StockCalculationService.available(p, self.store.warehouse),
            "barcode": bc.code,
        })


class StorePOSSearchView(StoreScopedMixin, APIView):
    store_permission = "pos.operate"

    def get(self, request):
        from catalog.models import Product
        from inventory.services import StockCalculationService

        from stores.services import store_sellable_queryset, store_view

        q = (request.query_params.get("q") or "").strip()
        wh = self.store.warehouse
        products = store_sellable_queryset(
            Product.objects.filter(is_active=True), self.store
        ).prefetch_related("variants")
        if q:
            products = products.filter(name__icontains=q)
        # Category filter (a department id aggregates its sub-categories' products).
        category = request.query_params.get("category")
        if category:
            from catalog.models import Category

            child_ids = list(
                Category.objects.filter(parent_id=category).values_list("id", flat=True)
            )
            products = products.filter(
                category_id__in=[category, *child_ids] if child_ids else [category]
            )
        brand = (request.query_params.get("brand") or "").strip()
        if brand:
            products = products.filter(brand__iexact=brand)
        rows = []
        for p in products[:30]:
            view = store_view(p, self.store)
            variant_rows = _variant_rows(p, view["price"], wh)
            rows.append({
                "productId": str(p.id), "name": view["name"], "brand": view["brand"],
                "unit": p.unit, "price": _f(view["price"]), "mrp": _f(view["mrp"]),
                "imageUrl": view["image_url"] or "",
                "variants": variant_rows,
                "hasVariants": bool(variant_rows),
                # Product total (sum of every bucket) …
                "available": StockCalculationService.available(p, wh) if wh else 0,
                # … and the bare base (no-variant) bucket on its own. For a variant
                # product the base isn't a sellable unit — the till must show the
                # SELECTED pack's stock, never the total — so the two are distinct.
                "baseAvailable": (
                    StockCalculationService.available(p, wh, variant=None) if wh else 0
                ),
            })
        return Response(rows)


class StorePOSProductView(StoreScopedMixin, APIView):
    """Full store-resolved product detail for the POS product dialog — mirrors the
    customer app's product page (gallery, brand·unit, rating/reviews, price/MRP/
    discount, variants, stock, description), with this store's overrides applied."""

    store_permission = "pos.operate"

    def get(self, request, product_id):
        from catalog.models import Product
        from inventory.services import StockCalculationService
        from stores.services import store_sellable_queryset, store_view

        # Only what this store actually carries — the till can't sell a company
        # product that has never been on its shelf.
        product = get_object_or_404(
            store_sellable_queryset(
                Product.objects.filter(is_active=True), self.store
            ).prefetch_related("variants", "gallery"),
            pk=product_id,
        )
        view = store_view(product, self.store)
        wh = self.store.warehouse
        available = StockCalculationService.available(product, wh) if wh else 0
        base_available = (
            StockCalculationService.available(product, wh, variant=None) if wh else 0
        )
        gallery = [g.url for g in product.gallery.all()]
        image = view["image_url"] or ""
        if not gallery and image:
            gallery = [image]
        price, mrp = view["price"], view["mrp"]
        discount = round((mrp - price) / mrp * 100) if (mrp and mrp > price) else 0
        return Response({
            "productId": str(product.id),
            "name": view["name"],
            "brand": view["brand"],
            "unit": product.unit,
            "price": _f(price),
            "mrp": _f(mrp),
            "discountPercent": discount,
            "imageUrl": image,
            "gallery": gallery,
            "rating": _f(product.rating),
            "reviews": product.review_count,
            "description": view["description"] or "",
            "specifications": product.specifications or {},
            "available": available,
            "baseAvailable": base_available,
            "variants": _variant_rows(product, price, self.store.warehouse),
        })


class StorePOSCatalogView(StoreScopedMixin, APIView):
    """Full sellable-catalog snapshot for OFFLINE POS caching: every active
    product with price, current stock and its primary barcode for this store's
    warehouse. The POS caches this so search/scan + billing keep working through
    an internet outage. Bulk stock/barcode maps avoid per-product queries."""

    store_permission = "pos.operate"

    def get(self, request):
        from catalog.models import Product
        from inventory.models import Barcode, StockItem

        from stores.models import StoreProduct
        from stores.services import store_sellable_queryset, store_view

        wh = self.store.warehouse
        avail = {}
        if wh is not None:
            avail = {
                si.product_id: si.available
                for si in StockItem.objects.filter(warehouse=wh)
            }
        barcodes = {}
        for bc in Barcode.objects.all().only("product_id", "code"):
            barcodes.setdefault(bc.product_id, bc.code)
        overrides = {sp.product_id: sp for sp in StoreProduct.objects.filter(store=self.store)}
        # The offline cache carries this store's shelf, not the global catalog.
        products = store_sellable_queryset(
            Product.objects.filter(is_active=True), self.store
        ).prefetch_related("variants").only(
            "id", "name", "brand", "unit", "price", "mrp", "image_url", "origin_store"
        )
        items = []
        for p in products:
            view = store_view(p, self.store, sp=overrides.get(p.id))
            items.append({
                "productId": str(p.id), "name": view["name"], "brand": view["brand"],
                "unit": p.unit, "price": _f(view["price"]), "mrp": _f(view["mrp"]),
                "imageUrl": view["image_url"] or "",
                "variants": _variant_rows(p, view["price"], wh),
                "available": avail.get(p.id, 0), "barcode": barcodes.get(p.id, ""),
            })
        return Response({
            "warehouseId": str(wh.id) if wh else None,
            "products": items,
        })


class StorePOSCustomerView(StoreScopedMixin, APIView):
    store_permission = "pos.operate"

    def get(self, request):
        from accounts.models import User
        from credit.services import ensure_account

        phone = (request.query_params.get("phone") or "").strip()
        if not phone:
            raise ValidationError({"phone": ["A phone number is required."]})
        user = User.objects.filter(phone__endswith=phone[-10:], role="customer").first()
        if user is None:
            return Response(
                {"error": {"code": "not_found", "message": "No customer with that phone.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        acc = ensure_account(user)
        return Response(_customer_payload(user, acc))


def _customer_payload(user, acc):
    return {
        "customerId": str(user.id), "name": user.name or user.phone, "phone": user.phone,
        "creditStatus": acc.status, "creditLimit": _f(acc.credit_limit),
        "creditAvailable": _f(acc.available), "outstanding": _f(acc.outstanding),
    }


class StorePOSCustomerCreateView(StoreScopedMixin, APIView):
    """Create a new walk-in customer from the POS and return them ready to attach."""

    store_permission = "pos.operate"

    def post(self, request):
        from accounts.models import Role, User
        from accounts.services import record_audit
        from credit.services import ensure_account

        from .io_utils import field

        phone = (field(request.data, "phone") or "").strip()
        name = " ".join(x for x in [(field(request.data, "firstName") or field(request.data, "name") or "").strip(),
                                    (field(request.data, "lastName") or "").strip()] if x).strip()
        email = (field(request.data, "email") or "").strip()
        if len(phone) < 10:
            raise ValidationError({"phone": ["A valid phone number is required."]})
        if not name:
            raise ValidationError({"firstName": ["A name is required."]})
        if User.objects.filter(phone=phone).exists():
            raise ValidationError({"phone": ["A customer with this phone already exists."]})
        # create_user sets an unusable password (customers log in by OTP) + syncs flags.
        user = User.objects.create_user(
            phone=phone, name=name, email=email or None, role=Role.CUSTOMER,
        )
        record_audit(request.user, "store_pos.customer_create", target=user,
                     after={"phone": phone})
        return Response(_customer_payload(user, ensure_account(user)),
                        status=http.HTTP_201_CREATED)


class StoreBrandsView(StoreScopedMixin, APIView):
    """Distinct product brands in this store's catalog (for the POS brand filter)."""

    store_permission = "pos.operate"

    def get(self, request):
        from catalog.models import Product
        from stores.services import store_sellable_queryset

        brands = (
            store_sellable_queryset(
                Product.objects.filter(is_active=True).exclude(brand=""), self.store
            )
            .values_list("brand", flat=True)
            .distinct()
            .order_by("brand")
        )
        return Response([b for b in brands if b])


class StorePOSCouponView(StoreScopedMixin, APIView):
    """Validate a coupon against a subtotal and preview the discount (no redemption)."""

    store_permission = "pos.operate"

    def post(self, request):
        from offers.services import resolve_coupon

        from .io_utils import field

        code = (field(request.data, "code") or "").strip()
        subtotal = field(request.data, "subtotal") or 0
        coupon, discount, message = resolve_coupon(code, subtotal)
        if coupon is None:
            raise ValidationError({"code": [message]})
        return Response({"code": coupon.code, "discount": _f(discount), "message": message})


def _line_qty(raw, product):
    """Validate a cart line quantity.

    This used to be ``int(raw or 1)``, which silently corrupted two cases:

      * ``0.5`` is truthy, so the ``or 1`` guard never fired and ``int(0.5)``
        billed the line as **zero** — the customer walked out with free goods and
        the stock ledger never moved.
      * ``1.35`` was quietly charged and decremented as ``1``.

    Quantity is an integer the whole way down the stock spine (POSTransactionItem,
    StockItem, StockBatch, InventoryLedger, GRNItem, OrderItem are all integer
    columns), so a fractional quantity cannot be honoured here. Reject it loudly
    instead of guessing — selling weighed goods by fractional quantity needs that
    spine migrated to Decimal, which is a separate piece of work.
    """
    if raw is None or raw == "":
        return 1
    try:
        qty = Decimal(str(raw))
    except (InvalidOperation, TypeError, ValueError):
        raise ValidationError({"items": [f"{product.name}: quantity must be a number."]})
    if qty != qty.to_integral_value():
        raise ValidationError({"items": [
            f"{product.name}: this till bills whole units only, so {qty} can't be "
            f"charged. Weigh the item and enter the price as a separate line."
        ]})
    qty = int(qty)
    if qty <= 0:
        raise ValidationError({"items": [f"{product.name}: quantity must be at least 1."]})
    return qty


# ── Checkout / transactions ──────────────────────────────
class StorePOSCheckoutView(StoreScopedMixin, APIView):
    store_permission = "pos.operate"

    def post(self, request):
        from accounts.models import User
        from catalog.models import Product, ProductVariant
        from pos.services import OutOfStockError, POSError, checkout, current_session

        from .io_utils import field

        session = current_session(request.user)
        if session is None:
            raise ValidationError({"session": ["Open a POS session before billing."]})
        items = field(request.data, "items") or []
        if not items:
            raise ValidationError({"items": ["The cart is empty."]})
        lines = []
        for it in items:
            product = get_object_or_404(Product, pk=field(it, "productId"))
            variant = None
            vid = field(it, "variantId")
            if vid:
                # Variant must belong to the product (ignore a stray id rather than 500).
                variant = ProductVariant.objects.filter(pk=vid, product=product).first()
            lines.append({"product": product, "variant": variant,
                          "qty": _line_qty(field(it, "qty"), product),
                          "discount": field(it, "discount", 0)})
        customer = None
        cid = field(request.data, "customerId")
        if cid:
            customer = User.objects.filter(pk=cid).first()

        # ── Normalise tenders: cash / online(Razorpay) / credit(2FA) ─────────
        from decimal import Decimal

        raw_payments = field(request.data, "payments") or []
        payments, credit_total, online_total = [], Decimal("0"), Decimal("0")
        for p in raw_payments:
            method = (field(p, "method") or "cash").lower()
            amount = Decimal(str(field(p, "amount") or 0))
            ref = field(p, "reference", "") or ""
            if method == "online":
                online_total += amount
                # Settled by Razorpay; recorded as a UPI tender with the payment id.
                ref = field(request.data, "razorpayPaymentId") or ref
                method = "upi"
            elif method == "credit":
                credit_total += amount
            payments.append({"method": method, "amount": float(amount), "reference": ref})

        # Credit needs the customer's in-app 2FA confirmation for the credit amount.
        if credit_total > 0:
            if customer is None:
                raise ValidationError({"customerId": ["Attach a customer to bill on credit."]})
            from credit.pos_otp import verify as verify_credit_otp

            ok_, err = verify_credit_otp(customer, field(request.data, "creditOtp"), credit_total)
            if not ok_:
                raise ValidationError({"creditOtp": [err]})

        # Online must carry a verified Razorpay signature (no-op-True on the mock gw).
        if online_total > 0:
            from payments.gateway import get_gateway

            if not get_gateway().verify_checkout_signature(
                field(request.data, "razorpayOrderId"),
                field(request.data, "razorpayPaymentId"),
                field(request.data, "razorpaySignature"),
            ):
                raise ValidationError({"payment": ["Online payment could not be verified."]})

        # Coupon → server-recomputed bill discount (never trust a client amount).
        coupon_code = (field(request.data, "couponCode") or "").strip()
        discount = Decimal(str(field(request.data, "discount") or 0))
        if coupon_code:
            from stores.services import store_view

            subtotal = Decimal("0")
            for ln in lines:
                view = store_view(ln["product"], self.store)
                price = Decimal(str(view["price"]))
                if ln.get("variant"):
                    price += (ln["variant"].price_delta or Decimal("0"))
                subtotal += price * ln["qty"]
            from offers.services import resolve_coupon

            coupon, discount, msg = resolve_coupon(coupon_code, subtotal)
            if coupon is None:
                raise ValidationError({"couponCode": [msg]})

        try:
            txn = checkout(
                session=session, lines=lines, payments=payments,
                customer=customer, discount=discount,
                note=field(request.data, "note", ""), by=request.user, warehouse=self.store.warehouse,
                idempotency_key=request.headers.get("Idempotency-Key", ""),
            )
        except OutOfStockError as e:
            # Structured 409 so the offline-sync client flags it as a conflict to
            # resolve (cash already taken) rather than a generic validation error.
            return Response(
                {"error": {"code": "pos_out_of_stock", "message": str(e),
                           "available": e.available, "fields": {}}},
                status=http.HTTP_409_CONFLICT,
            )
        except POSError as e:
            raise ValidationError({"detail": [str(e)]})

        # Surface the in-store purchase in the customer's app "story" (inbox + push).
        if customer is not None:
            from notifications.services import notify

            summary = ", ".join(f"{it.quantity}× {it.name}" for it in txn.items.all()[:3])
            more = "…" if txn.items.count() > 3 else ""
            notify(
                customer, type="order",
                title=f"Purchase at {self.store.name}",
                body=f"₹{txn.total} · {summary}{more}",
                data={"kind": "pos_purchase", "code": txn.code, "total": str(txn.total),
                      "store": self.store.name, "route": "orders"},
            )
        return Response(txn_payload(txn), status=http.HTTP_201_CREATED)


class StorePOSCreditOtpView(StoreScopedMixin, APIView):
    """Request an in-app 2FA code so a customer can confirm a credit sale. The code
    is shown in the customer's app (not in the push); the cashier enters what the
    customer reads back."""

    store_permission = "pos.operate"

    def post(self, request):
        from accounts.models import User

        from credit.pos_otp import issue
        from credit.services import ensure_account

        from .io_utils import field

        cid = field(request.data, "customerId")
        amount = field(request.data, "amount")
        if not cid or amount in (None, ""):
            raise ValidationError({"detail": ["Customer and amount are required."]})
        customer = get_object_or_404(User, pk=cid, role="customer")
        acc = ensure_account(customer)
        if acc.status != "active":
            raise ValidationError({"credit": ["This customer's credit is not active."]})
        from decimal import Decimal

        if Decimal(str(amount)) > acc.available:
            raise ValidationError({"amount": [f"Exceeds available credit (₹{acc.available})."]})
        issue(customer, Decimal(str(amount)), self.store)
        return Response({"sent": True, "expiresInSec": 300})


class StorePOSOnlineOrderView(StoreScopedMixin, APIView):
    """Create a Razorpay order for an online POS tender; the cashier opens Checkout
    with the returned key + order id, and completes the sale on success."""

    store_permission = "pos.operate"

    def post(self, request):
        from decimal import Decimal

        from payments.gateway import get_gateway, get_public_key_id

        from .io_utils import field

        amount = field(request.data, "amount")
        if amount in (None, "") or Decimal(str(amount)) <= 0:
            raise ValidationError({"amount": ["A positive amount is required."]})
        gw = get_gateway()
        order = gw.create_order(Decimal(str(amount)), receipt=f"pos-{self.store.code}")
        return Response({
            "keyId": get_public_key_id(),
            "orderId": order["gateway_order_id"],
            "amount": _f(amount),
            "currency": "INR",
            "gateway": gw.name,
        })


class StorePOSTransactionsView(StoreScopedMixin, APIView):
    store_permission = "pos.operate"

    def get(self, request):
        from pos.models import POSTransaction

        wh = self.store.warehouse_id
        qs = (
            POSTransaction.objects.filter(session__warehouse_id=wh)
            .select_related("customer")
            .prefetch_related("items", "payments")
            .order_by("-created_at")[:50]
        )
        return Response([txn_payload(t) for t in qs])


class StorePOSReceiptView(StoreScopedMixin, APIView):
    store_permission = "pos.operate"

    def get(self, request, code):
        from pos.models import POSTransaction
        from pos.services import build_receipt

        txn = get_object_or_404(
            POSTransaction.objects.prefetch_related("items", "payments"),
            code=code, session__warehouse_id=self.store.warehouse_id,
        )
        return Response(build_receipt(txn))


class StorePOSReceiptPdfView(StoreScopedMixin, APIView):
    """80mm thermal receipt PDF for a POS transaction (printable / shareable)."""

    store_permission = "pos.operate"

    def get(self, request, code):
        from django.http import HttpResponse

        from pos.models import POSTransaction
        from pos.receipt_pdf import build_pos_receipt_pdf

        txn = get_object_or_404(
            POSTransaction.objects.prefetch_related("items", "payments"),
            code=code, session__warehouse_id=self.store.warehouse_id,
        )
        pdf = build_pos_receipt_pdf(txn)
        resp = HttpResponse(pdf, content_type="application/pdf")
        resp["Content-Disposition"] = f'inline; filename="receipt-{txn.code}.pdf"'
        return resp


class StorePOSInvoiceView(StoreScopedMixin, APIView):
    """Branded A4 tax invoice for a POS sale (proper invoice, not the till receipt)."""

    store_permission = "pos.operate"

    def get(self, request, code):
        from django.http import HttpResponse

        from pos.invoice import build_pos_invoice_pdf
        from pos.models import POSTransaction

        txn = get_object_or_404(
            POSTransaction.objects.select_related("customer").prefetch_related("items", "payments"),
            code=code, session__warehouse_id=self.store.warehouse_id,
        )
        pdf = build_pos_invoice_pdf(txn, self.store)
        resp = HttpResponse(pdf, content_type="application/pdf")
        resp["Content-Disposition"] = f'inline; filename="invoice-{txn.code}.pdf"'
        return resp


class StorePOSReturnView(StoreScopedMixin, APIView):
    store_permission = "pos.operate"

    def post(self, request, code):
        from catalog.models import Product
        from pos.models import POSTransaction
        from pos.services import POSError, current_session, process_return

        session = current_session(request.user)
        if session is None:
            raise ValidationError({"session": ["Open a POS session first."]})
        from .io_utils import field

        original = get_object_or_404(
            POSTransaction, code=code, session__warehouse_id=self.store.warehouse_id
        )
        lines = []
        for it in field(request.data, "items") or []:
            product = get_object_or_404(Product, pk=field(it, "productId"))
            lines.append({"product": product, "qty": int(field(it, "qty") or 1)})
        try:
            rtxn = process_return(
                session=session, original=original, lines=lines,
                reason=field(request.data, "reason", ""),
                refund_method=field(request.data, "refundMethod"), by=request.user,
                warehouse=self.store.warehouse,
            )
        except POSError as e:
            raise ValidationError({"detail": [str(e)]})
        return Response(txn_payload(rtxn), status=http.HTTP_201_CREATED)


class StorePOSPaymentLinkView(StoreScopedMixin, APIView):
    """POST /store/pos/payment-link — raise a Razorpay link for a counter sale.

    UPI/card tender used to be recorded on the cashier's word: they typed a
    reference and the sale was marked paid with nothing verifying that money had
    moved. This charges the customer for real — they pay from their own phone and
    the till confirms against the gateway.
    """

    store_permission = "pos.operate"

    def post(self, request):
        from accounts.models import User
        from payments.pos_link_services import create_counter_link, link_payload

        customer = None
        customer_id = request.data.get("customerId") or request.data.get("customer_id")
        if customer_id:
            customer = User.objects.filter(pk=customer_id, role="customer").first()

        payment, link = create_counter_link(
            amount=request.data.get("amount"),
            store=self.store,
            cashier=request.user,
            customer=customer,
            note=request.data.get("note") or "",
        )
        return Response(link_payload(payment, link), status=http.HTTP_201_CREATED)


class StorePOSPaymentLinkStatusView(StoreScopedMixin, APIView):
    """GET /store/pos/payment-link/<pk> — has the customer paid yet?

    The till polls this; only a gateway-confirmed `success` should let the
    cashier complete the sale as paid.
    """

    store_permission = "pos.operate"

    def get(self, request, pk):
        from payments.models import Payment
        from payments.pos_link_services import link_payload, poll_counter_link

        payment = get_object_or_404(Payment, pk=pk)
        payment = poll_counter_link(payment, by=request.user)
        return Response(link_payload(payment))
