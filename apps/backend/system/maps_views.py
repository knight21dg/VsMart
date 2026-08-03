"""Google Maps Platform proxies (routing, ETAs, address quality, roads) via the
admin-managed SERVER key (core.runtime_settings). The app's Android-restricted key
can't call these web services, so everything funnels through here — same pattern as
geo_views (reverse geocode + places). Every endpoint degrades to an empty, shaped
result with a `source` flag when no key is set or Google fails, so the app can fall
back gracefully.
"""
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from core import runtime_settings as runtime


def _key():
    return runtime.cfg("google_maps_key")


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _latlng(raw):
    """Parse 'lat,lng' → (lat, lng) floats, or (None, None)."""
    if not raw:
        return None, None
    parts = str(raw).split(",")
    if len(parts) != 2:
        return None, None
    return _num(parts[0]), _num(parts[1])


class GeoRouteView(APIView):
    """GET /geo/route?origin=lat,lng&dest=lat,lng[&mode=DRIVE] -> road route.

    Returns {encodedPolyline, distanceMeters, durationSeconds, durationText}. Uses
    Routes API (computeRoutes) so the app draws the real road path + a live ETA on
    order tracking instead of a straight/curved guess.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        o_lat, o_lng = _latlng(request.query_params.get("origin"))
        d_lat, d_lng = _latlng(request.query_params.get("dest"))
        base = {"encodedPolyline": "", "distanceMeters": None,
                "durationSeconds": None, "durationText": ""}
        if None in (o_lat, o_lng, d_lat, d_lng):
            return Response({**base, "source": "bad_args"})
        key = _key()
        if not key:
            return Response({**base, "source": "no_key"})
        mode = (request.query_params.get("mode") or "DRIVE").upper()
        if mode not in ("DRIVE", "TWO_WHEELER", "WALK", "BICYCLE"):
            mode = "DRIVE"
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
                json={
                    "origin": {"location": {"latLng": {"latitude": o_lat, "longitude": o_lng}}},
                    "destination": {"location": {"latLng": {"latitude": d_lat, "longitude": d_lng}}},
                    "travelMode": mode,
                    "polylineEncoding": "ENCODED_POLYLINE",
                },
                timeout=8,
            )
            data = resp.json()
        except Exception:
            return Response({**base, "source": "error"})
        routes = data.get("routes") or []
        if resp.status_code != 200 or not routes:
            return Response({**base, "source": "no_result"})
        r = routes[0]
        secs = int(str(r.get("duration", "0s")).rstrip("s") or 0)
        return Response({
            "encodedPolyline": (r.get("polyline") or {}).get("encodedPolyline", ""),
            "distanceMeters": r.get("distanceMeters"),
            "durationSeconds": secs,
            "durationText": _mins(secs),
            "source": "google",
        })


class GeoDistanceMatrixView(APIView):
    """POST /geo/distance-matrix {origins:['lat,lng',...], destinations:[...]} ->
    matrix of drive distance + duration. Powers real ETAs and nearest-agent
    assignment (pick the agent with the shortest drive time, not straight line)."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        origins = request.data.get("origins") or []
        destinations = request.data.get("destinations") or []
        if not origins or not destinations:
            return Response({"rows": [], "source": "bad_args"})
        key = _key()
        if not key:
            return Response({"rows": [], "source": "no_key"})
        try:
            import requests

            resp = requests.get(
                "https://maps.googleapis.com/maps/api/distancematrix/json",
                params={
                    "origins": "|".join(str(o) for o in origins),
                    "destinations": "|".join(str(d) for d in destinations),
                    "mode": "driving", "key": key,
                },
                timeout=8,
            )
            data = resp.json()
        except Exception:
            return Response({"rows": [], "source": "error"})
        if data.get("status") != "OK":
            return Response({"rows": [], "source": "no_result"})
        rows = [
            [
                {
                    "distanceMeters": (el.get("distance") or {}).get("value"),
                    "durationSeconds": (el.get("duration") or {}).get("value"),
                    "durationText": (el.get("duration") or {}).get("text", ""),
                    "ok": el.get("status") == "OK",
                }
                for el in (row.get("elements") or [])
            ]
            for row in (data.get("rows") or [])
        ]
        return Response({"rows": rows, "source": "google"})


class GeoValidateAddressView(APIView):
    """POST /geo/validate-address {addressLines:[...], pincode} -> validation verdict.

    Uses the Address Validation API to catch incomplete / undeliverable addresses at
    checkout & add-address, and hand back a normalised formatted address.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        # The camelCase parser snake-cases the body, so read the snake key (with a
        # camel fallback) — reading "addressLines" alone always yielded [].
        lines = (
            request.data.get("address_lines")
            if "address_lines" in request.data
            else request.data.get("addressLines")
        ) or []
        if isinstance(lines, str):
            lines = [lines]
        pincode = str(request.data.get("pincode") or "").strip()
        base = {"valid": None, "complete": None, "formatted": "",
                "pincode": pincode, "missing": []}
        if not lines and not pincode:
            return Response({**base, "source": "bad_args"})
        key = _key()
        if not key:
            return Response({**base, "source": "no_key"})
        address = {"regionCode": "IN", "addressLines": [str(x) for x in lines if x]}
        if pincode:
            address["postalCode"] = pincode
        try:
            import requests

            resp = requests.post(
                "https://addressvalidation.googleapis.com/v1:validateAddress",
                headers={"Content-Type": "application/json", "X-Goog-Api-Key": key},
                json={"address": address},
                timeout=8,
            )
            data = resp.json()
        except Exception:
            return Response({**base, "source": "error"})
        result = data.get("result")
        if resp.status_code != 200 or not result:
            return Response({**base, "source": "no_result"})
        verdict = result.get("verdict") or {}
        addr = result.get("address") or {}
        missing = [c.get("componentType", "") for c in (addr.get("missingComponentTypes") or [])]
        return Response({
            "valid": not verdict.get("hasUnconfirmedComponents", False),
            "complete": verdict.get("addressComplete", False),
            "formatted": (result.get("address") or {}).get("formattedAddress", ""),
            "pincode": _pincode_from(addr) or pincode,
            "missing": missing,
            "source": "google",
        })


class GeoGeolocateView(APIView):
    """POST /geo/geolocate -> {lat, lng, accuracy} from cell/wifi/IP. A fallback
    for when device GPS is denied/unavailable so the app can still estimate area."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        base = {"lat": None, "lng": None, "accuracy": None}
        key = _key()
        if not key:
            return Response({**base, "source": "no_key"})
        payload = {"considerIp": True}
        # Optional caller-supplied wifi/cell towers improve accuracy.
        for f in ("wifiAccessPoints", "cellTowers"):
            if request.data.get(f):
                payload[f] = request.data[f]
        try:
            import requests

            resp = requests.post(
                "https://www.googleapis.com/geolocation/v1/geolocate",
                params={"key": key}, json=payload, timeout=8,
            )
            data = resp.json()
        except Exception:
            return Response({**base, "source": "error"})
        loc = data.get("location") or {}
        if resp.status_code != 200 or "lat" not in loc:
            return Response({**base, "source": "no_result"})
        return Response({
            "lat": loc.get("lat"), "lng": loc.get("lng"),
            "accuracy": data.get("accuracy"), "source": "google",
        })


class GeoSnapToRoadsView(APIView):
    """POST /geo/snap-to-roads {path:['lat,lng',...]} -> road-snapped points, so an
    agent's raw GPS breadcrumb trail draws cleanly along the road network."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        path = request.data.get("path") or []
        if len(path) < 2:
            return Response({"points": [], "source": "bad_args"})
        key = _key()
        if not key:
            return Response({"points": [], "source": "no_key"})
        try:
            import requests

            resp = requests.get(
                "https://roads.googleapis.com/v1/snapToRoads",
                params={"path": "|".join(str(p) for p in path),
                        "interpolate": "true", "key": key},
                timeout=8,
            )
            data = resp.json()
        except Exception:
            return Response({"points": [], "source": "error"})
        snapped = data.get("snappedPoints")
        if resp.status_code != 200 or snapped is None:
            return Response({"points": [], "source": "no_result"})
        points = [
            {"lat": (p.get("location") or {}).get("latitude"),
             "lng": (p.get("location") or {}).get("longitude")}
            for p in snapped
        ]
        return Response({"points": points, "source": "google"})


# ── helpers ──
def _mins(seconds):
    if not seconds:
        return ""
    m = round(seconds / 60)
    if m < 1:
        return "under a min"
    if m < 60:
        return f"{m} min"
    return f"{m // 60} hr {m % 60} min"


def _pincode_from(addr):
    for c in (addr.get("addressComponents") or []):
        if c.get("componentType") == "postal_code":
            return (c.get("componentName") or {}).get("text", "")
    return ""
