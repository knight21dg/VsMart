import re
from datetime import timedelta

from django.utils import timezone

from accounts.models import KycStatus
from core.app_errors import AppError
from credit.models import CreditBureauReport
from credit.services import fetch_bureau_score

from .models import (
    KycApplication,
    KycDocument,
    KycVerification,
    VerificationStep,
    hash_gov_id,
)
from .providers.base import mask_id, names_match

# Identity steps only. "credit" used to live here, which made a credit
# application part of identity verification; it is now a separate decision on
# credit.CreditApplication (see kyc.services.approve).
DEFAULT_STEPS = ["aadhaar", "pan", "selfie", "residence"]

PAN_RE = re.compile(r"^[A-Z]{5}[0-9]{4}[A-Z]$")
AADHAAR_RE = re.compile(r"^\d{12}$")

# Minimum CIBIL score to auto-advance to agent verification, and how long a
# passed check stays valid before the customer must re-check.
CREDIT_MIN_CIBIL = 700
CREDIT_CHECK_TTL_MIN = 60
CREDIT_CHECK_PURPOSE = "credit onboarding (CIBIL)"


def submit(user, documents, files=None) -> KycApplication:
    """Create/refresh the application from a list of {type, number_masked, file_key}.

    `files` is an optional {type: UploadedFile} map (multipart/form-data). When a
    file is supplied for a document type it's persisted to MEDIA storage on the
    matching KycDocument; JSON-only submits (no files) keep the old behavior.
    """
    files = files or {}
    app, _ = KycApplication.objects.get_or_create(user=user)
    app.status = KycApplication.Status.PENDING
    app.submitted_at = timezone.now()
    app.save(update_fields=["status", "submitted_at", "updated_at"])

    for doc in documents:
        defaults = {
            "number_masked": doc.get("number_masked", ""),
            "file_key": doc.get("file_key", ""),
            "status": "pending",
        }
        # Persist an optional geotag (e.g. residence-proof GPS) when supplied, so
        # the captured coordinates actually reach the reviewer.
        if doc.get("latitude") is not None:
            defaults["latitude"] = doc.get("latitude")
        if doc.get("longitude") is not None:
            defaults["longitude"] = doc.get("longitude")
        obj, _ = KycDocument.objects.update_or_create(
            application=app, type=doc["type"], defaults=defaults,
        )
        upload = files.get(doc["type"])
        if upload is not None:
            obj.file = upload
            # Record the stored key/path for masked reference too.
            obj.save(update_fields=["file"])
            if not obj.file_key:
                obj.file_key = obj.file.name
                obj.save(update_fields=["file_key"])
    for step in DEFAULT_STEPS:
        VerificationStep.objects.get_or_create(application=app, step=step)

    user.kyc_status = KycStatus.PENDING
    user.save(update_fields=["kyc_status"])
    return app


def approve(app: KycApplication, reviewer) -> KycApplication:
    """Final KYC approval: the user's **identity** is verified.

    This deliberately does NOT grant credit. KYC answers "is this person who they
    say they are"; how much credit they get is a separate underwriting decision
    made on a ``CreditApplication`` (see ``credit.services.approve_application``),
    which is the only thing that sets ``credit_enabled`` and a real limit.

    Fusing the two used to mean every verified customer was silently switched on
    at the same platform-default limit, with no per-customer assessment and no
    record of who decided what — which is also the wrong shape under the LSP
    lending model (see vsmart-credit-rbi-constraint).
    """
    app.status = KycApplication.Status.VERIFIED
    app.reviewed_by = reviewer
    app.reviewed_at = timezone.now()
    app.save(update_fields=["status", "reviewed_by", "reviewed_at", "updated_at"])
    app.steps.update(status="approved")
    app.documents.update(status="approved")

    user = app.user
    user.kyc_status = KycStatus.VERIFIED
    user.save(update_fields=["kyc_status"])
    return app


def reject(app: KycApplication, reviewer, reason="") -> KycApplication:
    app.status = KycApplication.Status.REJECTED
    app.reviewed_by = reviewer
    app.reviewed_at = timezone.now()
    app.rejection_reason = reason
    app.save(update_fields=["status", "reviewed_by", "reviewed_at",
                            "rejection_reason", "updated_at"])
    user = app.user
    user.kyc_status = KycStatus.REJECTED
    user.save(update_fields=["kyc_status"])
    return app


# ══════════════ Credit-bureau onboarding (no gov-source API) ══════════════
# The app collects the Aadhaar name, DOB and PAN, verifies phone ownership by OTP,
# then pulls the CIBIL record for that phone. The bureau returns the PAN-registered
# name + PAN, which we cross-check against what the customer entered. On a full
# match the application is submitted to the store's review queue; a reviewer then
# approves directly or assigns a field agent to verify documents.

def _record_credit_verification(app, report, *, entered_name, entered_dob,
                                entered_pan, status, name_match, pan_match, error=""):
    """Append the credit-onboarding attempt as a KycVerification (audit + review)."""
    now = timezone.now()
    return KycVerification.objects.create(
        application=app,
        kind=KycVerification.Kind.PAN,
        provider="payon",
        status=status,
        verified_name=report.name_on_bureau if report else "",
        id_masked=mask_id(entered_pan),
        id_hash=hash_gov_id("pan", entered_pan),
        name_match=name_match,
        reference_id=report.reference_id if report else "",
        error_code=error,
        consent=True,
        consent_at=now,
        consent_purpose="credit onboarding (CIBIL)",
        verified_at=now if status == KycVerification.Status.VERIFIED else None,
        raw={
            "score": report.score if report else 0,
            "band": report.band if report else "",
            "enteredName": entered_name,
            "enteredDob": entered_dob,
            "enteredPan": mask_id(entered_pan),
            "bureauName": report.name_on_bureau if report else "",
            "bureauPan": report.pan if report else "",
            "nameMatch": name_match,
            "panMatch": pan_match,
        },
    )


def check_credit_eligibility(user, *, full_name, pan, dob, mobile):
    """PHASE 1 of the credit apply flow. Pull the CIBIL record for the user's own
    registered ``mobile`` and GATE on three things, each blocking with its own
    coded error so the customer sees exactly why:

      • the bureau's name matches the entered legal name  → PAN_NAME_MISMATCH
      • the bureau's PAN matches the entered PAN           → PAN_NUMBER_MISMATCH
      • the score is at least ``CREDIT_MIN_CIBIL``          → CIBIL_SCORE_LOW
      • (a bureau record exists at all)                    → CIBIL_NO_RECORD

    On a full pass, a VERIFIED credit ``KycVerification`` is recorded — which
    :func:`submit_credit_documents` then requires before accepting the document
    scans. Does NOT submit the application or collect documents.
    """
    full_name = (full_name or "").strip()
    pan = (pan or "").upper().strip()
    if not full_name:
        raise AppError("VALIDATION_ERROR", fields={"fullName": ["Name is required."]})
    if not PAN_RE.match(pan):
        raise AppError("PAN_INVALID")

    app, _ = KycApplication.objects.get_or_create(user=user)
    report = fetch_bureau_score(
        user, mobile=mobile, consent=True,
        source=CreditBureauReport.Source.CUSTOMER, requested_by=user, force=True,
    )

    def _fail(error, *, name_match=None, pan_match=None):
        _record_credit_verification(
            app, report, entered_name=full_name, entered_dob=dob, entered_pan=pan,
            status=KycVerification.Status.FAILED,
            name_match=name_match, pan_match=pan_match, error=error)

    if report.status != CreditBureauReport.Status.SUCCESS:
        _fail("CIBIL_NO_RECORD")
        raise AppError("CIBIL_NO_RECORD")

    if not names_match(full_name, report.name_on_bureau):
        _fail("PAN_NAME_MISMATCH", name_match=False)
        raise AppError("PAN_NAME_MISMATCH")

    bureau_pan = (report.pan or "").upper()
    if not bureau_pan or pan != bureau_pan:
        _fail("PAN_NUMBER_MISMATCH", name_match=True, pan_match=False)
        raise AppError("PAN_NUMBER_MISMATCH")

    if report.score < CREDIT_MIN_CIBIL:
        _fail("CIBIL_SCORE_LOW", name_match=True, pan_match=True)
        raise AppError(
            "CIBIL_SCORE_LOW",
            context={"score": report.score, "minimum": CREDIT_MIN_CIBIL},
            message=f"Your CIBIL score is {report.score}. VS Credit needs at "
                    f"least {CREDIT_MIN_CIBIL}.")

    rec = _record_credit_verification(
        app, report, entered_name=full_name, entered_dob=dob, entered_pan=pan,
        status=KycVerification.Status.VERIFIED, name_match=True, pan_match=True)

    return {
        "passed": True,
        "score": report.score,
        "band": report.band,
        "bureauName": report.name_on_bureau,
        "verificationId": str(rec.id),
    }


def _passed_credit_check(user):
    """The most recent PASSED (verified) credit check within the TTL, else None."""
    cutoff = timezone.now() - timedelta(minutes=CREDIT_CHECK_TTL_MIN)
    return (
        KycVerification.objects.filter(
            application__user=user, kind=KycVerification.Kind.PAN,
            status=KycVerification.Status.VERIFIED,
            consent_purpose=CREDIT_CHECK_PURPOSE, created_at__gte=cutoff,
        )
        .order_by("-created_at")
        .first()
    )


def submit_credit_documents(user, *, files, consent=True):
    """PHASE 2. After a PASSED CIBIL check, store the Aadhaar + PAN scans (both
    sides), submit the application to the review queue, and create an agent
    VerificationTask so a field agent verifies the customer's details.

    Requires a recent passed check (CIBIL_CHECK_REQUIRED otherwise). ``files`` is a
    {type: UploadedFile} map keyed by ``aadhaar_front`` / ``aadhaar_back`` /
    ``pan_front`` / ``pan_back``. Returns (KycApplication, result).
    """
    files = files or {}
    check = _passed_credit_check(user)
    if check is None:
        raise AppError("CIBIL_CHECK_REQUIRED")

    app, _ = KycApplication.objects.get_or_create(user=user)
    app.status = KycApplication.Status.PENDING
    app.submitted_at = timezone.now()
    app.save(update_fields=["status", "submitted_at", "updated_at"])

    # Store the four scans. The PAN's masked number comes from the passed check.
    doc_masks = {
        "aadhaar_front": "",
        "aadhaar_back": "",
        "pan_front": check.id_masked or "",
        "pan_back": "",
    }
    for dtype, masked in doc_masks.items():
        defaults = {"status": "pending"}
        if masked:
            defaults["number_masked"] = masked
        doc, _ = KycDocument.objects.update_or_create(
            application=app, type=dtype, defaults=defaults,
        )
        upload = files.get(dtype)
        if upload is not None:
            doc.file = upload
            doc.save(update_fields=["file"])
            if not doc.file_key:
                doc.file_key = doc.file.name
                doc.save(update_fields=["file_key"])
    for step in ("aadhaar", "pan", "credit"):
        VerificationStep.objects.get_or_create(application=app, step=step)

    fields = ["kyc_status"]
    user.kyc_status = KycStatus.PENDING
    entered_name = (check.raw or {}).get("enteredName", "")
    if not (user.name or "").strip() and entered_name:
        user.name = entered_name
        fields.append("name")
    user.save(update_fields=fields)

    # Route to agent verification — a field agent verifies the documents/details.
    # Unassigned (PENDING) → picked up from the verification queue.
    from verification.models import VerificationTask

    task, _ = VerificationTask.objects.get_or_create(
        kyc_application=app, type=VerificationTask.Type.KYC,
        defaults={
            "customer": user, "status": VerificationTask.Status.PENDING,
            "note": "Credit apply — verify Aadhaar + PAN documents",
        },
    )

    return app, {
        "status": app.status,
        "taskId": str(task.id),
        "agentVerification": True,
    }
