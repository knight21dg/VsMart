"""Changing your own password while signed in.

There was no way to do this anywhere in the product. The only route to a new
password was the signed-*out* forgot-password flow, which needs an OTP to the
account's registered phone — useless to an admin rotating a password they
already know, and impossible for a store account whose phone has changed hands.
"""
from django.conf import settings
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from accounts.models import Role, User

URL = "/api/v1/auth/password/change"

# The endpoint shares the OTP throttle scope, so a rate limit could make these
# flaky. MERGE the rates into the real config — replacing REST_FRAMEWORK
# wholesale would also drop EXCEPTION_HANDLER, and every AppError would then
# escape as an unhandled exception instead of its proper envelope.
NO_THROTTLE = {
    **settings.REST_FRAMEWORK,
    "DEFAULT_THROTTLE_RATES": {
        **settings.REST_FRAMEWORK.get("DEFAULT_THROTTLE_RATES", {}),
        "otp": None,
        "anon": None,
        "user": None,
    },
}


@override_settings(REST_FRAMEWORK=NO_THROTTLE)
class ChangePasswordTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(
            phone="+919600044001", name="Admin", role=Role.ADMIN,
            email="pwadmin@vsmart.test",
        )
        self.admin.set_password("old-password-1")
        self.admin.save(update_fields=["password"])
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def _post(self, **body):
        return self.client.post(URL, body, format="json")

    def test_a_correct_change_updates_the_password(self):
        r = self._post(
            current_password="old-password-1",
            new_password="brand-new-pass-9",
            confirm_password="brand-new-pass-9",
        )
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.json()["code"], "PASSWORD_CHANGED")
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.check_password("brand-new-pass-9"))
        self.assertFalse(self.admin.check_password("old-password-1"))

    def test_the_new_password_actually_signs_in(self):
        """The real acceptance test: the change must be usable at the door."""
        self._post(current_password="old-password-1", new_password="brand-new-pass-9")
        anon = APIClient()
        r = anon.post(
            "/api/v1/auth/login",
            {"email": "pwadmin@vsmart.test", "password": "brand-new-pass-9"},
            format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        self.assertTrue(r.json()["data"]["access_token"])

    def test_a_wrong_current_password_is_refused_and_changes_nothing(self):
        r = self._post(current_password="not-my-password", new_password="brand-new-pass-9")
        self.assertEqual(r.status_code, 400, r.content)
        self.assertEqual(r.json()["code"], "CURRENT_PASSWORD_WRONG")
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.check_password("old-password-1"))

    def test_mismatched_confirmation_is_refused_server_side(self):
        """The browser checks this too, but the endpoint is reachable without
        the form and a typo would lock the operator out."""
        r = self._post(
            current_password="old-password-1",
            new_password="brand-new-pass-9",
            confirm_password="brand-new-pass-8",
        )
        self.assertEqual(r.status_code, 400, r.content)
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.check_password("old-password-1"))

    def test_reusing_the_current_password_is_refused(self):
        r = self._post(
            current_password="old-password-1", new_password="old-password-1"
        )
        self.assertEqual(r.status_code, 400, r.content)

    def test_a_weak_password_is_refused(self):
        r = self._post(current_password="old-password-1", new_password="1234")
        self.assertEqual(r.status_code, 400, r.content)
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.check_password("old-password-1"))

    def test_signing_out_is_not_forced(self):
        """A voluntary rotation must not eject the operator mid-task."""
        self._post(current_password="old-password-1", new_password="brand-new-pass-9")
        self.assertEqual(self.client.get("/api/v1/users/me").status_code, 200)

    def test_anonymous_callers_are_rejected(self):
        anon = APIClient()
        r = anon.post(
            URL,
            {"current_password": "x", "new_password": "brand-new-pass-9"},
            format="json",
        )
        self.assertEqual(r.status_code, 401)

    def test_an_otp_only_account_is_told_it_has_no_password(self):
        """Customers and agents sign in with a one-time code and are created
        with no password at all. `has_usable_password()` can't detect that —
        Django calls a blank password "usable" — so the gate is by role."""
        customer = User.objects.create(
            phone="+919600044002", name="Cust", role=Role.CUSTOMER
        )
        client = APIClient()
        client.force_authenticate(customer)
        r = client.post(
            URL,
            {"current_password": "anything", "new_password": "brand-new-pass-9"},
            format="json",
        )
        self.assertEqual(r.status_code, 400, r.content)
        self.assertEqual(r.json()["code"], "PASSWORD_LOGIN_UNAVAILABLE")

    def test_store_staff_may_change_their_password(self):
        staff = User.objects.create(
            phone="+919600044003", name="Staff", role=Role.STORE_STAFF,
            email="pwstaff@vsmart.test",
        )
        staff.set_password("store-old-pass-1")
        staff.save(update_fields=["password"])
        client = APIClient()
        client.force_authenticate(staff)
        r = client.post(
            URL,
            {"current_password": "store-old-pass-1", "new_password": "store-new-pass-9"},
            format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        staff.refresh_from_db()
        self.assertTrue(staff.check_password("store-new-pass-9"))

    def test_the_change_is_written_to_the_audit_trail(self):
        from accounts.models import AuditLog

        self._post(current_password="old-password-1", new_password="brand-new-pass-9")
        self.assertTrue(
            AuditLog.objects.filter(
                actor=self.admin, action="auth.password_change"
            ).exists()
        )
