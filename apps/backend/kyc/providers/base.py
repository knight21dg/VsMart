"""Provider-agnostic identity-verification contract.

Every concrete provider (Setu, mock, …) returns the same `VerificationResult`,
so the services + views never branch on which vendor is configured. Swapping
providers is a settings change, not a code change — mirrors payments.gateway.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

# Document kinds we can verify against a government / banking source.
PAN = "pan"
AADHAAR = "aadhaar"
BANK = "bank"
DIGILOCKER = "digilocker"  # generic DigiLocker doc pull (voter/DL/passport/…)

# Result states.
VERIFIED = "verified"   # matched a trusted source
FAILED = "failed"       # source says invalid / mismatch
PENDING = "pending"     # awaiting an out-of-band step (e.g. DigiLocker consent)


@dataclass
class VerificationResult:
    """The normalised outcome of one verification call."""

    kind: str
    status: str                      # VERIFIED | FAILED | PENDING
    verified_name: str = ""          # name as returned by the source
    verified_dob: str = ""           # DOB from the source (YYYY-MM-DD) — drives the 18+ gate
    verified_address: str = ""       # address from the source (Aadhaar) — usually left partner-side
    id_masked: str = ""              # masked id (e.g. XXXXXX1234B) — never the full id
    name_match: bool | None = None   # did the source name match what the user claims?
    reference_id: str = ""           # provider trace / request id (for support)
    error_code: str = ""             # catalog code to surface on FAILED
    redirect_url: str = ""           # for PENDING flows that need a user redirect
    message: str = ""
    raw: dict = field(default_factory=dict)  # redacted provider payload, for audit

    @property
    def ok(self) -> bool:
        return self.status == VERIFIED


def mask_id(value: str, *, keep: int = 4) -> str:
    """Mask all but the last `keep` characters: 'ABCDE1234B' -> 'XXXXXX234B'."""
    v = (value or "").strip()
    if len(v) <= keep:
        return v
    return "X" * (len(v) - keep) + v[-keep:]


_NAME_NOISE = re.compile(r"[^a-z ]+")
_HONORIFICS = {"mr", "mrs", "ms", "miss", "dr", "shri", "smt", "kum", "sri"}


def normalise_name(name: str) -> str:
    """Lowercase, strip honorifics/punctuation, collapse whitespace."""
    cleaned = _NAME_NOISE.sub(" ", (name or "").lower())
    tokens = [t for t in cleaned.split() if t and t not in _HONORIFICS]
    return " ".join(tokens)


def names_match(claimed: str, source: str) -> bool:
    """Tolerant name comparison for KYC. Exact after normalisation, or one is a
    token-subset of the other (handles middle names / initials / reordering)."""
    a, b = normalise_name(claimed), normalise_name(source)
    if not a or not b:
        return False
    if a == b:
        return True
    ta, tb = set(a.split()), set(b.split())
    return ta.issubset(tb) or tb.issubset(ta)


class VerificationProvider:
    """Interface implemented by every provider. Methods raise NotImplementedError
    when a provider doesn't support a given check."""

    name = "base"

    # ── PAN ──────────────────────────────────────────────────────────────
    def verify_pan(self, *, pan: str, name: str = "", consent: bool = False,
                   reason: str = "") -> VerificationResult:
        raise NotImplementedError

    # ── Aadhaar via DigiLocker (no AUA/KUA licence needed) ───────────────
    def start_digilocker(self, *, redirect_url: str, docs: list[str] | None = None,
                         mobile: str = "", purpose: str = "") -> VerificationResult:
        """Create a consent request; returns PENDING + a redirect_url + reference_id."""
        raise NotImplementedError

    def fetch_digilocker(self, *, request_id: str, name: str = "",
                         state: str = "") -> VerificationResult:
        """After consent, pull the Aadhaar (and any docs) for the request."""
        raise NotImplementedError

    # ── Aadhaar OKYC (OTP, offline eKYC) ─────────────────────────────────
    def aadhaar_okyc_init(self, *, aadhaar: str) -> VerificationResult:
        """Trigger the OTP to the Aadhaar-linked mobile; returns PENDING + reference_id."""
        raise NotImplementedError

    def aadhaar_okyc_submit(self, *, reference_id: str, otp: str, name: str = ""
                            ) -> VerificationResult:
        raise NotImplementedError

    # ── Bank account (penny-drop) ────────────────────────────────────────
    def verify_bank(self, *, account: str, ifsc: str, name: str = "") -> VerificationResult:
        raise NotImplementedError
