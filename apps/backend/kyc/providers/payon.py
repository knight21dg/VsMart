"""Payon — the ONE DigiLocker provider.

Per the owner's directive there is no alternate and no mock for DigiLocker: this
is the only implementation, so a misconfiguration fails loudly instead of quietly
returning a fabricated "verified".

Two endpoints, both form-encoded POSTs carrying `apiKey`:

* ``digilocker_initiate.php`` — returns the DigiLocker consent URL the customer is
  sent to, plus ``recordId``/``state`` to correlate the callback.
* ``digilocker_complete.php`` — exchanges that record for the document once the
  customer has authorised it.

HOST TRAP (the same one that cost days on the credit-score API): **reseller keys
are served from ``reseller.apipayon.in``, not the bare ``apipayon.in``.** The bare
host answers a perfectly valid reseller key with "Invalid API key", which reads as
a dead key and sends you hunting the wrong problem. Probed live 2026-08-11 — the
same key gives "Invalid API key" on the bare host and a real, authenticated
response on the reseller host.

HTTP 200 ON FAILURE: Payon returns 200 with a numeric ``statusCode`` in the body
for every error (bad key, no balance, service not entitled). The status line is
therefore worthless on its own — the body must be read, or an outage is silently
swallowed as an empty result.

FIELD TYPES ARE ENFORCED, and the vendor's own PHP sample gets them wrong.
Verified live 2026-08-11 against a funded wallet:

* ``consent`` must be a **boolean** (``"true"``). The documented ``"Y"`` is
  rejected with ``"consent" must be a boolean``.
* ``documentsForConsent`` must be an **array** — form-encoded as repeated
  ``documentsForConsent[]`` keys. A comma-joined string is rejected with
  ``"documentsForConsent" must be an array``.
* The body must be **form-encoded**. A JSON body fails with "Invalid request.
  Please provide both apiKey" even when the key is present.

Each failure is a validation error rather than an auth error, so getting any of
them wrong looks like a broken request rather than a broken integration.
"""
from __future__ import annotations

from . import base
from .base import VerificationResult as R

try:  # `requests` is a deployment dependency; absent in the local dev venv.
    import requests
except Exception:  # pragma: no cover - exercised only where requests is missing
    requests = None

from core import runtime_settings as runtime
from core.phone import msisdn10

#: Reseller host. See the module docstring before "fixing" this to the bare host.
DEFAULT_BASE = "https://reseller.apipayon.in/api/v1/serv2"
INITIATE_PATH = "/digilocker_initiate.php"
COMPLETE_PATH = "/digilocker_complete.php"

TIMEOUT = 30


class ProviderError(Exception):
    """Transport/HTTP/vendor failure — surfaced to the caller as KYC_PROVIDER_ERROR."""


def _base() -> str:
    from django.conf import settings

    return str(getattr(settings, "PAYON_BASE_URL", "") or DEFAULT_BASE).rstrip("/")


def _api_key() -> str:
    """The Payon key.

    Deliberately the SAME `credit_bureau_api_key` the super-admin panel already
    holds: DigiLocker and the credit score are one vendor on one account with one
    key. A second field would only create a way for the two to drift out of step
    and for half the integration to break with no obvious cause.
    """
    return runtime.cfg("credit_bureau_api_key") or ""


def _as_int(v) -> int:
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return 0


def _post(path: str, fields: dict) -> dict:
    if requests is None:
        raise ProviderError("HTTP client unavailable (requests not installed).")
    key = _api_key()
    if not key:
        raise ProviderError("DigiLocker is not configured (no Payon API key).")
    try:
        resp = requests.post(
            _base() + path,
            data={"apiKey": key, **{k: v for k, v in fields.items() if v not in (None, "")}},
            timeout=TIMEOUT,
        )
    except Exception as exc:  # noqa: BLE001 — any transport failure is a provider error
        raise ProviderError(str(exc)) from exc

    if resp.status_code >= 400:
        raise ProviderError(f"DigiLocker HTTP {resp.status_code}.")
    try:
        body = resp.json()
    except ValueError as exc:
        # A 404 returns Payon's HTML error page; treat it as the outage it is
        # rather than letting a JSON parse error reach the customer.
        raise ProviderError("Non-JSON response from DigiLocker provider.") from exc
    if not isinstance(body, dict):
        raise ProviderError("Unexpected DigiLocker response shape.")

    # Payon answers HTTP 200 for failures, packing a numeric statusCode + message.
    # Without this an invalid key / empty wallet / unentitled service would be
    # swallowed as "no data" and look like a customer problem.
    code = _as_int(body.get("statusCode") or body.get("status"))
    if body.get("success") is not True and code >= 400:
        raise ProviderError(str(body.get("message") or f"DigiLocker error {code}."))
    return body


class PayonProvider(base.VerificationProvider):
    """DigiLocker via Payon. The only DigiLocker implementation."""

    name = "payon"

    # ── consent ──────────────────────────────────────────────────────────
    def start_digilocker(self, *, redirect_url: str, docs: list[str] | None = None,
                         mobile: str = "", purpose: str = "") -> R:
        # REQUIRED by the API ("The field 'mobileNumber' is required"), and it
        # wants the bare 10 digits — our users are stored as E.164.
        if not msisdn10(mobile):
            raise ProviderError("A mobile number is required to start DigiLocker.")
        body = _post(INITIATE_PATH, {
            "mobileNumber": msisdn10(mobile),
            "redirectUrl": redirect_url,
            # Boolean, not the documented "Y" — see the module docstring.
            "consent": "true",
            "consentPurpose": purpose or "KYC verification",
            "redirectToSignup": "false",
            # `requests` renders a list as repeated keys, which is the array
            # encoding the API demands. Joining these into one string fails.
            "documentsForConsent[]": list(docs or ["AADHAAR"]),
        })
        data = body.get("data") if isinstance(body.get("data"), dict) else body
        auth_url = data.get("authUrl") or data.get("url") or ""
        record = str(data.get("recordId") or data.get("id") or "")
        if not auth_url or not record:
            raise ProviderError("DigiLocker did not return an authorisation URL.")
        return R(
            kind=base.DIGILOCKER, status=base.PENDING, reference_id=record,
            redirect_url=auth_url,
            message="Approve the request in DigiLocker, then return to the app.",
            # `state` correlates the callback; keep it so the completion call can
            # present it back without a second round trip.
            raw={"provider": "payon", "state": data.get("state") or "",
                 "redirectToSignup": data.get("redirectToSignup"),
                 # Whether DigiLocker already knows this number. Not a gate — the
                 # session is issued either way — but it tells support whether the
                 # customer is about to be asked to create an account mid-KYC.
                 "accountExists": (data.get("accountCheck") or {}).get("accountExists")
                 if isinstance(data.get("accountCheck"), dict) else None},
        )

    # ── document pull ────────────────────────────────────────────────────
    def fetch_digilocker(self, *, request_id: str, name: str = "", state: str = "") -> R:
        """Exchange an authorised record for the Aadhaar detail.

        ⚠️ `digilocker_complete.php` is **not yet entitled** on this Payon account
        (probed 2026-08-11: it answers "Permission denied for this service" while
        `digilocker_initiate.php` answers the balance error, i.e. is entitled). The
        response shape below therefore follows the vendor's documented conventions
        and has NOT been observed live. When Payon enables it, verify the field
        names against a real response before trusting this mapping.
        """
        body = _post(COMPLETE_PATH, {"recordId": request_id, "state": state})
        data = body.get("data") if isinstance(body.get("data"), dict) else body

        pending = str(data.get("status") or "").upper() in ("PENDING", "INITIATED", "")
        if pending and not (data.get("name") or data.get("aadhaar")):
            return R(kind=base.AADHAAR, status=base.PENDING, reference_id=request_id,
                     message="We haven't received your DigiLocker consent yet.",
                     raw={"provider": "payon"})

        verified_name = str(data.get("name") or data.get("fullName") or "")
        aadhaar = str(data.get("aadhaar") or data.get("aadhaarNumber") or "")
        return R(
            kind=base.AADHAAR, status=base.VERIFIED,
            verified_name=verified_name,
            id_masked=base.mask_id(aadhaar) if aadhaar else str(data.get("maskedAadhaar") or ""),
            reference_id=request_id,
            name_match=base.names_match(name, verified_name) if name else None,
            message="Aadhaar fetched from DigiLocker.",
            raw={"provider": "payon", "source": "digilocker",
                 "dob": data.get("dob") or "", "gender": data.get("gender") or "",
                 "address": data.get("address") or ""},
        )
