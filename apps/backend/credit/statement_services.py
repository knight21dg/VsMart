"""Credit billing-cycle close — the producer the Statement model never had.

Everything that CONSUMES statements existed (the app's statements screen, the
statement PDF, statement-scoped repayment, dunning buckets) — but nothing ever
CREATED one, so the entire credit billing cycle was dead: no dues dates, nothing
to repay against, nothing to fall overdue. This closes complete cycles per
account (respecting each account's weekly/monthly `billing_cycle`) and flips
past-due statements to OVERDUE. Idempotent — safe to run on every cron tick.
"""
from datetime import date, timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from .models import CreditAccount, CreditLedgerEntry, Statement

ZERO = Decimal("0.00")

#: Days after period end before the money is due.
GRACE_DAYS = {"weekly": 5, "monthly": 10}

#: Backfill guard: never create more than this many windows per account per run.
#: A seeded/ancient account should not spray years of empty paperwork.
MAX_WINDOWS_PER_RUN = 24


def _window_after(cycle: str, day: date) -> tuple[date, date]:
    """The billing window CONTAINING `day` → (start, end) inclusive."""
    if cycle == CreditAccount.BillingCycle.WEEKLY:
        start = day - timedelta(days=day.weekday())  # Monday
        return start, start + timedelta(days=6)
    start = day.replace(day=1)
    next_month = (start + timedelta(days=32)).replace(day=1)
    return start, next_month - timedelta(days=1)


def _sums(account, start: date, end: date) -> dict:
    """Per-type totals of the ledger inside the window (kept explicit per type
    for auditability)."""
    from django.db.models import Q

    entries = CreditLedgerEntry.objects.filter(
        account=account, created_at__date__gte=start, created_at__date__lte=end
    )
    agg = entries.aggregate(
        purchases=Sum("amount", filter=Q(type=CreditLedgerEntry.Type.PURCHASE)),
        repayments=Sum("amount", filter=Q(type=CreditLedgerEntry.Type.REPAYMENT)),
        fees=Sum("amount", filter=Q(type=CreditLedgerEntry.Type.FEE)),
        adjustments=Sum("amount", filter=Q(type=CreditLedgerEntry.Type.ADJUSTMENT)),
        refunds=Sum("amount", filter=Q(type=CreditLedgerEntry.Type.REFUND)),
    )
    return {k: (v or ZERO) for k, v in agg.items()}


@transaction.atomic
def close_cycles_for_account(account, *, today: date | None = None) -> list[Statement]:
    """Create every COMPLETE, not-yet-billed statement window for `account`."""
    today = today or timezone.localdate()
    last = account.statements.order_by("-period_end").first()
    if last is not None:
        cursor = last.period_end + timedelta(days=1)
        opening = last.closing_balance
    else:
        first_entry = account.entries.order_by("created_at").first()
        if first_entry is None:
            return []  # no activity ever — nothing to bill
        cursor = first_entry.created_at.date()
        opening = ZERO

    cycle = account.billing_cycle
    created: list[Statement] = []
    while len(created) < MAX_WINDOWS_PER_RUN:
        start, end = _window_after(cycle, cursor)
        if end >= today:
            break  # window not complete yet
        sums = _sums(account, start, end)
        purchases = sums["purchases"]
        # Repayments/refunds are stored negative; a statement reports magnitudes.
        payments = -(sums["repayments"] + sums["refunds"])
        fees = sums["fees"]
        closing = opening + purchases + fees + sums["adjustments"] - payments
        if closing < ZERO:
            closing = ZERO
        has_activity = any(
            v != ZERO for k, v in sums.items()
        )
        # Skip windows where nothing happened AND nothing was owed — a years-idle
        # account must not accumulate empty paperwork.
        if has_activity or opening > ZERO:
            statement = Statement.objects.create(
                account=account,
                period=cycle,
                period_start=start,
                period_end=end,
                opening_balance=opening,
                purchases=purchases,
                payments=payments,
                fees=fees,
                closing_balance=closing,
                due_date=end + timedelta(days=GRACE_DAYS.get(cycle, 10)),
                status=(Statement.Status.PAID if closing <= ZERO
                        else Statement.Status.OPEN),
            )
            created.append(statement)
        opening = closing
        cursor = end + timedelta(days=1)
    return created


def mark_overdue(*, today: date | None = None) -> int:
    """Flip past-due open statements to OVERDUE (drives dunning + credit gates)."""
    today = today or timezone.localdate()
    return Statement.objects.filter(
        status__in=[Statement.Status.OPEN, Statement.Status.PARTIALLY_PAID],
        due_date__lt=today,
        closing_balance__gt=ZERO,
    ).update(status=Statement.Status.OVERDUE)


def close_billing_cycles(*, today: date | None = None) -> dict:
    """Cron entry: close complete cycles for every account, then age the book."""
    today = today or timezone.localdate()
    created = 0
    accounts = CreditAccount.objects.filter(entries__isnull=False).distinct()
    for account in accounts:
        created += len(close_cycles_for_account(account, today=today))
    overdue = mark_overdue(today=today)
    return {"statements": created, "marked_overdue": overdue}
