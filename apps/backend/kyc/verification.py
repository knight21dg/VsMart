"""Identity-verification orchestration.

Each entry point calls the configured provider (Setu live, or the mock), persists
the attempt as a `KycVerification`, runs duplicate-fraud detection on the salted
gov-id hash, and — on success — auto-marks the matching review step green so the
human reviewer only handles what an API can't (selfie/face, field visit).

Deliberately does NOT auto-grant credit: final approval + credit enablement stay
with the admin (`AdminKycDecisionView` → services.approve), which keeps the
RBI NBFC/LSP lending model intact. API verification informs the reviewer; it does
not replace the credit-grant decision.
"""
from __future__ import annotations

from django.utils import timezone

from core.app_errors import AppError

from . import providers
from .models import KycApplication, KycVerification, VerificationStep, hash_gov_id
from .providers.setu import ProviderError

# Verification kind -> the review step it satisfies (bank/digilocker satisfy none).
KIND_TO_STEP = {"pan": "pan", "aadhaar": "aadhaar"}
# Which kind, when its id is reused on another account, raises which fraud code.
DUP_CODE = {"aadhaar": "AADHAAR_ALREADY_USED", "pan": "DUPLICATE_KYC"}


def _provider():
    return providers.get_provider()


def _call(fn, **kwargs):
    """Invoke a provider method, converting transport failures into a coded error."""
    try:
        return fn(**kwargs)
    except ProviderError as exc:
        raise AppError("KYC_PROVIDER_ERROR", message=str(exc)) from exc
    except NotImplementedError as exc:
        raise AppError("KYC_PROVIDER_ERROR",
                       message="This verification isn't supported by the provider.") from exc


def _record(application, result, *, provider_name, raw_id="", kind=None,
            consent=False, consent_purpose=""):
    """Persist a VerificationResult, after a duplicate-id fraud check on success."""
    kind = kind or result.kind
    id_hash = hash_gov_id(kind, raw_id) if raw_id else ""
    now = timezone.now()

    if result.ok and id_hash:
        clash = (
            KycVerification.objects.filter(
                kind=kind, status=KycVerification.Status.VERIFIED, id_hash=id_hash
            )
            .exclude(application=application)
            .exists()
        )
        if clash:
            KycVerification.objects.create(
                application=application, kind=kind, provider=provider_name,
                status=KycVerification.Status.FAILED, id_masked=result.id_masked,
                id_hash=id_hash, error_code=DUP_CODE.get(kind, "DUPLICATE_KYC"),
                consent=consent, consent_at=now if consent else None,
                consent_purpose=consent_purpose, raw=result.raw,
            )
            raise AppError(DUP_CODE.get(kind, "DUPLICATE_KYC"))

    verified = result.status == KycVerification.Status.VERIFIED
    rec = KycVerification.objects.create(
        application=application, kind=kind, provider=provider_name,
        status=result.status, verified_name=result.verified_name,
        verified_dob=result.verified_dob, verified_address=result.verified_address,
        id_masked=result.id_masked, id_hash=id_hash, name_match=result.name_match,
        reference_id=result.reference_id, redirect_url=result.redirect_url,
        error_code=result.error_code, raw=result.raw,
        consent=consent, consent_at=now if consent else None,
        consent_purpose=consent_purpose, verified_at=now if verified else None,
    )
    if verified:
        _mark_step(application, kind, result.verified_name)
    return rec


def _mark_step(application, kind, source_name):
    """Mark the matching review step green. Created on the fly when the customer
    verifies via API before ever calling /kyc/submit (so the step set may not exist)."""
    step = KIND_TO_STEP.get(kind)
    if not step:
        return
    note = f"Auto-verified ({source_name})"[:200]
    VerificationStep.objects.update_or_create(
        application=application, step=step,
        defaults={"status": "approved", "note": note, "agent": None},
    )


# ── public entry points ──────────────────────────────────────────────────
_AADHAAR_PURPOSE = "Aadhaar verification for VS Mart KYC"


def verify_pan(application: KycApplication, *, pan, name="", consent=False, reason=""):
    p = _provider()
    res = _call(p.verify_pan, pan=pan, name=name, consent=consent, reason=reason)
    return _record(application, res, provider_name=p.name, raw_id=pan, kind="pan",
                   consent=consent, consent_purpose=reason)


def start_aadhaar_digilocker(application: KycApplication, *, redirect_url, docs=None):
    p = _provider()
    res = _call(p.start_digilocker, redirect_url=redirect_url, docs=docs)
    return _record(application, res, provider_name=p.name, kind="aadhaar",
                   consent=True, consent_purpose=_AADHAAR_PURPOSE)


def refresh_aadhaar_digilocker(application: KycApplication, *, reference_id, name=""):
    p = _provider()
    res = _call(p.fetch_digilocker, request_id=reference_id, name=name)
    return _record(application, res, provider_name=p.name, kind="aadhaar",
                   consent=True, consent_purpose=_AADHAAR_PURPOSE)


def aadhaar_okyc_init(application: KycApplication, *, aadhaar):
    p = _provider()
    res = _call(p.aadhaar_okyc_init, aadhaar=aadhaar)
    # store the masked aadhaar + hash now so the eventual success is dup-checked
    return _record(application, res, provider_name=p.name, raw_id=aadhaar, kind="aadhaar",
                   consent=True, consent_purpose=_AADHAAR_PURPOSE)


def aadhaar_okyc_submit(application: KycApplication, *, reference_id, otp, name="", aadhaar=""):
    p = _provider()
    res = _call(p.aadhaar_okyc_submit, reference_id=reference_id, otp=otp, name=name)
    return _record(application, res, provider_name=p.name, raw_id=aadhaar, kind="aadhaar",
                   consent=True, consent_purpose=_AADHAAR_PURPOSE)


def verify_bank(application: KycApplication, *, account, ifsc, name=""):
    p = _provider()
    res = _call(p.verify_bank, account=account, ifsc=ifsc, name=name)
    return _record(application, res, provider_name=p.name, raw_id=account, kind="bank",
                   consent=True, consent_purpose="Bank account verification for VS Mart")


def retry(application: KycApplication) -> KycApplication:
    """Re-open a rejected application for another attempt. The verify endpoints can
    always be called again (each creates a fresh attempt); this just flips a terminal
    `rejected` application back to `pending` so the app un-blocks the retry UX."""
    from accounts.models import KycStatus

    if application.status == KycApplication.Status.REJECTED:
        application.status = KycApplication.Status.PENDING
        application.rejection_reason = ""
        application.save(update_fields=["status", "rejection_reason", "updated_at"])
        user = application.user
        user.kyc_status = KycStatus.PENDING
        user.save(update_fields=["kyc_status"])
    return application
