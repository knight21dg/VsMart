"""Credit application: customer apply/status + admin review queue and decisions.

The lifecycle this serves:

    customer submits  ->  SUBMITTED  ->  (reviewer claims) UNDER_REVIEW
                                     ->  APPROVED (with an explicit limit)
                                     ->  REJECTED (with a customer-facing reason)

Approving here is the *only* thing that switches on ``user.credit_enabled`` and
sets a spendable limit — KYC approval no longer does (see ``kyc.services.approve``).
"""
from decimal import Decimal

from django.shortcuts import get_object_or_404
from rest_framework import serializers
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.app_errors import AppError, ok
from core.permissions import IsAdmin

from .models import CreditApplication
from .services import (
    approve_application,
    current_application,
    reject_application,
    set_credit_limit,
    submit_application,
)


class CreditApplicationSerializer(serializers.ModelSerializer):
    """Customer-facing view. Deliberately omits ``decision_note`` — that is the
    reviewer's internal note and must never reach the applicant."""

    id = serializers.CharField(read_only=True)

    class Meta:
        model = CreditApplication
        fields = [
            "id", "status", "occupation", "monthly_income", "family_members",
            "house_type", "ownership", "requested_limit",
            "approved_limit", "rejection_reason", "submitted_at", "decided_at",
        ]
        read_only_fields = fields


class ApplySerializer(serializers.Serializer):
    """Validates what the app collects on the credit application screen."""

    occupation = serializers.CharField(max_length=120)
    monthly_income = serializers.DecimalField(
        max_digits=12, decimal_places=2, min_value=Decimal("0")
    )
    family_members = serializers.IntegerField(min_value=1, max_value=30)
    house_type = serializers.ChoiceField(choices=CreditApplication.HouseType.choices)
    ownership = serializers.ChoiceField(choices=CreditApplication.Ownership.choices)
    requested_limit = serializers.DecimalField(
        max_digits=12, decimal_places=2, min_value=Decimal("1")
    )


class CreditApplyView(APIView):
    """POST /credit/apply — submit (or resubmit) a credit application.
    GET  /credit/application — the customer's current application, or null."""

    def get(self, request):
        app = current_application(request.user)
        return Response(ok("OK", data=(
            CreditApplicationSerializer(app).data if app else None
        )))

    def post(self, request):
        payload = ApplySerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        app = submit_application(request.user, **payload.validated_data)
        record_audit(request.user, "credit.apply", target=app,
                     after={"requested": str(app.requested_limit)})
        return Response(
            ok("CREDIT_APPLICATION_SUBMITTED",
               data=CreditApplicationSerializer(app).data),
            status=201,
        )


class CreditApplicationWithdrawView(APIView):
    """POST /credit/application/withdraw — customer cancels a pending request."""

    def post(self, request):
        app = current_application(request.user)
        if app is None or not app.is_in_flight:
            raise AppError("INVALID_CREDIT_TRANSITION",
                           message="You have no application under review.")
        app.status = CreditApplication.Status.WITHDRAWN
        app.save(update_fields=["status", "updated_at"])
        record_audit(request.user, "credit.withdraw", target=app)
        return Response(ok("OK", data=CreditApplicationSerializer(app).data))


# ── Admin ────────────────────────────────────────────────────────────────────

class AdminCreditApplicationSerializer(serializers.ModelSerializer):
    """Reviewer view: adds the applicant and the underwriting context."""

    id = serializers.CharField(read_only=True)
    user_id = serializers.CharField(source="user.id", read_only=True)
    customer_name = serializers.CharField(source="user.name", read_only=True)
    customer_phone = serializers.CharField(source="user.phone", read_only=True)
    kyc_status = serializers.CharField(source="user.kyc_status", read_only=True)
    credit_enabled = serializers.BooleanField(
        source="user.credit_enabled", read_only=True
    )
    # NB: not CharField(source="decided_by_id") — DRF rejects a source identical
    # to the field name, and the AssertionError surfaces as a 500.
    decided_by_id = serializers.PrimaryKeyRelatedField(
        source="decided_by", read_only=True
    )

    class Meta:
        model = CreditApplication
        fields = [
            "id", "user_id", "customer_name", "customer_phone",
            "kyc_status", "credit_enabled", "status",
            "occupation", "monthly_income", "family_members", "house_type",
            "ownership", "requested_limit",
            "bureau_score_at_submit", "kyc_status_at_submit",
            "approved_limit", "rejection_reason", "decision_note",
            "decided_by_id", "decided_at", "submitted_at", "created_at",
        ]


class AdminCreditApplicationListView(ListAPIView):
    """GET /admin/credit/applications?status=submitted — the review queue."""

    permission_classes = [IsAdmin]
    serializer_class = AdminCreditApplicationSerializer

    def get_queryset(self):
        qs = CreditApplication.objects.select_related("user", "decided_by")
        status = self.request.query_params.get("status")
        if status == "pending":
            # The queue's default meaning: everything awaiting a decision.
            qs = qs.filter(status__in=CreditApplication.IN_FLIGHT_STATES)
        elif status:
            qs = qs.filter(status=status)
        search = (self.request.query_params.get("search") or "").strip()
        if search:
            from django.db.models import Q

            qs = qs.filter(
                Q(user__name__icontains=search) | Q(user__phone__icontains=search)
            )
        # Oldest in-flight first — a review queue is FIFO, not newest-first.
        return qs.order_by("submitted_at", "id")


class AdminCreditApplicationDetailView(APIView):
    """GET /admin/credit/applications/<pk> — full context for a decision."""

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        app = get_object_or_404(
            CreditApplication.objects.select_related("user", "decided_by"), pk=pk
        )
        data = AdminCreditApplicationSerializer(app).data
        # Live account + latest bureau pull give the reviewer the full picture.
        account = getattr(app.user, "credit_account", None)
        data["account"] = {
            "creditLimit": account.credit_limit,
            "outstanding": account.outstanding,
            "status": account.status,
        } if account else None
        from .models import CreditBureauReport

        report = (
            CreditBureauReport.objects.filter(user=app.user, status="success")
            .order_by("-id").first()
        )
        data["bureau"] = (
            {"score": report.score, "band": report.band,
             "pulledAt": report.created_at}
            if report else None
        )
        return Response(ok("OK", data=data))


class AdminCreditDecisionView(APIView):
    """POST /admin/credit/applications/<pk>/decision — approve or reject.

    Body: ``{"decision": "approve", "approvedLimit": 5000, "note": "..."}`` or
    ``{"decision": "reject", "reason": "...", "note": "..."}``.
    """

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        app = get_object_or_404(CreditApplication, pk=pk)
        decision = (request.data.get("decision") or "").strip().lower()
        note = request.data.get("note") or ""

        if decision == "approve":
            limit = request.data.get("approvedLimit",
                                     request.data.get("approved_limit"))
            if limit in (None, ""):
                raise AppError("INVALID_CREDIT_LIMIT",
                               message="An approved limit is required.")
            app = approve_application(app, request.user,
                                      approved_limit=limit, note=note)
            code = "CREDIT_APPLICATION_APPROVED"
            self._notify(app, approved=True)
        elif decision == "reject":
            reason = request.data.get("reason") or ""
            app = reject_application(app, request.user, reason=reason, note=note)
            code = "CREDIT_APPLICATION_REJECTED"
            self._notify(app, approved=False)
        elif decision == "review":
            # Claim it, so two reviewers don't work the same row.
            if not app.is_in_flight:
                raise AppError("INVALID_CREDIT_TRANSITION")
            app.status = CreditApplication.Status.UNDER_REVIEW
            app.save(update_fields=["status", "updated_at"])
            code = "OK"
        else:
            raise AppError("VALIDATION_ERROR",
                           message="decision must be approve, reject or review.")

        record_audit(request.user, f"credit.application.{decision}", target=app,
                     after={"status": app.status,
                            "limit": str(app.approved_limit or "")})
        return Response(ok(code, data=AdminCreditApplicationSerializer(app).data))

    def _notify(self, app, *, approved):
        """Tell the customer. Never blocks the decision if messaging is down."""
        try:
            from notifications.services import notify

            if approved:
                notify(
                    app.user, type="credit",
                    title="Your VS Credit is approved",
                    body=f"You have a credit limit of ₹{app.approved_limit:.0f}.",
                    data={"route": "credit"},
                )
            else:
                notify(
                    app.user, type="credit",
                    title="Update on your VS Credit application",
                    body=app.rejection_reason,
                    data={"route": "credit"},
                )
        except Exception:  # noqa: BLE001 - notification must never fail a decision
            pass


class AdminCreditLimitView(APIView):
    """POST /admin/credit/users/<user_id>/limit — adjust a live account's limit,
    independent of any application (e.g. a periodic review or a step-down)."""

    permission_classes = [IsAdmin]

    def post(self, request, user_id):
        from accounts.models import User

        user = get_object_or_404(User, pk=user_id)
        limit = request.data.get("creditLimit", request.data.get("credit_limit"))
        if limit in (None, ""):
            raise AppError("INVALID_CREDIT_LIMIT",
                           message="A credit limit is required.")
        account = set_credit_limit(user, limit, actor=request.user,
                                   note=request.data.get("note") or "")
        record_audit(request.user, "credit.limit.set", target=user,
                     after={"limit": str(account.credit_limit)})
        return Response(ok("OK", data={
            "userId": str(user.id),
            "creditLimit": account.credit_limit,
            "outstanding": account.outstanding,
            "creditEnabled": user.credit_enabled,
        }))
