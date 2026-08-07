"""CIBIL / credit-bureau score: provider parsing, service (consent + dedup +
persistence), and the customer / admin APIs.

There's one live provider (Payon). The provider's HTTP call is stubbed here — the
parsing test mocks `requests.post`; the service/API tests patch `get_provider`
with an in-test fake — so nothing touches the network."""
import sys
import types
from unittest.mock import MagicMock, patch

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from core.app_errors import AppError

from . import bureau
from .models import CreditBureauReport
from .services import fetch_bureau_score, latest_bureau_report


def _fake_requests(json_body, status=200):
    """A stand-in `requests` module (the real one isn't installed in dev/CI)."""
    mod = types.ModuleType("requests")

    class RequestException(Exception):
        pass

    resp = MagicMock(status_code=status)
    resp.json.return_value = json_body
    mod.RequestException = RequestException
    mod.post = MagicMock(return_value=resp)
    return mod


def _success(mobile):
    return bureau.BureauResult(
        status=bureau.SUCCESS, score=704, band="Good", name="MAGAPU LAXMI",
        pan="GHFPM4260N", mobile=mobile, reference_id="txn_" + mobile[-4:])


def _no_record(mobile):
    return bureau.BureauResult(status=bureau.NO_RECORD, mobile=mobile, message="none")


def _fake_provider(result_fn):
    """A stand-in provider whose fetch_score returns `result_fn(mobile)`."""
    class _F:
        name = "payon"

        def fetch_score(self, *, mobile):
            return result_fn(mobile)
    return _F()


class ProviderPatchMixin:
    """Patch the bureau provider so no test hits the live API."""

    result_fn = staticmethod(_success)

    def setUp(self):
        super().setUp()
        p = patch("credit.bureau.get_provider",
                  return_value=_fake_provider(type(self).result_fn))
        p.start()
        self.addCleanup(p.stop)


# ── Provider parsing (real PayonBureau, mocked HTTP) ──
class BureauProviderTests(TestCase):
    def test_band(self):
        self.assertEqual(bureau.band_for(800), "Excellent")
        self.assertEqual(bureau.band_for(704), "Good")
        self.assertEqual(bureau.band_for(0), "No Score")

    def test_default_provider_is_payon(self):
        self.assertEqual(bureau.get_provider().name, "payon")

    @patch("credit.bureau.runtime.cfg")
    def test_payon_parses_nested_data_success(self, mock_cfg):
        # The live API nests the credit fields under `data` (see 9494429963).
        mock_cfg.side_effect = lambda k: "key" if k == "credit_bureau_api_key" else ""
        fake = _fake_requests({
            "success": True, "status": "SUCCESS",
            "data": {
                "success": True, "status": "SUCCESS", "creditScore": 574,
                "scoreBand": None, "name": "SRINIVASU MAGAPU", "pan": "EHFPM2162H",
                "mobile": "9494429963", "transactionId": "t1", "chargeable": True,
            },
        })
        with patch.dict(sys.modules, {"requests": fake}):
            r = bureau.PayonBureau().fetch_score(mobile="9494429963")
        self.assertTrue(r.ok)
        self.assertEqual(r.score, 574)
        self.assertEqual(r.band, "Below Average")  # computed when API sends null
        self.assertEqual(r.pan, "EHFPM2162H")
        self.assertEqual(r.name, "SRINIVASU MAGAPU")

    @patch("credit.bureau.runtime.cfg")
    def test_payon_parses_documented_verified_response(self, mock_cfg):
        """The published API contract verbatim: status is "VERIFIED" (not
        "SUCCESS") and the band arrives as `scoreCategory`. Matching only
        "SUCCESS" made a perfectly good response fall through to the error
        branch and surface as a provider failure."""
        mock_cfg.side_effect = lambda k: "key" if k == "credit_bureau_api_key" else ""
        fake = _fake_requests({
            "success": True,
            "status": "VERIFIED",
            "data": {
                "mobile": "9876543210", "creditScore": 750,
                "scoreCategory": "GOOD", "bureau": "EXPERIAN",
                "reportDate": "2026-01-15",
            },
        })
        with patch.dict(sys.modules, {"requests": fake}):
            r = bureau.PayonBureau().fetch_score(mobile="9876543210")
        self.assertTrue(r.ok)
        self.assertEqual(r.score, 750)
        self.assertEqual(r.band, "GOOD")
        self.assertEqual(r.mobile, "9876543210")
        self.assertEqual(r.raw.get("bureau"), "EXPERIAN")
        self.assertEqual(r.raw.get("reportDate"), "2026-01-15")

    @patch("credit.bureau.runtime.cfg")
    def test_payon_permission_denied_raises_provider_error(self, mock_cfg):
        """A reseller key that isn't entitled to the credit-score service returns
        HTTP 200 with statusCode 400. It must surface as a provider/config error,
        never as "no credit record found" for the customer."""
        mock_cfg.side_effect = lambda k: "key" if k == "credit_bureau_api_key" else ""
        fake = _fake_requests({
            "statusCode": 400, "status": 400,
            "message": "Error: Permission denied for this service",
        })
        with patch.dict(sys.modules, {"requests": fake}):
            with self.assertRaises(bureau.BureauError) as ctx:
                bureau.PayonBureau().fetch_score(mobile="9876543210")
        self.assertIn("Permission denied", str(ctx.exception))

    @patch("credit.bureau.runtime.cfg")
    def test_payon_parses_top_level_fallback(self, mock_cfg):
        # Defensive: also handle a flat (non-nested) success payload.
        mock_cfg.side_effect = lambda k: "key" if k == "credit_bureau_api_key" else ""
        fake = _fake_requests({
            "success": True, "status": "SUCCESS", "creditScore": 704,
            "name": "MAGAPU LAXMI", "pan": "GHFPM4260N", "mobile": "9347625148",
        })
        with patch.dict(sys.modules, {"requests": fake}):
            r = bureau.PayonBureau().fetch_score(mobile="9347625148")
        self.assertTrue(r.ok)
        self.assertEqual(r.score, 704)

    @patch("credit.bureau.runtime.cfg")
    def test_payon_empty_report_is_no_record(self, mock_cfg):
        mock_cfg.side_effect = lambda k: "key" if k == "credit_bureau_api_key" else ""
        fake = _fake_requests({
            "success": True, "status": "SUCCESS",
            "data": {"success": True, "status": "SUCCESS", "creditScore": 0},
        })
        with patch.dict(sys.modules, {"requests": fake}):
            r = bureau.PayonBureau().fetch_score(mobile="9347625148")
        self.assertEqual(r.status, bureau.NO_RECORD)

    @patch("credit.bureau.runtime.cfg", return_value="")
    def test_missing_key_raises(self, _cfg):
        with self.assertRaises(bureau.BureauError):
            bureau.PayonBureau().fetch_score(mobile="9347625148")

    @patch("credit.bureau.runtime.cfg")
    def test_payon_invalid_key_raises_provider_error(self, mock_cfg):
        # Payon answers HTTP 200 with a 4xx statusCode + message for a bad/expired
        # key. This must surface as a provider error, NOT a silent "no record".
        mock_cfg.side_effect = lambda k: "key" if k == "credit_bureau_api_key" else ""
        fake = _fake_requests(
            {"statusCode": 400, "status": 400, "message": "Error: Invalid API key"})
        with patch.dict(sys.modules, {"requests": fake}):
            with self.assertRaises(bureau.BureauError) as ctx:
                bureau.PayonBureau().fetch_score(mobile="9494429963")
        self.assertIn("Invalid API key", str(ctx.exception))

    @patch("credit.bureau.runtime.cfg")
    def test_payon_permission_denied_raises_provider_error(self, mock_cfg):
        """Observed live 2026-08-05 on the reseller host: the key is recognised
        but credit-score isn't entitled on the account. The reviewer must see a
        provider error — showing "no credit record found" would blame the
        customer for a vendor provisioning gap."""
        mock_cfg.side_effect = lambda k: "key" if k == "credit_bureau_api_key" else ""
        fake = _fake_requests({
            "statusCode": 400, "status": 400,
            "message": "Error: Permission denied for this service",
        })
        with patch.dict(sys.modules, {"requests": fake}):
            with self.assertRaises(bureau.BureauError) as ctx:
                bureau.PayonBureau().fetch_score(mobile="9494429963")
        self.assertIn("Permission denied", str(ctx.exception))

    @patch("credit.bureau.runtime.cfg")
    def test_payon_http_500_raises(self, mock_cfg):
        mock_cfg.side_effect = lambda k: "key" if k == "credit_bureau_api_key" else ""
        fake = _fake_requests({"message": "upstream down"}, status=500)
        with patch.dict(sys.modules, {"requests": fake}):
            with self.assertRaises(bureau.BureauError):
                bureau.PayonBureau().fetch_score(mobile="9494429963")


class BureauServiceTests(ProviderPatchMixin, TestCase):
    def setUp(self):
        super().setUp()
        self.user = User.objects.create(phone="+919347625148", name="Laxmi")

    def test_consent_is_mandatory(self):
        with self.assertRaises(AppError) as ctx:
            fetch_bureau_score(self.user, mobile="9347625148", consent=False)
        self.assertEqual(ctx.exception.code, "CIBIL_CONSENT_REQUIRED")

    def test_invalid_mobile_rejected(self):
        with self.assertRaises(AppError) as ctx:
            fetch_bureau_score(self.user, mobile="123", consent=True)
        self.assertEqual(ctx.exception.code, "VALIDATION_ERROR")

    def test_success_persists_report(self):
        report = fetch_bureau_score(self.user, mobile="9347625148", consent=True)
        self.assertEqual(report.status, CreditBureauReport.Status.SUCCESS)
        self.assertEqual(report.score, 704)
        self.assertEqual(report.pan, "GHFPM4260N")   # full PAN, unmasked
        self.assertTrue(report.consent)
        self.assertEqual(report.provider, "payon")
        self.assertEqual(latest_bureau_report(self.user).id, report.id)

    def test_e164_mobile_is_normalised(self):
        report = fetch_bureau_score(self.user, mobile="+91 93476 25148", consent=True)
        self.assertEqual(report.mobile, "9347625148")

    def test_dedup_reuses_recent_success(self):
        first = fetch_bureau_score(self.user, mobile="9347625148", consent=True)
        second = fetch_bureau_score(self.user, mobile="9347625148", consent=True)
        self.assertEqual(first.id, second.id)
        self.assertEqual(self.user.bureau_reports.count(), 1)

    def test_force_bypasses_dedup(self):
        fetch_bureau_score(self.user, mobile="9347625148", consent=True)
        fetch_bureau_score(self.user, mobile="9347625148", consent=True, force=True)
        self.assertEqual(self.user.bureau_reports.count(), 2)


class BureauNoRecordServiceTests(ProviderPatchMixin, TestCase):
    result_fn = staticmethod(_no_record)

    def test_no_record_persisted(self):
        user = User.objects.create(phone="+919000000001", name="NR")
        report = fetch_bureau_score(user, mobile="9000000001", consent=True)
        self.assertEqual(report.status, CreditBureauReport.Status.NO_RECORD)
        self.assertEqual(report.score, 0)


class CustomerCibilApiTests(ProviderPatchMixin, TestCase):
    def setUp(self):
        super().setUp()
        self.user = User.objects.create(phone="+919347625148", name="Laxmi")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def test_check_requires_consent(self):
        resp = self.client.post("/api/v1/credit/cibil/check",
                                {"mobile": "9347625148"}, format="json")
        self.assertEqual(resp.json()["code"], "CIBIL_CONSENT_REQUIRED")

    def test_check_success(self):
        resp = self.client.post("/api/v1/credit/cibil/check",
                                {"mobile": "9347625148", "consent": True}, format="json")
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertEqual(body["code"], "CIBIL_FETCHED")
        self.assertEqual(body["data"]["score"], 704)
        self.assertEqual(body["data"]["band"], "Good")

    def test_latest_reflects_stored(self):
        self.client.post("/api/v1/credit/cibil/check",
                         {"mobile": "9347625148", "consent": True}, format="json")
        resp = self.client.get("/api/v1/credit/cibil")
        self.assertEqual(resp.status_code, 200)
        report = resp.json()["data"]["report"]
        self.assertIsNotNone(report)
        self.assertEqual(report["score"], 704)

    def test_latest_null_when_never_checked(self):
        resp = self.client.get("/api/v1/credit/cibil")
        self.assertIsNone(resp.json()["data"]["report"])


class AdminCibilApiTests(ProviderPatchMixin, TestCase):
    def setUp(self):
        super().setUp()
        self.customer = User.objects.create(phone="+919347625148", name="Laxmi")
        self.admin = User.objects.create(phone="+919999999999", name="Boss", role="admin")
        self.cust_client = APIClient()
        self.cust_client.force_authenticate(self.customer)
        self.admin_client = APIClient()
        self.admin_client.force_authenticate(self.admin)

    def _customer_self_check(self):
        return self.cust_client.post(
            "/api/v1/credit/cibil/check",
            {"mobile": "9347625148", "consent": True}, format="json")

    def test_admin_view_and_refresh(self):
        self._customer_self_check()
        url = f"/api/v1/admin/credit/cibil/{self.customer.id}"
        resp = self.admin_client.get(url)
        self.assertEqual(resp.status_code, 200)
        self.assertIsNotNone(resp.json()["data"]["report"])
        # refresh — re-pulls (force), writing a new history row
        resp = self.admin_client.post(url)
        self.assertEqual(resp.json()["code"], "CIBIL_FETCHED")
        self.assertEqual(self.customer.bureau_reports.count(), 2)
        self.assertEqual(
            self.customer.bureau_reports.first().source,
            CreditBureauReport.Source.ADMIN)

    def test_refresh_blocked_without_prior_consent(self):
        url = f"/api/v1/admin/credit/cibil/{self.customer.id}"
        resp = self.admin_client.post(url)
        self.assertEqual(resp.json()["code"], "CIBIL_CONSENT_REQUIRED")

    def test_customer_cannot_use_admin_endpoint(self):
        resp = self.cust_client.get(
            f"/api/v1/admin/credit/cibil/{self.customer.id}")
        self.assertEqual(resp.status_code, 403)
