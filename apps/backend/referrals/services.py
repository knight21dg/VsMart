"""Referrals that actually reward someone.

`ReferralApplyView` used to mark a referral COMPLETED the moment a code was
typed and return `{"reward": 100}` — while crediting **nobody**. No coupon, no
points, no credit; the `reward` column was a number sitting on a row. A customer
was told they'd earned ₹100 and got nothing, and the referrer never heard about
it at all.

It also completed on code entry, before the referee had bought anything, so the
scheme could be farmed by creating accounts and typing codes.

The rules now:

* Applying a code **links** referrer→referee and stays PENDING.
* The referral **completes on the referee's first delivered order**, and only
  then does anyone get paid.
* Payment is a personal, single-use voucher for each side — the same mechanism
  loyalty redemption uses, so a referral reward can't be shared or resold.
"""
import secrets
from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from core.app_errors import AppError
from offers.models import Coupon

from .models import Referral

#: How long a referral voucher stays usable.
REWARD_VALID_DAYS = 90


def _voucher_code():
    """Unguessable personal code — never a guessable sequence."""
    for _ in range(10):
        code = f"REF{secrets.token_hex(3).upper()}"
        if not Coupon.objects.filter(code=code).exists():
            return code
    raise AppError("SYSTEM_ERROR", message="Couldn't mint a referral voucher.")


def _mint_voucher(user, amount, *, note):
    """A personal, single-use voucher. Worthless to anyone but `user`."""
    return Coupon.objects.create(
        code=_voucher_code(),
        owner=user,
        discount_type=Coupon.DiscountType.FLAT,
        value=Decimal(str(amount)),
        usage_limit=1,
        per_user_limit=1,
        valid_to=(timezone.now() + timedelta(days=REWARD_VALID_DAYS)).date(),
        is_active=True,
    )


def generate_code(user):
    """Stable, unique referral code for a user (e.g. VS00042)."""
    base = f"VS{user.id:05d}"
    code, suffix = base, 1
    while Referral.objects.filter(code=code).exists():
        code = f"{base}{suffix}"
        suffix += 1
    return code


def my_referral(user):
    """The user's own shareable referral row, created on first view."""
    referral = Referral.objects.filter(referrer=user, referee__isnull=True).first()
    if referral is None:
        referral = Referral.objects.filter(referrer=user).first()
    if referral is None:
        referral = Referral.objects.create(referrer=user, code=generate_code(user))
    return referral


@transaction.atomic
def apply_code(user, code):
    """Link this customer to whoever referred them. Pays nothing yet.

    The reward lands when they actually order — see `complete_for_order`.
    """
    code = (code or "").strip().upper()
    if not code:
        raise AppError("REFERRAL_INVALID")

    if Referral.objects.filter(referee=user).exists():
        raise AppError("REFERRAL_ALREADY_APPLIED")

    source = (
        Referral.objects.select_for_update()
        .filter(code__iexact=code)
        .exclude(referrer=user)          # can't refer yourself
        .first()
    )
    if source is None:
        raise AppError("REFERRAL_INVALID")

    # One row per referred customer, so several people can use the same code.
    return Referral.objects.create(
        referrer=source.referrer,
        referee=user,
        code=generate_code(user),
        reward=source.reward,
        status=Referral.Status.PENDING,
    )


@transaction.atomic
def complete_for_order(order):
    """Pay out a referral once the referee's first order is delivered.

    Idempotent — a referral already COMPLETED is left alone, so re-delivering or
    replaying an order can't mint a second pair of vouchers.
    """
    user = order.user
    referral = (
        Referral.objects.select_for_update()
        .filter(referee=user, status=Referral.Status.PENDING)
        .first()
    )
    if referral is None:
        return None            # not referred, or already paid

    amount = referral.reward or Decimal("0")
    if amount <= 0:
        referral.status = Referral.Status.COMPLETED
        referral.save(update_fields=["status", "updated_at"])
        return referral

    referrer_voucher = _mint_voucher(
        referral.referrer, amount,
        note=f"Referral reward for inviting {user.phone}",
    )
    referee_voucher = _mint_voucher(
        user, amount, note="Welcome reward for joining via a referral",
    )

    referral.status = Referral.Status.COMPLETED
    referral.save(update_fields=["status", "updated_at"])

    # Tell them. Never let a messaging failure undo the payout.
    try:
        from notifications.services import notify

        notify(referral.referrer, type="promo",
               title="Your referral paid off",
               body=f"You've earned a ₹{amount:.0f} voucher — code "
                    f"{referrer_voucher.code}.",
               data={"route": "coupons"})
        notify(user, type="promo",
               title="Welcome reward unlocked",
               body=f"Your ₹{amount:.0f} voucher {referee_voucher.code} is ready.",
               data={"route": "coupons"})
    except Exception:  # noqa: BLE001 — payout already committed
        pass

    return referral
