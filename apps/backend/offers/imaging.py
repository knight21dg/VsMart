"""Banner image pipeline.

Validate an upload, crop it to the **placement's** aspect ratio, and generate
WebP size variants under ``MEDIA_ROOT/banners/<uuid>/v<version>/``.

Two crop modes, in priority order:

1. **Explicit crop rect** — the admin console's crop tool sends a normalized
   rect (``x/y/w/h`` in 0..1 of the source). We honour it exactly, then snap it
   to the placement ratio so the stored image can never be re-cropped by the
   client. This is the path marketing should always use.
2. **Focal point** — legacy/API uploads with no rect fall back to a centre crop
   that keeps ``(focus_x, focus_y)`` inside the frame.

The app is served **WebP only** (minSdk 23 → AVIF doesn't decode on Android 6–11).
AVIF-for-web is a later add and would write extra ``*.avif`` siblings here.
"""
import uuid as uuidlib
from pathlib import Path

from django.conf import settings
from PIL import Image, ImageOps

from core.app_errors import AppError

from .specs import sizes_for, spec_for

ALLOWED_EXT = {"jpg", "jpeg", "png", "webp"}
MAX_BYTES = 3 * 1024 * 1024          # 3 MB


def _ext_ok(name: str) -> bool:
    name = name or ""
    return "." in name and name.rsplit(".", 1)[-1].lower() in ALLOWED_EXT


def _clamp01(v, default=0.0):
    try:
        return min(max(float(v), 0.0), 1.0)
    except (TypeError, ValueError):
        return default


def normalize_crop_rect(rect):
    """Coerce an admin-supplied crop rect to ``{x, y, w, h}`` in 0..1, or None.

    Accepts camelCase or snake_case keys. A degenerate rect (zero/negative area,
    or one that starts outside the image) is treated as absent so we fall back to
    the focal crop rather than producing a 1px image.
    """
    if not isinstance(rect, dict):
        return None
    def g(*names):
        for n in names:
            if n in rect:
                return rect[n]
        return None

    x, y = _clamp01(g("x", "cropX", "crop_x")), _clamp01(g("y", "cropY", "crop_y"))
    w, h = _clamp01(g("w", "width", "cropW", "crop_w")), _clamp01(g("h", "height", "cropH", "crop_h"))
    if w <= 0 or h <= 0 or x >= 1 or y >= 1:
        return None
    # Keep the rect inside the image.
    w, h = min(w, 1.0 - x), min(h, 1.0 - y)
    if w <= 0 or h <= 0:
        return None
    return {"x": x, "y": y, "w": w, "h": h}


def _crop_to_ratio(img, ratio, fx, fy):
    """Crop ``img`` to ``ratio`` (w/h), keeping the focal point (fx, fy in 0..1)
    inside the frame."""
    w, h = img.size
    cur = w / h
    if abs(cur - ratio) < 1e-3:
        return img
    if cur > ratio:                       # too wide → trim width
        nw, nh = int(round(h * ratio)), h
    else:                                 # too tall → trim height
        nw, nh = w, int(round(w / ratio))
    cx, cy = fx * w, fy * h               # focal point in pixels
    left = int(min(max(cx - nw / 2, 0), w - nw))
    top = int(min(max(cy - nh / 2, 0), h - nh))
    return img.crop((left, top, left + nw, top + nh))


def _crop_to_rect(img, rect):
    """Crop ``img`` to a normalized rect. Guarantees a non-empty result."""
    w, h = img.size
    left = int(round(rect["x"] * w))
    top = int(round(rect["y"] * h))
    right = min(w, max(left + 1, int(round((rect["x"] + rect["w"]) * w))))
    bottom = min(h, max(top + 1, int(round((rect["y"] + rect["h"]) * h))))
    return img.crop((left, top, right, bottom))


def process_banner_image(uploaded, *, placement=None, crop_rect=None,
                         focus_x=0.5, focus_y=0.5, image_uuid=None, version=1):
    """Validate + crop + generate WebP variants for an uploaded banner image.

    Returns ``(uuid, version)``. Raises ``AppError`` with an actionable code on any
    validation failure. EXIF is honoured for orientation, then stripped (re-encode).
    """
    spec = spec_for(placement)
    ratio = spec["ratio"]
    min_w, min_h = spec["master"]
    sizes = sizes_for(placement)

    if uploaded is None:
        raise AppError("IMAGE_INVALID", message="No image file was provided.")
    if getattr(uploaded, "size", 0) > MAX_BYTES:
        raise AppError("IMAGE_TOO_LARGE")
    if not _ext_ok(getattr(uploaded, "name", "")):
        raise AppError("UNSUPPORTED_IMAGE_TYPE")

    try:
        img = Image.open(uploaded)
        fmt = (img.format or "").upper()      # actual decoded format, not the filename
        img = ImageOps.exif_transpose(img)   # apply orientation, drop EXIF on re-encode
        img = img.convert("RGB")
    except Exception:
        raise AppError("IMAGE_INVALID")

    # Content sniff: trust the decoded format, not just the extension.
    if fmt not in {"JPEG", "PNG", "WEBP"}:
        raise AppError("UNSUPPORTED_IMAGE_TYPE")

    w, h = img.size
    if w < min_w or h < min_h:
        raise AppError(
            "IMAGE_INVALID",
            message=(
                f"{spec['label']} needs an image of at least {min_w}×{min_h}px "
                f"({_ratio_label(ratio)})."
            ),
        )

    fx, fy = _clamp01(focus_x, 0.5), _clamp01(focus_y, 0.5)
    rect = normalize_crop_rect(crop_rect)
    if rect:
        img = _crop_to_rect(img, rect)
        # The cropper is aspect-locked, but never trust the client's arithmetic —
        # snap to the exact ratio around the middle of what they selected.
        img = _crop_to_ratio(img, ratio, 0.5, 0.5)
    else:
        img = _crop_to_ratio(img, ratio, fx, fy)

    bid = image_uuid or uuidlib.uuid4()
    base = Path(settings.MEDIA_ROOT) / "banners" / str(bid) / f"v{version}"
    base.mkdir(parents=True, exist_ok=True)
    for name, (tw, th) in sizes.items():
        out = img.resize((tw, th), Image.LANCZOS)
        out.save(base / f"{name}.webp", "WEBP", quality=85, method=6)
    return bid, version


def _ratio_label(ratio):
    from .specs import _aspect_label

    return _aspect_label(ratio)


def image_urls(image_uuid, version):
    """Public URL map for a stored banner image (WebP), or None."""
    if not image_uuid:
        return None
    base = f"{settings.MEDIA_URL}banners/{image_uuid}/v{version}"
    from .specs import LADDER

    return {name: f"{base}/{name}.webp" for name in LADDER}
