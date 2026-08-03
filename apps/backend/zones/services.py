import math

from .models import Zone


def haversine_km(lat1, lng1, lat2, lng2) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return r * 2 * math.asin(math.sqrt(a))


def resolve_zone(lat=None, lng=None, pincode=None):
    """Return the serviceable Zone for a point/pincode, or None if unserviceable.
    Pincode match wins; otherwise the nearest zone whose radius covers the point."""
    zones = list(Zone.objects.filter(is_active=True))
    if pincode:
        for z in zones:
            if pincode in (z.pincodes or []):
                return z
    if lat is not None and lng is not None:
        lat, lng = float(lat), float(lng)
        best, best_d = None, None
        for z in zones:
            # Polygon-only zones have no circle centre — skip them here (they are
            # resolved by the serviceability engine, not the radius fallback).
            if z.center_lat is None or z.center_lng is None:
                continue
            d = haversine_km(lat, lng, float(z.center_lat), float(z.center_lng))
            if d <= float(z.radius_km) and (best_d is None or d < best_d):
                best, best_d = z, d
        return best
    return None


def agents_for_zone(zone):
    """Delivery agents assigned to a zone (spec §DELIVERY ROUTING). Returns a User
    queryset; empty when the zone is None."""
    from django.contrib.auth import get_user_model

    User = get_user_model()
    if zone is None:
        return User.objects.none()
    return User.objects.filter(zones__zone=zone).distinct()


def emit_zone_event(event_type, *, zone=None, actor=None, **payload):
    """Append a ZoneEvent (best-effort — never breaks the calling transaction)."""
    from .models import ZoneEvent

    try:
        return ZoneEvent.objects.create(
            type=event_type, zone=zone, actor=actor, payload=payload
        )
    except Exception:  # pragma: no cover - telemetry must not break business flow
        return None


def effective_fees(zone) -> dict:
    """Resolve a zone's effective fees, falling back to PlatformConfig for nulls."""
    from siteconfig.models import PlatformConfig

    cfg = PlatformConfig.load()

    def pick(zval, cval):
        return zval if (zone is not None and zval is not None) else cval

    zv = (lambda f: getattr(zone, f) if zone else None)
    return {
        "delivery_fee": pick(zv("delivery_fee"), cfg.delivery_fee),
        "free_delivery_threshold": pick(zv("free_delivery_threshold"), cfg.free_delivery_threshold),
        "min_order": pick(zv("min_order"), cfg.min_order),
        "platform_fee_value": pick(zv("platform_fee_value"), cfg.platform_fee_value),
    }
