"""Admin general-ledger API: chart of accounts, journal, and the reports."""
from django.shortcuts import get_object_or_404
from rest_framework import serializers
from rest_framework.generics import ListAPIView, ListCreateAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import ok
from core.permissions import IsAdmin

from .models import Account, JournalEntry
from .services import (
    account_ledger,
    balance_sheet,
    post_entry,
    profit_and_loss,
    reverse_entry,
    trial_balance,
)


class AccountSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Account
        fields = ["id", "code", "name", "type", "parent_id", "description",
                  "is_control", "is_active"]


class JournalLineSerializer(serializers.Serializer):
    account_code = serializers.CharField(source="account.code", read_only=True)
    account_name = serializers.CharField(source="account.name", read_only=True)
    debit = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    credit = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    narration = serializers.CharField(read_only=True)


class JournalEntrySerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    lines = JournalLineSerializer(many=True, read_only=True)
    total = serializers.SerializerMethodField()
    created_by_name = serializers.CharField(
        source="created_by.name", read_only=True, default=None
    )

    class Meta:
        model = JournalEntry
        fields = ["id", "entry_date", "narration", "reference", "status",
                  "source_module", "source_ref", "store_id", "posted_at",
                  "created_by_name", "total", "lines"]

    def get_total(self, obj):
        return obj.total_debit


class AdminAccountListView(ListCreateAPIView):
    """GET/POST /admin/accounting/accounts — the chart of accounts."""

    permission_classes = [IsAdmin]
    serializer_class = AccountSerializer
    pagination_class = None

    def get_queryset(self):
        qs = Account.objects.all()
        p = self.request.query_params
        if p.get("type"):
            qs = qs.filter(type=p["type"])
        if p.get("active") != "all":
            qs = qs.filter(is_active=True)
        return qs


class AdminJournalListView(ListAPIView):
    """GET /admin/accounting/journal — the journal, newest first."""

    permission_classes = [IsAdmin]
    serializer_class = JournalEntrySerializer

    def get_queryset(self):
        qs = JournalEntry.objects.prefetch_related("lines__account").select_related(
            "created_by"
        )
        p = self.request.query_params
        if p.get("status"):
            qs = qs.filter(status=p["status"])
        if p.get("source"):
            qs = qs.filter(source_module=p["source"])
        if p.get("from"):
            qs = qs.filter(entry_date__gte=p["from"])
        if p.get("to"):
            qs = qs.filter(entry_date__lte=p["to"])
        search = (p.get("search") or "").strip()
        if search:
            from django.db.models import Q

            qs = qs.filter(Q(narration__icontains=search)
                           | Q(reference__icontains=search))
        return qs


class AdminJournalPostView(APIView):
    """POST /admin/accounting/journal — hand-post a balanced entry.

    Body: ``{entryDate, narration, reference?, lines: [{accountCode, debit|credit}]}``
    """

    permission_classes = [IsAdmin]

    def post(self, request):
        raw_lines = request.data.get("lines") or []
        lines = [
            {
                "account": line.get("accountCode") or line.get("account_code"),
                "debit": line.get("debit") or 0,
                "credit": line.get("credit") or 0,
                "narration": line.get("narration") or "",
            }
            for line in raw_lines
        ]
        entry = post_entry(
            entry_date=request.data.get("entryDate") or request.data.get("entry_date"),
            narration=request.data.get("narration") or "",
            reference=request.data.get("reference") or "",
            lines=lines,
            source_module="manual",
            actor=request.user,
        )
        return Response(ok("GL_POSTED", data=JournalEntrySerializer(entry).data),
                        status=201)


class AdminJournalReverseView(APIView):
    """POST /admin/accounting/journal/<pk>/reverse"""

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        entry = get_object_or_404(JournalEntry, pk=pk)
        reversal = reverse_entry(
            entry, request.user, reason=request.data.get("reason") or ""
        )
        return Response(ok("GL_REVERSED",
                           data=JournalEntrySerializer(reversal).data))


class AdminTrialBalanceView(APIView):
    """GET /admin/accounting/trial-balance?asOf="""

    permission_classes = [IsAdmin]

    def get(self, request):
        p = request.query_params
        return Response(ok("OK", data=trial_balance(
            as_of=p.get("asOf") or p.get("as_of") or None,
            store=p.get("store") or None,
        )))


class AdminProfitLossView(APIView):
    """GET /admin/accounting/pnl?from=&to="""

    permission_classes = [IsAdmin]

    def get(self, request):
        p = request.query_params
        return Response(ok("OK", data=profit_and_loss(
            date_from=p.get("from") or None,
            date_to=p.get("to") or None,
            store=p.get("store") or None,
        )))


class AdminBalanceSheetView(APIView):
    """GET /admin/accounting/balance-sheet?asOf="""

    permission_classes = [IsAdmin]

    def get(self, request):
        p = request.query_params
        return Response(ok("OK", data=balance_sheet(
            as_of=p.get("asOf") or p.get("as_of") or None,
            store=p.get("store") or None,
        )))


class AdminAccountLedgerView(APIView):
    """GET /admin/accounting/accounts/<pk>/ledger?from=&to — the drill-down."""

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        account = get_object_or_404(Account, pk=pk)
        p = request.query_params
        return Response(ok("OK", data=account_ledger(
            account,
            date_from=p.get("from") or None,
            date_to=p.get("to") or None,
            store=p.get("store") or None,
        )))
