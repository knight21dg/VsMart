import io
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from accounts.models import User

from .models import KycApplication, KycDocument

TMP_MEDIA = tempfile.mkdtemp(prefix="vsmart-kyc-test-")


def _png_upload(name="aadhaar.png"):
    img = Image.new("RGB", (300, 200), (10, 120, 60))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/png")


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class KycDocumentServingTests(TestCase):
    """The fix: identity documents are served only behind an ownership/reviewer
    gate, never on a guessable unauthenticated MEDIA url."""

    def setUp(self):
        self.owner = User.objects.create(phone="+919000000901", name="Owner")
        self.stranger = User.objects.create(phone="+919000000902", name="Stranger")
        self.agent = User.objects.create(
            phone="+919000000903", name="Agent", role="agent"
        )
        self.app = KycApplication.objects.create(user=self.owner)
        self.doc = KycDocument.objects.create(
            application=self.app, type="aadhaar", file=_png_upload()
        )
        self.client = APIClient()

    def test_owner_can_fetch_document(self):
        self.client.force_authenticate(self.owner)
        resp = self.client.get(f"/api/v1/kyc/documents/{self.doc.pk}/file")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "image/png")

    def test_stranger_is_forbidden(self):
        self.client.force_authenticate(self.stranger)
        resp = self.client.get(f"/api/v1/kyc/documents/{self.doc.pk}/file")
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.json()["code"], "INSUFFICIENT_PERMISSIONS")

    def test_reviewer_agent_can_fetch_document(self):
        self.client.force_authenticate(self.agent)
        resp = self.client.get(f"/api/v1/kyc/documents/{self.doc.pk}/file")
        self.assertEqual(resp.status_code, 200)

    def test_document_without_a_file_404s(self):
        empty = KycDocument.objects.create(application=self.app, type="pan")
        self.client.force_authenticate(self.owner)
        resp = self.client.get(f"/api/v1/kyc/documents/{empty.pk}/file")
        self.assertEqual(resp.status_code, 404)

    def test_url_view_returns_the_gated_path(self):
        self.client.force_authenticate(self.owner)
        resp = self.client.get(f"/api/v1/kyc/documents/{self.doc.pk}/url")
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(
            resp.json()["data"]["url"].endswith(
                f"/api/v1/kyc/documents/{self.doc.pk}/file"
            )
        )

    def test_url_view_is_owner_scoped(self):
        self.client.force_authenticate(self.stranger)
        resp = self.client.get(f"/api/v1/kyc/documents/{self.doc.pk}/url")
        self.assertEqual(resp.status_code, 404)


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class KycUploadValidationTests(TestCase):
    """KYC document uploads must be real images within the size cap (same policy
    as the media pipeline). Non-images / oversized files are rejected before
    they're persisted."""

    def setUp(self):
        self.user = User.objects.create(phone="+919000000910", name="K")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def test_rejects_non_image_upload(self):
        bad = SimpleUploadedFile(
            "aadhaar.txt", b"this is definitely not an image",
            content_type="text/plain")
        resp = self.client.post(
            "/api/v1/kyc/submit", {"aadhaar": bad}, format="multipart")
        self.assertGreaterEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["code"], "UNSUPPORTED_MEDIA_TYPE")
        # Nothing persisted on rejection.
        self.assertFalse(KycDocument.objects.filter(type="aadhaar").exists())

    def test_accepts_valid_image_upload(self):
        resp = self.client.post(
            "/api/v1/kyc/submit", {"aadhaar": _png_upload()}, format="multipart")
        self.assertEqual(resp.status_code, 201)
        self.assertTrue(KycDocument.objects.filter(type="aadhaar").exists())


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class AdminKycQueueReviewabilityTests(TestCase):
    """The reviewer saw only a masked number and a status chip: no document image,
    and no gov-source verification result — despite the backend storing both. And a
    rejection was accepted with an empty reason, leaving the customer with a failed
    KYC and nothing telling them what to fix."""

    def setUp(self):
        from .models import KycVerification

        self.admin = User.objects.create(
            phone="+919888888910", name="Admin", role="admin"
        )
        self.customer = User.objects.create(
            phone="+919000000910", name="Ravi Kumar", role="customer"
        )
        self.app = KycApplication.objects.create(user=self.customer, status="pending")
        self.doc = KycDocument.objects.create(
            application=self.app, type="aadhaar", file=_png_upload()
        )
        KycVerification.objects.create(
            application=self.app, kind="pan", status="verified",
            verified_name="RAVI KUMAR", verified_dob="1990-04-02",
            id_masked="XXXXX1234F", name_match=True, provider="signzy",
        )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def _row(self):
        body = self.client.get("/api/v1/admin/kyc/queue").json()
        return next(a for a in body["data"]["applications"] if a["id"] == str(self.app.id))

    def test_queue_exposes_the_gated_document_image_path(self):
        doc = self._row()["documents"][0]
        # The permission-gated endpoint, NOT the raw MEDIA url.
        self.assertEqual(doc["fileUrl"], f"/kyc/documents/{self.doc.pk}/file")

    def test_document_without_a_file_has_no_image_path(self):
        KycDocument.objects.create(application=self.app, type="pan")
        paths = {d["type"]: d["fileUrl"] for d in self._row()["documents"]}
        self.assertIsNone(paths["pan"])

    def test_queue_includes_the_api_verification_result(self):
        v = self._row()["verifications"][0]
        self.assertEqual(v["kind"], "pan")
        self.assertEqual(v["verifiedName"], "RAVI KUMAR")
        self.assertEqual(v["verifiedDob"], "1990-04-02")
        self.assertTrue(v["nameMatch"])
        self.assertEqual(v["provider"], "signzy")

    def test_queue_is_paginated(self):
        body = self.client.get("/api/v1/admin/kyc/queue").json()
        self.assertIn("meta", body)
        self.assertEqual(body["meta"]["page"], 1)
        self.assertEqual(body["meta"]["total"], 1)
        # Summary is the whole-queue backlog, alongside the page of applications.
        self.assertEqual(body["data"]["summary"]["pending"], 1)

    def test_rejection_without_a_reason_is_refused(self):
        resp = self.client.post(
            f"/api/v1/admin/kyc/{self.app.pk}/decision",
            {"decision": "reject"}, format="json",
        )
        self.assertEqual(resp.status_code, 400)
        self.app.refresh_from_db()
        self.assertEqual(self.app.status, "pending")

    def test_rejection_with_a_blank_reason_is_refused(self):
        resp = self.client.post(
            f"/api/v1/admin/kyc/{self.app.pk}/decision",
            {"decision": "reject", "note": "   "}, format="json",
        )
        self.assertEqual(resp.status_code, 400)
        self.app.refresh_from_db()
        self.assertEqual(self.app.status, "pending")

    def test_rejection_with_a_reason_is_stored(self):
        resp = self.client.post(
            f"/api/v1/admin/kyc/{self.app.pk}/decision",
            {"decision": "reject", "note": "  Aadhaar image unreadable  "},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.app.refresh_from_db()
        self.assertEqual(self.app.status, "rejected")
        self.assertEqual(self.app.rejection_reason, "Aadhaar image unreadable")

    def test_approval_needs_no_reason(self):
        resp = self.client.post(
            f"/api/v1/admin/kyc/{self.app.pk}/decision",
            {"decision": "approve"}, format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.app.refresh_from_db()
        self.assertEqual(self.app.status, "verified")


@override_settings(MEDIA_ROOT=TMP_MEDIA)
class AgentSelfKycTests(TestCase):
    """An AGENT verifying their own identity.

    The agent app only ever had the reviewer side of KYC (the queue of customer
    applications), so an agent whose own verification was pending or rejected had
    no route to submit anything. No new backend was needed — `/kyc/status` and
    `/kyc/submit` key on `request.user` and have never cared about role — but
    that has to stay true, so it is pinned here.
    """

    def setUp(self):
        from rest_framework.test import APIClient

        from accounts.models import Role, User

        self.agent = User.objects.create(
            phone="+919600055001", name="Rider", role=Role.AGENT
        )
        self.client = APIClient()
        self.client.force_authenticate(self.agent)

    def test_an_agent_can_read_their_own_kyc_status(self):
        r = self.client.get("/api/v1/kyc/status")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.json()["data"]["status"], "not_started")

    def test_an_agent_can_submit_their_own_documents(self):
        r = self.client.post("/api/v1/kyc/submit", {
            "aadhaar": _png_upload("aadhaar.png"),
            "selfie": _png_upload("selfie.png"),
        }, format="multipart")
        self.assertEqual(r.status_code, 201, r.content)

        from kyc.models import KycApplication

        app = KycApplication.objects.get(user=self.agent)
        self.assertNotEqual(app.status, "not_started")
        self.assertEqual(
            {d.type for d in app.documents.all()}, {"aadhaar", "selfie"}
        )

    def test_an_agents_application_reaches_the_admin_review_queue(self):
        """Otherwise the agent submits into a void — nobody ever sees it."""
        from rest_framework.test import APIClient

        from accounts.models import Role, User
        from kyc.models import KycApplication

        KycApplication.objects.create(user=self.agent, status="pending")
        admin_client = APIClient()
        admin_client.force_authenticate(User.objects.create(
            phone="+919600055002", name="Admin", role=Role.ADMIN
        ))
        r = admin_client.get("/api/v1/admin/kyc/queue")
        self.assertEqual(r.status_code, 200, r.content)
        phones = {
            a["userPhone"] for a in r.json()["data"]["applications"]
        }
        self.assertIn(self.agent.phone, phones)
