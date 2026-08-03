"""Runtime-editable integration config.

The `system.IntegrationSettings` singleton is seeded from env/settings the first
time it's accessed, then editable from the super-admin panel. Service code reads
values through `cfg(field)`; the cached snapshot is refreshed on save via
`invalidate()`. This lets an admin change SMTP / SMS / Razorpay / FCM credentials
without a redeploy, while env still provides the initial defaults.
"""
from django.conf import settings
from django.core.cache import cache

_CACHE_KEY = "integration_settings_snapshot_v1"
_TTL = 300

# model field -> settings attr used to seed the initial row
SEED = {
    "sms_provider": "SMS_PROVIDER",
    "msg91_auth_key": "MSG91_AUTH_KEY",
    "msg91_template_id": "MSG91_OTP_TEMPLATE_ID",
    "smslogin_username": "SMSLOGIN_USERNAME",
    "smslogin_api_key": "SMSLOGIN_API_KEY",
    "smslogin_sender_id": "SMSLOGIN_SENDER_ID",
    "smslogin_template_id": "SMSLOGIN_TEMPLATE_ID",
    "smslogin_otp_message": "SMSLOGIN_OTP_MESSAGE",
    "otp_bypass_code": "OTP_DEV_BYPASS_CODE",
    "email_host": "EMAIL_HOST",
    "email_port": "EMAIL_PORT",
    "email_user": "EMAIL_HOST_USER",
    "email_password": "EMAIL_HOST_PASSWORD",
    "email_use_tls": "EMAIL_USE_TLS",
    "email_from": "DEFAULT_FROM_EMAIL",
    "razorpay_key_id": "RAZORPAY_KEY_ID",
    "razorpay_key_secret": "RAZORPAY_KEY_SECRET",
    "razorpay_webhook_secret": "RAZORPAY_WEBHOOK_SECRET",
    "fcm_server_key": "FCM_SERVER_KEY",
    "google_maps_key": "GOOGLE_MAPS_API_KEY",
    # KYC / identity verification (Setu)
    "kyc_provider": "KYC_PROVIDER",
    "setu_base_url": "SETU_BASE_URL",
    "setu_dg_base_url": "SETU_DG_BASE_URL",
    "setu_client_id": "SETU_CLIENT_ID",
    "setu_client_secret": "SETU_CLIENT_SECRET",
    "setu_pan_product_id": "SETU_PAN_PRODUCT_ID",
    "setu_digilocker_product_id": "SETU_DIGILOCKER_PRODUCT_ID",
    "setu_aadhaar_product_id": "SETU_AADHAAR_PRODUCT_ID",
    "setu_bank_product_id": "SETU_BANK_PRODUCT_ID",
    # KYC (Signzy)
    "signzy_base_url": "SIGNZY_BASE_URL",
    "signzy_api_key": "SIGNZY_API_KEY",
    "signzy_username": "SIGNZY_USERNAME",
    "signzy_password": "SIGNZY_PASSWORD",
    # KYC (Cashfree Secure ID)
    "cashfree_base_url": "CASHFREE_BASE_URL",
    "cashfree_app_id": "CASHFREE_APP_ID",
    "cashfree_secret_key": "CASHFREE_SECRET_KEY",
    "cashfree_api_version": "CASHFREE_API_VERSION",
    # Credit bureau (CIBIL score pull) — Payon by default; mock when unset
    "credit_bureau_provider": "CREDIT_BUREAU_PROVIDER",
    "credit_bureau_base_url": "CREDIT_BUREAU_BASE_URL",
    "credit_bureau_api_key": "CREDIT_BUREAU_API_KEY",
}

# Never returned in clear text by the admin API.
SECRET_FIELDS = {
    "msg91_auth_key", "smslogin_api_key", "otp_bypass_code", "email_password",
    "razorpay_key_secret", "razorpay_webhook_secret", "fcm_server_key",
    "google_maps_key", "setu_client_secret",
    "signzy_api_key", "signzy_password", "cashfree_secret_key",
    "credit_bureau_api_key",
}


def get_obj():
    """Return the singleton, creating it (seeded from env) on first access."""
    from system.models import IntegrationSettings

    obj = IntegrationSettings.objects.first()
    if obj is not None:
        return obj
    seed = {f: (getattr(settings, attr, "") or "") for f, attr in SEED.items()}
    seed["email_port"] = int(getattr(settings, "EMAIL_PORT", 587) or 587)
    seed["email_use_tls"] = bool(getattr(settings, "EMAIL_USE_TLS", True))
    return IntegrationSettings.objects.create(**seed)


def _snapshot():
    snap = cache.get(_CACHE_KEY)
    if snap is None:
        obj = get_obj()
        snap = {f: getattr(obj, f) for f in SEED}
        cache.set(_CACHE_KEY, snap, _TTL)
    return snap


def cfg(field):
    """Current value for `field` (DB-backed, cached). When the stored value is
    blank — including fields added to the model AFTER the singleton row was first
    created — fall back to the env/settings seed default so newly-introduced
    integrations work without an admin having to re-save the panel."""
    val = _snapshot().get(field)
    if val in (None, ""):
        attr = SEED.get(field)
        if attr:
            return getattr(settings, attr, "") or ""
    return val


def invalidate():
    cache.delete(_CACHE_KEY)
