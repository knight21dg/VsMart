"""Live Setu (setu.co) identity-verification provider.

Activates when KYC_PROVIDER=setu and the client credentials are configured;
otherwise the mock provider runs (so dev/CI never needs keys or `requests`).

╔═══════════════════════════════════════════════════════════════════════════╗
║  CONFIRM THESE AGAINST YOUR SETU DASHBOARD → "API reference" before go-live ║
║  Setu groups verifications into *products*; each product has its own        ║
║  `x-product-instance-id`. The host + paths below match Setu's Data/KYC and  ║
║  DigiLocker APIs as documented, but Setu version their products — verify    ║
║  the exact path/host for YOUR product instance and tweak the constants.     ║
╚═══════════════════════════════════════════════════════════════════════════╝

Auth headers (all Setu Data APIs): x-client-id, x-client-secret, x-product-instance-id.
"""
from __future__ import annotations

from core import runtime_settings as runtime

from . import base
from .base import VerificationResult as R

# ── Endpoint paths (relative to the configured base / DigiLocker host) ──
PAN_VERIFY_PATH = "/api/verify/pan"
BANK_VERIFY_PATH = "/api/verify/bank"
AADHAAR_OKYC_INIT_PATH = "/api/verify/aadhaar/okyc"          # → returns a request id
AADHAAR_OKYC_SUBMIT_PATH = "/api/verify/aadhaar/okyc/verify"  # → submit the OTP

TIMEOUT = 20  # seconds


class ProviderError(Exception):
    """Transport / HTTP failure talking to Setu — surfaced as KYC_PROVIDER_ERROR."""


def _prod_base():
    return (runtime.cfg("setu_base_url") or "https://prod.setu.co").rstrip("/")


def _dg_base():
    return (runtime.cfg("setu_dg_base_url") or "https://dg.setu.co").rstrip("/")


def _headers(product_id: str) -> dict:
    return {
        "x-client-id": runtime.cfg("setu_client_id") or "",
        "x-client-secret": runtime.cfg("setu_client_secret") or "",
        "x-product-instance-id": product_id or "",
        "Content-Type": "application/json",
    }


def _post(url, headers, payload):
    import requests  # lazy: dev/CI on the mock provider never imports it

    try:
        resp = requests.post(url, json=payload, headers=headers, timeout=TIMEOUT)
    except requests.RequestException as exc:  # network / DNS / timeout
        raise ProviderError(str(exc)) from exc
    return _parse(resp)


def _get(url, headers):
    import requests

    try:
        resp = requests.get(url, headers=headers, timeout=TIMEOUT)
    except requests.RequestException as exc:
        raise ProviderError(str(exc)) from exc
    return _parse(resp)


def _parse(resp):
    if resp.status_code >= 500:
        raise ProviderError(f"Setu {resp.status_code}")
    try:
        return resp.json()
    except ValueError as exc:
        raise ProviderError("Non-JSON response from Setu") from exc


def _is_success(body: dict) -> bool:
    """Setu signals success via `verification: SUCCESS` (data APIs) or a 2xx-ish
    `status` string on the DigiLocker flow."""
    v = str(body.get("verification") or body.get("status") or "").upper()
    return v in ("SUCCESS", "VERIFIED", "AUTHENTICATED", "COMPLETED")


def _trim(body: dict) -> dict:
    """Keep only non-PII audit breadcrumbs from the provider payload."""
    keep = ("verification", "status", "traceId", "message", "category",
            "aadhaarSeedingStatus", "aadhaar_seeding_status")
    return {k: body.get(k) for k in keep if k in body}


class SetuProvider(base.VerificationProvider):
    name = "setu"

    # ── PAN ──────────────────────────────────────────────────────────────
    def verify_pan(self, *, pan, name="", consent=False, reason=""):
        pan = (pan or "").upper().strip()
        body = _post(
            _prod_base() + PAN_VERIFY_PATH,
            _headers(runtime.cfg("setu_pan_product_id")),
            {"pan": pan, "consent": "Y" if consent else "N",
             "reason": reason or "KYC verification for credit onboarding"},
        )
        if not _is_success(body):
            return R(kind=base.PAN, status=base.FAILED, id_masked=base.mask_id(pan),
                     error_code="PAN_INVALID", reference_id=body.get("traceId", ""),
                     message=body.get("message", "PAN could not be verified."),
                     raw=_trim(body))
        data = body.get("data", {}) or {}
        src_name = data.get("full_name") or data.get("name") or ""
        matched = base.names_match(name, src_name) if (name and src_name) else None
        if matched is False:
            return R(kind=base.PAN, status=base.FAILED, verified_name=src_name,
                     id_masked=base.mask_id(pan), name_match=False,
                     error_code="PAN_NAME_MISMATCH", reference_id=body.get("traceId", ""),
                     message="Name on PAN does not match.", raw=_trim(body))
        return R(kind=base.PAN, status=base.VERIFIED, verified_name=src_name,
                 id_masked=base.mask_id(pan), name_match=matched,
                 reference_id=body.get("traceId", ""), message="PAN verified.",
                 raw=_trim(body))

    # ── Aadhaar via DigiLocker ───────────────────────────────────────────
    # DigiLocker deliberately absent: Payon is the ONE DigiLocker
    # provider (kyc/providers/payon.py). A second implementation here
    # would be a way for a misconfiguration to silently answer instead
    # of failing, which for a mock means fabricating a verified Aadhaar.

    def aadhaar_okyc_init(self, *, aadhaar):
        body = _post(
            _prod_base() + AADHAAR_OKYC_INIT_PATH,
            _headers(runtime.cfg("setu_aadhaar_product_id")),
            {"aadhaar": (aadhaar or "").strip(), "consent": "Y"},
        )
        rid = body.get("id") or body.get("requestId") or body.get("traceId") or ""
        if not rid:
            raise ProviderError("Aadhaar OKYC init did not return a request id")
        return R(kind=base.AADHAAR, status=base.PENDING, reference_id=rid,
                 id_masked=base.mask_id(aadhaar), message="OTP sent.", raw=_trim(body))

    def aadhaar_okyc_submit(self, *, reference_id, otp, name=""):
        body = _post(
            _prod_base() + AADHAAR_OKYC_SUBMIT_PATH,
            _headers(runtime.cfg("setu_aadhaar_product_id")),
            {"id": reference_id, "otp": str(otp)},
        )
        if not _is_success(body):
            return R(kind=base.AADHAAR, status=base.FAILED, reference_id=reference_id,
                     error_code="AADHAAR_OTP_INVALID",
                     message=body.get("message", "Incorrect or expired OTP."),
                     raw=_trim(body))
        data = body.get("data", {}) or {}
        src_name = data.get("name") or data.get("full_name") or ""
        masked = data.get("maskedNumber") or "XXXXXXXX1234"
        return R(kind=base.AADHAAR, status=base.VERIFIED, verified_name=src_name,
                 id_masked=masked, reference_id=reference_id,
                 name_match=base.names_match(name, src_name) if (name and src_name) else None,
                 message="Aadhaar verified.", raw={"source": "okyc"})

    # ── Bank account (penny-drop) ────────────────────────────────────────
    def verify_bank(self, *, account, ifsc, name=""):
        body = _post(
            _prod_base() + BANK_VERIFY_PATH,
            _headers(runtime.cfg("setu_bank_product_id")),
            {"accountNumber": (account or "").strip(), "ifsc": (ifsc or "").upper().strip()},
        )
        if not _is_success(body):
            return R(kind=base.BANK, status=base.FAILED,
                     error_code="BANK_VERIFICATION_FAILED",
                     reference_id=body.get("traceId", ""),
                     message=body.get("message", "Bank account could not be verified."),
                     raw=_trim(body))
        data = body.get("data", {}) or {}
        src_name = data.get("name") or data.get("accountHolderName") or ""
        return R(kind=base.BANK, status=base.VERIFIED, verified_name=src_name,
                 id_masked=base.mask_id(account), reference_id=body.get("traceId", ""),
                 name_match=base.names_match(name, src_name) if (name and src_name) else None,
                 message="Bank account verified.", raw=_trim(body))
