import io
import tempfile

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from accounts.models import User
from accounts.services import issue_tokens
from core import runtime_settings as rt
from mediastore.models import MediaAsset

AVATAR_URL = "/api/v1/users/me/avatar"


def _png_bytes(w=400, h=400, color=(30, 120, 200)):
    img = Image.new("RGB", (w, h), color)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@override_settings(
    MEDIA_ROOT=tempfile.mkdtemp(prefix="vsmart-avatar-"),
    MEDIA_INTERNAL_REDIRECT_PREFIX="",
)
class AvatarUploadTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000400401", name="Avatar User")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def test_valid_png_sets_public_avatar_url(self):
        upload = SimpleUploadedFile("me.png", _png_bytes(), content_type="image/png")
        resp = self.client.post(AVATAR_URL, {"file": upload})

        self.assertEqual(resp.status_code, 201)
        body = resp.json()
        self.assertTrue(body["success"])
        avatar_url = body["data"]["avatar_url"]
        self.assertRegex(avatar_url, r"^/api/v1/media/public/[0-9a-f-]+/medium$")

        # Persisted on the user.
        self.user.refresh_from_db()
        self.assertEqual(self.user.avatar_url, avatar_url)

        # A single PUBLIC MediaAsset owned by the user was created.
        asset = MediaAsset.objects.get(owner=self.user)
        self.assertEqual(asset.visibility, MediaAsset.Visibility.PUBLIC)
        self.assertIn(str(asset.id), avatar_url)

    def test_avatar_field_name_also_accepted(self):
        upload = SimpleUploadedFile("me.png", _png_bytes(), content_type="image/png")
        resp = self.client.post(AVATAR_URL, {"avatar": upload})
        self.assertEqual(resp.status_code, 201)

    def test_non_image_is_rejected(self):
        upload = SimpleUploadedFile(
            "notes.txt", b"this is definitely not an image", content_type="text/plain"
        )
        resp = self.client.post(AVATAR_URL, {"file": upload})
        self.assertEqual(resp.json()["code"], "UNSUPPORTED_MEDIA_TYPE")
        self.user.refresh_from_db()
        self.assertFalse(self.user.avatar_url)

    def test_missing_file_is_validation_error(self):
        resp = self.client.post(AVATAR_URL, {})
        self.assertEqual(resp.json()["code"], "VALIDATION_ERROR")

    def test_requires_authentication(self):
        anon = APIClient()
        upload = SimpleUploadedFile("me.png", _png_bytes(), content_type="image/png")
        resp = anon.post(AVATAR_URL, {"file": upload})
        self.assertEqual(resp.status_code, 401)


class AuthOtpTests(TestCase):
    """Customer phone-OTP login: send -> verify -> tokens, wrong-OTP rejection,
    and the 5-attempt lockout. Previously only covered by live smoke scripts."""

    PHONE = "+919000000123"

    def setUp(self):
        cache.clear()  # reset the OTP store + throttle counters between tests
        self.client = APIClient()

    def _send(self):
        r = self.client.post(
            "/api/v1/auth/otp/send", {"phone": self.PHONE}, format="json")
        self.assertEqual(r.status_code, 200)
        return r.json()["data"]["verification_id"]

    def _set_bypass(self, code):
        obj = rt.get_obj()
        obj.otp_bypass_code = code
        obj.save()
        rt.invalidate()

    def test_send_returns_verification_id(self):
        self.assertTrue(self._send())

    def test_wrong_otp_is_rejected_and_creates_no_user(self):
        vid = self._send()
        r = self.client.post(
            "/api/v1/auth/otp/verify",
            {"verification_id": vid, "phone": self.PHONE, "otp": "000000"},
            format="json",
        )
        self.assertEqual(r.json()["code"], "OTP_INVALID")
        self.assertFalse(User.objects.filter(phone=self.PHONE).exists())

    def test_verify_issues_tokens_and_creates_customer(self):
        self._set_bypass("123456")
        vid = self._send()
        r = self.client.post(
            "/api/v1/auth/otp/verify",
            {"verification_id": vid, "phone": self.PHONE, "otp": "123456"},
            format="json",
        )
        self.assertEqual(r.status_code, 200)
        data = r.json()["data"]
        self.assertTrue(data["access_token"])
        self.assertTrue(data["refresh_token"])
        self.assertTrue(data["is_new_user"])
        self.assertTrue(User.objects.filter(phone=self.PHONE).exists())

    def test_otp_locks_out_after_max_attempts(self):
        from django.conf import settings

        from accounts import otp

        vid = otp.generate_and_send(self.PHONE)
        for _ in range(settings.OTP_MAX_ATTEMPTS):
            self.assertFalse(otp.verify(vid, self.PHONE, "000000"))
        # Locked out: the record is cleared, so further attempts also fail.
        self.assertFalse(otp.verify(vid, self.PHONE, "000000"))


class PasswordResetSmsTests(TestCase):
    """Staff/admin password reset now goes over SMS OTP (phone), not email —
    reuses accounts.otp end-to-end (send -> verify -> set_password)."""

    PHONE = "+919000000456"
    CUSTOMER_PHONE = "+919000000789"

    def setUp(self):
        cache.clear()
        self.client = APIClient()
        self.staff = User.objects.create(
            phone=self.PHONE, name="Store Admin", email="admin@example.com",
            role="store_staff",
        )
        self.staff.set_password("OldPassw0rd")
        self.staff.save()
        self.customer = User.objects.create(
            phone=self.CUSTOMER_PHONE, name="Customer", role="customer",
        )

    def _set_bypass(self, code):
        obj = rt.get_obj()
        obj.otp_bypass_code = code
        obj.save()
        rt.invalidate()

    def _forgot(self, phone):
        r = self.client.post(
            "/api/v1/auth/password/forgot", {"phone": phone}, format="json")
        self.assertEqual(r.status_code, 200)
        return r.json()["data"]["verificationId"]

    def test_forgot_password_sends_otp_and_returns_verification_id(self):
        self.assertTrue(self._forgot(self.PHONE))

    def test_reset_with_correct_otp_changes_password(self):
        self._set_bypass("123456")
        vid = self._forgot(self.PHONE)
        r = self.client.post(
            "/api/v1/auth/password/reset",
            {"phone": self.PHONE, "verification_id": vid, "code": "123456",
             "new_password": "NewPassw0rd!"},
            format="json",
        )
        self.assertEqual(r.status_code, 200)
        self.staff.refresh_from_db()
        self.assertTrue(self.staff.check_password("NewPassw0rd!"))

    def test_reset_with_wrong_otp_is_rejected(self):
        vid = self._forgot(self.PHONE)
        r = self.client.post(
            "/api/v1/auth/password/reset",
            {"phone": self.PHONE, "verification_id": vid, "code": "000000",
             "new_password": "NewPassw0rd!"},
            format="json",
        )
        self.assertEqual(r.json()["code"], "INVALID_RESET_CODE")
        self.staff.refresh_from_db()
        self.assertTrue(self.staff.check_password("OldPassw0rd"))

    def test_phone_only_customer_account_cannot_be_reset(self):
        """A phone-OTP-only account (no usable password) can't have one planted
        via password reset, even with a valid OTP for its own phone."""
        self._set_bypass("123456")
        vid = self._forgot(self.CUSTOMER_PHONE)
        r = self.client.post(
            "/api/v1/auth/password/reset",
            {"phone": self.CUSTOMER_PHONE, "verification_id": vid, "code": "123456",
             "new_password": "NewPassw0rd!"},
            format="json",
        )
        self.assertEqual(r.json()["code"], "INVALID_RESET_CODE")
        self.customer.refresh_from_db()
        self.assertFalse(self.customer.check_password("NewPassw0rd!"))


class AuthRefreshRotationTests(TestCase):
    """JWT refresh WITHOUT rotation: the presented refresh token stays valid for
    its whole lifetime. Rotation+blacklist force-signed-out real devices whenever
    the app died before persisting the freshly-minted pair (the only surviving
    token was already blacklisted). Explicit logout still blacklists."""

    def setUp(self):
        cache.clear()
        self.client = APIClient()
        self.user = User.objects.create(phone="+919000000200", name="R")

    def _refresh(self, token):
        return self.client.post(
            "/api/v1/auth/refresh", {"refresh": token}, format="json")

    def test_refresh_does_not_rotate_and_stays_reusable(self):
        old = issue_tokens(self.user)["refresh_token"]
        r1 = self._refresh(old)
        self.assertEqual(r1.status_code, 200)
        data = r1.json()["data"]
        # A usable access token is minted; the refresh token is returned as-is.
        self.assertTrue(data["access_token"])
        self.assertEqual(data["refresh_token"], old)
        # The SAME refresh token keeps working — a killed-before-persist app
        # can retry with what it already has.
        self.assertEqual(self._refresh(old).status_code, 200)

    def test_logout_still_blacklists_the_refresh_token(self):
        tokens = issue_tokens(self.user)
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {tokens['access_token']}")
        r = self.client.post(
            "/api/v1/auth/logout",
            {"refresh_token": tokens["refresh_token"]}, format="json")
        self.assertIn(r.status_code, (200, 204))
        self.client.credentials()
        self.assertEqual(
            self._refresh(tokens["refresh_token"]).status_code, 401)

    def test_garbage_refresh_token_is_401(self):
        self.assertEqual(self._refresh("not-a-jwt").status_code, 401)

    def test_missing_refresh_token_is_400(self):
        r = self.client.post("/api/v1/auth/refresh", {}, format="json")
        self.assertEqual(r.status_code, 400)
