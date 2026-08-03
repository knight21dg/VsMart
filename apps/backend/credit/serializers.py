from rest_framework import serializers

from .models import (
    CreditAccount,
    CreditBureauReport,
    CreditLedgerEntry,
    FamilyGroup,
    FamilyMember,
    Statement,
)


class CreditBureauReportSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    checked_at = serializers.DateTimeField(source="created_at", read_only=True)

    class Meta:
        model = CreditBureauReport
        fields = [
            "id", "status", "score", "band", "name_on_bureau", "pan",
            "mobile", "provider", "reference_id", "source", "checked_at",
        ]


class CreditAccountSerializer(serializers.ModelSerializer):
    available = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    # Lending-partner disclosure fields. Null until an LSP is configured on the
    # account; surfaced so the app can show a lender disclosure when present.
    lender_name = serializers.CharField(source="lender.name", read_only=True, default=None)

    class Meta:
        model = CreditAccount
        fields = [
            "credit_limit", "outstanding", "available", "vs_score", "status",
            "billing_cycle",
            "lender_name", "loan_account_number", "interest_rate", "sanctioned_limit",
        ]


class LedgerEntrySerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = CreditLedgerEntry
        fields = ["id", "type", "amount", "balance_after", "note", "created_at"]


class StatementSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Statement
        fields = [
            "id", "period", "period_start", "period_end", "opening_balance",
            "purchases", "payments", "fees", "closing_balance", "due_date", "status",
        ]


class FamilyMemberSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = FamilyMember
        fields = ["id", "phone", "relationship", "status", "shared_usage"]


class FamilyGroupSerializer(serializers.ModelSerializer):
    members = FamilyMemberSerializer(many=True, read_only=True)

    class Meta:
        model = FamilyGroup
        fields = ["shared_limit", "members"]
