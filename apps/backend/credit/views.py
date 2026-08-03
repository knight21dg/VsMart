from decimal import Decimal

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError, ok
from core.permissions import IsAdmin, IsCustomer

from .models import CreditBureauReport, CreditLedgerEntry, FamilyGroup, FamilyMember, Statement
from .serializers import (
    CreditAccountSerializer,
    CreditBureauReportSerializer,
    FamilyGroupSerializer,
    LedgerEntrySerializer,
    StatementSerializer,
)
from .services import ensure_account, fetch_bureau_score, latest_bureau_report

User = get_user_model()


def _bureau_response(report: CreditBureauReport):
    """Render a completed pull: a coded success payload, or the soft NO_RECORD
    envelope so the client shows a clear 'no record' message."""
    if report.status == CreditBureauReport.Status.SUCCESS:
        return Response(ok("CIBIL_FETCHED",
                           data=CreditBureauReportSerializer(report).data))
    raise AppError("CIBIL_NO_RECORD")


class DashboardView(APIView):
    def get(self, request):
        account = ensure_account(request.user)
        next_due = (
            account.statements.filter(status__in=["open", "overdue", "partially_paid"])
            .order_by("due_date")
            .first()
        )
        data = CreditAccountSerializer(account).data
        data["next_due_date"] = next_due.due_date if next_due else None
        data["next_due_amount"] = next_due.closing_balance if next_due else 0
        # Current-month activity for the dashboard (signed ledger: purchases are
        # positive, repayments negative — flip the latter so both read positive).
        now = timezone.now()
        month = account.entries.filter(
            created_at__year=now.year, created_at__month=now.month
        )
        data["purchases_this_month"] = sum(
            (e.amount for e in month if e.type == CreditLedgerEntry.Type.PURCHASE),
            Decimal("0.00"),
        )
        data["payments_this_month"] = sum(
            (-e.amount for e in month if e.type == CreditLedgerEntry.Type.REPAYMENT),
            Decimal("0.00"),
        )
        return Response(data)


def _score_factors(account):
    """The VS-score factors, computed from the account — NOT hardcoded.

    Every user used to get the same three static ratings ("good/fair/good")
    regardless of their actual behaviour, so the breakdown was decorative. These
    are derived from real signals: utilisation, on-time repayment, and account age.
    Each is good | fair | poor.
    """
    factors = []

    # ── Credit utilisation: lower is better. ──
    if account.credit_limit > 0:
        util = account.outstanding / account.credit_limit
        if util <= Decimal("0.3"):
            status = "good"
        elif util <= Decimal("0.6"):
            status = "fair"
        else:
            status = "poor"
    else:
        status = "fair"
    factors.append({"label": "Credit utilization", "status": status})

    # ── Repayment history: share of due statements settled on time. ──
    settled = account.statements.filter(status=Statement.Status.PAID).count()
    overdue = account.statements.filter(status=Statement.Status.OVERDUE).count()
    total = settled + overdue
    if total == 0:
        status = "fair"  # no history yet — neither good nor bad
    elif overdue == 0:
        status = "good"
    elif settled >= overdue:
        status = "fair"
    else:
        status = "poor"
    factors.append({"label": "Repayment history", "status": status})

    # ── Account age: older accounts are more established. ──
    age_days = (timezone.now() - account.created_at).days
    if age_days >= 180:
        status = "good"
    elif age_days >= 60:
        status = "fair"
    else:
        status = "poor"
    factors.append({"label": "Account age", "status": status})

    return factors


class ScoreView(APIView):
    def get(self, request):
        account = ensure_account(request.user)
        return Response(
            {
                "vs_score": account.vs_score,
                "factors": _score_factors(account),
            }
        )


class LedgerView(ListAPIView):
    serializer_class = LedgerEntrySerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return CreditLedgerEntry.objects.none()
        return ensure_account(self.request.user).entries.all()


class StatementListView(ListAPIView):
    serializer_class = StatementSerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Statement.objects.none()
        return ensure_account(self.request.user).statements.all()


class StatementDetailView(APIView):
    def get(self, request, pk):
        account = ensure_account(request.user)
        statement = get_object_or_404(Statement, pk=pk, account=account)
        return Response(StatementSerializer(statement).data)


class StatementPdfView(APIView):
    """The customer's own credit statement as a PDF. Backs the Download button on
    the statement-detail screen, which previously fired a fake 'downloaded'
    snackbar and fetched nothing."""

    def get(self, request, pk):
        from django.http import HttpResponse

        from .statement_pdf import build_statement_pdf

        account = ensure_account(request.user)
        statement = get_object_or_404(Statement, pk=pk, account=account)
        pdf = build_statement_pdf(statement)
        resp = HttpResponse(pdf, content_type="application/pdf")
        resp["Content-Disposition"] = (
            f'inline; filename="vsmart-statement-{statement.pk}.pdf"'
        )
        return resp


class OutstandingView(APIView):
    def get(self, request):
        account = ensure_account(request.user)
        statements = account.statements.filter(
            status__in=["open", "overdue", "partially_paid"]
        )
        return Response(
            {
                "total": account.outstanding,
                "statements": StatementSerializer(statements, many=True).data,
            }
        )


class BillsView(APIView):
    """Current cycle bill for a period (weekly|monthly) — latest statement or a
    computed summary when none generated yet."""

    period = "monthly"

    def get(self, request):
        account = ensure_account(request.user)
        statement = (
            account.statements.filter(period=self.period).order_by("-period_end").first()
        )
        if statement:
            return Response(StatementSerializer(statement).data)
        return Response(
            {
                "period": self.period,
                "closing_balance": account.outstanding,
                "due_date": None,
                "status": "open",
            }
        )


class FamilyView(APIView):
    def get(self, request):
        group, _ = FamilyGroup.objects.get_or_create(primary_user=request.user)
        return Response(FamilyGroupSerializer(group).data)

    def post(self, request):
        """Invite a member by phone."""
        group, _ = FamilyGroup.objects.get_or_create(primary_user=request.user)
        phone = request.data.get("phone")
        if not phone:
            return Response({"error": {"code": "bad_request",
                                       "message": "phone is required", "fields": {}}}, status=400)
        FamilyMember.objects.create(
            group=group,
            phone=phone,
            relationship=request.data.get("relationship", ""),
            status=FamilyMember.Status.PENDING,
        )
        return Response(FamilyGroupSerializer(group).data, status=201)


class FamilyMemberView(APIView):
    def delete(self, request, pk):
        group = get_object_or_404(FamilyGroup, primary_user=request.user)
        FamilyMember.objects.filter(pk=pk, group=group).delete()
        return Response({"status": "removed"})


# ══════════════════════ CIBIL / credit-bureau score ══════════════════════

def _truthy(v):
    return str(v).strip().lower() in ("1", "true", "yes", "y", "on")


class CibilCheckView(APIView):
    """Customer self-service: fetch (and store) my CIBIL score after consent."""

    def post(self, request):
        report = fetch_bureau_score(
            request.user,
            mobile=request.data.get("mobile"),
            consent=_truthy(request.data.get("consent")),
            source=CreditBureauReport.Source.CUSTOMER,
            requested_by=request.user,
        )
        return _bureau_response(report)


class CibilLatestView(APIView):
    """Customer: my most recent stored bureau report (null if never checked)."""

    def get(self, request):
        report = latest_bureau_report(request.user)
        return Response(
            {"report": CreditBureauReportSerializer(report).data if report else None}
        )


class AdminCibilView(APIView):
    """Admin/super-admin: view a customer's stored CIBIL, and refresh (re-pull).

    Refresh reuses the mobile + consent from the customer's own last check — RBI/
    DPDP-safe, staff cannot originate a bureau pull without prior customer consent.
    """

    permission_classes = [IsAdmin]

    def get(self, request, user_id):
        customer = get_object_or_404(User, pk=user_id)
        report = latest_bureau_report(customer)
        return Response(
            {"report": CreditBureauReportSerializer(report).data if report else None}
        )

    def post(self, request, user_id):
        customer = get_object_or_404(User, pk=user_id)
        prior = latest_bureau_report(customer)
        if prior is None or not prior.consent:
            raise AppError(
                "CIBIL_CONSENT_REQUIRED",
                message="This customer hasn't consented to a credit-score check yet. "
                        "They must run it once from the app before it can be refreshed.",
            )
        report = fetch_bureau_score(
            customer,
            mobile=prior.mobile or getattr(customer, "phone", ""),
            consent=True,
            source=CreditBureauReport.Source.ADMIN,
            requested_by=request.user,
            force=True,
        )
        return _bureau_response(report)


class PosCreditConfirmView(APIView):
    """Customer-facing: the pending POS credit-confirmation code + amount (the 2FA a
    store cashier asked for). The app shows this so the customer can read it back."""

    permission_classes = [IsCustomer]

    def get(self, request):
        from .pos_otp import pending_for

        return Response(ok("OK", data={"pending": pending_for(request.user)}))
