"""Double-entry general ledger.

Before this, VS Mart's P&L was an aggregate computed on the fly from orders and
payments — directionally useful but unauditable and not filing-safe: there was no
chart of accounts, no journal, no trial balance, and no way to prove that what
the reports said matched what actually moved.

The rules this enforces:

* **Every entry balances.** Total debits == total credits, checked at post time
  (``services.post_entry``). An unbalanced entry cannot be posted.
* **Posted entries are immutable.** A mistake is corrected with a *reversing*
  entry, never an edit or a delete — same discipline as the credit and inventory
  ledgers.
* **Source postings are idempotent.** ``(source_module, source_ref)`` is unique,
  so a retried webhook or a re-run job can't book the same money twice.
"""
from decimal import Decimal

from django.conf import settings
from django.db import models

from core.models import TimeStampedModel

ZERO = Decimal("0.00")


class Account(TimeStampedModel):
    """A line in the chart of accounts.

    ``type`` decides which side increases the balance, which is what makes the
    reports work without every caller having to remember sign conventions.
    """

    class Type(models.TextChoices):
        ASSET = "asset"
        LIABILITY = "liability"
        EQUITY = "equity"
        INCOME = "income"
        EXPENSE = "expense"

    #: Types whose balance grows on the debit side.
    DEBIT_NORMAL = (Type.ASSET, Type.EXPENSE)

    code = models.CharField(max_length=20, unique=True)
    name = models.CharField(max_length=120)
    type = models.CharField(max_length=10, choices=Type.choices, db_index=True)
    parent = models.ForeignKey(
        "self", on_delete=models.PROTECT, null=True, blank=True,
        related_name="children",
    )
    description = models.CharField(max_length=300, blank=True)
    # A control account is posted to by the system (e.g. Accounts Receivable);
    # staff shouldn't hand-post to it or the subsidiary ledger stops agreeing.
    is_control = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["code"]

    @property
    def is_debit_normal(self):
        return self.type in self.DEBIT_NORMAL

    def signed(self, debit, credit):
        """Movement in this account's own normal direction."""
        return (debit - credit) if self.is_debit_normal else (credit - debit)

    def __str__(self):
        return f"{self.code} {self.name}"


class JournalEntry(TimeStampedModel):
    """One balanced transaction: a date, a narration, and two or more lines."""

    class Status(models.TextChoices):
        DRAFT = "draft"        # editable
        POSTED = "posted"      # immutable, counts in the ledger
        REVERSED = "reversed"  # superseded by a reversing entry

    entry_date = models.DateField(db_index=True)
    narration = models.CharField(max_length=300)
    reference = models.CharField(max_length=80, blank=True)
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.DRAFT, db_index=True
    )

    # Where this came from — "payment", "vendor_payment", "manual", … plus the
    # originating row's id. Unique together so a replay can't double-post.
    source_module = models.CharField(max_length=40, blank=True, db_index=True)
    source_ref = models.CharField(max_length=80, blank=True)

    store = models.ForeignKey(
        "stores.Store", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="journal_entries",
    )
    posted_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="journal_entries",
    )
    # The entry this one reverses (and, via the reverse accessor, its reversal).
    reverses = models.OneToOneField(
        "self", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="reversed_by",
    )

    class Meta:
        ordering = ["-entry_date", "-id"]
        constraints = [
            models.UniqueConstraint(
                fields=["source_module", "source_ref"],
                condition=~models.Q(source_ref=""),
                name="uniq_journal_source",
            ),
        ]
        indexes = [models.Index(fields=["status", "entry_date"])]

    @property
    def total_debit(self):
        return sum((line.debit for line in self.lines.all()), ZERO)

    @property
    def total_credit(self):
        return sum((line.credit for line in self.lines.all()), ZERO)

    @property
    def is_balanced(self):
        return self.total_debit == self.total_credit

    def __str__(self):
        return f"JE{self.id} {self.entry_date} {self.narration[:40]}"


class JournalLine(models.Model):
    """One side of a journal entry. Exactly one of debit/credit is non-zero."""

    entry = models.ForeignKey(
        JournalEntry, on_delete=models.CASCADE, related_name="lines"
    )
    account = models.ForeignKey(
        Account, on_delete=models.PROTECT, related_name="lines"
    )
    debit = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    credit = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    narration = models.CharField(max_length=200, blank=True)

    class Meta:
        constraints = [
            # A line that is both, or neither, is meaningless and would quietly
            # corrupt every report downstream.
            models.CheckConstraint(
                check=(
                    models.Q(debit__gt=0, credit=0)
                    | models.Q(credit__gt=0, debit=0)
                ),
                name="journalline_one_side_only",
            ),
        ]

    def __str__(self):
        side = f"Dr {self.debit}" if self.debit else f"Cr {self.credit}"
        return f"{self.account_id} {side}"
