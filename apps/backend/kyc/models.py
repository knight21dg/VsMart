import hashlib

from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


def hash_gov_id(kind: str, value: str) -> str:
    """One-way, salted fingerprint of a government id (PAN/Aadhaar/account number).
    Lets us detect the same id reused on another account WITHOUT storing the id."""
    norm = (value or "").upper().replace(" ", "")
    if not norm:
        return ""
    return hashlib.sha256(f"{settings.SECRET_KEY}:{kind}:{norm}".encode()).hexdigest()

STEP_CHOICES = [
    ("aadhaar", "Aadhaar"),
    ("pan", "PAN"),
    ("selfie", "Selfie"),
    ("residence", "Residence"),
    ("credit", "Credit"),
]
# Document types the reviewer can be shown. A superset of STEP_CHOICES that adds
# the front/back scans the credit-onboarding flow collects (Aadhaar + PAN, both
# sides). Steps stay STEP_CHOICES; only KycDocument.type uses this wider set.
DOC_TYPE_CHOICES = STEP_CHOICES + [
    ("aadhaar_front", "Aadhaar (front)"),
    ("aadhaar_back", "Aadhaar (back)"),
    ("pan_front", "PAN (front)"),
    ("pan_back", "PAN (back)"),
]
REVIEW_STATUS = [
    ("pending", "Pending"),
    ("in_review", "In review"),
    ("approved", "Approved"),
    ("rejected", "Rejected"),
]


class KycApplication(TimeStampedModel):
    class Status(models.TextChoices):
        NOT_STARTED = "not_started"
        PENDING = "pending"
        VERIFIED = "verified"
        REJECTED = "rejected"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="kyc_application"
    )
    status = models.CharField(
        max_length=12, choices=Status.choices, default=Status.NOT_STARTED
    )
    submitted_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="kyc_reviews",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.CharField(max_length=200, blank=True)


def kyc_upload_to(instance, filename):
    """Per-application, per-type storage path under MEDIA_ROOT."""
    return f"kyc/{instance.application_id}/{instance.type}/{filename}"


class KycDocument(TimeStampedModel):
    application = models.ForeignKey(
        KycApplication, on_delete=models.CASCADE, related_name="documents"
    )
    type = models.CharField(max_length=20, choices=DOC_TYPE_CHOICES)
    number_masked = models.CharField(max_length=40, blank=True)
    file_key = models.CharField(max_length=200, blank=True)  # object key in storage
    # Actual uploaded image (multipart). Optional — JSON-only submits leave it blank
    # and keep working as before.
    file = models.ImageField(upload_to=kyc_upload_to, null=True, blank=True)
    # Optional geotag captured at upload time (e.g. residence proof GPS). Lets a
    # reviewer confirm the document was taken at the claimed location.
    latitude = models.DecimalField(
        max_digits=9, decimal_places=6, null=True, blank=True
    )
    longitude = models.DecimalField(
        max_digits=9, decimal_places=6, null=True, blank=True
    )
    status = models.CharField(max_length=10, choices=REVIEW_STATUS, default="pending")


class VerificationStep(TimeStampedModel):
    application = models.ForeignKey(
        KycApplication, on_delete=models.CASCADE, related_name="steps"
    )
    step = models.CharField(max_length=12, choices=STEP_CHOICES)
    status = models.CharField(max_length=10, choices=REVIEW_STATUS, default="pending")
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )
    note = models.CharField(max_length=200, blank=True)

    class Meta:
        unique_together = ("application", "step")


class KycVerification(TimeStampedModel):
    """One identity-verification attempt against a government / banking source via a
    provider (Setu, mock). Append-only audit of what was checked and what came back —
    raw PII is never stored, only a masked id, a salted id-hash, and the source name."""

    class Kind(models.TextChoices):
        PAN = "pan", "PAN"
        AADHAAR = "aadhaar", "Aadhaar"
        BANK = "bank", "Bank account"
        DIGILOCKER = "digilocker", "DigiLocker document"

    class Status(models.TextChoices):
        VERIFIED = "verified", "Verified"
        FAILED = "failed", "Failed"
        PENDING = "pending", "Pending"

    application = models.ForeignKey(
        KycApplication, on_delete=models.CASCADE, related_name="verifications"
    )
    kind = models.CharField(max_length=12, choices=Kind.choices)
    provider = models.CharField(max_length=20, blank=True)
    status = models.CharField(max_length=10, choices=Status.choices)
    verified_name = models.CharField(max_length=160, blank=True)
    verified_dob = models.CharField(max_length=10, blank=True)   # YYYY-MM-DD from the source
    # Aadhaar address from the source. Left blank for marketplace KYC by design — the
    # full eKYC record (address/photo/XML) is held by the regulated NBFC partner, keyed
    # by reference_id; storing it here would widen VS Mart's DPDP/Aadhaar liability.
    verified_address = models.TextField(blank=True)
    id_masked = models.CharField(max_length=40, blank=True)
    id_hash = models.CharField(max_length=64, blank=True, db_index=True)
    name_match = models.BooleanField(null=True, blank=True)
    reference_id = models.CharField(max_length=120, blank=True)  # provider trace / request id
    redirect_url = models.TextField(blank=True)                  # DigiLocker consent url (pending)
    error_code = models.CharField(max_length=40, blank=True)
    raw = models.JSONField(default=dict, blank=True)             # redacted provider breadcrumbs
    # DPDP 2023 + Aadhaar consent: captured before the call, auditable afterward.
    consent = models.BooleanField(default=False)
    consent_at = models.DateTimeField(null=True, blank=True)
    consent_purpose = models.CharField(max_length=120, blank=True)
    verified_at = models.DateTimeField(null=True, blank=True)    # when status became verified

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["application", "kind", "status"])]

    def __str__(self):
        return f"{self.kind}:{self.status} ({self.id_masked})"
