"""Shared byte-serving helper.

When ``MEDIA_INTERNAL_REDIRECT_PREFIX`` is set (prod, behind Caddy/nginx) the web
server streams the file via ``X-Accel-Redirect`` after the view has authorised the
request — Django never pumps the bytes. In dev (prefix unset) Django streams it.

Callers MUST do their own permission check before calling this; it serves the key
unconditionally.
"""
from django.conf import settings
from django.core.files.storage import default_storage
from django.http import FileResponse, HttpResponse


def serve_storage_key(key, *, content_type="application/octet-stream"):
    prefix = getattr(settings, "MEDIA_INTERNAL_REDIRECT_PREFIX", "")
    if prefix:
        resp = HttpResponse(content_type=content_type)
        resp["X-Accel-Redirect"] = f"{prefix.rstrip('/')}/{key}"
        return resp
    return FileResponse(default_storage.open(key, "rb"), content_type=content_type)
