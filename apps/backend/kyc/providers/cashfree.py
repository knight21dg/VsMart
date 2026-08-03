"""Live Cashfree "Secure ID" Verification-Suite provider.

⚠️ Requires the **Verification Suite** product to be ENABLED on your Cashfree
account. Plain Payment-Gateway keys authenticate but return a generic
`internal_error` on `/verification/*` until Secure ID is activated (Cashfree
dashboard → Verification Suite → activate; needs their approval). Confirm with
`python manage.py kyc_check --pan <PAN>` once enabled.

Activates when KYC_PROVIDER=cashfree and credentials are configured; otherwise
the mock runs (so dev/CI never needs keys or `requests`).

╔═══════════════════════════════════════════════════════════════════════════╗
║  Paths verified against Cashfree docs (api.cashfree.com/verification):      ║
║    PAN     POST /pan            GET /pan/{reference_id}                     ║
║    Aadhaar POST /offline-aadhaar/otp   POST /offline-aadhaar/verify        ║
║    Bank    POST /bank-account/sync                                          ║
║  Auth headers: x-client-id, x-client-secret, x-api-version. A unique        ║
║  verification_id is sent per request (Cashfree idempotency key).            ║
╚═══════════════════════════════════════════════════════════════════════════╝
"""
from __future__ import annotations

import uuid

from core import runtime_settings as runtime

from . import base
from .base import VerificationResult as R

PAN_PATH = "/pan"
AADHAAR_OTP_PATH = "/offline-aadhaar/otp"
AADHAAR_VERIFY_PATH = "/offline-aadhaar/verify"
BANK_PATH = "/bank-account/sync"

TIMEOUT = 25
DEFAULT_BASE = "https://api.cashfree.com/verification"
DEFAULT_API_VERSION = "2022-10-26"


class ProviderError(Exception):
    """Transport / HTTP / auth failure talking to Cashfree — KYC_PROVIDER_ERROR."""


def _base():
    return (runtime.cfg("cashfree_base_url") or DEFAULT_BASE).rstrip("/")


def _headers():
    return {
        "x-client-id": runtime.cfg("cashfree_app_id") or "",
        "x-client-secret": runtime.cfg("cashfree_secret_key") or "",
        "x-api-version": runtime.cfg("cashfree_api_version") or DEFAULT_API_VERSION,
        "Content-Type": "application/json",
    }


def _post(path, payload):
    import requests  # lazy: dev/CI on the mock never imports it

    try:
        resp = requests.post(_base() + path, json=payload, headers=_headers(),
                             timeout=TIMEOUT)
    except requests.RequestException as exc:
        raise ProviderError(str(exc)) from exc
    if resp.status_code == 401:
        raise ProviderError("Cashfree auth rejected (401).")
    try:
        body = resp.json()
    except ValueError as exc:
        raise ProviderError("Non-JSON response from Cashfree") from exc
    # Cashfree signals "Verification Suite not enabled" as a generic internal_error.
    if body.get("type") == "internal_error":
        raise ProviderError(
            "Cashfree Verification Suite (Secure ID) is not enabled for these keys.")
    return body


def _vid():
    return "vsmart_" + uuid.uuid4().hex[:20]


def _name_match(claimed, registered, explicit):
    if str(explicit).upper() == "NO_MATCH":
        return False
    if claimed and registered:
        return base.names_match(claimed, registered)
    return None


class CashfreeProvider(base.VerificationProvider):
    name = "cashfree"

    # ── PAN ──
    def verify_pan(self, *, pan, name="", consent=False, reason=""):
        pan = (pan or "").upper().strip()
        body = _post(PAN_PATH, {"pan": pan, "name": name, "verification_id": _vid()})
        if not body.get("valid", False):
            return R(kind=base.PAN, status=base.FAILED, id_masked=base.mask_id(pan),
                     error_code="PAN_INVALID", reference_id=str(body.get("reference_id", "")),
                     message=body.get("message", "PAN could not be verified."))
        registered = body.get("registered_name") or ""
        matched = _name_match(name, registered, body.get("name_match_result"))
        if matched is False:
            return R(kind=base.PAN, status=base.FAILED, verified_name=registered,
                     id_masked=base.mask_id(pan), name_match=False,
                     error_code="PAN_NAME_MISMATCH",
                     reference_id=str(body.get("reference_id", "")),
                     message="Name on PAN does not match.")
        return R(kind=base.PAN, status=base.VERIFIED, verified_name=registered,
                 id_masked=base.mask_id(pan), name_match=matched,
                 reference_id=str(body.get("reference_id", "")), message="PAN verified.",
                 raw={"pan_type": body.get("type")})

    # ── Aadhaar OKYC (OTP, offline) ──
    def aadhaar_okyc_init(self, *, aadhaar):
        body = _post(AADHAAR_OTP_PATH, {"aadhaar_number": (aadhaar or "").strip()})
        ref = body.get("ref_id") or body.get("reference_id") or ""
        if not ref:
            raise ProviderError("Cashfree Aadhaar OTP did not return a ref_id")
        return R(kind=base.AADHAAR, status=base.PENDING, reference_id=str(ref),
                 id_masked=base.mask_id(aadhaar), message="OTP sent.")

    def aadhaar_okyc_submit(self, *, reference_id, otp, name=""):
        body = _post(AADHAAR_VERIFY_PATH, {"otp": str(otp), "ref_id": reference_id})
        status = str(body.get("status") or "").upper()
        if status not in ("VALID", "SUCCESS"):
            return R(kind=base.AADHAAR, status=base.FAILED, reference_id=str(reference_id),
                     error_code="AADHAAR_OTP_INVALID",
                     message=body.get("message", "Incorrect or expired OTP."))
        src_name = body.get("name") or ""
        addr = body.get("address")
        address = addr if isinstance(addr, str) else (
            (addr or {}).get("combined_address", "") if isinstance(addr, dict) else "")
        return R(kind=base.AADHAAR, status=base.VERIFIED, verified_name=src_name,
                 verified_dob=body.get("dob", ""), verified_address=address,
                 id_masked="XXXXXXXX" + str(body.get("aadhaar_number", ""))[-4:],
                 reference_id=str(reference_id),
                 name_match=base.names_match(name, src_name) if (name and src_name) else None,
                 message="Aadhaar verified.", raw={"source": "cashfree-okyc"})

    # ── Bank account (penny-drop) ──
    def verify_bank(self, *, account, ifsc, name=""):
        body = _post(BANK_PATH, {"bank_account": (account or "").strip(),
                                 "ifsc": (ifsc or "").upper().strip(),
                                 "name": name, "verification_id": _vid()})
        if str(body.get("account_status") or "").upper() != "VALID":
            return R(kind=base.BANK, status=base.FAILED,
                     error_code="BANK_VERIFICATION_FAILED",
                     reference_id=str(body.get("reference_id", "")),
                     message=body.get("account_status_message", "Bank account could not be verified."))
        src_name = body.get("name_at_bank") or ""
        return R(kind=base.BANK, status=base.VERIFIED, verified_name=src_name,
                 id_masked=base.mask_id(account), reference_id=str(body.get("reference_id", "")),
                 name_match=base.names_match(name, src_name) if (name and src_name) else None,
                 message="Bank account verified.")
