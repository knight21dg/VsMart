"""Loyalty / reward-points operations. Every points change goes through `post`
and writes an append-only ledger entry inside a DB transaction. The balance is
derived from the ledger (SUM of signed points)."""
import secrets
from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from core.app_errors import AppError

from .models import PointsLedgerEntry

#: Points needed per ₹1 of reward. Earning is 1 point per ₹10 spent
#: (`earn_for_order`), so 10 points ≈ ₹1 back ≈ 1% back.
POINTS_PER_RUPEE = 10
#: Don't mint a coupon worth less than this — a ₹1 voucher is noise.
MIN_REDEEM_POINTS = POINTS_PER_RUPEE * 10          # ₹10
#: How long an issued reward voucher stays usable.
REWARD_VALID_DAYS = 90


def _balance(user) -> int:
    """Current points balance = sum of signed points across the ledger."""
    return PointsLedgerEntry.objects.filter(user=user).aggregate(
        s=Sum("points")
    )["s"] or 0


@transaction.atomic
def post(user, type, points, note="", ref_type="", ref_id="") -> PointsLedgerEntry:
    """Append a points ledger entry. `points` is signed by caller intent
    (earn +, redeem -). `balance_after` is the running balance after this entry."""
    points = int(points)
    balance_after = _balance(user) + points
    return PointsLedgerEntry.objects.create(
        user=user,
        type=type,
        points=points,
        balance_after=balance_after,
        note=note,
        ref_type=ref_type,
        ref_id=ref_id,
    )


def points_rate(zone=None) -> int:
    """Points granted per ₹100 spent, for `zone` (or the platform default).

    Resolves exactly like the zone fee overrides: a zone value wins, null falls
    back to PlatformConfig. Kept as a separate lookup rather than folded into
    ``zones.services.effective_fees`` because this is not a fee — it costs the
    business margin rather than charging the customer.
    """
    from siteconfig.models import PlatformConfig

    zone_rate = getattr(zone, "loyalty_points_per_100", None) if zone else None
    if zone_rate is not None:
        return int(zone_rate)
    return int(PlatformConfig.load().loyalty_points_per_100)


def earn_for_order(user, order_total, order_code, zone=None) -> PointsLedgerEntry:
    """Award loyalty points for a delivered order at the serving zone's rate.

    The rate used to be hardcoded (``order_total // 10``), so every area earned the
    same regardless of the zone's economics and a launch promo could not be run
    without a deploy. ``points_rate`` resolves the zone override, defaulting to the
    old 1-point-per-₹10 so existing behaviour is unchanged.
    """
    rate = points_rate(zone)
    # Floor: never round a customer UP into points the basket didn't earn.
    points = int(Decimal(order_total) * Decimal(rate) / Decimal("100"))
    note = f"Earned on order {order_code}"
    if zone is not None and getattr(zone, "loyalty_points_per_100", None) is not None:
        note = f"{note} ({zone.name} rate)"
    return post(
        user,
        type=PointsLedgerEntry.Type.EARN,
        points=points,
        note=note,
        ref_type="order",
        ref_id=order_code,
    )


def tier(lifetime_earned: int) -> str:
    """Membership tier from lifetime points earned."""
    if lifetime_earned >= 5000:
        return "Gold"
    if lifetime_earned >= 1000:
        return "Silver"
    return "Bronze"


def _reward_code() -> str:
    """Unguessable personal voucher code. Not derived from the user id, so one
    customer's code says nothing about anyone else's."""
    return f"VSR{secrets.token_hex(4).upper()}"


@transaction.atomic
def redeem_to_voucher(user, points):
    """Burn `points` and issue a personal, single-use coupon worth the equivalent.

    Redemption used to deduct points and create **nothing** — the ledger said
    "Redeemed to wallet" but no wallet exists, so customers lost the points and
    received no value, irreversibly (the ledger is append-only). This converts
    them into a real, spendable voucher instead.

    Both halves happen in one transaction: points are never burned without a
    voucher, and no voucher exists without the points being paid for.
    """
    from offers.models import Coupon

    points = int(points or 0)
    if points < MIN_REDEEM_POINTS:
        raise AppError(
            "INSUFFICIENT_POINTS",
            message=f"Redeem at least {MIN_REDEEM_POINTS} points "
                    f"(₹{MIN_REDEEM_POINTS // POINTS_PER_RUPEE}).",
        )
    # Only whole rupees are redeemable; the remainder stays on the balance
    # rather than silently evaporating.
    rupees = points // POINTS_PER_RUPEE
    spend = rupees * POINTS_PER_RUPEE

    if spend > _balance(user):
        raise AppError("INSUFFICIENT_POINTS")

    coupon = Coupon.objects.create(
        code=_reward_code(),
        owner=user,                      # personal — useless to anyone else
        discount_type=Coupon.DiscountType.FLAT,
        value=Decimal(rupees),
        usage_limit=1,
        per_user_limit=1,
        valid_to=(timezone.now() + timedelta(days=REWARD_VALID_DAYS)).date(),
        is_active=True,
    )
    entry = post(
        user,
        type=PointsLedgerEntry.Type.REDEEM,
        points=-spend,
        note=f"Redeemed for ₹{rupees} voucher {coupon.code}",
        ref_type="coupon",
        ref_id=str(coupon.id),
    )
    return coupon, entry
