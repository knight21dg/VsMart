"""Polygon-based serviceability engine.

The single source of truth for "can we serve this point, and from which store?".
Stores its polygons as GeoJSON (``Zone.polygon_geojson``) and resolves a customer
``Point`` against them with a pure-Python ray-casting test — **no PostGIS/GDAL
dependency**, so it runs on the dev SQLite stack unchanged.

GeoJSON convention: coordinates are ``[lng, lat]`` (longitude first). All callers
pass ``lat``/``lng`` named; we flip to lng/lat internally.

Prod-scale upgrade path: when the DB is PostgreSQL+PostGIS, swap ``_zone_for_point``
to a GeoDjango ``Zone.objects.filter(polygon__contains=Point(lng, lat))`` query with a
GiST index. The response shape and all callers stay identical.
"""
from __future__ import annotations


def _point_in_ring(lng: float, lat: float, ring: list) -> bool:
    """Ray-casting point-in-polygon for a single linear ring of [lng, lat] pairs."""
    inside = False
    n = len(ring)
    if n < 3:
        return False
    j = n - 1
    for i in range(n):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if ((yi > lat) != (yj > lat)) and (
            lng < (xj - xi) * (lat - yi) / ((yj - yi) or 1e-12) + xi
        ):
            inside = not inside
        j = i
    return inside


def _geometry(geojson):
    """Accept a raw geometry, a Feature, or a FeatureCollection — return the geometry."""
    if not isinstance(geojson, dict):
        return None
    t = geojson.get("type")
    if t == "Feature":
        return geojson.get("geometry")
    if t == "FeatureCollection":
        feats = geojson.get("features") or []
        return feats[0].get("geometry") if feats else None
    return geojson


def point_in_polygon(lng: float, lat: float, geojson) -> bool:
    """True if (lng, lat) is inside the GeoJSON Polygon/MultiPolygon (holes honoured)."""
    geom = _geometry(geojson)
    if not isinstance(geom, dict):
        return False
    gtype = geom.get("type")
    coords = geom.get("coordinates") or []
    if gtype == "Polygon":
        polys = [coords]
    elif gtype == "MultiPolygon":
        polys = coords
    else:
        return False
    for poly in polys:
        if not poly:
            continue
        exterior = poly[0]
        if _point_in_ring(lng, lat, exterior):
            # A point in a hole is NOT inside the polygon.
            if not any(_point_in_ring(lng, lat, hole) for hole in poly[1:]):
                return True
    return False


def _zone_for_point(lat: float, lng: float):
    """Highest-priority active zone whose polygon contains the point, else None."""
    from .models import Zone

    candidates = []
    qs = (
        Zone.objects.filter(is_active=True)
        .exclude(polygon_geojson__isnull=True)
        .select_related("store")
    )
    for z in qs:
        if z.polygon_geojson and point_in_polygon(lng, lat, z.polygon_geojson):
            candidates.append(z)
    if not candidates:
        return None
    # Higher priority wins on overlap; stable tie-break by id.
    candidates.sort(key=lambda z: (z.priority, -z.id), reverse=True)
    return candidates[0]


def resolve_serviceable_zone(lat=None, lng=None, pincode=None):
    """Return the serviceable Zone for a point (polygon-first), or None.

    Polygon match is authoritative. If no polygon zone matches (e.g. legacy
    radius-only zones not yet migrated), fall back to the radius/pincode resolver so
    existing flows keep working during the transition.
    """
    if lat is not None and lng is not None:
        try:
            flat, flng = float(lat), float(lng)
        except (TypeError, ValueError):
            flat = flng = None
        if flat is not None:
            zone = _zone_for_point(flat, flng)
            if zone is not None:
                return zone
    # Legacy fallback (radius circle / pincode list).
    from .services import resolve_zone

    return resolve_zone(lat=lat, lng=lng, pincode=pincode)


def serviceability(lat=None, lng=None, pincode=None) -> dict:
    """The serviceability response contract (spec §SERVICEABILITY RESPONSE)."""
    from .services import effective_fees

    zone = resolve_serviceable_zone(lat=lat, lng=lng, pincode=pincode)
    if zone is None:
        return {
            "serviceable": False,
            "zone_id": None,
            "zone_name": None,
            "store_id": None,
            "store_name": None,
            "delivery_fee": None,
            "minimum_order": None,
            "credit_available": False,
            "estimated_delivery_time": None,
            "free_delivery_threshold": None,
        }
    store = getattr(zone, "store", None)
    serviceable_store = store is not None and store.is_serviceable
    fees = effective_fees(zone)

    # A zone with no store — or an inactive one — cannot actually serve anybody.
    # This used to answer `serviceable: True` with `store_id: null`, so the app
    # unlocked the storefront and then every catalog call resolved no store and
    # returned an EMPTY set: a working-looking app with nothing in it, and no way
    # for the customer to understand why. Report it honestly instead, so they get
    # the not-serviceable screen with its change-location and notify-me actions.
    if not serviceable_store:
        return {
            "serviceable": False,
            # The zone IS named — we know where they are, we just don't serve it
            # yet. Keeping these lets the UI say "we're not in <zone> yet".
            "zone_id": str(zone.id),
            "zone_name": zone.name,
            "store_id": None,
            "store_name": None,
            "delivery_fee": None,
            "minimum_order": None,
            "credit_available": False,
            "estimated_delivery_time": None,
            "free_delivery_threshold": None,
        }

    def hhmm(t):
        return t.strftime("%H:%M") if t else None

    return {
        "serviceable": True,
        "zone_id": str(zone.id),
        "zone_name": zone.name,
        "store_id": str(store.id) if serviceable_store else None,
        "store_name": store.name if serviceable_store else None,
        # So the app's Help & Support "Call" button can ring the actual store
        # serving this customer instead of only ever a generic support line.
        "store_phone": (store.phone or None) if serviceable_store else None,
        "delivery_fee": fees["delivery_fee"],
        "minimum_order": fees["min_order"],
        "credit_available": bool(getattr(zone, "credit_enabled", False)),
        "estimated_delivery_time": getattr(zone, "estimated_delivery_minutes", None),
        "free_delivery_threshold": fees["free_delivery_threshold"],
        # Store availability — the catalog stays visible but the app should disable
        # checkout (and show the reason) when the store can't currently take orders.
        "store_open": store.is_open_now() if serviceable_store else None,
        "opens_at": hhmm(store.opens_at) if serviceable_store else None,
        "closes_at": hhmm(store.closes_at) if serviceable_store else None,
        "accepting_orders": bool(store.accepting_orders) if serviceable_store else None,
        "capacity_reached": store.capacity_reached() if serviceable_store else None,
    }
