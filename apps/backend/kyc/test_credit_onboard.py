"""Two-phase credit apply:
  (1) check_credit_eligibility — pull CIBIL for the user's registered number and
      GATE on bureau name + PAN match and score >= CREDIT_MIN_CIBIL (blocks with
      the exact reason otherwise);
  (2) submit_credit_documents — requires a passed check, stores the four scans and
      creates an agent VerificationTask.
The bureau provider is stubbed."""
from io import BytesIO
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from accounts.models import User
from core.app_errors import AppError
from credit import bureau
from kyc.models import KycApplication, KycVerification
from kyc.services import check_credit_eligibility, submit_credit_documents

BUREAU_NAME = "SRINIVASU MAGAPU"
BUREAU_PAN = "EHFPM2162H"
GOOD_SCORE = 780  # >= CREDIT_MIN_CIBIL (700)


def _img(name="doc.jpg"):
    """A tiny valid JPEG upload (passes mediastore's image validation)."""
    from PIL import Image

    buf = BytesIO()
    Image.new("RGB", (12, 12), "white").save(buf, format="JPEG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/jpeg")


def _docs():
    return {
        "aadhaar_front": _img("af.jpg"), "aadhaar_back": _img("ab.jpg"),
        "pan_front": _img("pf.jpg"), "pan_back": _img("pb.jpg"),
    }


def _provider(name=BUREAU_NAME, pan=BUREAU_PAN, score=GOOD_SCORE, status=bureau.SUCCESS):
    class _F:
        name = "payon"

        def fetch_score(self, *, mobile):
            if status != bureau.SUCCESS:
                return bureau.BureauResult(status=status, mobile=mobile)
            return bureau.BureauResult(
                status=bureau.SUCCESS, score=score, band=bureau.band_for(score),
                name=name, pan=pan, mobile=mobile, reference_id="txn1")
    return _F()


class CheckEligibilityTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919494429963", name="")

    def _check(self, provider=None, **kw):
        params = dict(full_name=BUREAU_NAME, pan=BUREAU_PAN, dob="1990-01-01",
                      mobile="9494429963")
        params.update(kw)
        with patch("credit.bureau.get_provider", return_value=provider or _provider()):
            return check_credit_eligibility(self.user, **params)

    def test_pass_records_verified_check(self):
        result = self._check()
        self.assertTrue(result["passed"])
        self.assertEqual(result["score"], GOOD_SCORE)
        v = self.user.kyc_application.verifications.get()
        self.assertEqual(v.status, KycVerification.Status.VERIFIED)

    def test_name_mismatch_blocks(self):
        with self.assertRaises(AppError) as ctx:
            self._check(full_name="SOMEONE ELSE")
        self.assertEqual(ctx.exception.code, "PAN_NAME_MISMATCH")

    def test_pan_mismatch_blocks(self):
        with self.assertRaises(AppError) as ctx:
            self._check(pan="ABCDE1234F")   # valid format, wrong PAN
        self.assertEqual(ctx.exception.code, "PAN_NUMBER_MISMATCH")

    def test_low_score_blocks(self):
        with self.assertRaises(AppError) as ctx:
            self._check(provider=_provider(score=640))
        self.assertEqual(ctx.exception.code, "CIBIL_SCORE_LOW")

    def test_no_record_blocks(self):
        with self.assertRaises(AppError) as ctx:
            self._check(provider=_provider(status=bureau.NO_RECORD))
        self.assertEqual(ctx.exception.code, "CIBIL_NO_RECORD")

    def test_invalid_pan_format(self):
        with self.assertRaises(AppError) as ctx:
            self._check(pan="NOTAPAN")
        self.assertEqual(ctx.exception.code, "PAN_INVALID")


@override_settings(MEDIA_ROOT="/tmp/vsmart_test_media")
class SubmitDocumentsTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919494429963", name="")

    def _pass_check(self):
        with patch("credit.bureau.get_provider", return_value=_provider()):
            check_credit_eligibility(self.user, full_name=BUREAU_NAME, pan=BUREAU_PAN,
                                     dob="1990-01-01", mobile="9494429963")

    def test_submit_requires_passed_check(self):
        with self.assertRaises(AppError) as ctx:
            submit_credit_documents(self.user, files=_docs())
        self.assertEqual(ctx.exception.code, "CIBIL_CHECK_REQUIRED")

    def test_submit_stores_docs_and_creates_agent_task(self):
        from verification.models import VerificationTask

        self._pass_check()
        app, result = submit_credit_documents(self.user, files=_docs())
        self.assertEqual(app.status, KycApplication.Status.PENDING)
        self.assertTrue(result["agentVerification"])
        self.assertEqual(
            {d.type for d in app.documents.all()},
            {"aadhaar_front", "aadhaar_back", "pan_front", "pan_back"},
        )
        self.assertTrue(all(d.file for d in app.documents.all()))
        task = VerificationTask.objects.get(kyc_application=app)
        self.assertEqual(task.type, VerificationTask.Type.KYC)
        self.assertEqual(task.customer_id, self.user.id)
        self.user.refresh_from_db()
        self.assertEqual(self.user.kyc_status, "pending")


@override_settings(MEDIA_ROOT="/tmp/vsmart_test_media")
class CreditApiTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919494429963", name="")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def _check(self, **kw):
        body = {"fullName": BUREAU_NAME, "pan": BUREAU_PAN, "dob": "1990-01-01",
                "consent": True}
        body.update(kw)
        with patch("credit.bureau.get_provider", return_value=_provider()):
            return self.client.post("/api/v1/kyc/credit/check", body, format="json")

    def _submit(self, with_docs=True, **kw):
        body = {"consent": True}
        if with_docs:
            body.update(_docs())
        body.update(kw)
        return self.client.post("/api/v1/kyc/credit/submit", body, format="multipart")

    def test_check_requires_consent(self):
        resp = self.client.post(
            "/api/v1/kyc/credit/check",
            {"fullName": BUREAU_NAME, "pan": BUREAU_PAN, "consent": False},
            format="json")
        self.assertEqual(resp.json()["code"], "CIBIL_CONSENT_REQUIRED")

    def test_check_pass_returns_score(self):
        resp = self._check()
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertEqual(body["code"], "CIBIL_CHECKED")
        self.assertEqual(body["data"]["score"], GOOD_SCORE)

    def test_check_name_mismatch_blocks(self):
        resp = self._check(fullName="WRONG NAME")
        self.assertEqual(resp.json()["code"], "PAN_NAME_MISMATCH")

    def test_submit_requires_check_first(self):
        resp = self._submit()  # docs present, but no passed check
        self.assertEqual(resp.json()["code"], "CIBIL_CHECK_REQUIRED")

    def test_submit_requires_documents(self):
        self._check()
        resp = self._submit(with_docs=False)
        self.assertEqual(resp.json()["code"], "VALIDATION_ERROR")

    def test_full_flow_check_then_submit(self):
        self.assertEqual(self._check().status_code, 200)
        resp = self._submit()
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["code"], "KYC_SUBMITTED")
        self.assertTrue(resp.json()["data"]["agentVerification"])
