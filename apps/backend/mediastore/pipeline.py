"""Image ingest pipeline: validate → strip metadata → convert to WebP → render
thumb/medium/original variants, written through Django storage.

Everything funnels through :func:`store_image`, which returns a saved
:class:`~mediastore.models.MediaAsset`. Validation failures raise catalog-coded
``AppError``s so the API surfaces actionable messages.
"""
import hashlib
import io

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from PIL import Image, ImageOps

from core.app_errors import AppError

from .models import MediaAsset

# Pillow format names we accept (sniffed from the bytes, not the file extension).
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}
DEFAULT_VARIANT_SIZES = {"thumb": 256, "medium": 1024, "original": 2048}
DEFAULT_MAX_BYTES = 5 * 1024 * 1024


def _max_bytes() -> int:
    return getattr(settings, "MEDIA_MAX_UPLOAD_BYTES", DEFAULT_MAX_BYTES)


def _variant_sizes() -> dict:
    return getattr(settings, "MEDIA_VARIANT_SIZES", DEFAULT_VARIANT_SIZES)


def validate_image_upload(src) -> None:
    """Validate an uploaded image WITHOUT storing it: within the size cap, and a
    real image of an allowed format. Raises ``FILE_TOO_LARGE`` /
    ``UNSUPPORTED_MEDIA_TYPE`` (same policy as :func:`store_image`). Rewinds ``src``
    so the caller can still persist it.

    For upload paths that keep their own storage (e.g. KYC ImageField) but must
    apply the same sanitization as the media pipeline."""
    raw = src.read() if hasattr(src, "read") else bytes(src)
    if hasattr(src, "seek"):
        src.seek(0)  # rewind so the caller can still save the file
    if len(raw) > _max_bytes():
        raise AppError("FILE_TOO_LARGE")
    try:
        probe = Image.open(io.BytesIO(raw))
        fmt = (probe.format or "").upper()  # captured before verify() invalidates it
        probe.verify()
    except Exception as exc:
        raise AppError("UNSUPPORTED_MEDIA_TYPE") from exc
    if fmt not in ALLOWED_FORMATS:
        raise AppError("UNSUPPORTED_MEDIA_TYPE")


def _resized(img: Image.Image, max_edge: int) -> Image.Image:
    """Downscale so the longest edge is at most ``max_edge`` (never upscale)."""
    w, h = img.size
    longest = max(w, h)
    if longest <= max_edge:
        return img
    scale = max_edge / float(longest)
    return img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)


def store_image(src, *, category="misc", owner=None, visibility="private",
                original_name=""):
    """Validate and ingest ``src`` (an uploaded file or raw bytes) into a new
    :class:`MediaAsset`. Raises ``FILE_TOO_LARGE`` / ``UNSUPPORTED_MEDIA_TYPE``."""
    raw = src.read() if hasattr(src, "read") else bytes(src)
    if len(raw) > _max_bytes():
        raise AppError("FILE_TOO_LARGE")

    # Sniff: it must be a real image of an allowed format. verify() consumes the
    # buffer, so reopen from a fresh stream for the actual decode.
    try:
        probe = Image.open(io.BytesIO(raw))
        probe.verify()
        img = Image.open(io.BytesIO(raw))
        img.load()
    except Exception:
        raise AppError("UNSUPPORTED_MEDIA_TYPE")
    if (img.format or "").upper() not in ALLOWED_FORMATS:
        raise AppError("UNSUPPORTED_MEDIA_TYPE")

    # Honour EXIF orientation, then drop all metadata by re-encoding. Keep alpha
    # for PNG/WebP sources, flatten everything else to RGB.
    img = ImageOps.exif_transpose(img)
    img = img.convert("RGBA") if img.mode in ("RGBA", "LA", "P") else img.convert("RGB")

    asset = MediaAsset(
        owner=owner,
        category=(category or "misc")[:32],
        visibility=visibility,
        content_type="image/webp",
        original_name=(original_name or getattr(src, "name", "") or "")[:200],
        checksum=hashlib.sha256(raw).hexdigest(),
    )

    for variant, max_edge in _variant_sizes().items():
        rendered = _resized(img, max_edge)
        buf = io.BytesIO()
        rendered.save(buf, format="WEBP", quality=82, method=4)
        default_storage.save(asset.variant_key(variant), ContentFile(buf.getvalue()))
        if variant == "original":
            asset.size_bytes = buf.tell()
            asset.width, asset.height = rendered.size

    asset.save()
    return asset


def ingest_public_image(upload, *, owner=None, category="catalog"):
    """Store an uploaded image as a PUBLIC media asset and return its canonical
    medium-variant URL — the value to persist in a ``*.image_url`` field.

    Used by the admin/store panels' image pickers so images live on VS Mart's own
    media engine (no external URLs). Raises the same validation ``AppError``s as
    :func:`store_image`.
    """
    asset = store_image(
        upload,
        category=category,
        owner=owner,
        visibility="public",
        original_name=getattr(upload, "name", ""),
    )
    return f"/api/v1/media/public/{asset.id}/medium"
