"""Live Signzy identity-verification provider — the recommended production provider
for VS Mart (one vendor covers PAN, Aadhaar OTP eKYC, CKYC, bank, face match, video
KYC as the lending product grows).

Activates when KYC_PROVIDER=signzy and credentials are configured; otherwise the
mock runs (so dev/CI never needs keys or `requests`).

╔═══════════════════════════════════════════════════════════════════════════╗
║  CONFIRM THESE AGAINST YOUR SIGNZY DASHBOARD → "API marketplace" docs       ║
║  Base host + v3 paths below match Signzy's published examples, but Signzy   ║
║  version their products and some paths differ per contract. Verify the      ║
║  exact path + auth style (static API key vs patron-login token) for YOUR    ║
║  account and tweak the constants. The mock path is what dev/CI exercises.   ║
╚═══════════════════════════════════════════════════════════════════════════╝

Auth: Signzy is token-based. Either a static API key is sent as the Authorization
header, or username/password are exchanged at the login endpoint for an access
token (cached). Keys are server-side only — the app never sees them (Signzy's own
guidance: never send the key client-side, proxy through your backend).
"""
from __future__ import annotations

from django.core.cache import cache

from core import runtime_settings as runtime

from . import base
from .base import VerificationResult as R

# ── Endpoint paths (relative to the configured base host) ──
LOGIN_PATH = "/api/v2/patrons/login"          # username/password → access token
PAN_PATH = "/api/v3/pan/simple"
AADHAAR_VERIFY_PATH = "/api/v3/aadhaar/verify"        # offline / DigiLocker pull
AADHAAR_OTP_INIT_PATH = "/api/v3/aadhaar/okyc/init"   # send OTP
AADHAAR_OTP_VERIFY_PATH = "/api/v3/aadhaar/okyc/verify"
BANK_VERIFY_PATH = "/api/v3/bankaccountverifications/verify"

TIMEOUT = 20
_TOKEN_CACHE_KEY = "signzy_access_token_v1"
_TOKEN_TTL = 45 * 60  # refresh comfortably inside Signzy's token lifetime


class ProviderError(Exception):
    """Transport / HTTP / auth failure talking to Signzy — surfaced as KYC_PROVIDER_ERROR."""


def _base():
    return (runtime.cfg("signzy_base_url") or "https://api.signzy.app").rstrip("/")


def _auth_token():
    """Static API key if configured, else a cached patron-login access token."""
    key = runtime.cfg("signzy_api_key")
    if key:
        return key
    token = cache.get(_TOKEN_CACHE_KEY)
    if token:
        return token
    import requests  # lazy

    user = runtime.cfg("signzy_username")
    pwd = runtime.cfg("signzy_password")
    if not (user and pwd):
        raise ProviderError("Signzy credentials are not configured.")
    try:
        resp = requests.post(_base() + LOGIN_PATH,
                             json={"username": user, "password": pwd}, timeout=TIMEOUT)
        data = resp.json()
    except Exception as exc:  # noqa: BLE001 — any login failure is a provider error
        raise ProviderError(f"Signzy login failed: {exc}") from exc
    token = data.get("id") or data.get("accessToken") or data.get("access_token")
    if not token:
        raise ProviderError("Signzy login did not return an access token.")
    cache.set(_TOKEN_CACHE_KEY, token, _TOKEN_TTL)
    return token


def _headers():
    return {"Authorization": _auth_token(), "Content-Type": "application/json"}


def _post(path, payload):
    import requests  # lazy: dev/CI on the mock never imports it

    try:
        resp = requests.post(_base() + path, json=payload, headers=_headers(),
                             timeout=TIMEOUT)
    except requests.RequestException as exc:
        raise ProviderError(str(exc)) from exc
    if resp.status_code == 401:
        cache.delete(_TOKEN_CACHE_KEY)  # token expired — force re-login next call
        raise ProviderError("Signzy auth rejected (401).")
    if resp.status_code >= 500:
        raise ProviderError(f"Signzy {resp.status_code}")
    try:
        return resp.json()
    except ValueError as exc:
        raise ProviderError("Non-JSON response from Signzy") from exc


def _result_obj(body: dict) -> dict:
    """Signzy nests the payload under `result` (sometimes `data`)."""
    return body.get("result") or body.get("data") or body


def _is_success(body: dict) -> bool:
    if str(body.get("error") or "").strip():
        return False
    sc = body.get("statusCode") or body.get("status")
    if sc not in (None, 200, "200", "SUCCESS", "success"):
        return False
    r = _result_obj(body)
    status = str(r.get("panStatus") or r.get("status") or r.get("verified") or "").upper()
    if status in ("INVALID", "FALSE", "NOT EXIST", "DEACTIVATED"):
        return False
    return True


def _full_name(r: dict) -> str:
    if r.get("name"):
        return r["name"]
    parts = [r.get("firstName"), r.get("middleName"), r.get("lastName")]
    return " ".join(p for p in parts if p).strip()


def _trim(body: dict) -> dict:
    r = _result_obj(body)
    keep = ("panStatus", "status", "category", "aadhaarSeedingStatus")
    out = {k: r.get(k) for k in keep if k in r}
    if "statusCode" in body:
        out["statusCode"] = body["statusCode"]
    return out


class SignzyProvider(base.VerificationProvider):
    name = "signzy"

    # ── PAN ──
    def verify_pan(self, *, pan, name="", consent=False, reason=""):
        pan = (pan or "").upper().strip()
        body = _post(PAN_PATH, {"pan": pan, "name": name, "consent": bool(consent)})
        if not _is_success(body):
            return R(kind=base.PAN, status=base.FAILED, id_masked=base.mask_id(pan),
                     error_code="PAN_INVALID", message="PAN could not be verified.",
                     raw=_trim(body))
        r = _result_obj(body)
        src_name = _full_name(r)
        matched = base.names_match(name, src_name) if (name and src_name) else None
        if matched is False:
            return R(kind=base.PAN, status=base.FAILED, verified_name=src_name,
                     id_masked=base.mask_id(pan), name_match=False,
                     error_code="PAN_NAME_MISMATCH", message="Name on PAN does not match.",
                     raw=_trim(body))
        return R(kind=base.PAN, status=base.VERIFIED, verified_name=src_name,
                 verified_dob=r.get("dob", ""), id_masked=base.mask_id(pan),
                 name_match=matched, reference_id=str(body.get("requestId", "")),
                 message="PAN verified.", raw=_trim(body))

    # ── Aadhaar via DigiLocker / offline ──
    def start_digilocker(self, *, redirect_url, docs=None):
        body = _post(AADHAAR_VERIFY_PATH, {"redirectUrl": redirect_url,
                                           "docs": docs or ["AADHAAR"]})
        r = _result_obj(body)
        rid = r.get("id") or r.get("requestId") or ""
        url = r.get("url") or r.get("authorizationUrl") or ""
        if not (rid and url):
            raise ProviderError("Signzy DigiLocker did not return an id/url")
        return R(kind=base.DIGILOCKER, status=base.PENDING, reference_id=rid,
                 redirect_url=url, message="Consent pending.")

    def fetch_digilocker(self, *, request_id, name=""):
        body = _post(AADHAAR_VERIFY_PATH, {"requestId": request_id})
        if not _is_success(body):
            return R(kind=base.AADHAAR, status=base.PENDING, reference_id=request_id,
                     message="Consent not completed yet.", raw=_trim(body))
        return self._aadhaar_result(body, request_id, name)

    # ── Aadhaar OKYC (OTP) ──
    def aadhaar_okyc_init(self, *, aadhaar):
        body = _post(AADHAAR_OTP_INIT_PATH, {"uid": (aadhaar or "").strip(), "consent": "Y"})
        r = _result_obj(body)
        rid = r.get("requestId") or r.get("id") or body.get("requestId") or ""
        if not rid:
            raise ProviderError("Signzy Aadhaar OTP init did not return a request id")
        return R(kind=base.AADHAAR, status=base.PENDING, reference_id=rid,
                 id_masked=base.mask_id(aadhaar), message="OTP sent.", raw=_trim(body))

    def aadhaar_okyc_submit(self, *, reference_id, otp, name=""):
        body = _post(AADHAAR_OTP_VERIFY_PATH, {"requestId": reference_id, "otp": str(otp)})
        if not _is_success(body):
            return R(kind=base.AADHAAR, status=base.FAILED, reference_id=reference_id,
                     error_code="AADHAAR_OTP_INVALID",
                     message="Incorrect or expired OTP.", raw=_trim(body))
        return self._aadhaar_result(body, reference_id, name)

    def _aadhaar_result(self, body, reference_id, name):
        r = _result_obj(body)
        src_name = _full_name(r)
        masked = r.get("maskedNumber") or r.get("maskedAadhaar") or "XXXXXXXX1234"
        matched = base.names_match(name, src_name) if (name and src_name) else None
        if matched is False:
            return R(kind=base.AADHAAR, status=base.FAILED, verified_name=src_name,
                     id_masked=masked, name_match=False, error_code="PAN_NAME_MISMATCH",
                     reference_id=reference_id, message="Name on Aadhaar does not match.")
        return R(kind=base.AADHAAR, status=base.VERIFIED, verified_name=src_name,
                 verified_dob=r.get("dob", ""), verified_address=r.get("address", ""),
                 id_masked=masked, name_match=matched, reference_id=reference_id,
                 message="Aadhaar verified.", raw={"source": "signzy"})

    # ── Bank account (penny-drop) ──
    def verify_bank(self, *, account, ifsc, name=""):
        body = _post(BANK_VERIFY_PATH, {"beneficiaryAccount": (account or "").strip(),
                                        "beneficiaryIFSC": (ifsc or "").upper().strip()})
        if not _is_success(body):
            return R(kind=base.BANK, status=base.FAILED,
                     error_code="BANK_VERIFICATION_FAILED",
                     message="Bank account could not be verified.", raw=_trim(body))
        r = _result_obj(body)
        src_name = r.get("beneficiaryName") or r.get("name") or ""
        return R(kind=base.BANK, status=base.VERIFIED, verified_name=src_name,
                 id_masked=base.mask_id(account),
                 name_match=base.names_match(name, src_name) if (name and src_name) else None,
                 message="Bank account verified.", raw=_trim(body))
