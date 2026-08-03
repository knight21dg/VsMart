"""Credit money operations. Every balance change goes through here and writes an
append-only ledger entry inside a DB transaction. `outstanding` is the running
cache; `reconcile()` rebuilds it from the ledger as the integrity check."""
import re
from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from core.app_errors import AppError

from . import bureau
from .models import CreditAccount, CreditBureauReport, CreditLedgerEntry

ZERO = Decimal("0.00")

# Self-service pulls are throttled: a fresh SUCCESS result within this window is
# reused instead of hitting the (chargeable) provider again. Staff refresh forces.
BUREAU_REFRESH_MINUTES = 10


def ensure_account(user, default_limit=None) -> CreditAccount:
    if default_limit is None:
        from siteconfig.models import PlatformConfig

        default_limit = PlatformConfig.load().credit_default_limit
    account, _ = CreditAccount.objects.get_or_create(
        user=user, defaults={"credit_limit": default_limit}
    )
    return account


class CreditError(Exception):
    pass


@transaction.atomic
def _post(account: CreditAccount, entry_type: str, amount: Decimal, *,
          enforce_limit=False, **refs) -> CreditLedgerEntry:
    """Append a ledger entry and update the cached outstanding. `amount` is signed
    by caller intent; we normalise per type.

    The account row is locked (`select_for_update`) BEFORE computing the new balance,
    so `enforce_limit` (purchases) re-checks the credit limit against the freshly-read
    outstanding — two concurrent purchases serialise here and the second sees the
    first's charge, so outstanding can never exceed the limit (available never < 0)."""
    account = CreditAccount.objects.select_for_update().get(pk=account.pk)
    amount = Decimal(amount)
    new_outstanding = account.outstanding + amount
    if enforce_limit and new_outstanding > account.credit_limit:
        raise CreditError("Amount exceeds available credit.")
    if new_outstanding < ZERO:
        new_outstanding = ZERO  # never go negative; overpayment is a credit balance elsewhere
    entry = CreditLedgerEntry.objects.create(
        account=account,
        type=entry_type,
        amount=amount,
        balance_after=new_outstanding,
        order=refs.get("order"),
        payment=refs.get("payment"),
        statement=refs.get("statement"),
        note=refs.get("note", ""),
        created_by=refs.get("created_by"),
    )
    account.outstanding = new_outstanding
    account.save(update_fields=["outstanding", "updated_at"])
    return entry


def assert_credit_eligible(account) -> None:
    """Gate every credit charge: account active + the customer KYC-verified and
    credit-enabled. BNPL cannot be extended to an unverified customer."""
    if account.status != CreditAccount.Status.ACTIVE:
        raise CreditError("Your credit account is not active.")
    user = account.user
    # Two DIFFERENT refusals that were collapsed into one KYC message — a
    # verified customer whose credit simply wasn't enabled was told to redo
    # KYC, which they'd already passed ("unable to use it even approved").
    if user.kyc_status != "verified":
        raise CreditError("Credit requires a completed KYC verification.")
    if not getattr(user, "credit_enabled", False):
        raise CreditError(
            "VS Credit isn't enabled on your account yet — apply for credit "
            "or ask support to activate your approved limit.")


def debit_purchase(account, amount, *, order=None, note="") -> CreditLedgerEntry:
    """Charge a purchase to credit. Raises if ineligible or over the available limit.
    The limit is enforced authoritatively inside `_post` under the account row lock
    (the early check here is just a fast, pre-lock rejection)."""
    amount = Decimal(amount)
    assert_credit_eligible(account)
    if amount > account.available:
        raise CreditError("Amount exceeds available credit.")
    return _post(account, CreditLedgerEntry.Type.PURCHASE, amount,
                 enforce_limit=True, order=order, note=note)


def capture_purchase(account, amount, *, order=None, note="") -> CreditLedgerEntry:
    """Post a purchase that has ALREADY been earned by physical delivery
    (called from `delivery.services.complete_delivery`, never at checkout).

    Unlike `debit_purchase` — a pre-commitment gate, checked against the
    limit at order time via `orders.services.pending_credit_exposure` —
    this never refuses. Once the goods are actually in the customer's
    hands the debt is real regardless of whether the account was frozen or
    the limit changed in the meantime; refusing to record it here would
    leave delivered goods with no debt on the books at all.
    """
    return _post(account, CreditLedgerEntry.Type.PURCHASE, Decimal(amount),
                 enforce_limit=False, order=order, note=note)


def apply_repayment(account, amount, *, payment=None, note="") -> CreditLedgerEntry:
    return _post(account, CreditLedgerEntry.Type.REPAYMENT, -Decimal(amount),
                 payment=payment, note=note)


def apply_refund(account, amount, *, order=None, note="") -> CreditLedgerEntry:
    return _post(account, CreditLedgerEntry.Type.REFUND, -Decimal(amount),
                 order=order, note=note)


def adjust(account, signed_amount, *, by=None, note="") -> CreditLedgerEntry:
    return _post(account, CreditLedgerEntry.Type.ADJUSTMENT, Decimal(signed_amount),
                 created_by=by, note=note)


def reconcile(account: CreditAccount) -> Decimal:
    """Rebuild outstanding from the ledger — the invariant SUM(amount)==outstanding."""
    total = account.entries.aggregate(s=Sum("amount"))["s"] or ZERO
    total = max(total, ZERO)
    if total != account.outstanding:
        account.outstanding = total
        account.save(update_fields=["outstanding", "updated_at"])
    return total


# ══════════════════════ CIBIL / credit-bureau score ══════════════════════

def _normalise_mobile(mobile) -> str:
    """Reduce any input (E.164 '+91…', spaces, etc.) to the last 10 digits."""
    digits = re.sub(r"\D", "", str(mobile or ""))
    return digits[-10:] if len(digits) >= 10 else digits


def latest_bureau_report(user) -> CreditBureauReport | None:
    """Most recent bureau pull for this user (SUCCESS or NO_RECORD), or None."""
    return user.bureau_reports.order_by("-created_at").first()


def fetch_bureau_score(user, *, mobile, consent, source=CreditBureauReport.Source.CUSTOMER,
                       requested_by=None, force=False) -> CreditBureauReport:
    """Pull a CIBIL score for `user` and persist it as a new report row.

    Consent is mandatory (DPDP). Self-service pulls reuse a recent SUCCESS result
    unless `force` (staff refresh) is set. Provider/transport failures raise a
    catalog-coded AppError so the client can act on it.
    """
    if not consent:
        raise AppError("CIBIL_CONSENT_REQUIRED")

    mobile = _normalise_mobile(mobile)
    if len(mobile) != 10:
        raise AppError("VALIDATION_ERROR",
                       fields={"mobile": ["Enter a valid 10-digit mobile number."]})

    if not force:
        cutoff = timezone.now() - timedelta(minutes=BUREAU_REFRESH_MINUTES)
        recent = (
            user.bureau_reports.filter(
                status=CreditBureauReport.Status.SUCCESS,
                mobile=mobile, created_at__gte=cutoff,
            )
            .order_by("-created_at")
            .first()
        )
        if recent is not None:
            return recent

    try:
        result = bureau.get_provider().fetch_score(mobile=mobile)
    except bureau.BureauError as exc:
        raise AppError("CIBIL_PROVIDER_ERROR", context={"detail": str(exc)}) from exc

    return CreditBureauReport.objects.create(
        user=user,
        status=(CreditBureauReport.Status.SUCCESS if result.ok
                else CreditBureauReport.Status.NO_RECORD),
        score=result.score,
        band=result.band,
        name_on_bureau=result.name,
        pan=result.pan,
        mobile=result.mobile or mobile,
        dob=result.dob,
        gender=result.gender,
        provider=bureau.get_provider().name,
        reference_id=result.reference_id,
        consent=True,
        source=source,
        requested_by=requested_by,
    )


# ---------------------------------------------------------------------------
# Credit applications (apply -> review -> decision -> grant)
# ---------------------------------------------------------------------------
def current_application(user):
    """The application that represents this user's current position, or None.

    The newest row wins: an in-flight or approved one is the live state, and a
    rejected/withdrawn one is the thing a customer would re-apply from.
    """
    return user.credit_applications.order_by("-id").first()


def _require_kyc(user):
    """Identity must be verified before we will underwrite.

    KYC no longer *grants* credit (that's the approved limit's job) but it stays a
    precondition — we will not extend a line to an unverified identity.
    """
    if getattr(user, "kyc_status", None) != "verified":
        raise AppError(
            "KYC_REQUIRED",
            message="Complete your KYC verification before applying for VS Credit.",
        )


@transaction.atomic
def submit_application(user, *, occupation, monthly_income, family_members,
                       house_type, ownership, requested_limit):
    """Create (or resubmit) a credit application and put it in the review queue.

    Re-submitting reuses the existing open row rather than piling up history, so
    the admin queue shows one row per customer.
    """
    from .models import CreditApplication

    _require_kyc(user)

    # Lock the user's applications so two taps can't create two queue entries.
    existing = (
        user.credit_applications.select_for_update().order_by("-id").first()
    )
    if existing and existing.is_in_flight:
        raise AppError(
            "CREDIT_APPLICATION_IN_REVIEW",
            message="Your credit application is already under review.",
        )
    if existing and existing.status == CreditApplication.Status.APPROVED:
        raise AppError(
            "CREDIT_ALREADY_ACTIVE",
            message="You already have an active VS Credit line.",
        )

    app = existing if (existing and existing.is_editable) else CreditApplication(user=user)
    app.occupation = occupation or ""
    app.monthly_income = monthly_income
    app.family_members = family_members
    app.house_type = house_type or ""
    app.ownership = ownership or ""
    app.requested_limit = requested_limit
    app.status = CreditApplication.Status.SUBMITTED
    app.submitted_at = timezone.now()
    # Clear any prior decision so a resubmission reads clean in the queue.
    app.approved_limit = None
    app.decided_by = None
    app.decided_at = None
    app.rejection_reason = ""
    # Snapshot the underwriting context so the decision stays explainable later.
    app.kyc_status_at_submit = getattr(user, "kyc_status", "") or ""
    latest_report = (
        CreditBureauReport.objects.filter(user=user, status="success")
        .order_by("-id")
        .first()
    )
    app.bureau_score_at_submit = latest_report.score if latest_report else None
    app.save()
    return app


@transaction.atomic
def approve_application(app, reviewer, *, approved_limit, note=""):
    """Approve an application and grant the line.

    This is the ONLY path that switches on ``user.credit_enabled``. The limit is
    applied to the account and mirrored to ``sanctioned_limit`` so the LSP view
    and the spendable limit agree.
    """
    from .models import CreditApplication

    if app.status not in CreditApplication.IN_FLIGHT_STATES:
        raise AppError("INVALID_CREDIT_TRANSITION",
                       message="Only a submitted application can be approved.")
    limit = Decimal(str(approved_limit))
    if limit <= ZERO:
        raise AppError("INVALID_CREDIT_LIMIT",
                       message="An approved limit must be greater than zero.")

    app.status = CreditApplication.Status.APPROVED
    app.approved_limit = limit
    app.decided_by = reviewer
    app.decided_at = timezone.now()
    app.decision_note = (note or "")[:300]
    app.rejection_reason = ""
    app.save()

    account = ensure_account(app.user, default_limit=limit)
    account.credit_limit = limit
    account.sanctioned_limit = limit
    account.status = CreditAccount.Status.ACTIVE
    account.save(update_fields=["credit_limit", "sanctioned_limit", "status",
                                "updated_at"])

    user = app.user
    user.credit_enabled = True
    user.save(update_fields=["credit_enabled"])
    return app


@transaction.atomic
def reject_application(app, reviewer, *, reason, note=""):
    """Reject an application. Never touches an existing account or limit — a
    rejection here is about *this* request, not a revocation of a live line."""
    from .models import CreditApplication

    if app.status not in CreditApplication.IN_FLIGHT_STATES:
        raise AppError("INVALID_CREDIT_TRANSITION",
                       message="Only a submitted application can be rejected.")
    if not (reason or "").strip():
        raise AppError("VALIDATION_ERROR",
                       message="A customer-facing reason is required to reject.")
    app.status = CreditApplication.Status.REJECTED
    app.rejection_reason = reason.strip()[:300]
    app.decision_note = (note or "")[:300]
    app.decided_by = reviewer
    app.decided_at = timezone.now()
    app.save()
    return app


@transaction.atomic
def set_credit_limit(user, new_limit, *, actor, note=""):
    """Adjust a live account's limit (admin lever, independent of applications).

    Lowering a limit below what's already drawn is allowed — it stops *new*
    spending without retroactively invalidating settled purchases — but it is
    recorded so the reduction is explainable.
    """
    limit = Decimal(str(new_limit))
    if limit < ZERO:
        raise AppError("INVALID_CREDIT_LIMIT",
                       message="A credit limit cannot be negative.")
    account = ensure_account(user, default_limit=limit)
    account.credit_limit = limit
    account.sanctioned_limit = limit
    account.save(update_fields=["credit_limit", "sanctioned_limit", "updated_at"])
    # A zero limit is effectively a revocation — keep the flag honest.
    user.credit_enabled = limit > ZERO
    user.save(update_fields=["credit_enabled"])
    return account
