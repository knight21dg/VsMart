"""Banner placement geometry — the single source of truth.

Every surface that decides how big a banner is derives from this table:

* ``offers.imaging`` crops + resizes uploads to the placement's exact ratio,
* the admin console fetches ``GET /offers/specs`` to drive its crop tool,
* the Flutter app mirrors these ratios in ``BannerSpec`` (user_app) so a slot's
  rendered box matches the stored image *exactly* — no second crop by
  ``BoxFit.cover``.

Before this table existed the pipeline cropped everything to 2:1 while the app
rendered the home hero at 16:10 and the strips at 16:9, so every banner was
cropped twice and marketing could never predict what would be visible. If you
change a ratio here, change ``BannerSpec`` in the app in the same commit.
"""
from .models import Offer

# Ladder keys are fixed (the app's DPR picker and image_urls() both key off them).
LADDER = ("large", "medium", "small", "thumb")


def _ladder(w, h, scales=(1.0, 0.7, 0.5, 0.2)):
    """Size ladder for a master (w, h).

    Width is rounded to an even pixel and the height is then *derived* from the
    master ratio — rounding both independently drifts the aspect (720×404 instead
    of 720×405), which would reintroduce the very stretching this table exists to
    prevent.
    """
    ratio = w / h
    out = {}
    for name, s in zip(LADDER, scales):
        sw = int(round(w * s / 2)) * 2
        out[name] = (sw, int(round(sw / ratio)))
    return out


#: placement -> spec. ``ratio`` is width/height. ``master`` is the largest
#: rendition *and* the minimum accepted upload size.
PLACEMENT_SPECS = {
    Offer.Placement.TOP: {
        "label": "Home hero carousel",
        "ratio": 16 / 10,
        "master": (1600, 1000),
        "note": "Full-bleed carousel at the top of Home. Keep text inside the "
                "centre 80% — the card is inset 4px per side and rounded 20px.",
    },
    Offer.Placement.MIDDLE: {
        "label": "Home mid strip",
        "ratio": 16 / 9,
        "master": (1440, 810),
        "note": "Secondary carousel below the category rail on Home.",
    },
    Offer.Placement.PRODUCT_LIST: {
        "label": "Category / product listing",
        "ratio": 16 / 9,
        "master": (1440, 810),
        "note": "Shown above the grid on category and search-result screens.",
    },
    Offer.Placement.PRODUCT_DETAIL: {
        "label": "Product detail",
        "ratio": 16 / 9,
        "master": (1440, 810),
        "note": "Single banner (no carousel) inside the product detail body.",
    },
    Offer.Placement.CART: {
        "label": "Cart",
        "ratio": 16 / 9,
        "master": (1440, 810),
        "note": "Above the bill summary in the cart. Good slot for coupon nudges.",
    },
    Offer.Placement.SPOTLIGHT: {
        "label": "Spotlight card",
        "ratio": 1.0,
        "master": (800, 800),
        "note": "Square product cut-out rendered over a gradient card. Use a "
                "transparent-background PNG subject; it is drawn with contain.",
    },
}

#: The placement used when a row has an unknown/blank placement (legacy rows).
DEFAULT_PLACEMENT = Offer.Placement.TOP


def spec_for(placement):
    """Spec dict for ``placement``, falling back to the default placement."""
    return PLACEMENT_SPECS.get(placement) or PLACEMENT_SPECS[DEFAULT_PLACEMENT]


def sizes_for(placement):
    """The rendition ladder ``{name: (w, h)}`` for ``placement``."""
    spec = spec_for(placement)
    return _ladder(*spec["master"])


def public_specs():
    """JSON-safe spec table for ``GET /offers/specs`` (admin crop tool + docs).

    Returned as a **list**, not a dict keyed by placement: the API renderer
    camelCases response dict *keys*, which would rewrite ``product_list`` to
    ``productList`` and leave every client unable to look up its own placement.
    Values are passed through untouched, so the key lives in a ``placement``
    field instead.
    """
    out = []
    for placement, spec in PLACEMENT_SPECS.items():
        w, h = spec["master"]
        out.append({
            "placement": str(placement),
            "label": spec["label"],
            "note": spec["note"],
            "ratio": round(spec["ratio"], 6),
            "aspect": _aspect_label(spec["ratio"]),
            "master": {"width": w, "height": h},
            "minUpload": {"width": w, "height": h},
            "sizes": [
                {"name": name, "width": sw, "height": sh}
                for name, (sw, sh) in sizes_for(placement).items()
            ],
        })
    return out


def public_spec_for(placement):
    """The single public spec entry for ``placement``."""
    target = str(placement)
    for entry in public_specs():
        if entry["placement"] == target:
            return entry
    return None


def _aspect_label(ratio):
    """Human aspect label ('16:10') for the admin UI."""
    for w, h in ((1, 1), (16, 9), (16, 10), (2, 1), (3, 2), (4, 3)):
        if abs(ratio - w / h) < 1e-3:
            return f"{w}:{h}"
    return f"{ratio:.2f}:1"
