"""Shared byte-serving helper.

When ``MEDIA_INTERNAL_REDIRECT_PREFIX`` is set (prod, behind Caddy/nginx) the web
server streams the file via ``X-Accel-Redirect`` after the view has authorised the
request — Django never pumps the bytes. In dev (prefix unset) Django streams it.

Callers MUST do their own permission check before calling this; it serves the key
unconditionally.
"""
import logging

from django.conf import settings
from django.core.files.storage import default_storage
from django.http import FileResponse, HttpResponse

from core.app_errors import AppError

logger = logging.getLogger("vsmart.media")


def serve_storage_key(key, *, content_type="application/octet-stream"):
    prefix = getattr(settings, "MEDIA_INTERNAL_REDIRECT_PREFIX", "")
    if prefix:
        resp = HttpResponse(content_type=content_type)
        resp["X-Accel-Redirect"] = f"{prefix.rstrip('/')}/{key}"
        return resp
    try:
        return FileResponse(default_storage.open(key, "rb"), content_type=content_type)
    except FileNotFoundError:
        # The MediaAsset row exists but its bytes don't — a half-restored backup,
        # a cleanup that outran its references, a variant that never rendered.
        # Every caller has already authorised the request, so the only honest
        # answer is "that image isn't there", not a 500 telling a store manager
        # the server is broken when they open a delivery proof photo.
        logger.warning("media_missing key=%s", key)
        raise AppError(
            "NOT_FOUND",
            message="That image is no longer available.",
        )
