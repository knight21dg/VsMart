"""Server-side Google Maps helpers for backend services (the assignment engine).
Thin, best-effort wrappers over the Routes API using the admin server key; every
function returns None on any failure so callers fall back to haversine math."""
from decimal import Decimal

from core import runtime_settings as runtime


def _key():
    return runtime.cfg("google_maps_key")


def route_multi(points):
    """Optimized-order road route through `points` = [(lat,lng), ...] (len >= 2).
    Returns {encodedPolyline, distanceMeters, durationSeconds} or None."""
    key = _key()
    if not key or len(points) < 2:
        return None
    origin, dest, inter = points[0], points[-1], points[1:-1]

    def _pt(p):
        return {"location": {"latLng": {"latitude": float(p[0]), "longitude": float(p[1])}}}

    body = {
        "origin": _pt(origin),
        "destination": _pt(dest),
        "travelMode": "DRIVE",
        "polylineEncoding": "ENCODED_POLYLINE",
    }
    if inter:
        body["intermediates"] = [_pt(p) for p in inter]
    try:
        import requests

        resp = requests.post(
            "https://routes.googleapis.com/directions/v2:computeRoutes",
            headers={
                "Content-Type": "application/json",
                "X-Goog-Api-Key": key,
                "X-Goog-FieldMask":
                    "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline",
            },
            json=body,
            timeout=10,
        )
        data = resp.json()
    except Exception:
        return None
    routes = data.get("routes") or []
    if resp.status_code != 200 or not routes:
        return None
    r = routes[0]
    secs = int(str(r.get("duration", "0s")).rstrip("s") or 0)
    return {
        "encodedPolyline": (r.get("polyline") or {}).get("encodedPolyline", ""),
        "distanceMeters": r.get("distanceMeters") or 0,
        "durationSeconds": secs,
    }


def to_decimal(v):
    try:
        return Decimal(str(round(float(v), 2)))
    except (TypeError, ValueError):
        return Decimal("0")
