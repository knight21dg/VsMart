"""Coupon resolution — the single source of truth for coupon discounts, shared by
the `/coupons/validate` preview and order checkout so the previewed discount and the
charged discount always agree."""
import uuid
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from .models import Coupon, CouponRedemption

ZERO = Decimal("0.00")


class CouponError(Exception):
    """A coupon could not be applied/redeemed. Carries a catalog `code` so the
    checkout surfaces an actionable message (expired / limit reached / already used)."""

    def __init__(self, message, *, code="COUPON_INVALID"):
        super().__init__(message)
        self.code = code


def _coupon_expired(coupon) -> bool:
    return coupon.valid_to is not None and timezone.localdate() > coupon.valid_to


def _safe_uuid(value):
    """Parse a client-supplied click_id into a valid UUID string, or None.
    Prevents a malformed string from raising a Django ValidationError inside
    bulk_create (which would 500 the public events endpoint and drop the batch)."""
    if not value:
        return None
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, TypeError, AttributeError):
        return None


def _limit_message(coupon, user):
    """Why this coupon can't be used any more, or None if it still can.

    Shared by the preview (`resolve_coupon`) and the authoritative, row-locked
    redemption (`redeem_coupon`) so the two can never disagree — a coupon that
    previews as valid must actually be redeemable.
    """
    if coupon.usage_limit is not None and (
        CouponRedemption.objects.filter(coupon=coupon).count() >= coupon.usage_limit
    ):
        return "This coupon has reached its usage limit"
    if user is not None and coupon.per_user_limit is not None and (
        CouponRedemption.objects.filter(coupon=coupon, user=user).count()
        >= coupon.per_user_limit
    ):
        return "You've already used this coupon"
    return None


def resolve_coupon(code, cart_total, user=None):
    """Resolve a coupon code against a cart total.

    Returns ``(coupon, discount, message)`` where ``coupon`` is None when the code is
    invalid/ineligible. ``discount`` is a Decimal, never exceeding ``cart_total``.

    ``user`` is required to redeem a **personal** coupon (one with an ``owner`` —
    e.g. issued from loyalty points). Personal codes are rejected for everyone
    else, so a leaked code is worthless to a stranger.
    """
    code = (code or "").strip()
    try:
        cart_total = Decimal(str(cart_total))
    except (TypeError, ValueError):
        cart_total = ZERO

    if not code:
        return None, ZERO, "No coupon code"

    coupon = Coupon.objects.filter(code__iexact=code, is_active=True).first()
    if not coupon:
        return None, ZERO, "Invalid coupon code"

    if _coupon_expired(coupon):
        return None, ZERO, "This coupon has expired"

    # A personal coupon is only valid for the customer it was issued to. Report
    # it as invalid rather than "not yours" so the code can't be probed.
    if coupon.owner_id is not None:
        uid = getattr(user, "id", None)
        if uid is None or coupon.owner_id != uid:
            return None, ZERO, "Invalid coupon code"

    if coupon.min_order is not None and cart_total < coupon.min_order:
        return None, ZERO, f"Minimum order of {coupon.min_order} required"

    # Usage caps, same as `redeem_coupon` enforces at checkout. Without this the
    # preview happily said "Applied — ₹100 off" for a coupon that was already
    # spent, and the customer only found out when placing the order blew up.
    # (Unlocked count: this is a preview. `redeem_coupon` re-checks under a row
    # lock, and that remains the authority.)
    exhausted = _limit_message(coupon, user)
    if exhausted is not None:
        return None, ZERO, exhausted

    if coupon.discount_type == Coupon.DiscountType.FLAT:
        discount = coupon.value
    else:
        discount = cart_total * coupon.value / Decimal("100")
        if coupon.max_discount is not None:
            discount = min(discount, coupon.max_discount)

    discount = max(ZERO, min(discount, cart_total)).quantize(Decimal("0.01"))
    return coupon, discount, "Applied"


def coupon_discount(code, cart_total, user=None):
    """Just the discount amount (Decimal) for a code+total — 0 when not applicable."""
    _, discount, _ = resolve_coupon(code, cart_total, user=user)
    return discount


@transaction.atomic
def release_coupon(order_code):
    """Give a coupon back when its order never completed.

    Redemptions are the ONLY record `redeem_coupon` counts against `usage_limit`
    and `per_user_limit`, and nothing ever deleted them — so a single-use coupon
    was burned permanently by a cancelled order, including one auto-cancelled by
    the reservation-expiry job because the customer simply abandoned the payment
    sheet. Retrying then failed with "already used" for an order that never
    existed.

    Returns the number of redemptions released.
    """
    if not order_code:
        return 0
    deleted, _ = CouponRedemption.objects.filter(order_code=order_code).delete()
    return deleted


def redeem_coupon(code, user, *, order_code, amount):
    """Record one coupon redemption, enforcing expiry + global `usage_limit` +
    `per_user_limit` under a row lock so concurrent checkouts can't exceed the cap.

    Locks the Coupon row (`select_for_update`) and counts committed redemptions
    inside the lock — two simultaneous redemptions of the same coupon serialise, so
    the second sees the first and is rejected. Raises `CouponError`. Call from inside
    the order's atomic block so a rejection rolls the whole checkout back.
    """
    code = (code or "").strip()
    if not code:
        return None
    coupon = (
        Coupon.objects.select_for_update()
        .filter(code__iexact=code, is_active=True)
        .first()
    )
    if coupon is None:
        raise CouponError("This coupon isn't valid.", code="COUPON_INVALID")
    if _coupon_expired(coupon):
        raise CouponError("This coupon has expired.", code="COUPON_EXPIRED")
    # A personal coupon belongs to exactly one customer. `resolve_coupon` already
    # refuses it at preview; re-check here so a crafted checkout can't skip the
    # preview and spend someone else's voucher.
    if coupon.owner_id is not None and coupon.owner_id != getattr(user, "id", None):
        raise CouponError("This coupon isn't valid.", code="COUPON_INVALID")

    # Same caps the preview reports, re-counted here INSIDE the row lock — two
    # concurrent checkouts serialise, so the second sees the first.
    if coupon.usage_limit is not None and (
        CouponRedemption.objects.filter(coupon=coupon).count() >= coupon.usage_limit
    ):
        raise CouponError("This coupon has reached its usage limit.",
                          code="COUPON_LIMIT_REACHED")
    if coupon.per_user_limit is not None and (
        CouponRedemption.objects.filter(coupon=coupon, user=user).count()
        >= coupon.per_user_limit
    ):
        raise CouponError("You've already used this coupon.",
                          code="COUPON_ALREADY_USED")
    return CouponRedemption.objects.create(
        coupon=coupon, user=user, order_code=order_code, amount=amount,
    )


# ── Banner v1.0 ──────────────────────────────────────────────────────────────

def resolve_request_zone_store(request):
    """Resolve ``(zone, store)`` for a public banner request — SERVER-SIDE.

    Mirrors the catalog store resolution: device ``lat``/``lng``/``pincode`` query
    params first, then the authenticated user's saved address. A client-supplied store
    id is never trusted to *widen* targeting; banners only narrow to the resolved
    store/zone, falling back to global when nothing resolves (e.g. a guest with no
    location). Returns ``(zone_or_None, store_or_None)``.
    """
    from zones.serviceability import resolve_serviceable_zone

    qp = getattr(request, "query_params", None) or {}
    lat, lng, pincode = qp.get("lat"), qp.get("lng"), qp.get("pincode")

    zone = None
    if lat or lng or pincode:
        zone = resolve_serviceable_zone(lat=lat, lng=lng, pincode=pincode)
    if zone is None:
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
    store = getattr(zone, "store", None) if zone is not None else None
    return zone, store


def record_banner_events(events, *, user=None, store=None, zone=None):
    """Ingest app-reported banner events ``[{offer_id, kind, click_id?}, ...]``.

    Bulk-inserts ``BannerEvent`` rows (source of truth) and bumps the denormalized
    impression/click counters on Offer. Unknown offers/kinds are skipped silently so a
    noisy client can never error the call. Returns the number of events stored.
    """
    from collections import Counter

    from django.db.models import F

    from .models import BannerEvent, Offer

    if not isinstance(events, list):
        return 0
    events = events[:500]  # cap batch size — public endpoint, prevent bulk-insert abuse
    valid_kinds = set(BannerEvent.Kind.values)
    user = user if (user is not None and getattr(user, "is_authenticated", False)) else None

    wanted = set()
    for e in events:
        try:
            wanted.add(int(e.get("offer_id")))
        except (TypeError, ValueError, AttributeError):
            continue
    existing = set(Offer.objects.filter(id__in=wanted).values_list("id", flat=True))

    rows, imp, clk = [], Counter(), Counter()
    for e in events:
        try:
            oid = int(e.get("offer_id"))
        except (TypeError, ValueError, AttributeError):
            continue
        kind = e.get("kind")
        if oid not in existing or kind not in valid_kinds:
            continue
        rows.append(BannerEvent(
            offer_id=oid, kind=kind, user=user, store=store, zone=zone,
            click_id=_safe_uuid(e.get("click_id")),
        ))
        if kind == "impression":
            imp[oid] += 1
        elif kind == "click":
            clk[oid] += 1

    if rows:
        BannerEvent.objects.bulk_create(rows, batch_size=500)
    for oid, n in imp.items():
        Offer.objects.filter(id=oid).update(impressions=F("impressions") + n)
    for oid, n in clk.items():
        Offer.objects.filter(id=oid).update(clicks=F("clicks") + n)
    return len(rows)
