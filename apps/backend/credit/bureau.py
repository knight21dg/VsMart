"""Credit-bureau score provider (CIBIL / credit score pull by mobile number).

One live provider — Payon `check_credit_score.php`. It takes a form-encoded
`apiKey` + `mobile`. The API key never leaves the server; it's read from runtime
settings (super-admin panel) with an env/settings default.

HOST: reseller keys are served from `reseller.apipayon.in`, NOT the bare
`apipayon.in`. Probed live 2026-08-05 — the same key returns "Invalid API key"
on the bare host and is recognised on the reseller host, so pointing at the wrong
one looks exactly like a dead key.

Services and views depend only on `BureauResult` / `BureauError`, so the provider
internals stay swappable without touching callers.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from core import runtime_settings as runtime

DEFAULT_BASE = "https://reseller.apipayon.in/api/v1/serv2/check_credit_score.php"
TIMEOUT = 25

# Result states.
SUCCESS = "success"      # a real score/PAN came back
NO_RECORD = "no_record"  # provider answered but carried no report (dedup / no history)

# CIBIL scores run 300–900.
SCORE_MIN, SCORE_MAX = 300, 900


class BureauError(Exception):
    """Transport / HTTP / auth failure talking to the bureau — CIBIL_PROVIDER_ERROR."""


@dataclass
class BureauResult:
    """Normalised outcome of one bureau pull."""

    status: str                      # SUCCESS | NO_RECORD
    score: int = 0
    band: str = ""
    name: str = ""
    pan: str = ""                    # masked before persistence, kept raw here briefly
    mobile: str = ""
    dob: str = ""
    gender: str = ""
    reference_id: str = ""           # provider transaction id (for support / audit)
    message: str = ""
    raw: dict = field(default_factory=dict)  # redacted provider payload, for audit

    @property
    def ok(self) -> bool:
        return self.status == SUCCESS


def _as_int(v) -> int:
    """Best-effort int() — a non-numeric status like 'SUCCESS' reads as 0."""
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


def band_for(score: int) -> str:
    """Map a raw CIBIL score to a human band."""
    if not score or score < SCORE_MIN:
        return "No Score"
    if score >= 750:
        return "Excellent"
    if score >= 700:
        return "Good"
    if score >= 650:
        return "Fair"
    if score >= 550:
        return "Below Average"
    return "Poor"


class PayonBureau:
    """Live provider — proxies apipayon.in. Credit fields arrive at the top level;
    a miss (dedup / no history) still returns HTTP 200 with an empty score."""

    name = "payon"

    def _url(self) -> str:
        return runtime.cfg("credit_bureau_base_url") or DEFAULT_BASE

    def fetch_score(self, *, mobile: str) -> BureauResult:
        api_key = runtime.cfg("credit_bureau_api_key") or ""
        if not api_key:
            raise BureauError("Credit-bureau API key is not configured.")

        import requests  # lazy: only the live path needs it installed

        try:
            resp = requests.post(
                self._url(),
                data={"apiKey": api_key, "mobile": mobile},
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                timeout=TIMEOUT,
            )
        except requests.RequestException as exc:
            raise BureauError(str(exc)) from exc
        if resp.status_code >= 400:
            raise BureauError(
                f"Credit-bureau HTTP {resp.status_code}"
                + (" (auth rejected)" if resp.status_code in (401, 403) else "."))
        try:
            body = resp.json()
        except ValueError as exc:
            raise BureauError("Non-JSON response from credit bureau") from exc

        # The credit fields are nested under `data`; success/status live on both the
        # envelope and the inner object. Fall back to the top level defensively.
        payload = body.get("data") if isinstance(body.get("data"), dict) else body

        # Payon signals a good lookup with status "VERIFIED" (per the current API
        # doc); older/other endpoints use "SUCCESS". Accept both — matching only
        # "SUCCESS" made a perfectly good VERIFIED response fall through to the
        # error branch below and surface as a provider failure.
        status_token = str(payload.get("status") or body.get("status") or "").upper()
        ok = (payload.get("success") is True or body.get("success") is True) and \
            status_token in ("SUCCESS", "VERIFIED")

        # Provider-level failure vs a genuine empty report. Payon returns HTTP 200
        # even for errors (bad/expired API key, no balance, malformed request),
        # packing a numeric statusCode + message; a real lookup instead carries
        # success:true / status:"SUCCESS". Without this, an invalid key was being
        # swallowed as "no credit record found", masking a config outage.
        if not ok:
            err_code = _as_int(payload.get("statusCode") or body.get("statusCode")
                               or payload.get("status") or body.get("status"))
            if err_code >= 400:
                raise BureauError(
                    payload.get("message") or body.get("message")
                    or f"Credit bureau returned status {err_code}.")

        score = int(payload.get("creditScore") or 0)
        pan = payload.get("pan") or ""
        name = payload.get("name") or ""
        ref = str(payload.get("transactionId")
                  or payload.get("providerTransactionId") or "")

        # success:true with an empty report (recently queried / no history) is a miss.
        if not ok or not (score or pan or name):
            return BureauResult(
                status=NO_RECORD, mobile=mobile, reference_id=ref,
                message=payload.get("message") or body.get("message")
                or "No credit record found.",
            )
        return BureauResult(
            status=SUCCESS, score=score,
            # `scoreCategory` is what the documented response carries ("GOOD");
            # `scoreBand` is the older key. band_for() is the local fallback.
            band=payload.get("scoreCategory") or payload.get("scoreBand")
            or band_for(score),
            name=name, pan=pan, mobile=payload.get("mobile") or mobile,
            dob=payload.get("dob") or "", gender=payload.get("gender") or "",
            reference_id=ref,
            message=payload.get("message") or "Credit score fetched.",
            raw={"provider": "payon", "chargeable": payload.get("chargeable"),
                 # Which bureau actually supplied the score, and as of when —
                 # a reviewer needs both to judge how much weight to give it.
                 "bureau": payload.get("bureau") or "",
                 "reportDate": payload.get("reportDate") or ""},
        )


def get_provider() -> PayonBureau:
    """The credit-bureau provider. Payon is the single live source."""
    return PayonBureau()
