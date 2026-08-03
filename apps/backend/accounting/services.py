"""General-ledger operations: posting, reversal, and the statutory reports.

Everything that writes to the ledger goes through ``post_entry``. It is the only
place that can move an entry to POSTED, and it refuses anything unbalanced — so
"debits equal credits" is an invariant of the data, not a convention people are
trusted to follow.
"""
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from accounts.services import record_audit
from core.app_errors import AppError

from .models import Account, JournalEntry, JournalLine

ZERO = Decimal("0.00")


def _dec(v):
    return Decimal(str(v or 0)).quantize(Decimal("0.01"))


@transaction.atomic
def post_entry(*, entry_date, narration, lines, reference="", store=None,
               source_module="manual", source_ref="", actor=None):
    """Create and post a balanced journal entry.

    ``lines`` is a list of dicts: ``{"account": <Account|code>, "debit": x}`` or
    ``{"account": ..., "credit": x}``.

    Raises ``AppError`` if the entry doesn't balance, has fewer than two lines,
    or duplicates an existing source posting.
    """
    if not lines or len(lines) < 2:
        raise AppError(
            "GL_UNBALANCED",
            message="A journal entry needs at least two lines.",
        )

    if source_ref:
        existing = JournalEntry.objects.filter(
            source_module=source_module, source_ref=str(source_ref)
        ).first()
        if existing:
            # Idempotent by design: a retried webhook or a re-run job returns
            # the entry that already exists instead of booking the money twice.
            return existing

    prepared = []
    total_debit = total_credit = ZERO
    for raw in lines:
        account = raw["account"]
        if not isinstance(account, Account):
            account = Account.objects.filter(code=str(account)).first()
            if account is None:
                raise AppError(
                    "GL_ACCOUNT_UNKNOWN",
                    message=f"No such ledger account: {raw['account']}.",
                )
        if not account.is_active:
            raise AppError(
                "GL_ACCOUNT_UNKNOWN",
                message=f"Account {account.code} is archived and can't be posted to.",
            )
        debit, credit = _dec(raw.get("debit")), _dec(raw.get("credit"))
        if (debit > ZERO) == (credit > ZERO):
            raise AppError(
                "GL_UNBALANCED",
                message="Each line must be either a debit or a credit, not both.",
            )
        total_debit += debit
        total_credit += credit
        prepared.append((account, debit, credit, raw.get("narration", "")))

    if total_debit != total_credit:
        raise AppError(
            "GL_UNBALANCED",
            message=(
                f"Debits ({total_debit}) and credits ({total_credit}) must match. "
                f"Out by {abs(total_debit - total_credit)}."
            ),
        )
    if total_debit == ZERO:
        raise AppError("GL_UNBALANCED",
                       message="A journal entry can't be for zero.")

    entry = JournalEntry.objects.create(
        entry_date=entry_date,
        narration=narration[:300],
        reference=(reference or "")[:80],
        status=JournalEntry.Status.POSTED,
        source_module=source_module,
        source_ref=str(source_ref or ""),
        store=store,
        posted_at=timezone.now(),
        created_by=actor,
    )
    JournalLine.objects.bulk_create([
        JournalLine(entry=entry, account=a, debit=d, credit=c, narration=n[:200])
        for a, d, c, n in prepared
    ])
    record_audit(actor, "gl.post", target=entry,
                 after={"amount": str(total_debit), "source": source_module})
    return entry


@transaction.atomic
def reverse_entry(entry, actor=None, *, entry_date=None, reason=""):
    """Reverse a posted entry with a mirror-image entry.

    Posted entries are never edited or deleted — that's what makes the ledger
    trustworthy — so a correction is always a new, opposite entry that leaves
    both the mistake and the fix on the record.
    """
    if entry.status != JournalEntry.Status.POSTED:
        raise AppError("GL_INVALID_TRANSITION",
                       message="Only a posted entry can be reversed.")
    if hasattr(entry, "reversed_by") and entry.reversed_by is not None:
        raise AppError("GL_ALREADY_REVERSED",
                       message="This entry has already been reversed.")

    reversal = JournalEntry.objects.create(
        entry_date=entry_date or timezone.localdate(),
        narration=(reason or f"Reversal of JE{entry.id}: {entry.narration}")[:300],
        reference=entry.reference,
        status=JournalEntry.Status.POSTED,
        source_module=entry.source_module,
        source_ref="",              # keep the source slot free for the original
        store=entry.store,
        posted_at=timezone.now(),
        created_by=actor,
        reverses=entry,
    )
    JournalLine.objects.bulk_create([
        JournalLine(entry=reversal, account=line.account,
                    debit=line.credit, credit=line.debit,
                    narration=line.narration)
        for line in entry.lines.all()
    ])
    entry.status = JournalEntry.Status.REVERSED
    entry.save(update_fields=["status", "updated_at"])
    record_audit(actor, "gl.reverse", target=entry,
                 after={"reversal": reversal.id, "reason": reason})
    return reversal


def _posted_lines(date_from=None, date_to=None, store=None):
    """Lines that count: POSTED only.

    REVERSED originals are excluded, but their reversal entries are themselves
    POSTED — so the two cancel out and the ledger stays self-consistent.
    """
    qs = JournalLine.objects.filter(entry__status=JournalEntry.Status.POSTED)
    if date_from:
        qs = qs.filter(entry__entry_date__gte=date_from)
    if date_to:
        qs = qs.filter(entry__entry_date__lte=date_to)
    if store is not None:
        qs = qs.filter(entry__store=store)
    return qs


def trial_balance(as_of=None, store=None):
    """Every account's debit/credit totals. Debits must equal credits overall —
    if they don't, something bypassed ``post_entry``."""
    rows = (
        _posted_lines(date_to=as_of, store=store)
        .values("account__id", "account__code", "account__name", "account__type")
        .annotate(debit=Sum("debit"), credit=Sum("credit"))
        .order_by("account__code")
    )
    out = []
    total_debit = total_credit = ZERO
    for r in rows:
        debit, credit = r["debit"] or ZERO, r["credit"] or ZERO
        total_debit += debit
        total_credit += credit
        net = debit - credit
        out.append({
            "accountId": str(r["account__id"]),
            "code": r["account__code"],
            "name": r["account__name"],
            "type": r["account__type"],
            # Presented on whichever side the account actually sits.
            "debit": net if net > ZERO else ZERO,
            "credit": -net if net < ZERO else ZERO,
        })
    return {
        "asOf": as_of or timezone.localdate(),
        "rows": out,
        "totalDebit": total_debit,
        "totalCredit": total_credit,
        "balanced": total_debit == total_credit,
    }


def _totals_by_type(types, date_from=None, date_to=None, store=None):
    rows = (
        _posted_lines(date_from, date_to, store)
        .filter(account__type__in=types)
        .values("account__id", "account__code", "account__name", "account__type")
        .annotate(debit=Sum("debit"), credit=Sum("credit"))
        .order_by("account__code")
    )
    out, total = [], ZERO
    for r in rows:
        debit, credit = r["debit"] or ZERO, r["credit"] or ZERO
        # Income/liability/equity grow on the credit side; asset/expense on debit.
        amount = (credit - debit) if r["account__type"] in (
            Account.Type.INCOME, Account.Type.LIABILITY, Account.Type.EQUITY
        ) else (debit - credit)
        if amount == ZERO:
            continue
        total += amount
        out.append({
            "code": r["account__code"], "name": r["account__name"],
            "type": r["account__type"], "amount": amount,
        })
    return out, total


def profit_and_loss(date_from=None, date_to=None, store=None):
    """Income less expenses for a period, from the ledger — not an aggregate
    guessed from orders."""
    income, total_income = _totals_by_type(
        [Account.Type.INCOME], date_from, date_to, store)
    expense, total_expense = _totals_by_type(
        [Account.Type.EXPENSE], date_from, date_to, store)
    return {
        "from": date_from,
        "to": date_to,
        "income": income,
        "totalIncome": total_income,
        "expenses": expense,
        "totalExpenses": total_expense,
        "netProfit": total_income - total_expense,
    }


def balance_sheet(as_of=None, store=None):
    """Assets against liabilities + equity + retained earnings.

    Retained earnings is derived from cumulative P&L rather than stored, so the
    sheet balances without anyone having to remember a year-end closing step.
    """
    as_of = as_of or timezone.localdate()
    assets, total_assets = _totals_by_type([Account.Type.ASSET], None, as_of, store)
    liabilities, total_liabilities = _totals_by_type(
        [Account.Type.LIABILITY], None, as_of, store)
    equity, total_equity = _totals_by_type([Account.Type.EQUITY], None, as_of, store)

    pnl = profit_and_loss(None, as_of, store)
    retained = pnl["netProfit"]
    total_equity_with_earnings = total_equity + retained

    return {
        "asOf": as_of,
        "assets": assets,
        "totalAssets": total_assets,
        "liabilities": liabilities,
        "totalLiabilities": total_liabilities,
        "equity": equity,
        "retainedEarnings": retained,
        "totalEquity": total_equity_with_earnings,
        "balanced": total_assets == total_liabilities + total_equity_with_earnings,
    }


def account_ledger(account, date_from=None, date_to=None, store=None):
    """Running statement for one account — the drill-down behind every figure."""
    lines = (
        _posted_lines(date_from, date_to, store)
        .filter(account=account)
        .select_related("entry")
        .order_by("entry__entry_date", "entry_id", "id")
    )
    opening = ZERO
    if date_from:
        prior = (
            _posted_lines(None, None, store)
            .filter(account=account, entry__entry_date__lt=date_from)
            .aggregate(d=Sum("debit"), c=Sum("credit"))
        )
        opening = account.signed(prior["d"] or ZERO, prior["c"] or ZERO)

    running = opening
    rows = []
    for line in lines:
        running += account.signed(line.debit, line.credit)
        rows.append({
            "entryId": str(line.entry_id),
            "date": line.entry.entry_date,
            "narration": line.narration or line.entry.narration,
            "reference": line.entry.reference,
            "debit": line.debit,
            "credit": line.credit,
            "balance": running,
        })
    return {
        "account": {"code": account.code, "name": account.name,
                    "type": account.type},
        "opening": opening,
        "rows": rows,
        "closing": running,
    }
