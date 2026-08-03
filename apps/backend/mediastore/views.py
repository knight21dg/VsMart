"""Media endpoints.

  POST /api/v1/media                       authenticated upload → private asset
  GET  /api/v1/media/<uuid>/<variant>      private: owner-or-staff gated bytes
  GET  /api/v1/media/public/<uuid>/<var>   public: open, CDN-cacheable bytes

Byte-serving: when ``MEDIA_INTERNAL_REDIRECT_PREFIX`` is set (prod, behind
Caddy/nginx) Django authorises the request and hands the actual streaming to the
web server via ``X-Accel-Redirect`` — so we never pump megabytes through Python.
In dev (prefix unset) Django streams the file itself.
"""
from django.core.files.storage import default_storage
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError, ok

from .models import MediaAsset
from .pipeline import store_image
from .serving import serve_storage_key

VARIANTS = ("thumb", "medium", "original")


def _variant_or_404(variant: str) -> str:
    if variant not in VARIANTS:
        raise AppError("NOT_FOUND")
    return variant


def _resolve_key(asset, variant: str) -> str:
    """Storage key for the requested variant, falling back to the original if a
    specific size is missing. Raises NOT_FOUND if nothing is stored."""
    key = asset.variant_key(variant)
    if default_storage.exists(key):
        return key
    original = asset.variant_key("original")
    if default_storage.exists(original):
        return original
    raise AppError("NOT_FOUND")


def _serve(asset, variant: str):
    key = _resolve_key(asset, variant)
    return serve_storage_key(key, content_type="image/webp")


class MediaUploadView(APIView):
    """Authenticated multipart upload. Stores a private asset owned by the caller
    and returns the variant URLs the client should render."""

    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        upload = request.FILES.get("file")
        if upload is None:
            raise AppError("VALIDATION_ERROR", fields={"file": ["A file is required."]})
        asset = store_image(
            upload,
            category=request.data.get("category") or "misc",
            owner=request.user,
            visibility="private",
            original_name=getattr(upload, "name", ""),
        )
        data = {
            "id": str(asset.id),
            "variants": {v: f"/api/v1/media/{asset.id}/{v}" for v in VARIANTS},
        }
        return Response(ok("MEDIA_UPLOADED", data=data), status=201)


class PrivateMediaView(APIView):
    """Serve a private asset only to its owner (or admin/superadmin staff)."""

    permission_classes = [IsAuthenticated]

    def get(self, request, pk, variant):
        variant = _variant_or_404(variant)
        try:
            asset = MediaAsset.objects.get(pk=pk)
        except MediaAsset.DoesNotExist:
            raise AppError("NOT_FOUND")
        user = request.user
        is_staff = getattr(user, "role", "") in ("admin", "superadmin")
        if asset.visibility == MediaAsset.Visibility.PRIVATE and not (
            asset.owner_id == user.id or is_staff
        ):
            raise AppError("INSUFFICIENT_PERMISSIONS")
        resp = _serve(asset, variant)
        resp["Cache-Control"] = "private, max-age=60"
        return resp


class PublicMediaView(APIView):
    """Serve a public asset to anyone. The unguessable UUID is the access control;
    responses are immutable + long-cached so a CDN/Caddy can take the load."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request, pk, variant):
        variant = _variant_or_404(variant)
        try:
            asset = MediaAsset.objects.get(
                pk=pk, visibility=MediaAsset.Visibility.PUBLIC
            )
        except MediaAsset.DoesNotExist:
            raise AppError("NOT_FOUND")
        resp = _serve(asset, variant)
        resp["Cache-Control"] = "public, max-age=31536000, immutable"
        return resp
