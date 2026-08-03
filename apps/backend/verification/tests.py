import io
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from accounts.models import User
from mediastore.models import MediaAsset

from .models import VerificationEvidence, VerificationTask

# Isolate every test's media writes to a throwaway MEDIA_ROOT and force the dev
# (FileResponse) serving path so the streamed bytes are real, not an X-Accel header.
TMP_MEDIA = tempfile.mkdtemp(prefix="vsmart-verif-")


def _png_upload(name="proof.png", w=400, h=300, color=(40, 120, 200)):
    img = Image.new("RGB", (w, h), color)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/png")


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class FieldVerificationPhotoTests(TestCase):
    def setUp(self):
        # E.164, unique within the +91900020020..+91900020029 sibling-safe range.
        self.customer = User.objects.create(
            phone="+919000200201", name="Cust", role="customer"
        )
        self.agent = User.objects.create(
            phone="+919000200202", name="Agent", role="agent"
        )
        self.other_agent = User.objects.create(
            phone="+919000200203", name="OtherAgent", role="agent"
        )
        self.stranger = User.objects.create(
            phone="+919000200204", name="Stranger", role="customer"
        )
        self.admin = User.objects.create(
            phone="+919000200205", name="Admin", role="admin"
        )
        self.task = VerificationTask.objects.create(
            customer=self.customer, agent=self.agent, status="in_progress"
        )
        self.client = APIClient()

    # ── Upload ──────────────────────────────────────────────
    def test_photo_upload_stores_media_asset_and_sets_key(self):
        self.client.force_authenticate(self.agent)
        resp = self.client.post(
            "/api/v1/verification/photo",
            {"task_id": self.task.id, "file": _png_upload()},
            format="multipart",
        )
        self.assertEqual(resp.status_code, 201)
        # One asset created, owned by the customer, in the verification bucket.
        self.assertEqual(MediaAsset.objects.count(), 1)
        asset = MediaAsset.objects.get()
        self.assertEqual(asset.owner_id, self.customer.id)
        self.assertEqual(asset.category, "verification")
        self.assertEqual(asset.visibility, "private")
        # photo_key holds the MediaAsset id.
        ev = VerificationEvidence.objects.get()
        self.assertEqual(ev.photo_key, str(asset.id))
        # The envelope renderer camelCases response keys (photo_key -> photoKey).
        self.assertEqual(resp.json()["data"]["photoKey"], str(asset.id))

    def test_photo_endpoint_still_works_without_a_file(self):
        # Backward compatible: no photo supplied → loose string key, no asset.
        self.client.force_authenticate(self.agent)
        resp = self.client.post(
            "/api/v1/verification/photo",
            {"task_id": self.task.id, "photo_key": "legacy-string-123"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(MediaAsset.objects.count(), 0)
        ev = VerificationEvidence.objects.get()
        self.assertEqual(ev.photo_key, "legacy-string-123")

    def _make_evidence_with_photo(self):
        self.client.force_authenticate(self.agent)
        self.client.post(
            "/api/v1/verification/photo",
            {"task_id": self.task.id, "file": _png_upload()},
            format="multipart",
        )
        return VerificationEvidence.objects.get()

    # ── Gated serving ───────────────────────────────────────
    def test_customer_can_fetch_photo(self):
        ev = self._make_evidence_with_photo()
        self.client.force_authenticate(self.customer)
        resp = self.client.get(f"/api/v1/verification/evidence/{ev.id}/photo")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "image/webp")

    def test_verifying_agent_can_fetch_photo(self):
        ev = self._make_evidence_with_photo()
        self.client.force_authenticate(self.agent)
        resp = self.client.get(f"/api/v1/verification/evidence/{ev.id}/photo")
        self.assertEqual(resp.status_code, 200)

    def test_staff_can_fetch_photo(self):
        ev = self._make_evidence_with_photo()
        self.client.force_authenticate(self.admin)
        resp = self.client.get(f"/api/v1/verification/evidence/{ev.id}/photo")
        self.assertEqual(resp.status_code, 200)

    def test_stranger_is_forbidden(self):
        ev = self._make_evidence_with_photo()
        self.client.force_authenticate(self.stranger)
        resp = self.client.get(f"/api/v1/verification/evidence/{ev.id}/photo")
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.json()["code"], "INSUFFICIENT_PERMISSIONS")

    def test_unrelated_agent_is_forbidden(self):
        # An agent who is NOT the verifying agent on this task gets no access.
        ev = self._make_evidence_with_photo()
        self.client.force_authenticate(self.other_agent)
        resp = self.client.get(f"/api/v1/verification/evidence/{ev.id}/photo")
        self.assertEqual(resp.status_code, 403)

    def test_missing_photo_is_404(self):
        # Evidence row exists but carries no photo_key.
        ev = VerificationEvidence.objects.create(
            task=self.task, kind="photo", photo_key=""
        )
        self.client.force_authenticate(self.agent)
        resp = self.client.get(f"/api/v1/verification/evidence/{ev.id}/photo")
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(resp.json()["code"], "NOT_FOUND")

    def test_legacy_non_uuid_key_is_404(self):
        # A loose string that isn't a MediaAsset UUID → nothing to serve.
        ev = VerificationEvidence.objects.create(
            task=self.task, kind="photo", photo_key="legacy-string-123"
        )
        self.client.force_authenticate(self.admin)
        resp = self.client.get(f"/api/v1/verification/evidence/{ev.id}/photo")
        self.assertEqual(resp.status_code, 404)

    def test_unknown_evidence_is_404(self):
        self.client.force_authenticate(self.admin)
        resp = self.client.get("/api/v1/verification/evidence/999999/photo")
        self.assertEqual(resp.status_code, 404)


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class FieldVerificationWriteBackTests(TestCase):
    """The agent RECOMMENDS; the loop reaches a reviewer; the agent never
    self-adjudicates the KYC."""

    def setUp(self):
        from kyc.models import KycApplication

        self.customer = User.objects.create(
            phone="+919000200301", name="Cust", role="customer"
        )
        self.agent = User.objects.create(
            phone="+919000200302", name="Agent", role="agent"
        )
        self.app = KycApplication.objects.create(
            user=self.customer, status=KycApplication.Status.PENDING
        )
        self.task = VerificationTask.objects.create(
            customer=self.customer, agent=self.agent,
            kyc_application=self.app, status="in_progress",
        )
        self.client = APIClient()

    def test_submit_records_recommendation_not_a_verdict(self):
        self.client.force_authenticate(self.agent)
        resp = self.client.post(
            f"/api/v1/verification/tasks/{self.task.id}/submit",
            {"decision": "approve", "note": "Address confirmed on site"},
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.data)
        self.task.refresh_from_db()
        # A recommendation, and SUBMITTED — never 'approved'/'rejected' by the agent.
        self.assertEqual(self.task.recommendation, "approve")
        self.assertEqual(self.task.status, "submitted")
        # The KYC application is untouched — a human reviewer still decides.
        self.app.refresh_from_db()
        self.assertEqual(self.app.status, "pending")

    def test_reject_becomes_a_recommendation_too(self):
        self.client.force_authenticate(self.agent)
        self.client.post(
            f"/api/v1/verification/tasks/{self.task.id}/submit",
            {"decision": "reject"}, format="json",
        )
        self.task.refresh_from_db()
        self.assertEqual(self.task.recommendation, "reject")
        self.assertEqual(self.task.status, "submitted")

    def test_admin_queue_surfaces_the_field_recommendation(self):
        self.task.recommendation = "approve"
        self.task.status = "submitted"
        self.task.save()
        admin = User.objects.create(phone="+919000200309", role="admin")
        self.client.force_authenticate(admin)
        resp = self.client.get("/api/v1/admin/kyc/queue")
        self.assertEqual(resp.status_code, 200)
        # The queue is paginated: {"data": {applications, summary}, "meta": {...}}.
        row = next(
            a for a in resp.data["data"]["applications"] if a["id"] == str(self.app.id)
        )
        self.assertIsNotNone(row["fieldVerification"])
        self.assertEqual(row["fieldVerification"]["recommendation"], "approve")
