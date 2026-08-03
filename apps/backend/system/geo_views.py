"""Reverse geocoding (lat/lng -> area/address) via the admin-managed Google Maps
server key (core.runtime_settings). Powers the app's "Delivery to <area>" header
and address auto-fill. Returns empty fields (HTTP 200, source flag) when no key is
configured or Google fails, so the app can fall back to the device's native geocoder.
"""
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from core import runtime_settings as runtime


def _component(result, *types):
    for c in result.get("address_components", []):
        if any(t in c.get("types", []) for t in types):
            return c.get("long_name", "")
    return ""


def _component_new(components, *types):
    """Same as _component but for Places API (New) `addressComponents`
    (`longText`/`types` instead of `long_name`)."""
    for c in components or []:
        if any(t in (c.get("types") or []) for t in types):
            return c.get("longText", "")
    return ""


class GeoReverseView(APIView):
    """GET /geo/reverse?lat=<>&lng=<> -> {formatted, area, city, state, pincode, lat, lng, source}."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        lat = request.query_params.get("lat")
        lng = request.query_params.get("lng")
        base = {"formatted": "", "area": "", "city": "", "state": "",
                "pincode": "", "lat": lat, "lng": lng}
        if not lat or not lng:
            return Response({**base, "source": "none"})
        key = runtime.cfg("google_maps_key")
        if not key:
            return Response({**base, "source": "no_key"})
        try:
            import requests

            resp = requests.get(
                "https://maps.googleapis.com/maps/api/geocode/json",
                params={"latlng": f"{lat},{lng}", "key": key}, timeout=8,
            )
            data = resp.json()
        except Exception:
            return Response({**base, "source": "error"})
        results = data.get("results") or []
        if data.get("status") != "OK" or not results:
            return Response({**base, "source": "no_result"})
        res = results[0]
        return Response({
            "formatted": res.get("formatted_address", ""),
            "area": (_component(res, "sublocality_level_1", "sublocality", "neighborhood")
                     or _component(res, "locality")),
            "city": _component(res, "locality", "administrative_area_level_2"),
            "state": _component(res, "administrative_area_level_1"),
            "pincode": _component(res, "postal_code"),
            "lat": lat, "lng": lng, "source": "google",
        })


class GeoPlacesAutocompleteView(APIView):
    """GET /geo/places/autocomplete?q=<text>&session=<token> -> place suggestions.

    Proxies Google Places Autocomplete with the admin-managed SERVER key (the
    app's Android-restricted key is rejected by the web service). India-biased.
    Pass a stable `session` token across the autocomplete→detail pair so Google
    bills it as one session. Degrades to an empty list (source flag) when the key
    is absent or Google fails, so the app can fall back.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        q = (request.query_params.get("q") or "").strip()
        session = request.query_params.get("session") or ""
        if len(q) < 2:
            return Response({"predictions": [], "source": "short"})
        key = runtime.cfg("google_maps_key")
        if not key:
            return Response({"predictions": [], "source": "no_key"})
        try:
            import requests

            body = {"input": q, "includedRegionCodes": ["in"]}
            if session:
                body["sessionToken"] = session
            resp = requests.post(
                "https://places.googleapis.com/v1/places:autocomplete",
                headers={"Content-Type": "application/json", "X-Goog-Api-Key": key},
                json=body,
                timeout=8,
            )
            data = resp.json()
        except Exception:
            return Response({"predictions": [], "source": "error"})
        if resp.status_code != 200:
            return Response({"predictions": [], "source": "no_result"})
        predictions = []
        for s in (data.get("suggestions") or []):
            pp = s.get("placePrediction")
            if not pp or not pp.get("placeId"):
                continue
            sf = pp.get("structuredFormat") or {}
            main = (sf.get("mainText") or {}).get("text") \
                or (pp.get("text") or {}).get("text", "")
            secondary = (sf.get("secondaryText") or {}).get("text", "")
            predictions.append({
                "placeId": pp.get("placeId", ""),
                "primary": main,
                "secondary": secondary,
                "description": (pp.get("text") or {}).get("text", ""),
            })
        return Response({"predictions": predictions, "source": "google"})


class GeoPlaceDetailView(APIView):
    """GET /geo/places/detail?placeId=<id>&session=<token> -> {lat,lng,address...}.

    Resolves a selected autocomplete suggestion to coordinates + address parts via
    Google Place Details (same server key + session token). Used to centre the map
    pin-picker on the chosen place. Graceful empty result when the key is absent.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        place_id = (request.query_params.get("placeId")
                    or request.query_params.get("place_id") or "").strip()
        session = request.query_params.get("session") or ""
        base = {"lat": None, "lng": None, "formatted": "", "area": "",
                "city": "", "state": "", "pincode": ""}
        if not place_id:
            return Response({**base, "source": "none"})
        key = runtime.cfg("google_maps_key")
        if not key:
            return Response({**base, "source": "no_key"})
        try:
            import requests

            resp = requests.get(
                f"https://places.googleapis.com/v1/places/{place_id}",
                headers={
                    "X-Goog-Api-Key": key,
                    "X-Goog-FieldMask": "id,location,formattedAddress,addressComponents",
                },
                params={"sessionToken": session} if session else None,
                timeout=8,
            )
            data = resp.json()
        except Exception:
            return Response({**base, "source": "error"})
        loc = data.get("location") or {}
        if resp.status_code != 200 or "latitude" not in loc:
            return Response({**base, "source": "no_result"})
        comps = data.get("addressComponents") or []
        return Response({
            "lat": loc.get("latitude"), "lng": loc.get("longitude"),
            "formatted": data.get("formattedAddress", ""),
            "area": (_component_new(comps, "sublocality_level_1", "sublocality", "neighborhood")
                     or _component_new(comps, "locality")),
            "city": _component_new(comps, "locality", "administrative_area_level_2"),
            "state": _component_new(comps, "administrative_area_level_1"),
            "pincode": _component_new(comps, "postal_code"),
            "source": "google",
        })
