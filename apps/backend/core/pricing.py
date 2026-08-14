"""Server-side bill computation — the single source of truth for money on a cart
or order. Reads the superadmin-controlled PlatformConfig (DB), applies the platform
fee, and honours per-zone fee overrides. Never trust client totals."""
from decimal import ROUND_HALF_UP, Decimal


def q(amount) -> Decimal:
    """Quantize to 2 decimal places (half-up)."""
    return Decimal(amount).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


# ── GST units ────────────────────────────────────────────
# There is exactly ONE rule: **the API and the operator always speak percentages
# (18), the pricing maths always uses fractions (0.18).** Nothing else in the
# codebase may convert between them — call the helpers below.
#
# This exists because the two conventions used to be mixed silently. The admin
# product form was labelled "GST rate (0–1)" and stored 0.18 into a column that
# `OrderItem.gst_rate` documents as a percentage, so a line's recorded tax rate
# was 0.18% where the operator meant 18%. Nothing read the column yet, which is
# the only reason it never reached an invoice.
#
# The statutory Indian GST slabs. An arbitrary rate is almost always a typo (a
# "1.8" meant as 18, a "0.18" meant as 18%), so the API refuses anything else.
GST_SLABS = (
    Decimal("0"), Decimal("0.25"), Decimal("3"), Decimal("5"),
    Decimal("12"), Decimal("18"), Decimal("28"),
)


def gst_pct_to_fraction(pct) -> Decimal:
    """18 → 0.18. The form the pricing maths multiplies by."""
    return (Decimal(str(pct)) / Decimal("100")).quantize(
        Decimal("0.0001"), rounding=ROUND_HALF_UP
    )


def gst_fraction_to_pct(fraction) -> Decimal:
    """0.18 → 18. The form the API and every human being uses."""
    return (Decimal(str(fraction)) * Decimal("100")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )


def gst_slab_error(rate) -> str:
    """The message shown when a GST value isn't a real slab.

    Shared by the product and platform-settings serializers so the operator gets
    the same wording (and the same "you meant a percentage" nudge) wherever they
    mistype it. `_trim` keeps 18 as "18" rather than "18.00" — the hint has to
    read like the number they should type.
    """
    def _trim(d):
        d = Decimal(str(d))
        return f"{d.normalize():f}" if d == d.to_integral_value() else f"{d.normalize():f}"

    slabs = ", ".join(f"{_trim(s)}%" for s in GST_SLABS)
    rate = Decimal(str(rate))
    hint = ""
    if 0 < rate < 1:
        as_pct = _trim(gst_fraction_to_pct(rate))
        hint = f" Enter {as_pct} for {as_pct}%, not {_trim(rate)}."
    return f"GST must be one of the standard slabs: {slabs}.{hint}"


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
    # What the delivery WOULD have cost when it is being waived. The customer app
    # showed a hardcoded "₹45" struck through next to "FREE", which is a claim about
    # the saving that had no connection to the zone's actual fee — a zone charging
    # ₹30 or ₹60 still advertised ₹45. The server knows the real number, so it sends
    # it rather than letting the client invent one.
    delivery_waived = (
        q(fees["delivery_fee"]) if (delivery == 0 and subtotal > 0) else Decimal("0.00")
    )
    return {
        "subtotal": subtotal,
        "savings": q(savings),
        "delivery_fee": delivery,
        "delivery_fee_waived": delivery_waived,
        "gst": gst,
        "platform_fee": platform_fee,
        "small_cart_fee": small_cart,
        "handling_fee": handling,
        "surge_fee": surge,
        "coupon_discount": discount,
        "total": max(total, Decimal("0.00")),
        "min_order": q(fees["min_order"]),
    }
