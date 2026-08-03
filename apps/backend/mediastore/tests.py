import io
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from accounts.models import User

from .models import MediaAsset
from .pipeline import store_image
from .services import delete_asset

# Isolate every test's writes to a throwaway MEDIA_ROOT.
TMP_MEDIA = tempfile.mkdtemp(prefix="vsmart-media-test-")


def _png_bytes(w=600, h=400, color=(20, 160, 70)):
    img = Image.new("RGB", (w, h), color)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class PipelineTests(TestCase):
    def test_store_image_renders_three_webp_variants(self):
        asset = store_image(_png_bytes(1200, 900), category="products",
                            visibility="public")
        from django.core.files.storage import default_storage

        for variant in ("thumb", "medium", "original"):
            self.assertTrue(
                default_storage.exists(asset.variant_key(variant)),
                f"missing {variant}",
            )
        self.assertEqual(asset.content_type, "image/webp")
        # Original is capped at the 2048 long-edge default; 1200x900 stays as-is.
        self.assertEqual((asset.width, asset.height), (1200, 900))
        self.assertGreater(asset.size_bytes, 0)
        self.assertEqual(len(asset.checksum), 64)

    def test_original_is_downscaled_to_the_cap(self):
        asset = store_image(_png_bytes(4000, 2000), category="products")
        self.assertEqual(max(asset.width, asset.height), 2048)

    @override_settings(MEDIA_MAX_UPLOAD_BYTES=128)
    def test_oversize_is_rejected(self):
        from core.app_errors import AppError

        with self.assertRaises(AppError) as ctx:
            store_image(_png_bytes(), category="products")
        self.assertEqual(ctx.exception.code, "FILE_TOO_LARGE")

    def test_non_image_is_rejected(self):
        from core.app_errors import AppError

        with self.assertRaises(AppError) as ctx:
            store_image(b"this is definitely not an image")
        self.assertEqual(ctx.exception.code, "UNSUPPORTED_MEDIA_TYPE")

    def test_delete_asset_removes_files_and_row(self):
        from django.core.files.storage import default_storage

        asset = store_image(_png_bytes(), category="temp")
        key = asset.variant_key("original")
        self.assertTrue(default_storage.exists(key))
        delete_asset(asset)
        self.assertFalse(default_storage.exists(key))
        self.assertFalse(MediaAsset.objects.filter(pk=asset.id).exists())


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class ServingTests(TestCase):
    def setUp(self):
        self.owner = User.objects.create(phone="+919000000801", name="Owner")
        self.stranger = User.objects.create(phone="+919000000802", name="Stranger")
        self.admin = User.objects.create(
            phone="+919000000803", name="Admin", role="admin"
        )
        self.client = APIClient()

    def test_upload_returns_variant_urls(self):
        self.client.force_authenticate(self.owner)
        upload = SimpleUploadedFile("p.png", _png_bytes(), content_type="image/png")
        resp = self.client.post("/api/v1/media", {"file": upload, "category": "profile"})
        self.assertEqual(resp.status_code, 201)
        body = resp.json()
        self.assertTrue(body["success"])
        self.assertEqual(set(body["data"]["variants"]), {"thumb", "medium", "original"})
        self.assertEqual(MediaAsset.objects.filter(owner=self.owner).count(), 1)

    def test_owner_can_fetch_private_bytes(self):
        asset = store_image(_png_bytes(), owner=self.owner, visibility="private")
        self.client.force_authenticate(self.owner)
        resp = self.client.get(f"/api/v1/media/{asset.id}/thumb")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "image/webp")

    def test_stranger_is_forbidden(self):
        asset = store_image(_png_bytes(), owner=self.owner, visibility="private")
        self.client.force_authenticate(self.stranger)
        resp = self.client.get(f"/api/v1/media/{asset.id}/thumb")
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.json()["code"], "INSUFFICIENT_PERMISSIONS")

    def test_staff_can_fetch_any_private_asset(self):
        asset = store_image(_png_bytes(), owner=self.owner, visibility="private")
        self.client.force_authenticate(self.admin)
        resp = self.client.get(f"/api/v1/media/{asset.id}/medium")
        self.assertEqual(resp.status_code, 200)

    def test_public_asset_is_open(self):
        asset = store_image(_png_bytes(), visibility="public", category="products")
        # No authentication.
        resp = self.client.get(f"/api/v1/media/public/{asset.id}/thumb")
        self.assertEqual(resp.status_code, 200)
        self.assertIn("immutable", resp["Cache-Control"])

    def test_private_asset_not_exposed_via_public_route(self):
        asset = store_image(_png_bytes(), owner=self.owner, visibility="private")
        resp = self.client.get(f"/api/v1/media/public/{asset.id}/thumb")
        self.assertEqual(resp.status_code, 404)

    def test_unknown_variant_404s(self):
        asset = store_image(_png_bytes(), visibility="public")
        resp = self.client.get(f"/api/v1/media/public/{asset.id}/huge")
        self.assertEqual(resp.status_code, 404)
