from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


class FeatureFlag(TimeStampedModel):
    """Runtime toggle keyed by a stable string (e.g. "maintenance")."""

    key = models.CharField(max_length=60, unique=True)
    enabled = models.BooleanField(default=False)
    description = models.CharField(max_length=255, blank=True)

    def __str__(self):
        return f"{self.key} ({'on' if self.enabled else 'off'})"


class Feedback(TimeStampedModel):
    """Free-form app feedback, optionally tied to a user and a star rating."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="feedback",
    )
    message = models.TextField()
    rating = models.PositiveSmallIntegerField(null=True, blank=True)

    def __str__(self):
        return f"Feedback #{self.pk}"


class IntegrationSettings(TimeStampedModel):
    """Singleton (first row) of admin-editable integration credentials. Seeded from
    env on first access, then overridable from the super-admin panel at runtime.
    Service code reads values via core.runtime_settings.cfg()."""

    # SMS / OTP
    sms_provider = models.CharField(max_length=20, blank=True, default="")  # ""|console|msg91|smslogin
    msg91_auth_key = models.CharField(max_length=255, blank=True, default="")
    msg91_template_id = models.CharField(max_length=64, blank=True, default="")
    # smslogin.co — unlike MSG91's OTP API (which renders the template server-side
    # from just the code), this gateway takes the FULL message text plus the DLT
    # template id. The text must match the registered DLT template exactly or the
    # operator rejects the SMS, so the body lives in config, not in code.
    smslogin_username = models.CharField(max_length=64, blank=True, default="")
    smslogin_api_key = models.CharField(max_length=255, blank=True, default="")
    smslogin_sender_id = models.CharField(max_length=16, blank=True, default="")
    smslogin_template_id = models.CharField(max_length=64, blank=True, default="")
    smslogin_otp_message = models.CharField(max_length=480, blank=True, default="")
    otp_bypass_code = models.CharField(max_length=8, blank=True, default="")
    # Email / SMTP
    email_host = models.CharField(max_length=200, blank=True, default="")
    email_port = models.PositiveIntegerField(default=587)
    email_user = models.CharField(max_length=200, blank=True, default="")
    email_password = models.CharField(max_length=255, blank=True, default="")
    email_use_tls = models.BooleanField(default=True)
    email_from = models.CharField(max_length=200, blank=True, default="")
    # Payments (Razorpay)
    razorpay_key_id = models.CharField(max_length=120, blank=True, default="")
    razorpay_key_secret = models.CharField(max_length=120, blank=True, default="")
    razorpay_webhook_secret = models.CharField(max_length=120, blank=True, default="")
    # Push (FCM)
    fcm_server_key = models.CharField(max_length=400, blank=True, default="")
    # Maps (server-side Google APIs: directions, geocoding, distance-matrix, static)
    google_maps_key = models.CharField(max_length=120, blank=True, default="")
    # KYC / identity verification (Setu). Blank/`mock` provider → the bundled mock
    # verifier runs everything in dev/CI without live keys; set provider=setu plus
    # the client credentials + per-product instance ids to verify against gov sources.
    kyc_provider = models.CharField(max_length=20, blank=True, default="")  # ""|mock|setu
    setu_base_url = models.CharField(max_length=120, blank=True, default="")     # data/KYC host
    setu_dg_base_url = models.CharField(max_length=120, blank=True, default="")  # DigiLocker host
    setu_client_id = models.CharField(max_length=120, blank=True, default="")
    setu_client_secret = models.CharField(max_length=200, blank=True, default="")
    setu_pan_product_id = models.CharField(max_length=120, blank=True, default="")
    setu_digilocker_product_id = models.CharField(max_length=120, blank=True, default="")
    setu_aadhaar_product_id = models.CharField(max_length=120, blank=True, default="")
    setu_bank_product_id = models.CharField(max_length=120, blank=True, default="")
    # KYC — Signzy (recommended production provider; one vendor across PAN/Aadhaar/
    # CKYC/bank/face/video as the lending product grows). Static API key OR
    # username/password (patron-login token). Set kyc_provider=signzy to activate.
    signzy_base_url = models.CharField(max_length=120, blank=True, default="")
    signzy_api_key = models.CharField(max_length=400, blank=True, default="")
    signzy_username = models.CharField(max_length=200, blank=True, default="")
    signzy_password = models.CharField(max_length=200, blank=True, default="")
    # KYC — Cashfree "Secure ID" Verification Suite (needs the product enabled on
    # the account; plain Payment-Gateway keys alone won't reach /verification/*).
    cashfree_base_url = models.CharField(max_length=120, blank=True, default="")
    cashfree_app_id = models.CharField(max_length=120, blank=True, default="")
    cashfree_secret_key = models.CharField(max_length=200, blank=True, default="")
    cashfree_api_version = models.CharField(max_length=20, blank=True, default="")

    # ── Credit bureau (CIBIL score pull) ──
    # provider ""|mock|payon. Payon proxies a bureau score by mobile number.
    credit_bureau_provider = models.CharField(max_length=20, blank=True, default="")
    credit_bureau_base_url = models.CharField(max_length=200, blank=True, default="")
    credit_bureau_api_key = models.CharField(max_length=200, blank=True, default="")

    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+",
    )

    class Meta:
        verbose_name = verbose_name_plural = "Integration settings"

    def __str__(self):
        return "Integration settings"


class AuditLog(TimeStampedModel):
    """Immutable trail of every coded response/event. Powers compliance review,
    security monitoring and risk analytics. Written best-effort by core.audit."""

    event_id = models.CharField(max_length=40, unique=True, db_index=True)
    timestamp = models.DateTimeField(db_index=True)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="audit_events",
    )
    actor_phone = models.CharField(max_length=15, blank=True)
    source_module = models.CharField(max_length=40, db_index=True)
    entity_type = models.CharField(max_length=60, blank=True)
    entity_id = models.CharField(max_length=64, blank=True)
    code = models.CharField(max_length=60, db_index=True)
    severity = models.CharField(max_length=12)
    success = models.BooleanField(default=False)
    is_security_event = models.BooleanField(default=False, db_index=True)
    is_risk_event = models.BooleanField(default=False, db_index=True)
    method = models.CharField(max_length=8, blank=True)
    path = models.CharField(max_length=200, blank=True)
    ip = models.GenericIPAddressField(null=True, blank=True)
    message = models.CharField(max_length=300, blank=True)
    context = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["-timestamp"]
        indexes = [models.Index(fields=["code", "timestamp"])]

    def __str__(self):
        return f"{self.code} @ {self.timestamp:%Y-%m-%d %H:%M}"
