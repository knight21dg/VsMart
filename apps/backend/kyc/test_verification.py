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

    # ── Aadhaar: DigiLocker (optional path) ──
    def test_digilocker_start_then_status(self):
        start = self.client.post("/api/v1/kyc/aadhaar/digilocker/start", {}, format="json")
        self.assertEqual(start.status_code, 200)
        ref = start.json()["data"]["referenceId"]
        self.assertTrue(start.json()["data"]["redirectUrl"])

        status = self.client.get(f"/api/v1/kyc/aadhaar/digilocker/{ref}/status")
        self.assertEqual(status.status_code, 200)
        self.assertEqual(status.json()["code"], "AADHAAR_VERIFIED")
        app = KycApplication.objects.get(user=self.user)
        self.assertEqual(app.steps.get(step="aadhaar").status, "approved")

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
