from decimal import Decimal

from django.conf import settings
from django.db import models

from core.models import TimeStampedModel

ZERO = Decimal("0.00")


class LendingPartner(TimeStampedModel):
    """RBI-registered NBFC / lending partner (LSP model). Pure reference data so the
    app can surface a lender disclosure when one is configured. No lending logic,
    disbursement, or interest accrual lives here — see vsmart-credit-rbi-constraint."""

    name = models.CharField(max_length=120)
    nbfc_registration_no = models.CharField(max_length=64, blank=True)
    is_active = models.BooleanField(default=True)

    def __str__(self):
        return self.name


class CreditAccount(TimeStampedModel):
    class BillingCycle(models.TextChoices):
        WEEKLY = "weekly"
        MONTHLY = "monthly"

    class Status(models.TextChoices):
        ACTIVE = "active"
        FROZEN = "frozen"
        CLOSED = "closed"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="credit_account"
    )
    credit_limit = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    outstanding = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    vs_score = models.PositiveIntegerField(default=650)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.ACTIVE)
    # Billing cadence for this account's statements. Defaults to monthly (the app's
    # previous hardcoded value) but is now the real source of truth.
    billing_cycle = models.CharField(
        max_length=8, choices=BillingCycle.choices, default=BillingCycle.MONTHLY
    )
    # ── LSP scaffolding (nullable; null until a partner is configured) ──
    # Pure data so the UI can show a lender disclosure. No lending behavior here.
    lender = models.ForeignKey(
        LendingPartner, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="accounts",
    )
    loan_account_number = models.CharField(max_length=64, null=True, blank=True)
    interest_rate = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True
    )
    sanctioned_limit = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )

    @property
    def available(self):
        return max(self.credit_limit - self.outstanding, ZERO)

    def __str__(self):
        return f"Credit({self.user_id}) {self.outstanding}/{self.credit_limit}"


class CreditApplication(TimeStampedModel):
    """A customer's request for a VS Credit line, and the underwriting decision.

    This is deliberately **separate from KYC**. KYC answers "is this person who
    they say they are"; this answers "how much credit, if any, do we extend". They
    used to be fused — approving KYC flipped ``user.credit_enabled`` on and opened
    an account with a ₹0 limit, so a customer became "credit active" with nothing
    to spend. An explicit ``approved_limit`` on this record is now the only thing
    that grants a usable line.

    Note the RBI constraint (see vsmart-credit-rbi-constraint): VS Mart cannot lend
    on its own books. This record is the *decision and its audit trail*; when a
    lending partner is configured, the sanction it produces is mirrored onto
    ``CreditAccount.lender`` / ``sanctioned_limit``.
    """

    class Status(models.TextChoices):
        DRAFT = "draft"                # saved but not submitted
        SUBMITTED = "submitted"        # awaiting pickup
        UNDER_REVIEW = "under_review"  # a reviewer has claimed it
        APPROVED = "approved"
        REJECTED = "rejected"
        WITHDRAWN = "withdrawn"        # customer cancelled

    class HouseType(models.TextChoices):
        INDEPENDENT = "independent"
        APARTMENT = "apartment"
        SHARED = "shared"

    class Ownership(models.TextChoices):
        OWNED = "owned"
        RENTED = "rented"
        FAMILY = "family"

    #: States a customer may still edit / resubmit from.
    OPEN_STATES = (Status.DRAFT, Status.REJECTED, Status.WITHDRAWN)
    #: States that mean "a decision is pending" — blocks a second application.
    IN_FLIGHT_STATES = (Status.SUBMITTED, Status.UNDER_REVIEW)

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="credit_applications",
    )
    status = models.CharField(
        max_length=14, choices=Status.choices, default=Status.DRAFT, db_index=True
    )

    # ── What the customer told us (the fields the app collects) ──
    occupation = models.CharField(max_length=120, blank=True)
    monthly_income = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    family_members = models.PositiveSmallIntegerField(null=True, blank=True)
    house_type = models.CharField(
        max_length=12, choices=HouseType.choices, blank=True
    )
    ownership = models.CharField(
        max_length=8, choices=Ownership.choices, blank=True
    )
    requested_limit = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )

    # ── Underwriting context captured at submission (point-in-time snapshot) ──
    # Stored on the application so a later decision can be explained even if the
    # customer's live score or KYC state has since changed.
    bureau_score_at_submit = models.PositiveIntegerField(null=True, blank=True)
    kyc_status_at_submit = models.CharField(max_length=20, blank=True)

    # ── Decision ──
    approved_limit = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True,
        help_text="The sanctioned limit. Only set on approval; this is what "
                  "actually grants the customer a usable credit line.",
    )
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="credit_applications_decided",
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    decision_note = models.CharField(
        max_length=300, blank=True,
        help_text="Internal reviewer note. Never shown to the customer.",
    )
    rejection_reason = models.CharField(
        max_length=300, blank=True,
        help_text="Customer-facing reason. Shown verbatim in the app.",
    )
    submitted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-id"]
        indexes = [
            # The admin queue reads "oldest in-flight first" constantly.
            models.Index(fields=["status", "submitted_at"]),
        ]

    def __str__(self):
        return f"CreditApplication({self.user_id}) {self.status}"

    @property
    def is_in_flight(self):
        return self.status in self.IN_FLIGHT_STATES

    @property
    def is_editable(self):
        return self.status in self.OPEN_STATES


class CreditLedgerEntry(models.Model):
    """Append-only. Never UPDATE/DELETE — corrections are new `adjustment` rows."""

    class Type(models.TextChoices):
        PURCHASE = "purchase"      # + outstanding
        REPAYMENT = "repayment"    # - outstanding
        FEE = "fee"                # + outstanding
        ADJUSTMENT = "adjustment"  # signed
        REFUND = "refund"          # - outstanding

    account = models.ForeignKey(
        CreditAccount, on_delete=models.PROTECT, related_name="entries"
    )
    type = models.CharField(max_length=12, choices=Type.choices)
    amount = models.DecimalField(max_digits=12, decimal_places=2)  # signed
    balance_after = models.DecimalField(max_digits=12, decimal_places=2)
    order = models.ForeignKey(
        "orders.Order", on_delete=models.SET_NULL, null=True, blank=True
    )
    payment = models.ForeignKey(
        "payments.Payment", on_delete=models.SET_NULL, null=True, blank=True
    )
    statement = models.ForeignKey(
        "credit.Statement", on_delete=models.SET_NULL, null=True, blank=True
    )
    note = models.CharField(max_length=200, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["account", "created_at"])]

    def save(self, *args, **kwargs):
        # Append-only: rows are immutable; corrections are new `adjustment` rows.
        if not self._state.adding:
            raise ValueError("CreditLedgerEntry is append-only and cannot be modified.")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("CreditLedgerEntry is append-only and cannot be deleted.")


class Statement(TimeStampedModel):
    class Period(models.TextChoices):
        WEEKLY = "weekly"
        MONTHLY = "monthly"

    class Status(models.TextChoices):
        OPEN = "open"
        PAID = "paid"
        PARTIALLY_PAID = "partially_paid"
        OVERDUE = "overdue"

    account = models.ForeignKey(
        CreditAccount, on_delete=models.CASCADE, related_name="statements"
    )
    period = models.CharField(max_length=8, choices=Period.choices, default=Period.MONTHLY)
    period_start = models.DateField()
    period_end = models.DateField()
    opening_balance = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    purchases = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    payments = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    fees = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    closing_balance = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    due_date = models.DateField()
    status = models.CharField(max_length=14, choices=Status.choices, default=Status.OPEN)


class CreditBureauReport(TimeStampedModel):
    """One CIBIL / credit-bureau pull for a customer. Append-only history — a
    refresh writes a NEW row rather than mutating the old one, so the full audit
    trail of every score check (who, when, consent) is preserved. The latest row
    is the current score. RBI-safe: informational only, never auto-sets credit."""

    class Status(models.TextChoices):
        SUCCESS = "success"      # a real score came back
        NO_RECORD = "no_record"  # provider answered but had no report

    class Source(models.TextChoices):
        CUSTOMER = "customer"    # self-service pull from the app
        ADMIN = "admin"          # refreshed from the super-admin console
        STORE = "store"          # refreshed from the store panel

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="bureau_reports",
    )
    status = models.CharField(max_length=10, choices=Status.choices)
    score = models.PositiveIntegerField(default=0)      # 0 when NO_RECORD
    band = models.CharField(max_length=20, blank=True)  # Excellent / Good / …
    name_on_bureau = models.CharField(max_length=120, blank=True)
    pan = models.CharField(max_length=10, blank=True)   # full PAN as returned by the bureau
    mobile = models.CharField(max_length=15, blank=True)
    dob = models.CharField(max_length=20, blank=True)
    gender = models.CharField(max_length=10, blank=True)
    provider = models.CharField(max_length=20, blank=True)     # payon / mock
    reference_id = models.CharField(max_length=64, blank=True)  # provider txn id
    consent = models.BooleanField(default=False)                # DPDP consent captured
    source = models.CharField(max_length=10, choices=Source.choices,
                              default=Source.CUSTOMER)
    requested_by = models.ForeignKey(  # who triggered it (customer=self, or staff on refresh)
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+",
    )

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "-created_at"])]

    def __str__(self):
        return f"Bureau({self.user_id}) {self.score} {self.status}"


class FamilyGroup(TimeStampedModel):
    primary_user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="family_group"
    )
    shared_limit = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)


class FamilyMember(TimeStampedModel):
    class Status(models.TextChoices):
        ACTIVE = "active"
        PENDING = "pending"
        REMOVED = "removed"

    group = models.ForeignKey(
        FamilyGroup, on_delete=models.CASCADE, related_name="members"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True
    )
    phone = models.CharField(max_length=15)
    relationship = models.CharField(max_length=40, blank=True)
    status = models.CharField(max_length=8, choices=Status.choices, default=Status.PENDING)
    shared_usage = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
