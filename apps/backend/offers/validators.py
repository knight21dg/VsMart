"""Deep-link validation for banner actions.

The app never parses URLs — it switches on ``Offer.action`` and reads typed keys
out of ``Offer.payload``. Nothing validated that contract before, so a banner
could ship with ``action=product`` and an empty payload (tap → silent fallback
to the offers hub) or ``action=external`` with a ``javascript:`` URL.

``validate_action_payload`` is the gate: it normalizes payload keys to the
camelCase the app reads, requires the keys each action needs, and checks that
referenced rows actually exist.
"""
from urllib.parse import urlparse

from django.conf import settings
from rest_framework import serializers

#: action -> (payload key the app reads, human label, optional existence check)
REQUIRED_KEYS = {
    "product": ("productId", "a product"),
    "category": ("categoryId", "a category"),
    "order": ("orderId", "an order"),
    "search": ("query", "a search term"),
    "brand": ("brandId", "a brand"),
    "store": ("storeId", "a store"),
    "external": ("url", "a link"),
}

#: Accept snake_case / loose keys from older clients, store camelCase.
_ALIASES = {
    "product_id": "productId",
    "category_id": "categoryId",
    "subcategory_id": "subcategoryId",
    "order_id": "orderId",
    "brand_id": "brandId",
    "store_id": "storeId",
    "q": "query",
    "search": "query",
    "link": "url",
}


def normalize_payload(payload):
    """Coerce payload keys to the camelCase names the Flutter app reads."""
    if not isinstance(payload, dict):
        return {}
    out = {}
    for key, value in payload.items():
        out[_ALIASES.get(key, key)] = value
    return out


def _check_external(url):
    parsed = urlparse(str(url).strip())
    if parsed.scheme not in ("https",):
        raise serializers.ValidationError(
            {"payload": "External links must be absolute https:// URLs."}
        )
    if not parsed.netloc:
        raise serializers.ValidationError({"payload": "External link has no host."})
    # Optional hardening: pin outbound banner links to hosts we control/trust.
    allow = getattr(settings, "BANNER_EXTERNAL_HOST_ALLOWLIST", None)
    if allow:
        host = parsed.netloc.split("@")[-1].split(":")[0].lower()
        if not any(host == a or host.endswith("." + a) for a in allow):
            raise serializers.ValidationError(
                {"payload": f"'{host}' is not an allowed external banner host."}
            )


def _check_exists(action, key, value):
    """Verify the referenced row exists so a live banner can't dead-end."""
    if action == "product":
        from catalog.models import Product
        model, label = Product, "Product"
    elif action == "category":
        from catalog.models import Category
        model, label = Category, "Category"
    elif action == "store":
        from stores.models import Store
        model, label = Store, "Store"
    else:
        return
    try:
        pk = int(value)
    except (TypeError, ValueError):
        raise serializers.ValidationError({"payload": f"{key} must be a numeric id."})
    if not model.objects.filter(pk=pk).exists():
        raise serializers.ValidationError({"payload": f"{label} {pk} does not exist."})


def validate_action_payload(action, payload):
    """Return the normalized payload for ``action``, or raise ValidationError."""
    payload = normalize_payload(payload)
    if action not in REQUIRED_KEYS:
        return payload                      # home/cart/credit/offers/profile/none

    key, label = REQUIRED_KEYS[action]
    value = payload.get(key)
    if value in (None, "", []):
        raise serializers.ValidationError(
            {"payload": f"Action '{action}' needs {label} — set '{key}' in the payload."}
        )
    if action == "external":
        _check_external(value)
    else:
        _check_exists(action, key, value)
    return payload
