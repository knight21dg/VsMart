"""OTP generation, storage (cache/Redis) and delivery (SMS).

Codes are never stored in plaintext — only a salted hash, in the cache with a TTL.
In dev (SMS_PROVIDER=console) the code is printed to the server log.
"""
import hashlib
import secrets
import uuid

from django.conf import settings
from django.core.cache import cache

from core import runtime_settings as runtime


def _hash(code: str) -> str:
    return hashlib.sha256(f"{settings.SECRET_KEY}:{code}".encode()).hexdigest()


def _key(verification_id: str) -> str:
    return f"otp:{verification_id}"


def generate_and_send(phone: str, purpose: str = "login") -> str:
    """Create an OTP for `phone`, store its hash, send it, return a verification id."""
    code = "".join(secrets.choice("0123456789") for _ in range(settings.OTP_LENGTH))
    verification_id = uuid.uuid4().hex
    cache.set(
        _key(verification_id),
        {"phone": phone, "hash": _hash(code), "purpose": purpose, "attempts": 0},
        timeout=settings.OTP_TTL_SECONDS,
    )
    send_sms(phone, code, purpose)
    return verification_id


def verify(verification_id: str, phone: str, code: str) -> bool:
    record = cache.get(_key(verification_id))
    if not record or record["phone"] != phone:
        return False
    if record["attempts"] >= settings.OTP_MAX_ATTEMPTS:
        cache.delete(_key(verification_id))
        return False
    # Dev-only master code (e.g. "123456") so testers can log in without reading
    # the server console. Empty/unset in prod, so it never applies there.
    bypass = runtime.cfg("otp_bypass_code")
    if bypass and secrets.compare_digest(str(code), str(bypass)):
        cache.delete(_key(verification_id))
        return True
    if secrets.compare_digest(record["hash"], _hash(code)):
        cache.delete(_key(verification_id))
        return True
    record["attempts"] += 1
    cache.set(_key(verification_id), record, timeout=settings.OTP_TTL_SECONDS)
    return False


# ── DLT-registered templates (India TRAI) ────────────────────────────────
# Every OTP purpose needs its OWN template approved on the DLT portal, and the
# body sent must match the registered text byte-for-byte — otherwise the gateway
# rejects the send. Note the URL runs straight on after "anyone." with NO space:
# that is how the templates were approved, so it is reproduced exactly.
#
# The id and the body are a matched pair — changing either requires a fresh DLT
# registration — so they live together here rather than as two separately
# admin-editable fields that could silently drift apart. `test_otp_templates.py`
# locks the exact strings.
_SUFFIX = "https://thevsmart.com/login"
DLT_TEMPLATES = {
    "login": (
        "1777178591139204185",
        "{code} is your VS Mart login OTP. Valid for 5 minutes."
        " Do not share this code with anyone." + _SUFFIX,
    ),
    "agent_login": (
        "1777178591135927753",
        "{code} is your VS Mart Partner App login OTP. Valid for 5 minutes."
        " Do not share this code with anyone." + _SUFFIX,
    ),
    "kyc_credit": (
        "1777178591129663873",
        "{code} is your OTP to verify your mobile number for a VS Mart credit"
        " check. Valid for 5 minutes. Do not share this code with anyone." + _SUFFIX,
    ),
    # No password-reset-specific template was registered. Rather than leave the
    # admin/store password-reset OTP unable to send, it uses the second approved
    # "VS Mart login OTP" template — same wording, different id, so the two stay
    # separable in the gateway's delivery reports. Swap in a dedicated template
    # here if one is ever approved.
    "password_reset": (
        "1777178591167080776",
        "{code} is your VS Mart login OTP. Valid for 5 minutes."
        " Do not share this code with anyone.https://thevsmart.com/",
    ),
}


def send_sms(phone: str, code: str, purpose: str) -> None:
    # Default to "console" (log the code) when unset, so a blank provider never
    # 500s the OTP-send endpoint — it just logs instead of sending. Read from the
    # runtime config (super-admin panel), seeded from SMS_PROVIDER.
    provider = runtime.cfg("sms_provider") or "console"
    if provider == "console":
        print(f"\n[OTP] {purpose} code for {phone}: {code}\n")
        return
    if provider == "msg91":
        _send_via_msg91(phone, code)
        return
    if provider == "smslogin":
        _send_via_smslogin(phone, code, purpose)
        return
    raise NotImplementedError(f"SMS provider '{provider}' not configured yet.")


def template_for(purpose: str) -> tuple[str, str]:
    """(template_id, message body) for `purpose`.

    Falls back to the legacy single-template config for purposes that have no
    DLT registration yet, so adding a new OTP purpose doesn't hard-break before
    its template is approved.
    """
    if purpose in DLT_TEMPLATES:
        return DLT_TEMPLATES[purpose]
    template_id = runtime.cfg("smslogin_template_id")
    body = runtime.cfg("smslogin_otp_message")
    if not template_id or not body:
        raise RuntimeError(
            f"No DLT template registered for OTP purpose '{purpose}', and no "
            f"fallback smslogin_template_id/smslogin_otp_message is configured. "
            f"Register the template on the DLT portal and add it to DLT_TEMPLATES."
        )
    return template_id, body


def _local_mobile(phone: str) -> str:
    """smslogin.co expects a bare 10-digit Indian mobile.

    Numbers are stored E.164 (`+919876543210`), so strip the `+` and the `91`
    country code. Anything that isn't a 12-digit Indian number is passed through
    with just the `+` removed rather than mangled.
    """
    digits = "".join(ch for ch in phone if ch.isdigit())
    if len(digits) == 12 and digits.startswith("91"):
        return digits[2:]
    return digits


def _send_via_smslogin(phone: str, code: str, purpose: str = "login") -> None:
    """Send the OTP via smslogin.co's v3 HTTP API (SMS_PROVIDER=smslogin).

    The gateway is a plain GET that returns a MessageID on success and a plain
    text error otherwise — always HTTP 200 — so the body has to be inspected to
    tell the two apart.
    """
    import requests

    api_key = runtime.cfg("smslogin_api_key")
    username = runtime.cfg("smslogin_username")
    sender_id = runtime.cfg("smslogin_sender_id")
    # Each purpose carries its own DLT-approved template id + body; they must be
    # sent as a matched pair or the gateway rejects the message.
    template_id, body = template_for(purpose)

    missing = [
        name for name, value in (
            ("smslogin_api_key", api_key),
            ("smslogin_username", username),
            ("smslogin_sender_id", sender_id),
            ("smslogin_template_id", template_id),
        ) if not value
    ]
    if missing:
        raise RuntimeError(
            "smslogin is not fully configured — missing: " + ", ".join(missing))

    base = getattr(settings, "SMSLOGIN_BASE_URL", "https://smslogin.co/v3/api.php")
    resp = requests.get(
        base,
        params={
            "username": username,
            "apikey": api_key,
            "senderid": sender_id,
            "mobile": _local_mobile(phone),
            # The body must match the DLT-registered template exactly; only the
            # code varies. requests URL-encodes this for us.
            "message": body.replace("{code}", code),
            "templateid": template_id,
        },
        timeout=10,
    )
    resp.raise_for_status()
    text = (resp.text or "").strip()
    # A successful send returns a MessageID. Errors come back 200 with a body
    # like {'Error':'Invalid Template ID'} — without this check a failed send
    # would report "OTP sent" and the customer would wait forever.
    lowered = text.lower()
    if not text or any(
        w in lowered for w in ("invalid", "error", "fail", "insufficient", "not ")
    ):
        raise RuntimeError(f"smslogin rejected the OTP: {text or 'empty response'}")
    # Verified against the live gateway: when senderid/templateid are absent it
    # does NOT error — it answers the CREDIT-BALANCE query instead ({"Credits":
    # "9890"}) and sends nothing. That body contains none of the words above, so
    # it would otherwise be mistaken for a MessageID and reported as a success.
    if "credit" in lowered:
        raise RuntimeError(
            "smslogin returned a credit balance instead of a message id — the "
            "send parameters were not accepted, so no SMS was sent.")


def smslogin_balance() -> str:
    """Remaining SMS credits, as reported by the gateway.

    Worth surfacing to ops: when credits run out the gateway starts refusing
    sends, and the only symptom is customers not receiving OTPs.
    """
    import requests

    resp = requests.get(
        getattr(settings, "SMSLOGIN_BASE_URL", "https://smslogin.co/v3/api.php"),
        params={
            "username": runtime.cfg("smslogin_username"),
            "apikey": runtime.cfg("smslogin_api_key"),
        },
        timeout=10,
    )
    resp.raise_for_status()
    return (resp.text or "").strip()


def _send_via_msg91(phone: str, code: str) -> None:
    """Send the OTP via MSG91's OTP API. Activated by SMS_PROVIDER=msg91 + an auth key."""
    import requests

    key = runtime.cfg("msg91_auth_key")
    if not key:
        raise RuntimeError("MSG91_AUTH_KEY is not configured.")
    requests.post(
        "https://control.msg91.com/api/v5/otp",
        json={
            "template_id": runtime.cfg("msg91_template_id"),
            "mobile": phone.lstrip("+"),
            "otp": code,
        },
        headers={"authkey": key, "Content-Type": "application/json"},
        timeout=10,
    )
