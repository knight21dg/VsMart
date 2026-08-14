"""API verification (Signzy / Setu / mock) flow tests — all run on the bundled mock
provider, so no live keys or `requests` install is needed."""
from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User

from .models import KycApplication, KycVerification


class VerificationFlowTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000001001", name="Asha Rao")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    # ── PAN ──
    def test_pan_verified_marks_step_records_and_captures_consent(self):
        resp = self.client.post("/api/v1/kyc/pan/verify",
                                {"pan": "ABCPR1234F", "consent": True}, format="json")
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertTrue(body["success"])
        self.assertEqual(body["code"], "PAN_VERIFIED")
        self.assertEqual(body["data"]["status"], "verified")
        self.assertTrue(body["data"]["idMasked"].endswith("234F"))
        self.assertEqual(body["data"]["verifiedDob"], "1995-06-14")
        self.assertTrue(body["data"]["consent"])
        self.assertTrue(body["data"]["verifiedAt"])

        app = KycApplication.objects.get(user=self.user)
        rec = app.verifications.get(kind="pan", status="verified")
        self.assertTrue(rec.consent)
        self.assertIsNotNone(rec.consent_at)
        self.assertIsNotNone(rec.verified_at)
        # Aadhaar address is deliberately NOT stored for marketplace KYC.
        self.assertEqual(rec.verified_address, "")
        self.assertEqual(app.steps.get(step="pan").status, "approved")

    def test_pan_invalid_returns_coded_failure(self):
        resp = self.client.post("/api/v1/kyc/pan/verify",
                                {"pan": "ABCDE1234B", "consent": True}, format="json")
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["code"], "PAN_INVALID")

    def test_pan_name_mismatch(self):
        resp = self.client.post("/api/v1/kyc/pan/verify",
                                {"pan": "MISMT1234A", "consent": True}, format="json")
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["code"], "PAN_NAME_MISMATCH")

    def test_pan_requires_consent(self):
        resp = self.client.post("/api/v1/kyc/pan/verify",
                                {"pan": "ABCPR1234F"}, format="json")
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["code"], "CONSENT_REQUIRED")

    # ── Aadhaar: DigiLocker — ONE provider (Payon), no mock ──
    #
    # This used to run on the mock verifier and assert AADHAAR_VERIFIED. That made
    # a green test out of a fabricated government identity: with no credentials
    # configured anywhere (the state prod is in today), the generic selector falls
    # through to MockProvider, which returns "verified" for any input. DigiLocker
    # now resolves only to Payon, so an unconfigured install fails loudly.
    def test_digilocker_without_credentials_fails_loudly(self):
        start = self.client.post("/api/v1/kyc/aadhaar/digilocker/start", {}, format="json")
        self.assertEqual(start.status_code, 503)
        self.assertEqual(start.json()["code"], "KYC_PROVIDER_ERROR")
        # Nothing was recorded — an unconfigured provider must not create a step.
        self.assertFalse(
            KycApplication.objects.filter(user=self.user)
            .filter(steps__step="aadhaar", steps__status="approved").exists())

    #: What a live `digilocker_initiate.php` success actually looks like, captured
    #: from the vendor on 2026-08-11 against a funded wallet.
    LIVE_INITIATE = {
        "success": True,
        "message": "DigiLocker session initiated. Redirect user to authUrl",
        "data": {
            "recordId": "rec_456", "publicId": "digilocker_1786467333601_g2lqh4o1e",
            "authUrl": "https://digilocker.idto.ai/digilocker?client_id=e7b&state=st_123",
            "state": "st_123",
            "accountCheck": {"status": True, "code": 1004, "accountExists": True},
            "redirectToSignup": False},
        "statusCode": 200,
    }

    def test_digilocker_start_calls_payon_and_returns_the_consent_url(self):
        from unittest.mock import patch

        with patch("kyc.providers.payon._post",
                   return_value=self.LIVE_INITIATE) as post:
            start = self.client.post("/api/v1/kyc/aadhaar/digilocker/start",
                                     {}, format="json")
        self.assertEqual(start.status_code, 200)
        data = start.json()["data"]
        self.assertEqual(data["referenceId"], "rec_456")
        self.assertTrue(data["redirectUrl"].startswith("https://digilocker.idto.ai/"))
        path, fields = post.call_args[0]
        self.assertEqual(path, "/digilocker_initiate.php")
        self.assertTrue(fields["redirectUrl"])
        # The state is kept so the completion call can present it back.
        rec = KycVerification.objects.get(reference_id="rec_456")
        self.assertEqual(rec.raw["state"], "st_123")
        self.assertIs(rec.raw["accountExists"], True)

    def test_digilocker_sends_the_field_types_the_vendor_enforces(self):
        """The vendor validates types, and its own PHP sample gets them wrong.

        Each of these was a live `Validation error` before it was fixed, and the
        previous version of this test pinned the broken shape (`consent="Y"`,
        a comma-joined document string) — so the integration could not work while
        the suite stayed green. Asserted at the `requests` boundary, because the
        array encoding only exists once the form is built.
        """
        from unittest.mock import patch

        resp = type("R", (), {"status_code": 200,
                              "json": lambda self: self.LIVE})()
        resp.LIVE = self.LIVE_INITIATE
        with patch("kyc.providers.payon.requests.post", return_value=resp) as post, \
                patch("kyc.providers.payon._api_key", return_value="k"):
            self.client.post("/api/v1/kyc/aadhaar/digilocker/start", {}, format="json")

        sent = post.call_args.kwargs["data"]
        # "Y" is rejected with '"consent" must be a boolean'.
        self.assertIn(str(sent["consent"]).lower(), ("true", "1"))
        # A joined string is rejected with '"documentsForConsent" must be an array';
        # `requests` renders a list as the repeated keys the API wants.
        self.assertEqual(sent["documentsForConsent[]"], ["AADHAAR"])
        self.assertNotIn("documentsForConsent", sent)
        # Required, and the bare 10 digits — the user is stored as E.164.
        self.assertEqual(sent["mobileNumber"], "9000001001")

    def test_digilocker_start_without_a_mobile_is_refused_before_the_call(self):
        """The vendor requires it; failing here beats spending a wallet charge."""
        from unittest.mock import patch

        from kyc.providers.payon import PayonProvider, ProviderError

        with patch("kyc.providers.payon._post") as post:
            with self.assertRaises(ProviderError):
                PayonProvider().start_digilocker(
                    redirect_url="https://x.test/cb", mobile="")
        post.assert_not_called()

    def test_digilocker_status_replays_the_state_from_the_start_record(self):
        """The status GET carries no state, so it must be recovered, not dropped."""
        from unittest.mock import patch

        with patch("kyc.providers.payon._post", return_value=self.LIVE_INITIATE):
            self.client.post("/api/v1/kyc/aadhaar/digilocker/start", {}, format="json")

        pending = {"success": True, "data": {"status": "PENDING"}}
        with patch("kyc.providers.payon._post", return_value=pending) as post:
            self.client.get("/api/v1/kyc/aadhaar/digilocker/rec_456/status")
        _, fields = post.call_args[0]
        self.assertEqual(fields["state"], "st_123")
        self.assertEqual(fields["recordId"], "rec_456")

    # ── Aadhaar: OTP eKYC (primary, no DigiLocker) ──
    def test_aadhaar_otp_flow(self):
        init = self.client.post("/api/v1/kyc/aadhaar/send-otp",
                                {"aadhaar": "999988887777"}, format="json")
        self.assertEqual(init.status_code, 200)
        self.assertEqual(init.json()["code"], "AADHAAR_OTP_SENT")
        ref = init.json()["data"]["referenceId"]

        bad = self.client.post("/api/v1/kyc/aadhaar/verify-otp",
                               {"reference_id": ref, "otp": "000000",
                                "aadhaar": "999988887777"}, format="json")
        self.assertEqual(bad.status_code, 400)
        self.assertEqual(bad.json()["code"], "AADHAAR_OTP_INVALID")

        good = self.client.post("/api/v1/kyc/aadhaar/verify-otp",
                                {"reference_id": ref, "otp": "123456",
                                 "aadhaar": "999988887777"}, format="json")
        self.assertEqual(good.status_code, 200)
        self.assertEqual(good.json()["code"], "AADHAAR_VERIFIED")

    # ── Bank ──
    def test_bank_verify_success_and_failure(self):
        ok = self.client.post("/api/v1/kyc/bank/verify",
                              {"account": "123456789012", "ifsc": "HDFC0001234"},
                              format="json")
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.json()["code"], "BANK_VERIFIED")

        bad = self.client.post("/api/v1/kyc/bank/verify",
                               {"account": "abc", "ifsc": "nope"}, format="json")
        self.assertEqual(bad.status_code, 400)
        self.assertEqual(bad.json()["code"], "BANK_VERIFICATION_FAILED")

    # ── Retry re-opens a rejected application ──
    def test_retry_reopens_rejected_application(self):
        app = KycApplication.objects.create(
            user=self.user, status=KycApplication.Status.REJECTED,
            rejection_reason="blurry")
        resp = self.client.post("/api/v1/kyc/retry", {}, format="json")
        self.assertEqual(resp.status_code, 200)
        app.refresh_from_db()
        self.assertEqual(app.status, KycApplication.Status.PENDING)
        self.assertEqual(app.rejection_reason, "")

    # ── Fraud: same gov id on two accounts ──
    def test_duplicate_pan_on_another_account_is_blocked(self):
        self.client.post("/api/v1/kyc/pan/verify",
                         {"pan": "ABCPR1234F", "consent": True}, format="json")

        other = User.objects.create(phone="+919000001002", name="Other User")
        c2 = APIClient()
        c2.force_authenticate(other)
        resp = c2.post("/api/v1/kyc/pan/verify",
                       {"pan": "ABCPR1234F", "consent": True}, format="json")
        self.assertEqual(resp.status_code, 409)
        self.assertEqual(resp.json()["code"], "DUPLICATE_KYC")
        self.assertTrue(KycVerification.objects.filter(
            application__user=other, kind="pan", status="failed").exists())


class ProviderSelectionTests(TestCase):
    def test_defaults_to_mock_without_keys(self):
        from .providers import get_provider

        self.assertEqual(get_provider().name, "mock")

    def test_signzy_selected_when_configured(self):
        from core import runtime_settings as rt
        from .providers import get_provider

        obj = rt.get_obj()
        obj.kyc_provider = "signzy"
        obj.signzy_api_key = "test-key"
        obj.save()
        rt.invalidate()
        try:
            # SignzyProvider builds fine (network is only touched on an actual call).
            self.assertEqual(get_provider().name, "signzy")
        finally:
            obj.kyc_provider = ""
            obj.signzy_api_key = ""
            obj.save()
            rt.invalidate()

    def test_cashfree_selected_when_configured(self):
        from core import runtime_settings as rt
        from .providers import get_provider

        obj = rt.get_obj()
        obj.kyc_provider = "cashfree"
        obj.cashfree_app_id = "test-id"
        obj.cashfree_secret_key = "test-secret"
        obj.save()
        rt.invalidate()
        try:
            self.assertEqual(get_provider().name, "cashfree")
        finally:
            obj.kyc_provider = ""
            obj.cashfree_app_id = ""
            obj.cashfree_secret_key = ""
            obj.save()
            rt.invalidate()
