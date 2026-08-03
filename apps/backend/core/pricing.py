"""Server-side bill computation — the single source of truth for money on a cart
or order. Reads the superadmin-controlled PlatformConfig (DB), applies the platform
fee, and honours per-zone fee overrides. Never trust client totals."""
from decimal import ROUND_HALF_UP, Decimal


def q(amount) -> Decimal:
    """Quantize to 2 decimal places (half-up)."""
    return Decimal(amount).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _platform_fee(cfg, fee_value, subtotal) -> Decimal:
    if subtotal <= 0:
        return Decimal("0.00")
    if cfg.platform_fee_type == "percent":
        fee = subtotal * Decimal(fee_value) / Decimal("100")
        if cfg.platform_fee_cap is not None:
            fee = min(fee, cfg.platform_fee_cap)
    else:
        fee = Decimal(fee_value)
    return q(fee)


def compute_bill(subtotal, savings=0, coupon_discount=0, zone=None) -> dict:
    """Full bill breakdown. `zone` (optional) overrides delivery/threshold/platform
    fee; otherwise platform defaults apply."""
    from siteconfig.models import PlatformConfig
    from zones.services import effective_fees

    cfg = PlatformConfig.load()
    fees = effective_fees(zone)  # resolves zone overrides ↔ config defaults

    subtotal = q(subtotal)
    gst = q(subtotal * cfg.gst_rate)
    free_threshold = Decimal(fees["free_delivery_threshold"])
    delivery = (
        Decimal("0.00")
        if (subtotal <= 0 or subtotal >= free_threshold)
        else q(fees["delivery_fee"])
    )
    base_platform = _platform_fee(cfg, fees["platform_fee_value"], subtotal)

    # Dynamic fees (default 0). small-cart only below the threshold; handling is flat;
    # surge applies while surge_active is on. Folded into platform_fee so the order
    # total stays consistent, and returned itemized for transparent cart display.
    has_items = subtotal > 0
    threshold = Decimal(cfg.small_cart_threshold or 0)
    small_cart = (
        q(cfg.small_cart_fee)
        if (has_items and threshold > 0 and subtotal < threshold)
        else Decimal("0.00")
    )
    handling = q(cfg.handling_fee) if has_items else Decimal("0.00")
    surge = q(cfg.surge_fee) if (has_items and cfg.surge_active) else Decimal("0.00")

    platform_fee = q(base_platform + small_cart + handling + surge)
    discount = q(coupon_discount)
    total = q(subtotal + delivery + gst + platform_fee - discount)
    return {
        "subtotal": subtotal,
        "savings": q(savings),
        "delivery_fee": delivery,
        "gst": gst,
        "platform_fee": platform_fee,
        "small_cart_fee": small_cart,
        "handling_fee": handling,
        "surge_fee": surge,
        "coupon_discount": discount,
        "total": max(total, Decimal("0.00")),
        "min_order": q(fees["min_order"]),
    }
