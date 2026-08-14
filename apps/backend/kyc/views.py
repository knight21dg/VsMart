import mimetypes

from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.app_errors import AppError, ok
from core.pagination import EnvelopePagination
from core.permissions import IsAdmin, IsAgent
from mediastore.serving import serve_storage_key

from . import verification
from .models import KycApplication, KycDocument, KycVerification, VerificationStep
from .serializers import (
    AdminKycApplicationSerializer,
    KycApplicationSerializer,
    ReviewSerializer,
    SubmitSerializer,
    VerificationSerializer,
)
from .services import (
    approve,
    check_credit_eligibility,
    reject,
    submit,
    submit_credit_documents,
)

_OK_CODE = {  # verified-kind -> success code
    "pan": "PAN_VERIFIED", "aadhaar": "AADHAAR_VERIFIED", "bank": "BANK_VERIFIED",
}


def _truthy(v):
    return str(v).strip().lower() in ("1", "true", "yes", "y", "on")


def _app_for(request):
    app, _ = KycApplication.objects.get_or_create(user=request.user)
    return app


def _result(rec: KycVerification):
    """Turn a recorded verification into the right actionable envelope: a coded
    failure (so the app drives retry/escalation) or a coded success payload."""
    data = VerificationSerializer(rec).data
    if rec.status == KycVerification.Status.FAILED:
        raise AppError(rec.error_code or "VERIFICATION_REJECTED")
    code = _OK_CODE.get(rec.kind, "KYC_SUBMITTED")
    return Response(ok(code, data=data))

# Document types that may arrive as multipart file fields on /kyc/submit.
FILE_DOC_TYPES = ["aadhaar", "pan", "selfie", "residence"]


class KycStatusView(APIView):
    def get(self, request):
        app, _ = KycApplication.objects.get_or_create(user=request.user)
        return Response(
            KycApplicationSerializer(app, context={"request": request}).data
        )


class KycSubmitView(APIView):
    # Accept multipart file uploads (selfie/aadhaar/pan/residence) AND/OR the
    # existing JSON `documents` metadata. JSON-only submits still work as before.
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request):
        # Uploaded image files keyed by document type (multipart).
        files = {t: request.FILES[t] for t in FILE_DOC_TYPES if t in request.FILES}
        # Sanitize uploads: identity docs must be real images within the size cap
        # (same policy as the media pipeline) — reject non-images / oversized files
        # before they're persisted.
        from mediastore.pipeline import validate_image_upload

        for upload in files.values():
            validate_image_upload(upload)

        # `documents` metadata is optional. In JSON it's a list; in multipart it may
        # arrive as a JSON string (or be omitted entirely). Normalize before validating.
        docs_in = request.data.get("documents")
        if isinstance(docs_in, str):
            import json
            try:
                docs_in = json.loads(docs_in) if docs_in.strip() else []
            except (ValueError, TypeError):
                docs_in = []
        s = SubmitSerializer(data={"documents": docs_in} if docs_in is not None else {})
        s.is_valid(raise_exception=True)

        docs = s.validated_data.get("documents")
        if not docs:
            # No explicit metadata list. Derive the doc set from whichever files were
            # uploaded; if none, fall back to the full default set (legacy behavior).
            types = list(files.keys()) or FILE_DOC_TYPES
            docs = [{"type": t} for t in types]

        app = submit(request.user, docs, files=files)
        return Response(
            KycApplicationSerializer(app, context={"request": request}).data,
            status=201,
        )


class DocumentUrlView(APIView):
    def get(self, request, pk):
        # Hand back the *permission-gated* file endpoint, not the raw MEDIA url.
        # Identity documents must never be served on a guessable, unauthenticated
        # path — DocumentFileView re-checks ownership on every fetch.
        doc = get_object_or_404(KycDocument, pk=pk, application__user=request.user)
        if doc.file:
            url = request.build_absolute_uri(f"/api/v1/kyc/documents/{pk}/file")
            return Response({"url": url, "expires_in": 300})
        # No real file stored (legacy JSON-only doc) — keep a stable placeholder path.
        return Response({"url": f"/media/kyc/{pk}", "expires_in": 300})


class DocumentFileView(APIView):
    """Stream a KYC document image only to people allowed to see it: the customer
    who owns the application, or a KYC reviewer (agent/admin/superadmin). Everyone
    else gets 403. This closes the hole where identity docs (Aadhaar/PAN/selfie)
    were served on a direct, unauthenticated MEDIA url."""

    def get(self, request, pk):
        try:
            doc = KycDocument.objects.select_related("application").get(pk=pk)
        except KycDocument.DoesNotExist:
            raise AppError("NOT_FOUND")
        user = request.user
        is_reviewer = getattr(user, "role", "") in ("agent", "admin", "superadmin")
        if not (is_reviewer or doc.application.user_id == user.id):
            raise AppError("INSUFFICIENT_PERMISSIONS")
        if not doc.file:
            raise AppError("NOT_FOUND")
        content_type = mimetypes.guess_type(doc.file.name)[0] or "application/octet-stream"
        resp = serve_storage_key(doc.file.name, content_type=content_type)
        resp["Cache-Control"] = "private, max-age=60"
        return resp


# ── Agent review ─────────────────────────────────────────
class AgentKycQueueView(ListAPIView):
    serializer_class = KycApplicationSerializer
    permission_classes = [IsAgent]
    pagination_class = None

    def get_queryset(self):
        return KycApplication.objects.filter(status="pending")


class AgentReviewView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        app = get_object_or_404(KycApplication, pk=pk)
        s = ReviewSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        step = s.validated_data.get("step")
        decision = s.validated_data["decision"]
        new_status = "approved" if decision == "approve" else "rejected"
        if step:
            VerificationStep.objects.filter(application=app, step=step).update(
                status=new_status, agent=request.user, note=s.validated_data.get("note", "")
            )
        record_audit(request.user, "kyc.step.review", target=app,
                     after={"step": step, "decision": decision})
        return Response(KycApplicationSerializer(app).data)


# ── Admin queue + final decision ─────────────────────────
class AdminKycQueueView(APIView):
    """Admin-scoped verification queue — PAGINATED. Optional ?status= / ?store= /
    ?zone= filters; defaults to everything except not_started. Each application is
    attributed to the applicant's serving store + zone, and a status summary is
    returned.

    Emits ``{data: {applications, summary}, meta: {page, total, totalPages}}`` via
    :class:`core.pagination.EnvelopePagination`. The queue was previously entirely
    unbounded — every application ever submitted was serialised on every request,
    together with a per-application field-verification lookup, so it degraded
    without limit and the reviewer had no way to work through it in order.

    ``summary`` deliberately counts the WHOLE queue, not the current page — it is
    the backlog figure the reviewer is working down.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        from reports.filters import user_store_zone_map

        umap = user_store_zone_map()
        qs = KycApplication.objects.select_related("user").prefetch_related(
            "steps", "documents", "verifications"
        )
        status = request.query_params.get("status")
        if status:
            qs = qs.filter(status=status)
        else:
            qs = qs.exclude(status="not_started")
        store = request.query_params.get("store")
        zone = request.query_params.get("zone")
        if store or zone:
            allowed = {
                uid for uid, m in umap.items()
                if (not store or str(m.get("store_id")) == store) and (not zone or str(m.get("zone_id")) == zone)
            }
            qs = qs.filter(user_id__in=allowed)
        qs = qs.order_by("-submitted_at", "-id")

        # Backlog totals cover the entire queue, independent of the page below.
        summary = {
            s: KycApplication.objects.filter(status=s).count()
            for s in ["pending", "verified", "rejected"]
        }

        paginator = EnvelopePagination()
        page = paginator.paginate_queryset(qs, request, view=self)

        # Latest field-verification per application, so the admin sees the agent's
        # recommendation + captured evidence alongside the docs before deciding — the
        # field visit is no longer a dead end. Scoped to the current page, so this
        # lookup no longer grows with the whole queue.
        from verification.models import VerificationTask

        fv_map = {}
        for t in (
            VerificationTask.objects.filter(kyc_application__in=[a.id for a in page])
            .select_related("agent")
            .prefetch_related("evidence")
            .order_by("kyc_application_id", "-created_at")
        ):
            fv_map.setdefault(t.kyc_application_id, t)

        rows = []
        for app in page:
            # `request` in context makes the document URLs absolute.
            d = AdminKycApplicationSerializer(app, context={"request": request}).data
            loc = umap.get(app.user_id, {})
            d["storeName"] = loc.get("store__name")
            d["zoneName"] = loc.get("zone__name")
            t = fv_map.get(app.id)
            d["fieldVerification"] = None if t is None else {
                "taskId": str(t.id),
                "status": t.status,
                "agent": t.agent.name if t.agent_id else None,
                "recommendation": t.recommendation or None,
                "note": t.note or "",
                "submittedAt": t.submitted_at,
                "evidence": [
                    {
                        "kind": e.kind,
                        # EvidencePhotoView authorises admin/superadmin staff.
                        "photoUrl": f"/verification/evidence/{e.id}/photo"
                        if e.photo_key else None,
                        "lat": float(e.latitude) if e.latitude is not None else None,
                        "lng": float(e.longitude) if e.longitude is not None else None,
                    }
                    for e in t.evidence.all().order_by("created_at")
                ],
            }
            rows.append(d)
        return paginator.get_paginated_response(
            {"applications": rows, "summary": summary}
        )


class AdminKycDecisionView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        app = get_object_or_404(KycApplication, pk=pk)
        s = ReviewSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        if s.validated_data["decision"] == "approve":
            approve(app, request.user)
        else:
            # ReviewSerializer guarantees a non-blank note on a rejection.
            reject(app, request.user, s.validated_data["note"].strip())
        record_audit(request.user, "kyc.decision", target=app,
                     after={"decision": s.validated_data["decision"]})
        return Response(KycApplicationSerializer(app).data)


# ── API verification (Setu / mock): customer-driven gov-source checks ─────
class VerifyPanView(APIView):
    """POST /kyc/pan/verify  {pan, name?, consent} → verify a PAN against the source."""

    def post(self, request):
        pan = (request.data.get("pan") or "").strip()
        if not pan:
            raise AppError("VALIDATION_ERROR", fields={"pan": ["PAN is required."]})
        if not _truthy(request.data.get("consent")):
            raise AppError("CONSENT_REQUIRED")
        name = (request.data.get("name") or request.user.name or "").strip()
        rec = verification.verify_pan(
            _app_for(request), pan=pan, name=name, consent=True,
            reason="KYC verification for VS Mart credit onboarding",
        )
        record_audit(request.user, "kyc.verify.pan", target=rec,
                     after={"status": rec.status, "id": rec.id_masked})
        return _result(rec)


class DigiLockerStartView(APIView):
    """POST /kyc/verify/aadhaar/digilocker/start {redirect_url?} → consent URL."""

    def post(self, request):
        redirect_url = (request.data.get("redirect_url")
                        or "https://thevsmart.com/kyc/digilocker/callback")
        # The provider requires a mobile number. It is taken from the authenticated
        # user, never from the request body: the DigiLocker session is issued
        # against whoever's number is supplied, so accepting a client-supplied one
        # would let a customer start consent for somebody else's identity.
        rec = verification.start_aadhaar_digilocker(
            _app_for(request), redirect_url=redirect_url,
            mobile=request.user.phone or "")
        return Response(ok("DIGILOCKER_CONSENT_REQUIRED",
                           data=VerificationSerializer(rec).data))


class DigiLockerStatusView(APIView):
    """GET /kyc/verify/aadhaar/digilocker/<reference_id>/status → pull once consented."""

    def get(self, request, reference_id):
        name = (request.user.name or "").strip()
        rec = verification.refresh_aadhaar_digilocker(
            _app_for(request), reference_id=reference_id, name=name)
        if rec.status == KycVerification.Status.PENDING:
            raise AppError("DIGILOCKER_PENDING")
        return _result(rec)


class AadhaarOtpInitView(APIView):
    """POST /kyc/aadhaar/send-otp {aadhaar} → send OTP to the Aadhaar-linked mobile."""

    def post(self, request):
        aadhaar = (request.data.get("aadhaar") or "").strip()
        if not aadhaar:
            raise AppError("VALIDATION_ERROR", fields={"aadhaar": ["Aadhaar is required."]})
        rec = verification.aadhaar_okyc_init(_app_for(request), aadhaar=aadhaar)
        return Response(ok("AADHAAR_OTP_SENT",
                           data={"reference_id": rec.reference_id}))


class AadhaarOtpSubmitView(APIView):
    """POST /kyc/aadhaar/verify-otp {reference_id, otp, aadhaar?} → verify the OTP."""

    def post(self, request):
        ref = (request.data.get("reference_id") or "").strip()
        otp = (request.data.get("otp") or "").strip()
        if not ref or not otp:
            raise AppError("VALIDATION_ERROR",
                           fields={"otp": ["reference_id and otp are required."]})
        rec = verification.aadhaar_okyc_submit(
            _app_for(request), reference_id=ref, otp=otp,
            name=(request.user.name or "").strip(),
            aadhaar=(request.data.get("aadhaar") or "").strip(),
        )
        record_audit(request.user, "kyc.verify.aadhaar", target=rec,
                     after={"status": rec.status})
        return _result(rec)


class VerifyBankView(APIView):
    """POST /kyc/bank/verify {account, ifsc, name?} → penny-drop bank verification."""

    def post(self, request):
        account = (request.data.get("account") or "").strip()
        ifsc = (request.data.get("ifsc") or "").strip()
        if not account or not ifsc:
            raise AppError("VALIDATION_ERROR",
                           fields={"account": ["account and ifsc are required."]})
        rec = verification.verify_bank(
            _app_for(request), account=account, ifsc=ifsc,
            name=(request.data.get("name") or request.user.name or "").strip())
        record_audit(request.user, "kyc.verify.bank", target=rec,
                     after={"status": rec.status})
        return _result(rec)


class KycRetryView(APIView):
    """POST /kyc/retry → re-open a rejected application so the customer can try again."""

    def post(self, request):
        app = verification.retry(_app_for(request))
        return Response(ok("KYC_SUBMITTED",
                           data=KycApplicationSerializer(app, context={"request": request}).data))


# ── Credit-bureau onboarding (Aadhaar name + DOB + PAN + phone OTP → CIBIL) ──

def _mobile10(value):
    """Reduce any input (E.164, spaces) to the last 10 digits."""
    import re as _re
    digits = _re.sub(r"\D", "", str(value or ""))
    return digits[-10:] if len(digits) >= 10 else digits


class CreditOnboardOtpView(APIView):
    """POST /kyc/credit/send-otp {mobile} → send an OTP to the phone whose CIBIL
    record will be pulled (proves ownership before the chargeable bureau call)."""

    def post(self, request):
        from accounts import otp

        mobile = _mobile10(request.data.get("mobile"))
        if len(mobile) != 10:
            raise AppError("VALIDATION_ERROR",
                           fields={"mobile": ["Enter a valid 10-digit mobile number."]})
        verification_id = otp.generate_and_send(mobile, purpose="kyc_credit")
        return Response(ok("OTP_SENT", data={"verificationId": verification_id,
                                             "mobile": mobile}))


# (request file field -> KycDocument type). The PAN *image* field is `pan_card`
# so it never collides with the `pan` *number* text field in multipart bodies.
# The 4 document scans this flow collects. Client multipart field name → the
# KycDocument.type the reviewer sees.
CREDIT_FILE_FIELDS = [
    ("aadhaarFront", "aadhaar_front"),
    ("aadhaarBack", "aadhaar_back"),
    ("panFront", "pan_front"),
    ("panBack", "pan_back"),
]


class CreditOnboardCheckView(APIView):
    """POST /kyc/credit/check → PHASE 1 of the credit apply flow.

    JSON: ``fullName`` (legal name as per PAN), ``dob``, ``pan``, ``consent``.
    Pulls the CIBIL score for the user's OWN registered number and gates on the
    bureau name + PAN matching and a score ≥ the minimum. On a pass, returns the
    score and the customer can proceed to upload documents; on any failure it
    blocks with the exact coded reason.
    """

    def post(self, request):
        data = request.data
        if not _truthy(data.get("consent")):
            raise AppError("CIBIL_CONSENT_REQUIRED")
        # CIBIL is pulled for the user's OWN registered number (verified at login);
        # a client-supplied mobile is ignored for security.
        mobile = _mobile10(getattr(request.user, "phone", ""))
        result = check_credit_eligibility(
            request.user,
            full_name=data.get("full_name", ""),
            pan=data.get("pan", ""),
            dob=str(data.get("dob", "")),
            mobile=mobile,
        )
        record_audit(request.user, "kyc.credit_check",
                     after={"score": result["score"]})
        return Response(ok("CIBIL_CHECKED", data=result))


class CreditOnboardSubmitView(APIView):
    """POST /kyc/credit/submit → PHASE 2 of the credit apply flow.

    Multipart: ``consent`` + the four document scans ``aadhaarFront`` /
    ``aadhaarBack`` / ``panFront`` / ``panBack``. Requires a passed CIBIL check
    first; stores the scans, submits the application, and creates an agent
    verification task.
    """

    def post(self, request):
        from mediastore.pipeline import validate_image_upload

        data = request.data
        if not _truthy(data.get("consent")):
            raise AppError("CIBIL_CONSENT_REQUIRED")

        # All four scans are required. Accept camelCase or snake_case field names.
        files, missing = {}, []
        for field_name, dtype in CREDIT_FILE_FIELDS:
            upload = request.FILES.get(field_name) or request.FILES.get(dtype)
            if upload is not None:
                files[dtype] = upload
            else:
                missing.append(field_name)
        if missing:
            raise AppError("VALIDATION_ERROR", fields={
                f: ["This document image is required."] for f in missing})
        for upload in files.values():
            validate_image_upload(upload)

        app, result = submit_credit_documents(request.user, files=files)
        record_audit(request.user, "kyc.credit_onboard", target=app,
                     after={"taskId": result.get("taskId")})
        return Response(ok("KYC_SUBMITTED", data=result))
