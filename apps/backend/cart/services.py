from decimal import Decimal

from django.db import transaction

from core.pricing import compute_bill

from .models import Cart, CartItem
from .serializers import MAX_LINE_QUANTITY


def get_cart(user) -> Cart:
    cart, _ = Cart.objects.get_or_create(user=user)
    return cart


def cart_bill(cart: Cart, coupon_discount=0, zone=None) -> dict:
    items = cart.items.select_related("product")
    subtotal = Decimal("0")
    savings = Decimal("0")
    for it in items:
        subtotal += it.price_snapshot * it.quantity
        if it.product.mrp > it.price_snapshot:
            savings += (it.product.mrp - it.price_snapshot) * it.quantity
    bill = compute_bill(subtotal, savings=savings, coupon_discount=coupon_discount,
                        zone=zone)
    bill["items_count"] = sum(i.quantity for i in items)
    return bill


@transaction.atomic
def replace_items(cart: Cart, lines) -> Cart:
    """Make the server cart exactly ``lines``, atomically.

    Exists because the app used to sync by deleting every server line and then
    POSTing each local item one at a time. That is neither atomic nor idempotent
    against an ACCUMULATING POST: a failure mid-loop left a partial cart, and the
    retry re-POSTed the lines that had already landed, DOUBLING their quantity.
    The customer then paid for a basket they never built.

    Two properties make the retry safe here:

    * **Absolute, not accumulating** — a line's quantity is what the cart becomes,
      so replaying the same PUT converges on the same cart instead of climbing.
    * **All-or-nothing** — the whole reconcile is one transaction, so a mid-flight
      failure rolls back to the previous cart rather than a half-synced one.

    ``lines`` is validated ``ReplaceCartSerializer`` output: dicts of
    ``{product, variant, quantity}``. Zero-quantity lines are drops. An empty list
    legitimately clears the cart.
    """
    # Lock the cart so two concurrent syncs (a retry racing its own timed-out
    # original) serialise instead of interleaving deletes and upserts.
    cart = Cart.objects.select_for_update().get(pk=cart.pk)

    wanted: dict[tuple[int, int | None], dict] = {}
    for line in lines:
        quantity = line["quantity"]
        if quantity <= 0:
            continue
        product = line["product"]
        variant = line.get("variant")
        key = (product.pk, variant.pk if variant is not None else None)
        entry = wanted.get(key)
        if entry is None:
            wanted[key] = {
                "product": product,
                "variant": variant,
                "quantity": quantity,
            }
        else:
            # A well-behaved client keys its local cart by product×variant and so
            # never sends the same line twice. Sum defensively rather than let the
            # last one silently win, and re-clamp — the cap must hold on the merged
            # total, not just per line.
            entry["quantity"] = min(entry["quantity"] + quantity, MAX_LINE_QUANTITY)

    stale = [
        item.pk
        for item in cart.items.all()
        if (item.product_id, item.variant_id) not in wanted
    ]
    if stale:
        cart.items.filter(pk__in=stale).delete()

    for entry in wanted.values():
        upsert_item(cart, entry["product"], entry["variant"], entry["quantity"])
    return cart


def upsert_item(cart: Cart, product, variant, quantity: int) -> CartItem | None:
    if quantity <= 0:
        CartItem.objects.filter(cart=cart, product=product, variant=variant).delete()
        return None
    # Per-store selling price when store_pricing is enabled (falls back to the global
    # Product.price otherwise — i.e. unchanged behaviour by default).
    base = product.price
    from stores.services import (
        resolve_user_store,
        store_price,
        store_pricing_enabled,
        store_visibility_enabled,
    )

    serving = None
    if store_pricing_enabled() or store_visibility_enabled():
        serving = resolve_user_store(cart.user)
    if store_pricing_enabled():
        base = store_price(product, serving)
    # Bind the cart to the store it's being built against, so checkout can detect an
    # address change into another store's zone (→ STORE_CHANGED) and never let a
    # Store-A cart become a Store-B order.
    if store_visibility_enabled() and serving is not None and cart.store_id != serving.id:
        cart.store = serving
        cart.save(update_fields=["store"])
    price = base + (variant.price_delta if variant else 0)
    item, _ = CartItem.objects.update_or_create(
        cart=cart,
        product=product,
        variant=variant,
        defaults={"quantity": quantity, "price_snapshot": price},
    )
    return item
