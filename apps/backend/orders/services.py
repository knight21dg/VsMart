from datetime import date as _date
from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from cart.services import cart_bill, get_cart, upsert_item
from core.app_errors import AppError
from core.pricing import gst_fraction_to_pct, q
from credit.services import ensure_account
from inventory.models import InventoryLedger
from inventory.services import InventoryError, InventoryService, consume_fefo
from zones.serviceability import resolve_serviceable_zone

from .models import (
    TERMINAL_STATUSES,
    Order,
    OrderItem,
    OrderStatus,
    OrderStatusEvent,
    can_transition,
)


def pending_credit_exposure(user) -> Decimal:
    """This user's credit orders still in flight toward delivery — not yet
    delivered, and not cancelled/rejected/returned either.

    Nothing is posted to the credit ledger until an order is actually
    delivered (see `delivery.services.complete_delivery`), so
    `account.available` alone doesn't reflect orders already placed but not
    yet delivered. Without this, several credit orders placed back-to-back
    could each individually look affordable and together blow past the
    customer's real limit by the time they all deliver.
    """
    total = (
        Order.objects.filter(user=user, payment_method=Order.PaymentMethod.CREDIT)
        .exclude(status__in=TERMINAL_STATUSES | {OrderStatus.DELIVERED})
        .aggregate(total=Sum("credit_used"))["total"]
    )
    return total or Decimal("0")


class CheckoutError(AppError):
    """A checkout / order-lifecycle gate failure, carrying a catalog `code`.

    It **is** an :class:`AppError`, so the exception handler renders it with the
    right status and the operator-readable message wherever it is raised. It used
    to be a plain ``Exception`` that each view had to catch and re-raise by hand
    — and the views that forgot (the store panel's order-status endpoint, for
    one) turned "An order that is delivered cannot become rejected." into a bare
    500 "We hit a temporary problem on our end."

    The ``(message, code)`` signature is kept because every call site uses it,
    and the existing ``except CheckoutError`` blocks keep working unchanged.
    """

    def __init__(self, message, code="VALIDATION_ERROR"):
        super().__init__(code, message=message)


def compute_payout_date(plan, today=None):
    """Authoritative VS Credit repayment due date for a [plan]:
    - ``month_end`` → the last calendar day of the current month
    - ``weekend`` (default) → the upcoming Sunday (next Sunday if today is Sunday)
    Kept in sync with the app's ``CreditRepaymentPlan.payoutDate``."""
    today = today or timezone.localdate()
    if plan == "month_end":
        first_next = _date(
            today.year + (1 if today.month == 12 else 0),
            1 if today.month == 12 else today.month + 1,
            1,
        )
        return first_next - timedelta(days=1)
    # weekday(): Mon=0 … Sun=6.
    days = (6 - today.weekday()) % 7 or 7
    return today + timedelta(days=days)


@transaction.atomic
def place_order(user, *, address, payment_method, delivery_slot="", coupon_discount=0,
                coupon_code="", credit_plan="", idempotency_key=""):
    """Atomically turn the user's cart into an order. Stock is **reserved** (not yet
    decremented) so a pending order can't oversell; the actual `order` ledger movement
    is posted on fulfilment. Credit orders debit the credit ledger here. Idempotent on
    `idempotency_key` — a repeat (e.g. a network retry) returns the existing order."""
    if idempotency_key:
        existing = Order.objects.filter(
            user=user, idempotency_key=idempotency_key
        ).first()
        if existing:
            return existing

    cart = get_cart(user)
    items = list(cart.items.select_related("product"))
    if not items:
        raise CheckoutError("Your cart is empty.", code="CART_EMPTY")

    # Resolve the serving zone (polygon-first) → its store. Drives fee overrides,
    # order routing, the stock source, and the zone credit gate.
    zone = resolve_serviceable_zone(
        lat=address.latitude, lng=address.longitude, pincode=address.pincode
    )
    store = getattr(zone, "store", None)
    from stores.services import (
        store_visibility_enabled,
        visible_product_ids,
        zone_enforcement_enabled,
    )

    # Hard serviceability enforcement is opt-in (zone_enforcement flag): when on, an
    # address outside every zone — or in a zone with no active serving store — cannot
    # place an order. OFF by default so legacy/global flows are unaffected.
    if zone_enforcement_enabled():
        if zone is None:
            raise CheckoutError(
                "We don't deliver to this address yet. Try a different location.",
                code="OUTSIDE_SERVICE_AREA",
            )
        if store is None or not store.is_serviceable:
            raise CheckoutError(
                "The store for your area isn't accepting orders right now.",
                code="OUTSIDE_SERVICE_AREA",
            )

    # Store operating gates — an order can only be placed when the serving store is
    # open and under its daily delivery capacity. Both are no-ops when the store has no
    # hours / no capacity configured, so existing flows are unaffected.
    if store is not None:
        if not store.is_open_now():
            raise CheckoutError(
                "Your store isn't accepting orders right now. Please order during opening hours.",
                code="STORE_CLOSED",
            )
        if store.capacity_reached():
            raise CheckoutError(
                "Today's delivery capacity for your area is full. Please try again tomorrow.",
                code="DELIVERY_CAPACITY_REACHED",
            )

    # The warehouse that actually fulfils this order is the serving store's warehouse.
    # Only fall back to the global default warehouse when no store is resolved (legacy
    # single-store / pre-zone mode) — this is what guarantees an order can ONLY ever
    # draw down the stock of the store that serves the customer's zone.
    fulfil_warehouse = (
        store.warehouse if (store is not None and store.warehouse_id) else None
    )

    # Store-scoped catalog gate (zone_store_visibility): every item must be carried by
    # the serving store. Closes the deep-link / spoofed-?store= / stale-cart loophole.
    # If the cart was built against a DIFFERENT store (the customer changed address into
    # another store's zone) → STORE_CHANGED (refresh the cart); otherwise the items were
    # delisted since they were added → PRODUCT_UNAVAILABLE. Either way the Store-A cart
    # can never become a Store-B order.
    if store is not None and store_visibility_enabled():
        carried = visible_product_ids(store)
        if carried is not None:
            missing = [it for it in items if it.product_id not in carried]
            if missing:
                if cart.store_id and cart.store_id != store.id:
                    raise CheckoutError(
                        "Your delivery address changed to a different store's area. "
                        "Your cart has been refreshed for what's available there.",
                        code="STORE_CHANGED",
                    )
                names = [it.product.name for it in missing]
                raise CheckoutError(
                    f"{names[0]} isn't available at your store yet."
                    if len(names) == 1
                    else f"{len(names)} items in your cart aren't available at your store yet.",
                    code="PRODUCT_UNAVAILABLE",
                )

    # Stock pre-check against the FULFILLING store's warehouse (not global on-hand): a
    # product in stock at another store can't be ordered from a store that's out of it.
    # The atomic reserve below (same warehouse) is the real oversell guard.
    from inventory.services import StockCalculationService

    for it in items:
        if it.product.stock_count is None:
            continue  # stock not tracked for this product
        if fulfil_warehouse is not None:
            if StockCalculationService.available(it.product, fulfil_warehouse) < it.quantity:
                raise CheckoutError(
                    f"{it.product.name} is out of stock at your store.",
                    code="OUT_OF_STOCK",
                )
        elif not it.product.in_stock:
            raise CheckoutError(
                f"{it.product.name} is currently out of stock.", code="OUT_OF_STOCK"
            )

    # Zone credit gate (spec §CREDIT SERVICEABILITY): a zone may disable BNPL while
    # still allowing cash/online purchase.
    if (
        payment_method == Order.PaymentMethod.CREDIT
        and zone is not None
        and not zone.credit_enabled
    ):
        raise CheckoutError(
            "VS Credit isn't available in your area yet.", code="CREDIT_DISABLED"
        )
    # Recompute the coupon discount SERVER-SIDE from the code. The client sends a
    # figure so it can render the bill, but trusting it here meant a crafted
    # checkout could pair a real ₹50 code with `couponDiscount: 99999` and buy an
    # order for nothing — `redeem_coupon` below only records the redemption, it
    # never re-derived the amount. The client's number is now ignored entirely.
    if coupon_code:
        from offers.services import coupon_discount as _coupon_discount

        subtotal = sum(
            (it.product.price * it.quantity for it in items), Decimal("0")
        )
        coupon_discount = _coupon_discount(coupon_code, subtotal, user=user)
        # FAIL LOUD. A customer who attached a code believes they're getting the
        # discount — if it resolves to nothing (expired, used up, min not met),
        # silently charging full price is how VSNEW100 billed ₹649 instead of
        # ₹549 through the gateway. Refuse the order; the app tells them to
        # remove or replace the coupon.
        if coupon_discount <= 0:
            raise CheckoutError(
                "That coupon can't be applied to this order — remove it or "
                "use a different code.",
                code="COUPON_INVALID",
            )
    else:
        coupon_discount = Decimal("0")

    bill = cart_bill(cart, coupon_discount=coupon_discount, zone=zone)

    # Minimum order value. The figure has always been configured (per zone, with
    # a PlatformConfig fallback) and surfaced on the bill, but **nothing ever
    # checked it** — a zone set to ₹1,000 happily accepted a ₹300 order. It is
    # enforced here, on the server, against the item subtotal: fees and GST are
    # not goods, so counting them would let a ₹850 cart clear a ₹1,000 minimum on
    # delivery charges alone, and the coupon discount is applied after the
    # threshold for the same reason.
    min_order = Decimal(bill.get("min_order") or 0)
    if min_order > 0 and bill["subtotal"] < min_order:
        shortfall = q(min_order - bill["subtotal"])
        raise CheckoutError(
            f"Minimum order value is ₹{min_order:,.0f}. "
            f"Add ₹{shortfall:,.0f} more to continue.",
            code="MIN_ORDER_NOT_MET",
        )

    order = Order.objects.create(
        user=user,
        payment_method=payment_method,
        zone=zone,
        store=store,
        # Immutable provenance snapshot for the invoice (survives store/zone renames
        # or deletes — the FKs are SET_NULL).
        store_name=store.name if store is not None else "",
        store_address=store.address if store is not None else "",
        zone_name=zone.name if zone is not None else "",
        address_snapshot={
            "name": address.name, "phone": address.phone,
            "formatted": address.formatted, "pincode": address.pincode,
            # Destination coordinates power delivery geofencing + live tracking.
            "latitude": float(address.latitude) if address.latitude is not None else None,
            "longitude": float(address.longitude) if address.longitude is not None else None,
        },
        delivery_slot=delivery_slot,
        estimated_delivery=timezone.now() + timezone.timedelta(hours=2),
        subtotal=bill["subtotal"],
        delivery_fee=bill["delivery_fee"],
        gst=bill["gst"],
        platform_fee=bill["platform_fee"],
        discount=bill["coupon_discount"],
        total=bill["total"],
        coupon_code=coupon_code,
    )

    # Redeem the coupon (only when a discount actually applied): records the
    # redemption and enforces expiry + global/per-user limits under a row lock, so a
    # one-time / capped coupon can't be claimed twice — even by concurrent checkouts.
    if coupon_code and bill["coupon_discount"] > 0:
        from offers.services import CouponError, redeem_coupon

        try:
            redeem_coupon(coupon_code, user, order_code=order.code,
                          amount=bill["coupon_discount"])
        except CouponError as e:
            raise CheckoutError(str(e), code=e.code)

    from siteconfig.models import PlatformConfig

    # OrderItem.gst_rate is a PERCENTAGE (see its field docstring), and so is
    # Product.gst_rate. PlatformConfig.gst_rate is the fraction the pricing maths
    # multiplies by, so the fallback has to be converted — copying it raw
    # snapshotted every line without an explicit product rate at "0.18%".
    default_gst = gst_fraction_to_pct(PlatformConfig.load().gst_rate)
    reserved_any = False
    for it in items:
        # Carry the cart line's pack onto the order line. The cart has always known
        # which variant was chosen; the order line didn't record it, so the pack
        # survived only inside the composed name and fulfilment had to guess which
        # stock to take.
        variant = it.variant
        OrderItem.objects.create(
            order=order, product=it.product, variant=variant,
            name=f"{it.product.name} · {variant.label}" if variant else it.product.name,
            brand=it.product.brand, unit=it.product.unit,
            image_url=(variant.image_url if variant and variant.image_url
                       else it.product.image_url),
            price=it.price_snapshot,
            mrp=(variant.mrp if variant and variant.mrp is not None else it.product.mrp),
            quantity=it.quantity,
            gst_rate=(it.product.gst_rate if it.product.gst_rate is not None else default_gst),
        )
        # Reserve stock atomically in the serving store's warehouse (holds it without
        # reducing on-hand). The reserve itself is the oversell guard — it rejects under
        # lock if availability at THAT store is short, for THAT pack.
        if it.product.stock_count is not None:
            try:
                InventoryService.reserve(
                    product=it.product, variant=variant, quantity=it.quantity,
                    warehouse=fulfil_warehouse, created_by=user,
                )
            except InventoryError as e:
                raise CheckoutError(str(e), code="INSUFFICIENT_QUANTITY")
            reserved_any = True
    if reserved_any:
        order.stock_state = Order.StockState.RESERVED
    if idempotency_key:
        order.idempotency_key = idempotency_key

    # Payment handling.
    if payment_method == Order.PaymentMethod.CREDIT:
        account = ensure_account(user)
        # Precise, actionable credit gates (the catalog drives the app's UX).
        if account.status == "frozen":
            raise CheckoutError("Your credit is temporarily frozen.", code="CREDIT_FROZEN")
        if account.status == "closed":
            raise CheckoutError("Your credit account is closed.", code="CREDIT_SUSPENDED")
        if user.kyc_status != "verified":
            raise CheckoutError(
                "Complete KYC before paying with VS Credit.", code="KYC_REQUIRED")
        if not getattr(user, "credit_enabled", False):
            raise CheckoutError(
                "Credit isn't enabled on your account.", code="CREDIT_DISABLED")
        if account.statements.filter(status="overdue").exists():
            raise CheckoutError(
                "Clear your overdue dues before a new credit order.", code="OVERDUE_PAYMENT")
        # The debt is only actually posted to the ledger once the order is
        # DELIVERED (see delivery.services.complete_delivery) — the customer
        # hasn't really used the money until the goods are in their hands, and
        # an order that's cancelled or fails delivery should never have touched
        # their credit at all. But every order still in flight toward delivery
        # is a real commitment against the limit, so it must count here too —
        # otherwise several credit orders placed back-to-back, none delivered
        # yet, could together exceed the customer's limit even though each one
        # individually looked affordable.
        pending = pending_credit_exposure(user)
        if order.total > (account.available - pending):
            raise CheckoutError(
                "This order exceeds your available credit.", code="LIMIT_EXCEEDED")
        order.credit_used = order.total
        order.payment_status = Order.PaymentStatus.PENDING  # billed on statement
        order.status = OrderStatus.CONFIRMED
        # Record the repayment plan + compute the authoritative payout date.
        order.credit_plan = credit_plan or Order.CreditPlan.WEEKEND
        order.credit_due_date = compute_payout_date(order.credit_plan)
    elif payment_method == Order.PaymentMethod.COD:
        order.payment_status = Order.PaymentStatus.PENDING
        order.status = OrderStatus.CONFIRMED
    else:  # upi / card / netbanking → client completes via /payments
        order.payment_status = Order.PaymentStatus.PENDING
        order.status = OrderStatus.PENDING
    order.save(update_fields=["credit_used", "payment_status", "status",
                              "stock_state", "idempotency_key",
                              "credit_plan", "credit_due_date"])

    OrderStatusEvent.objects.create(order=order, status=order.status, note="Order placed")
    cart.items.all().delete()

    # Zone event: this order has been routed to its serving store.
    from zones.services import emit_zone_event

    emit_zone_event(
        "order_routed", zone=zone, actor=user,
        order_code=order.code, store_id=store.id if store else None,
    )

    from notifications.services import notify, notify_store_staff
    # `route` is a PATH the app opens directly. Sending the bare "orders" list
    # plus a separate orderCode meant a tap always landed on the order list and
    # the customer had to find their own order.
    notify(user, type="order", title="Order Confirmed",
           body=f"Your order {order.code} has been placed.",
           data={"route": f"/orders/{order.code}", "orderCode": order.code,
                 "actionLabel": "Track Order"},
           dedupe_key=f"order_placed:{order.code}")
    # Tell the serving store's staff a new order has arrived to fulfil. Keyed so
    # a replayed checkout can never ring the counter twice for one order.
    notify_store_staff(store, type="order", title="New Order",
                       body=f"{order.code} · ₹{order.total}",
                       data={"route": f"/orders/{order.code}", "orderCode": order.code},
                       dedupe_key=f"new_order:{order.code}")
    # Live push to the Store panel while it's open (sound/banner is the
    # frontend's job) — deferred to commit so a WS client can't be told about
    # an order that then rolls back.
    if store is not None:
        from storeops.realtime import broadcast_new_order

        transaction.on_commit(lambda: broadcast_new_order(order))
    return order


def order_warehouse(order: Order):
    """The warehouse that holds/fulfils an order's stock = the order's serving store's
    warehouse, or None (→ InventoryService default) for legacy/global orders. This is
    the SAME warehouse the reservation was made against in `place_order`, so reserve →
    release → fulfil all act on one store's stock and never leak across stores."""
    store = getattr(order, "store", None)
    if store is not None and store.warehouse_id:
        return store.warehouse
    return None


@transaction.atomic
def fulfil_order(order: Order):
    """On delivery: convert the reservation into an actual `order` ledger movement
    (release the hold, reduce on-hand). Idempotent — only fulfils a RESERVED order."""
    if order.stock_state != Order.StockState.RESERVED:
        return order
    wh = order_warehouse(order)
    for item in order.items.select_related("product", "variant"):
        if item.product.stock_count is not None:
            InventoryService.release(
                product=item.product, variant=item.variant,
                quantity=item.quantity, warehouse=wh,
            )
            # FEFO, same as the POS sale path — an online order consumes the
            # oldest-expiring lot first, of the pack that was actually ordered.
            consume_fefo(
                product=item.product, variant=item.variant,
                type=InventoryLedger.Type.ORDER,
                quantity=item.quantity, warehouse=wh, ref_type="order", ref_id=order.code,
                note=f"Order {order.code} delivered", created_by=order.user,
                allow_negative=True,
            )
    order.stock_state = Order.StockState.FULFILLED
    order.save(update_fields=["stock_state"])
    return order


def release_reservation(order):
    """Free a reservation this order is still holding, once.

    Idempotent via ``stock_state``: a second call is a no-op, so a re-attempted
    delivery that fails again can't double-release and inflate available stock.
    """
    if order.stock_state != Order.StockState.RESERVED:
        return order
    wh = order_warehouse(order)
    for item in order.items.select_related("product", "variant"):
        # Mirrors the reserve-time condition. Note this predicate is re-evaluated
        # against the LIVE product, so an admin who clears stock_count between
        # reserve and release orphans the hold — tracked separately.
        if item.product.stock_count is not None:
            InventoryService.release(
                product=item.product, variant=item.variant,
                quantity=item.quantity, warehouse=wh,
            )
    order.stock_state = Order.StockState.RELEASED
    order.save(update_fields=["stock_state"])
    return order


def collected_amount(order) -> Decimal:
    """Money actually taken for ``order`` through a payment instrument.

    The sum of SUCCESS order-payments minus anything already refunded — NOT
    ``order.total``, which includes a VS Credit leg that is reversed in the credit
    ledger instead, and would over-refund a part-credit order.
    """
    from django.db.models import Sum

    from payments.models import Payment

    paid = Payment.objects.filter(
        order=order, purpose=Payment.Purpose.ORDER,
        status__in=[Payment.Status.SUCCESS, Payment.Status.REFUNDED],
    ).aggregate(total=Sum("amount"))["total"] or Decimal("0")
    refunded = Payment.objects.filter(
        order=order, purpose=Payment.Purpose.REFUND, status=Payment.Status.SUCCESS,
    ).aggregate(total=Sum("amount"))["total"] or Decimal("0")
    return max(paid - refunded, Decimal("0"))


@transaction.atomic
def cancel_order(order: Order, *, by=None, note=""):
    """Cancel an order and unwind stock + credit.

    ``by``/``note`` identify who cancelled it and why. They default to the
    customer-initiated case: the admin console's cancellation used to drop both,
    so every staff cancellation was written to the timeline as "Cancelled by
    customer" and the real reason (out of stock, customer unreachable) was lost.
    """
    # Lock the order row + re-read status so a double-tap / concurrent customer+admin
    # cancel can't release stock or refund credit twice, and so the whole unwind
    # (stock + credit + status + timeline) commits all-or-nothing.
    order = Order.objects.select_for_update().get(pk=order.pk)
    if order.status not in ["pending", "confirmed"]:
        raise CheckoutError(
            "This order can no longer be cancelled.", code="ORDER_NOT_CANCELLABLE")
    order.status = OrderStatus.CANCELLED
    # Unwind stock: a still-reserved order just releases the hold; an already-fulfilled
    # one (shipped) puts stock back via an `order_cancel` ledger movement. Both act on
    # the order's serving-store warehouse (same one the reservation was held against).
    wh = order_warehouse(order)
    if order.stock_state == Order.StockState.RESERVED:
        for item in order.items.select_related("product", "variant"):
            if item.product.stock_count is not None:
                InventoryService.release(
                    product=item.product, variant=item.variant,
                    quantity=item.quantity, warehouse=wh,
                )
        order.stock_state = Order.StockState.RELEASED
    elif order.stock_state == Order.StockState.FULFILLED:
        for item in order.items.select_related("product", "variant"):
            if item.product.stock_count is not None:
                # Restock the pack that left, not the product pool — otherwise a
                # cancelled 1kg order would credit stock nothing can sell.
                InventoryService.post_movement(
                    product=item.product, variant=item.variant,
                    type=InventoryLedger.Type.ORDER_CANCEL,
                    quantity=item.quantity, warehouse=wh, ref_type="order_cancel", ref_id=order.code,
                    note=f"Cancel {order.code}", created_by=order.user,
                )
        order.stock_state = Order.StockState.RELEASED
    order.save(update_fields=["status", "stock_state"])
    OrderStatusEvent.objects.create(
        order=order, status=OrderStatus.CANCELLED, by=by,
        note=note or ("Cancelled by staff" if by is not None else "Cancelled by customer"),
    )
    # Hand the coupon back — a cancelled order must not consume a single-use code
    # (worst on the abandoned-payment path, where checkout never even completed).
    try:
        from offers.services import release_coupon

        release_coupon(order.code)
    except Exception:  # noqa: BLE001 — never block an unwind on coupon bookkeeping
        pass

    # NOTE: no credit reversal here. A credit charge is only ever POSTED to the
    # ledger once an order is actually delivered (`delivery.services.
    # complete_delivery`), and this function only ever runs on a still
    # pending/confirmed order (the status check above) — i.e. always BEFORE
    # that could have happened. There is nothing to reverse.

    # Give back money taken on a real instrument. ONLY the credit leg above was
    # ever reversed here, so a customer who paid ₹2,000 by UPI and cancelled a
    # confirmed order had the order cancelled, the stock returned — and the money
    # kept, with `payment_status` still reading "paid". `refund_payment` has
    # existed the whole time; nothing outside the returns flow called it.
    #
    # Deliberately the LAST step: it talks to the gateway inside this transaction,
    # so nothing may follow it that could roll back a refund the gateway has
    # already executed.
    _refund_cancelled_order(order)
    return order


def _refund_cancelled_order(order):
    """Refund whatever was collected for a cancelled order, once."""
    collected = collected_amount(order)
    if collected <= 0:
        return None
    from payments.services import refund_payment

    # Keyed on the order code so a concurrent customer+admin cancel, or a retry of
    # the expiry cron, settles to a single refund.
    refund = refund_payment(
        order, collected,
        reason=f"Order {order.code} cancelled",
        idempotency_key=f"cancel_{order.code}",
    )
    order.payment_status = Order.PaymentStatus.REFUNDED
    order.save(update_fields=["payment_status"])
    return refund


@transaction.atomic
def advance_status(order: Order, status: str, by=None, note=""):
    """Move an order to ``status``, refusing illegal moves.

    This used to assign and save whatever it was handed. With no check, the agent
    delivery endpoint could mark a CANCELLED or never-paid order "delivered" —
    which fulfilled its stock and awarded loyalty points for goods nobody bought.

    Atomic because the status write, its timeline event and the delivered-side
    effects (fulfilment, loyalty) must not land half-applied: an order committed as
    "delivered" whose `fulfil_order` then failed was permanently delivered with its
    stock still merely RESERVED, and nothing re-attempts it.
    """
    order = Order.objects.select_for_update().get(pk=order.pk)
    if order.status == status:
        return order  # idempotent: a retried tap or duplicate event
    if not can_transition(order.status, status):
        raise CheckoutError(
            f"An order that is {order.status.replace('_', ' ')} cannot become "
            f"{status.replace('_', ' ')}.",
            code="ORDER_STATUS_INVALID",
        )
    order.status = status
    order.save(update_fields=["status"])
    OrderStatusEvent.objects.create(order=order, status=status, by=by, note=note)
    # Dispatch the moment an order is ready. The ENGINE (batching + route +
    # scoring) is the real path: it used to be starved to death right here —
    # this hook fired the legacy single-task auto_assign instantly, so by the
    # time the engine's cron looked for ready orders WITHOUT active tasks there
    # were never any. Zero batches ever, and the whole dispatch board sat dead.
    # Now the engine runs first (event-driven — no waiting for the 2-minute
    # tick); the legacy path remains only as the fallback for an order the
    # engine cannot see (no store) or could not place.
    if status == OrderStatus.READY_FOR_DISPATCH:
        try:
            active = ["assigned", "accepted", "picked_up", "out_for_delivery", "reached"]
            if not order.delivery_tasks.filter(status__in=active).exists():
                if order.store_id:
                    from delivery import assignment_engine

                    assignment_engine.run_auto_assign(order.store, by=by)
                if not order.delivery_tasks.filter(status__in=active).exists():
                    from delivery.services import auto_assign

                    auto_assign(order, by=by)
        except Exception:  # noqa: BLE001 — never block the order transition on assignment
            pass
    # Release a still-held reservation when the order ends WITHOUT being delivered.
    # Only `cancel_order` ever released stock, and it refuses anything outside
    # pending/confirmed — so `failed_delivery` and `rejected` left their units held
    # forever with no reachable path to free them, permanently shrinking sellable
    # stock at that store, one failed delivery at a time.
    if status in (OrderStatus.FAILED_DELIVERY, OrderStatus.REJECTED):
        release_reservation(order)
    if status == OrderStatus.REJECTED:
        # A rejection is the store refusing to fulfil, so the customer must be
        # made whole exactly as a cancellation makes them whole. Only the stock
        # was being released: a prepaid order that the store rejected kept the
        # customer's money (payment_status still "paid") and burned their
        # single-use coupon. `cancel_order` has always done both; nothing on the
        # rejection path did either.
        try:
            from offers.services import release_coupon

            release_coupon(order.code)
        except Exception:  # noqa: BLE001 — never block the unwind on coupon bookkeeping
            pass
        # Last, like the cancel path: it calls the gateway, so nothing that
        # could roll back may follow a refund the gateway has already executed.
        _refund_cancelled_order(order)
    if status == OrderStatus.DELIVERED:
        fulfil_order(order)
        # A credit order's debt is only posted to the ledger NOW — the customer
        # hasn't really used the money until the goods are actually in their
        # hands (`pending_credit_exposure` is what protects the limit before
        # this point; `cancel_order` never reaches here, so there's nothing to
        # double-post). Not fail-soft: unlike loyalty/referrals below, silently
        # swallowing this would deliver real goods with no debt on the books.
        if order.payment_method == Order.PaymentMethod.CREDIT and order.credit_used > 0:
            from credit.services import capture_purchase

            capture_purchase(ensure_account(order.user), order.credit_used,
                             order=order, note=f"Order {order.code}")
        # Issue the invoice row — but only once the order is PAID. A tax invoice
        # for money never received is wrong paper: COD orders invoice when the
        # agent confirms the cash (finalize_payment hooks the delivered+paid
        # case), prepaid ones invoice right here.
        if order.payment_status == "paid":
            try:
                from billing.services import invoice_for_order

                invoice_for_order(order)
            except Exception:  # noqa: BLE001
                pass
        # Award loyalty points on delivery (fail-soft — never block fulfilment).
        try:
            from loyalty.services import earn_for_order

            # Earn at the SERVING ZONE's rate — the order carries the zone it was
            # routed through, so a zone promo pays out even if the zone's rate is
            # changed afterwards for new orders.
            earn_for_order(order.user, order.total, order.code, zone=order.zone)
        except Exception:  # noqa: BLE001
            pass
        # Pay out a pending referral. Delivery — not code entry — is what earns
        # it, so the scheme can't be farmed by creating accounts. Idempotent, so
        # a replayed delivery can't mint a second pair of vouchers. Fail-soft:
        # a reward is never worth failing a fulfilment over.
        try:
            from referrals.services import complete_for_order

            complete_for_order(order)
        except Exception:  # noqa: BLE001
            pass
    from notifications.services import notify
    label = status.replace("_", " ").title()
    is_delivery = status in (OrderStatus.OUT_FOR_DELIVERY, OrderStatus.DELIVERED)
    notify(order.user, type="delivery" if is_delivery else "order",
           title=f"Order {label}",
           body=f"Your order {order.code} is now {status.replace('_', ' ')}.",
           data={"route": f"/orders/{order.code}", "orderCode": order.code},
           # One notification per (order, status). `advance_status` already
           # returns early on a no-op, but an order that legitimately revisits a
           # status — failed_delivery → out_for_delivery on a re-attempt — must
           # not re-announce a state the customer was already told about.
           dedupe_key=f"order_status:{order.code}:{status}")
    return order


def release_expired_reservations(ttl_minutes=None):
    """Auto-release stock held by abandoned (unpaid) orders: cancel PENDING-payment
    orders whose reservation has outlived the TTL, returning their held stock to the
    pool. Run periodically (cron / Celery beat). Returns the cancelled order codes."""
    from django.conf import settings

    ttl = ttl_minutes if ttl_minutes is not None else getattr(
        settings, "RESERVATION_TTL_MINUTES", 30
    )
    deadline = timezone.now() - timezone.timedelta(minutes=ttl)
    stale = Order.objects.filter(
        status=OrderStatus.PENDING,
        stock_state=Order.StockState.RESERVED,
        placed_at__lt=deadline,
    )
    from payments.services import (
        has_inflight_gateway_payment,
        reconcile_pending_payments,
    )

    # Ask the gateway about anything we never heard back on BEFORE cancelling.
    # Without this the job cancelled orders whose money had already been captured
    # (app killed before the callback, webhook never landed) — the customer was
    # charged for an order that no longer existed.
    try:
        reconcile_pending_payments(older_than_minutes=min(ttl, 10))
    except Exception:  # noqa: BLE001 — reconciliation is best-effort
        pass

    cancelled = []
    for order in stale:
        order.refresh_from_db()
        if order.status != OrderStatus.PENDING:
            continue  # reconciliation settled it
        if has_inflight_gateway_payment(order):
            # Still unresolved at the gateway: leave the stock held rather than
            # cancel an order that may turn out to be paid.
            continue
        try:
            cancel_order(order)
            cancelled.append(order.code)
        except CheckoutError:
            continue
    return cancelled


# ── Reorder ──────────────────────────────────────────────
#: Why a past order line can't be put back in the cart.
REORDER_DISCONTINUED = "discontinued"   # product delisted, or the pack was removed
REORDER_OUT_OF_STOCK = "out_of_stock"   # still sold, just not right now


def reorder_plan(order, user):
    """What re-adding ``order``'s lines to ``user``'s cart would do — WITHOUT doing it.

    Drives both the customer's "review before adding" sheet and the commit below, so
    the two can't disagree about what is available.

    Each returned line carries the ORIGINAL pack (``variant``). Reorder used to pass
    ``variant=None``, which silently swapped a 5 kg pack for the base product: a
    different SKU at a different price, drawn from a different stock pool. The
    customer tapped "Reorder" and got something they hadn't ordered.

    Price is re-read live rather than reused from the order, because a past line's
    price is historical — showing it would promise a total the cart won't honour.
    """
    from decimal import Decimal as _D

    from inventory.services import StockCalculationService
    from stores.services import resolve_user_store, store_price, store_pricing_enabled

    store = resolve_user_store(user)
    warehouse = getattr(store, "warehouse", None)
    pricing = store_pricing_enabled()

    lines = []
    for item in order.items.select_related("product", "variant"):
        product = item.product
        variant = item.variant
        name = item.name or (product.name if product else "")
        if variant is not None:
            name = f"{name} · {variant.label}"

        if product is None or not product.is_active:
            lines.append({
                "product": None, "variant": None, "name": name,
                "quantity": item.quantity, "price": None, "mrp": None,
                "available": False, "reason": REORDER_DISCONTINUED,
            })
            continue

        if warehouse is not None:
            on_hand = StockCalculationService.available(product, warehouse, variant)
            in_stock = on_hand is None or on_hand >= item.quantity
        else:
            # No serving store resolved — fall back to the flag, same as /cart/validate.
            in_stock = variant.in_stock if variant is not None else product.in_stock

        base = store_price(product, store) if pricing else product.price
        price = base + (variant.price_delta if variant is not None else _D("0"))
        # A variant carries its own MRP when the pack is priced separately; fall
        # back to the product's so the strike-through price is never blank.
        mrp = (variant.mrp if variant is not None and variant.mrp is not None
               else product.mrp)

        lines.append({
            "product": product, "variant": variant, "name": name,
            "quantity": item.quantity, "price": price, "mrp": mrp,
            "available": bool(in_stock),
            "reason": "" if in_stock else REORDER_OUT_OF_STOCK,
        })
    return lines


@transaction.atomic
def reorder_into_cart(order, user):
    """Add every still-available line of ``order`` to ``user``'s cart.

    Returns ``(cart, lines)`` — ``lines`` is the full plan including the ones that
    could NOT be added, so the caller can tell the customer what was left out.
    Silently dropping them (the old behaviour) meant a five-item reorder could put
    two items in the cart with no explanation.
    """
    from cart.serializers import MAX_LINE_QUANTITY

    cart = get_cart(user)
    lines = reorder_plan(order, user)
    for line in lines:
        if not line["available"]:
            continue
        existing = cart.items.filter(
            product=line["product"], variant=line["variant"]
        ).first()
        base_qty = existing.quantity if existing else 0
        # Reorder ACCUMULATES onto whatever is already in the cart, and the per-line
        # ceiling has to hold on the merged total.
        quantity = min(base_qty + line["quantity"], MAX_LINE_QUANTITY)
        upsert_item(cart, line["product"], line["variant"], quantity)
    return cart, lines
