"""Provider selection. Mirrors payments.gateway.get_gateway():

  • KYC_PROVIDER=signzy   + credentials → live Signzy (recommended for production)
  • KYC_PROVIDER=cashfree + credentials → live Cashfree Secure ID (needs the
                                          Verification Suite product enabled)
  • KYC_PROVIDER=setu     + credentials → live Setu
  • anything else (blank / `mock` / missing keys) → the mock verifier

DIGILOCKER IS NOT PART OF THAT CHOICE. It always resolves to Payon via
`get_digilocker_provider()` — there is one DigiLocker vendor by directive, and no
mock, so a missing key fails loudly instead of fabricating a verified Aadhaar.

so dev/CI and any environment without keys run the full flow end-to-end. Adding a
new provider (e.g. an NBFC partner's own API) is one class + one branch here.
"""
from core import runtime_settings as runtime

from .base import (  # noqa: F401  (re-exported for callers)
    AADHAAR,
    BANK,
    DIGILOCKER,
    FAILED,
    PAN,
    PENDING,
    VERIFIED,
    VerificationProvider,
    VerificationResult,
)
from .mock import MockProvider
from .payon import PayonProvider  # noqa: F401


def get_provider() -> VerificationProvider:
    choice = (runtime.cfg("kyc_provider") or "").lower()
    if choice == "signzy" and (
        runtime.cfg("signzy_api_key")
        or (runtime.cfg("signzy_username") and runtime.cfg("signzy_password"))
    ):
        try:
            from .signzy import SignzyProvider

            return SignzyProvider()
        except Exception:  # missing `requests`, import error → degrade to mock
            return MockProvider()
    if choice == "cashfree" and runtime.cfg("cashfree_app_id") and \
            runtime.cfg("cashfree_secret_key"):
        try:
            from .cashfree import CashfreeProvider

            return CashfreeProvider()
        except Exception:
            return MockProvider()
    if choice == "setu" and runtime.cfg("setu_client_id") and runtime.cfg("setu_client_secret"):
        try:
            from .setu import SetuProvider

            return SetuProvider()
        except Exception:
            return MockProvider()
    return MockProvider()


def get_digilocker_provider() -> VerificationProvider:
    """The DigiLocker provider — always Payon, never the mock.

    Kept separate from `get_provider()` on purpose. DigiLocker returns a
    government-sourced identity document; a mock that answers "verified" for any
    input is not an acceptable fallback for that, and with every provider
    credential currently empty the generic selector resolves to exactly that mock.
    An unconfigured DigiLocker now raises instead.
    """
    return PayonProvider()
