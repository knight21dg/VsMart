"""Deterministic mock verifier — lets the whole KYC flow run and be tested without
live Setu keys (the same role MockGateway plays for payments).

Behaviour is keyed off the *input* so tests can drive every branch:
  • PAN `ABCDE1234B`           → invalid (Setu's documented invalid test PAN)
  • PAN starting with `MISMT`  → name mismatch
  • any other well-formed PAN  → verified (echoes the claimed name)
  • Aadhaar OKYC OTP `123456`  → verified; anything else → invalid OTP
"""
from __future__ import annotations

import re
import uuid

from . import base
from .base import VerificationResult as R

PAN_RE = re.compile(r"^[A-Z]{5}[0-9]{4}[A-Z]$")
IFSC_RE = re.compile(r"^[A-Z]{4}0[A-Z0-9]{6}$")
INVALID_TEST_PAN = "ABCDE1234B"


class MockProvider(base.VerificationProvider):
    name = "mock"

    def verify_pan(self, *, pan, name="", consent=False, reason=""):
        pan = (pan or "").upper().strip()
        if not PAN_RE.match(pan) or pan == INVALID_TEST_PAN:
            return R(kind=base.PAN, status=base.FAILED, id_masked=base.mask_id(pan),
                     error_code="PAN_INVALID", message="PAN could not be verified.")
        if pan.startswith("MISMT"):
            src = "Some Other Person"
            return R(kind=base.PAN, status=base.FAILED, verified_name=src,
                     id_masked=base.mask_id(pan), name_match=False,
                     error_code="PAN_NAME_MISMATCH", reference_id=uuid.uuid4().hex,
                     message="Name on PAN does not match.")
        verified_name = name or "Verified Holder"
        return R(kind=base.PAN, status=base.VERIFIED, verified_name=verified_name,
                 verified_dob="1995-06-14", id_masked=base.mask_id(pan),
                 reference_id=uuid.uuid4().hex,
                 name_match=base.names_match(name, verified_name) if name else None,
                 message="PAN verified.", raw={"category": "person", "mock": True})

    def start_digilocker(self, *, redirect_url, docs=None):
        ref = uuid.uuid4().hex
        return R(kind=base.DIGILOCKER, status=base.PENDING, reference_id=ref,
                 redirect_url=f"https://mock.setu.local/digilocker/{ref}",
                 message="Consent pending.")

    def fetch_digilocker(self, *, request_id, name=""):
        verified_name = name or "Verified Holder"
        return R(kind=base.AADHAAR, status=base.VERIFIED, verified_name=verified_name,
                 id_masked="XXXXXXXX1234", reference_id=request_id,
                 name_match=base.names_match(name, verified_name) if name else None,
                 message="Aadhaar fetched from DigiLocker.",
                 raw={"source": "digilocker", "mock": True})

    def aadhaar_okyc_init(self, *, aadhaar):
        return R(kind=base.AADHAAR, status=base.PENDING, reference_id=uuid.uuid4().hex,
                 id_masked=base.mask_id(aadhaar), message="OTP sent.")

    def aadhaar_okyc_submit(self, *, reference_id, otp, name=""):
        if str(otp) != "123456":
            return R(kind=base.AADHAAR, status=base.FAILED, reference_id=reference_id,
                     error_code="AADHAAR_OTP_INVALID", message="Incorrect OTP.")
        verified_name = name or "Verified Holder"
        return R(kind=base.AADHAAR, status=base.VERIFIED, verified_name=verified_name,
                 verified_dob="1995-06-14", verified_address="12 MG Road, Hyderabad, TG 500001",
                 reference_id=reference_id, id_masked="XXXXXXXX1234",
                 name_match=base.names_match(name, verified_name) if name else None,
                 message="Aadhaar verified.", raw={"source": "okyc", "mock": True})

    def verify_bank(self, *, account, ifsc, name=""):
        ifsc = (ifsc or "").upper().strip()
        if not (account or "").isdigit() or not IFSC_RE.match(ifsc):
            return R(kind=base.BANK, status=base.FAILED, error_code="BANK_VERIFICATION_FAILED",
                     message="Bank account could not be verified.")
        verified_name = name or "Verified Holder"
        return R(kind=base.BANK, status=base.VERIFIED, verified_name=verified_name,
                 id_masked=base.mask_id(account), reference_id=uuid.uuid4().hex,
                 name_match=base.names_match(name, verified_name) if name else None,
                 message="Bank account verified.", raw={"mock": True})
