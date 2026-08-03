from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin
from django.db import models

from core.models import TimeStampedModel

from .managers import UserManager


class Role(models.TextChoices):
    SUPERADMIN = "superadmin", "Super Admin"
    ADMIN = "admin", "Admin"
    STORE_STAFF = "store_staff", "Store Staff"
    AGENT = "agent", "Agent"
    CUSTOMER = "customer", "Customer"


class KycStatus(models.TextChoices):
    NOT_STARTED = "not_started", "Not started"
    PENDING = "pending", "Pending"
    VERIFIED = "verified", "Verified"
    REJECTED = "rejected", "Rejected"


class Gender(models.TextChoices):
    MALE = "male", "Male"
    FEMALE = "female", "Female"
    OTHER = "other", "Other"


class User(AbstractBaseUser, PermissionsMixin):
    """Single user table; `role` drives RBAC. Customers authenticate by phone OTP
    (no usable password); staff can have passwords for the Django admin."""

    phone = models.CharField(max_length=15, unique=True)
    email = models.EmailField(blank=True, null=True)
    name = models.CharField(max_length=120, blank=True)
    role = models.CharField(max_length=12, choices=Role.choices, default=Role.CUSTOMER)
    avatar_url = models.URLField(blank=True, null=True)
    gender = models.CharField(
        max_length=6, choices=Gender.choices, blank=True
    )
    date_of_birth = models.DateField(null=True, blank=True)

    kyc_status = models.CharField(
        max_length=12, choices=KycStatus.choices, default=KycStatus.NOT_STARTED
    )
    credit_enabled = models.BooleanField(default=False)

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    objects = UserManager()

    USERNAME_FIELD = "phone"
    REQUIRED_FIELDS = []

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.name or 'User'} ({self.phone})"

    @property
    def has_profile(self):
        return bool(self.name.strip())

    @property
    def is_kyc_verified(self):
        return self.kyc_status == KycStatus.VERIFIED

    def save(self, *args, **kwargs):
        # Keep Django staff/superuser flags in sync with role.
        if self.role == Role.SUPERADMIN:
            self.is_staff = self.is_superuser = True
        elif self.role == Role.ADMIN:
            self.is_staff = True
        super().save(*args, **kwargs)


class AgentProfile(TimeStampedModel):
    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="agent_profile"
    )
    code = models.CharField(max_length=20, unique=True)
    assigned_pincodes = models.JSONField(default=list, blank=True)
    is_available = models.BooleanField(default=True)

    # The store that HIRES and manages this agent. Agents are store-owned: a store
    # onboards its own riders and only ever sees its own roster, while the
    # super-admin oversees duty/performance and routes them to zones.
    # NULL = a legacy/unassigned agent (visible to admin, to no store) — kept
    # nullable so existing rows survive and an agent can outlive a store.
    store = models.ForeignKey(
        "stores.Store",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="agents",
    )

    # Capacity / vehicle — bounds the batching engine per agent.
    class Vehicle(models.TextChoices):
        BIKE = "bike", "Bike"
        SCOOTER = "scooter", "Scooter"
        CYCLE = "cycle", "Cycle"
        VAN = "van", "Van"
        FOOT = "foot", "On foot"

    vehicle_type = models.CharField(
        max_length=10, choices=Vehicle.choices, default=Vehicle.BIKE
    )
    bag_capacity = models.PositiveSmallIntegerField(default=5)      # max orders per trip
    weight_capacity_kg = models.PositiveSmallIntegerField(default=20)
    cash_capacity = models.DecimalField(max_digits=10, decimal_places=2, default=10000)
    max_stops = models.PositiveSmallIntegerField(default=8)         # deliveries + collections
    rating = models.DecimalField(max_digits=3, decimal_places=2, default=5)  # 0..5

    # How the store pays this agent. MONTHLY (the default — most VS Mart riders
    # are salaried) hides earnings figures in the app since their pay isn't
    # driven by what's shown there. GIG is paid per task and sees per-task/
    # lifetime earnings.
    class EmploymentType(models.TextChoices):
        GIG = "gig", "Freelance / Gig (per task)"
        MONTHLY = "monthly", "Monthly Employee (salaried)"

    employment_type = models.CharField(
        max_length=10, choices=EmploymentType.choices, default=EmploymentType.MONTHLY
    )

    def __str__(self):
        return f"Agent {self.code}"


class DeviceToken(TimeStampedModel):
    class Platform(models.TextChoices):
        ANDROID = "android"
        IOS = "ios"
        WEB = "web"  # browser push (store-admin panel), via FCM Web Push

    user = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name="device_tokens"
    )
    token = models.CharField(max_length=255)
    platform = models.CharField(max_length=10, choices=Platform.choices)
    is_active = models.BooleanField(default=True)

    class Meta:
        unique_together = ("user", "token")


class AccountDeletionRequest(TimeStampedModel):
    """A user's request to delete their account + data (Play Store compliance).
    Submitted from the public web form; reviewed/processed by an admin."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        IN_REVIEW = "in_review", "In review"
        COMPLETED = "completed", "Completed"
        REJECTED = "rejected", "Rejected"

    user = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="deletion_requests")
    name = models.CharField(max_length=120, blank=True)
    contact = models.CharField(max_length=120)  # email or phone supplied by the requester
    reason = models.TextField(blank=True)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDING)
    note = models.TextField(blank=True)  # internal admin note
    processed_at = models.DateTimeField(null=True, blank=True)
    processed_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="processed_deletions")

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"DeletionRequest({self.contact}, {self.status})"


class AuditLog(models.Model):
    """Append-only record of staff (agent/admin) writes that affect customers."""

    actor = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, related_name="audit_actions"
    )
    action = models.CharField(max_length=80)
    target_type = models.CharField(max_length=40, blank=True)
    target_id = models.CharField(max_length=40, blank=True)
    before = models.JSONField(null=True, blank=True)
    after = models.JSONField(null=True, blank=True)
    ip = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.action} by {self.actor_id} @ {self.created_at:%Y-%m-%d %H:%M}"
