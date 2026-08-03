from decimal import Decimal

from rest_framework import status
from rest_framework.generics import get_object_or_404
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import Product, ProductVariant
from catalog.serializers import ProductListSerializer
from core.authentication import OptionalJWTAuthentication
from core.pricing import compute_bill

from .models import CartItem, WishlistItem
from .serializers import (
    MAX_LINE_QUANTITY,
    AddCartItemSerializer,
    CartItemSerializer,
    ReplaceCartSerializer,
    UpdateCartItemSerializer,
)
from .services import cart_bill, get_cart, replace_items, upsert_item


def _cart_payload(cart):
    bill = cart_bill(cart)
    return {
        "items": CartItemSerializer(
            cart.items.select_related("product"), many=True
        ).data,
        "bill": bill,
    }


class CartView(APIView):
    def get(self, request):
        return Response(_cart_payload(get_cart(request.user)))

    def put(self, request):
        """Replace the whole cart in one atomic, idempotent call.

        The checkout sync needs "make the server cart match mine" — expressing that
        as delete-all + N accumulating POSTs was neither atomic nor safe to retry.
        See ``cart.services.replace_items``.
        """
        s = ReplaceCartSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        cart = replace_items(get_cart(request.user), s.validated_data["items"])
        return Response(_cart_payload(cart))


def _quote_zone(request):
    """The zone whose fee overrides apply to this quote, or None.

    A zone overrides the delivery fee, the free-delivery threshold, the platform
    fee and the min-order (``zones.services.effective_fees``). ``place_order``
    passes the zone to ``cart_bill``; this preview did not, so a customer in a
    zone with its own delivery fee was quoted the platform default and then
    CHARGED the zone rate — the bill moved between the cart screen and the
    receipt.

    Prefers a saved address id (the server derives the coordinates, so the figure
    can't be shifted from the client). Falls back to explicit coordinates for a
    guest who has no saved address yet. With neither, behaviour is unchanged:
    platform defaults. Note this endpoint is a PREVIEW either way — ``place_order``
    re-resolves the zone from the real delivery address and is the authority on
    what is actually charged.
    """
    from zones.serviceability import resolve_serviceable_zone

    address_id = request.data.get("address_id")
    if address_id and request.user.is_authenticated:
        from addresses.models import Address

        address = Address.objects.filter(pk=address_id, user=request.user).first()
        if address is not None:
            return resolve_serviceable_zone(
                lat=address.latitude, lng=address.longitude, pincode=address.pincode
            )

    lat = request.data.get("latitude")
    lng = request.data.get("longitude")
    pincode = request.data.get("pincode")
    if lat is None and lng is None and not pincode:
        return None
    return resolve_serviceable_zone(lat=lat, lng=lng, pincode=pincode)


class CartQuoteView(APIView):
    """Stateless authoritative bill for a client cart. Prices each item
    server-side (store pricing + variant delta) and runs the same pricing engine
    as the real cart/checkout — so the app never displays a hand-rolled total.
    Does NOT mutate the server cart.

    Guest-accessible (OptionalJWT): pricing a body-supplied item list needs no
    session, so a not-yet-signed-in shopper can see their cart bill without a 401.
    A signed-in user still gets their serving store's pricing."""

    authentication_classes = [OptionalJWTAuthentication]
    permission_classes = [AllowAny]

    def post(self, request):
        from stores.services import (
            resolve_user_store,
            store_price,
            store_pricing_enabled,
        )

        raw_items = request.data.get("items") or []
        coupon_discount = request.data.get("coupon_discount") or 0
        store = resolve_user_store(request.user) if store_pricing_enabled() else None

        subtotal = Decimal("0")
        savings = Decimal("0")
        count = 0
        for it in raw_items:
            if not isinstance(it, dict):
                continue
            product = Product.objects.filter(
                pk=it.get("product_id"), is_active=True
            ).first()
            if product is None:
                continue
            try:
                qty = int(it.get("quantity") or 0)
            except (TypeError, ValueError):
                qty = 0
            if qty <= 0:
                continue
            base = store_price(product, store) if store else product.price
            variant = None
            vid = it.get("variant_id")
            if vid:
                variant = ProductVariant.objects.filter(pk=vid, product=product).first()
            price = base + (variant.price_delta if variant else Decimal("0"))
            subtotal += price * qty
            if product.mrp > price:
                savings += (product.mrp - price) * qty
            count += qty

        bill = compute_bill(subtotal, savings=savings, coupon_discount=coupon_discount,
                            zone=_quote_zone(request))
        bill["items_count"] = count
        return Response({"bill": bill})


class CartValidateView(APIView):
    """Re-check every cart line's stock at the serving store BEFORE checkout, per
    product×variant. The final guard is still the reserve at Pay (which rejects a
    short line), but this gives the customer an explicit, itemised "these are out of
    stock" moment when they tap Secure Checkout — instead of a late failure.

    Takes the client cart (``items:[{product_id, variant_id, quantity}]``) so it works
    before the server cart is synced. Does not mutate anything.

    Guest-accessible (OptionalJWT): a stock pre-check on a body-supplied item list
    needs no session, so the cart page never 401s before sign-in. The real reserve
    at Pay (checkout) stays authenticated."""

    authentication_classes = [OptionalJWTAuthentication]
    permission_classes = [AllowAny]

    def post(self, request):
        from inventory.services import StockCalculationService
        from stores.services import resolve_user_store, store_view

        store = resolve_user_store(request.user)
        wh = store.warehouse if store is not None else None
        raw_items = request.data.get("items") or []
        lines, all_ok = [], True
        for it in raw_items:
            if not isinstance(it, dict):
                continue
            product = Product.objects.filter(
                pk=it.get("product_id"), is_active=True
            ).first()
            if product is None:
                continue
            try:
                qty = int(it.get("quantity") or 0)
            except (TypeError, ValueError):
                qty = 0
            variant = None
            vid = it.get("variant_id")
            if vid:
                variant = ProductVariant.objects.filter(pk=vid, product=product).first()

            if wh is not None:
                # The exact bucket the order will draw from.
                available = StockCalculationService.available(product, wh, variant)
            else:
                # No serviceable store resolved — fall back to the product/variant flag.
                available = None
            in_stock = (available >= qty) if available is not None else (
                variant.in_stock if variant is not None else product.in_stock
            )
            if not in_stock:
                all_ok = False
            view = store_view(product, store)
            name = view["name"]
            if variant is not None:
                name = f"{name} · {variant.label}"
            lines.append({
                "productId": str(product.id),
                "variantId": str(variant.id) if variant else None,
                "name": name,
                "requested": qty,
                "available": available,   # null when store stock is unknown
                "inStock": in_stock,
            })
        return Response({"ok": all_ok, "items": lines})


class CartItemsView(APIView):
    def post(self, request):
        s = AddCartItemSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        cart = get_cart(request.user)
        existing = CartItem.objects.filter(
            cart=cart,
            product=s.validated_data["product"],
            variant=s.validated_data.get("variant"),
        ).first()
        base_qty = existing.quantity if existing else 0
        qty = s.validated_data["quantity"]
        # POST adds to the existing quantity (default 1); 0 is treated as "set 1".
        # Clamped: the per-request cap can't bound an ACCUMULATING endpoint, so
        # repeated adds would climb past it one legal request at a time.
        new_qty = min(base_qty + (qty or 1), MAX_LINE_QUANTITY)
        upsert_item(cart, s.validated_data["product"], s.validated_data.get("variant"), new_qty)
        return Response(_cart_payload(cart), status=status.HTTP_201_CREATED)


class CartItemDetailView(APIView):
    def patch(self, request, pk):
        cart = get_cart(request.user)
        item = get_object_or_404(CartItem, pk=pk, cart=cart)
        s = UpdateCartItemSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        upsert_item(cart, item.product, item.variant, s.validated_data["quantity"])
        return Response(_cart_payload(cart))

    def delete(self, request, pk):
        cart = get_cart(request.user)
        CartItem.objects.filter(pk=pk, cart=cart).delete()
        return Response(_cart_payload(cart))


class WishlistView(APIView):
    def get(self, request):
        products = Product.objects.filter(
            wishlistitem__user=request.user, is_active=True
        ).prefetch_related("variants")
        return Response(ProductListSerializer(products, many=True).data)


class WishlistItemView(APIView):
    def post(self, request, product_id):
        product = get_object_or_404(Product, pk=product_id)
        WishlistItem.objects.get_or_create(user=request.user, product=product)
        return Response({"status": "added"}, status=status.HTTP_201_CREATED)

    def delete(self, request, product_id):
        WishlistItem.objects.filter(user=request.user, product_id=product_id).delete()
        return Response({"status": "removed"})
