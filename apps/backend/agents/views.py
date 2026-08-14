from datetime import timedelta
from decimal import Decimal

from django.db.models import Sum
from django.utils import timezone
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import AgentProfile
from core.permissions import IsAdmin, IsAgent

from . import services
from .models import AgentIncentive
from .serializers import (
    AgentEarningsSerializer,
    AgentIncentiveSerializer,
    AgentPerformanceSerializer,
    AgentProfileSerializer,
    AgentProfileUpdateSerializer,
)

ZERO = Decimal("0.00")
# `PER_DELIVERY` / `PER_COLLECTION` lived here as bare constants and were the source
# of the invented agent pay this audit removed. Rates now live in `agents/earnings.py`,
# which both this view and the finance settlement view read.


def _get_profile(user):
    profile, _ = AgentProfile.objects.get_or_create(
        user=user, defaults={"code": f"VSAGT{user.pk}"}
    )
    return profile


def _profile_payload(user, profile):
    return {
        "id": str(profile.pk),
        "code": profile.code,
        "assigned_pincodes": profile.assigned_pincodes,
        "is_available": profile.is_available,
        "name": user.name,
        "phone": user.phone,
        "employment_type": profile.employment_type,
        "avatar_url": user.avatar_url or "",
    }


def _deliveries_completed(user):
    from delivery.models import DeliveryTask

    return DeliveryTask.objects.filter(agent=user, status="delivered").count()


def _collections_done(user):
    from payments.models import CashCollection

    return CashCollection.objects.filter(agent=user, status="collected").count()


def _verifications_done(user):
    from verification.models import VerificationTask

    return VerificationTask.objects.filter(
        agent=user, status__in=["submitted", "approved"]
    ).count()


def _daily_breakdown(user, days=14):
    """Completed work per day, oldest to newest, for a trend chart. Local
    calendar date (not UTC) so a task finished at 11pm counts for the day the
    agent actually worked, not the next one."""
    from delivery.models import DeliveryTask
    from payments.models import CashCollection
    from verification.models import VerificationTask

    today = timezone.localdate()
    start = today - timedelta(days=days - 1)
    counts = {
        start + timedelta(n): {"deliveries": 0, "collections": 0, "verifications": 0}
        for n in range(days)
    }

    def _bucket(queryset, key):
        for at in queryset:
            d = timezone.localtime(at).date()
            if d in counts:
                counts[d][key] += 1

    _bucket(
        DeliveryTask.objects.filter(
            agent=user, status="delivered", delivered_at__date__gte=start
        ).values_list("delivered_at", flat=True),
        "deliveries",
    )
    _bucket(
        CashCollection.objects.filter(
            agent=user, status="collected", collected_at__date__gte=start
        ).values_list("collected_at", flat=True),
        "collections",
    )
    _bucket(
        VerificationTask.objects.filter(
            agent=user, status__in=["submitted", "approved"],
            submitted_at__date__gte=start,
        ).values_list("submitted_at", flat=True),
        "verifications",
    )

    return [{"date": d.isoformat(), **counts[d]} for d in sorted(counts)]


class AgentMeView(APIView):
    permission_classes = [IsAgent]

    def get(self, request):
        profile = _get_profile(request.user)
        data = AgentProfileSerializer(_profile_payload(request.user, profile)).data
        return Response(data)

    def put(self, request):
        profile = _get_profile(request.user)
        s = AgentProfileUpdateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        update_fields = []
        if "is_available" in s.validated_data:
            profile.is_available = s.validated_data["is_available"]
            update_fields.append("is_available")
        if "assigned_pincodes" in s.validated_data:
            profile.assigned_pincodes = s.validated_data["assigned_pincodes"]
            update_fields.append("assigned_pincodes")
        if update_fields:
            profile.save(update_fields=update_fields)
        data = AgentProfileSerializer(_profile_payload(request.user, profile)).data
        return Response(data)


class AgentPerformanceView(APIView):
    permission_classes = [IsAgent]

    def get(self, request):
        data = {
            "deliveries_completed": _deliveries_completed(request.user),
            "collections_done": _collections_done(request.user),
            "verifications_done": _verifications_done(request.user),
            "daily": _daily_breakdown(request.user),
        }
        return Response(AgentPerformanceSerializer(data).data)


class AgentEarningsView(APIView):
    permission_classes = [IsAgent]

    def get(self, request):
        # One definition, shared with the finance view that actually pays this out
        # (`reports/accounting_views.py`). The two used to compute pay differently —
        # the agent's own screen read the DeliveryEarnings ledger while finance
        # invented ₹20 × delivered-count — so an agent and the person paying them
        # could read different numbers off the same data.
        #
        # Note this drops the `released=True` filter. Nothing ever writes
        # `released=False`, so it never excluded anything; keeping it implied a
        # paid/unpaid distinction the data does not support.
        from .earnings import breakdown

        b = breakdown(request.user)
        data = {
            "base": b["base"],
            "incentives": b["incentives"],
            "total": b["total"],
        }
        return Response(AgentEarningsSerializer(data).data)


class AgentIncentivesView(ListAPIView):
    serializer_class = AgentIncentiveSerializer
    permission_classes = [IsAgent]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return AgentIncentive.objects.none()
        return AgentIncentive.objects.filter(agent=self.request.user)


# ── Attendance (agent) ───────────────────────────────────
def _att_payload(att):
    return {
        "date": att.date,
        "checkInAt": att.check_in_at,
        "checkOutAt": att.check_out_at,
        "onDuty": att.on_duty,
    }


class AgentCheckInView(APIView):
    permission_classes = [IsAgent]

    def post(self, request):
        return Response(_att_payload(services.check_in(request.user)))


class AgentCheckOutView(APIView):
    permission_classes = [IsAgent]

    def post(self, request):
        return Response(_att_payload(services.check_out(request.user)))


class AgentAttendanceMeView(APIView):
    permission_classes = [IsAgent]

    def get(self, request):
        from .models import AgentAttendance
        from django.utils import timezone

        att = AgentAttendance.objects.filter(
            agent=request.user, date=timezone.localdate()
        ).first()
        if not att:
            return Response({"date": timezone.localdate(), "checkInAt": None,
                             "checkOutAt": None, "onDuty": False})
        return Response(_att_payload(att))


class AgentAttendanceHistoryView(APIView):
    """GET /agents/attendance/history?month=YYYY-MM — this agent's attendance
    for one calendar month (default: the current month), for the app's
    attendance calendar. A day with no row simply has no record (the agent
    wasn't checked in that day) — there's no separate leave/absence concept."""

    permission_classes = [IsAgent]

    def get(self, request):
        from calendar import monthrange
        from datetime import date

        from django.utils import timezone

        from .models import AgentAttendance

        raw = (request.query_params.get("month") or "").strip()
        try:
            year, month = (int(p) for p in raw.split("-", 1))
            first = date(year, month, 1)
        except (ValueError, TypeError):
            today = timezone.localdate()
            first = today.replace(day=1)
        last = first.replace(day=monthrange(first.year, first.month)[1])

        rows = AgentAttendance.objects.filter(
            agent=request.user, date__gte=first, date__lte=last
        ).order_by("date")
        days = []
        for att in rows:
            hours = None
            if att.check_in_at and att.check_out_at:
                hours = round(
                    (att.check_out_at - att.check_in_at).total_seconds() / 3600, 2
                )
            days.append({
                **_att_payload(att),
                "hoursWorked": hours,
            })
        return Response({
            "month": first.strftime("%Y-%m"),
            "days": days,
        })


# ── Live Operations (admin) ──────────────────────────────
class LiveOperationsView(APIView):
    """Live geo + on-duty agents + active deliveries/collections for the admin
    dashboard's Live Operations panel."""

    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(services.live_operations())


class AdminAttendanceView(APIView):
    """Today's agent attendance roster (admin)."""

    permission_classes = [IsAdmin]

    def get(self, request):
        rows = [
            {
                "agentId": str(a.agent_id),
                "name": a.agent.name or a.agent.phone,
                "checkInAt": a.check_in_at,
                "checkOutAt": a.check_out_at,
                "onDuty": a.on_duty,
            }
            for a in services.attendance_today()
        ]
        return Response(rows)


class AdminAgentRosterView(APIView):
    """GET /admin/agents — the platform-wide agent roster with today's duty.

    Super-admin oversight across every store's agents (agents are store-owned;
    a store only sees its own). Optional ``?store=`` / ``?zone=`` narrows it.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        from django.utils import timezone

        from .models import AgentAttendance

        qs = AgentProfile.objects.select_related("user", "store").filter(
            user__role="agent"
        )
        store = request.query_params.get("store")
        if store:
            qs = qs.filter(store_id=store)

        today = timezone.localdate()
        duty = {
            a.agent_id: a
            for a in AgentAttendance.objects.filter(date=today)
        }
        rows = []
        for p in qs:
            att = duty.get(p.user_id)
            rows.append({
                "agentId": str(p.user_id),
                "code": p.code,
                "name": p.user.name or p.user.phone,
                "phone": p.user.phone,
                "storeId": str(p.store_id) if p.store_id else None,
                "storeName": p.store.name if p.store_id else None,
                "vehicle": p.vehicle_type,
                "available": p.is_available,
                "isActive": p.user.is_active,
                "rating": float(p.rating or 0),
                "bagCapacity": p.bag_capacity,
                "weightCapacityKg": p.weight_capacity_kg,
                "cashCapacity": float(p.cash_capacity or 0),
                "maxStops": p.max_stops,
                "employmentType": p.employment_type,
                "onDuty": bool(att and att.on_duty),
                "checkInAt": att.check_in_at if att else None,
                "checkOutAt": att.check_out_at if att else None,
            })
        return Response(rows)


class AdminAgentLeaderboardView(APIView):
    """GET /admin/agents/leaderboard — delivery + collection performance for EVERY
    agent in one call.

    The existing ``admin/delivery/performance`` and ``admin/collections/performance``
    are per-agent (``?agent_id=``), so a leaderboard over them would be an N+1 from
    the browser. This composes the same two service functions server-side.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        from cashcollections import services as coll_services
        from delivery import services as del_services

        qs = AgentProfile.objects.select_related("user", "store").filter(
            user__role="agent"
        )
        store = request.query_params.get("store")
        if store:
            qs = qs.filter(store_id=store)

        rows = []
        for p in qs:
            try:
                d = del_services.agent_performance(p.user)
            except Exception:  # a module being unavailable must not 500 the board
                d = {}
            try:
                c = coll_services.agent_performance(p.user)
            except Exception:
                c = {}
            rows.append({
                "agentId": str(p.user_id),
                "code": p.code,
                "name": p.user.name or p.user.phone,
                "storeName": p.store.name if p.store_id else None,
                "rating": float(p.rating or 0),
                # delivery
                "deliveries": d.get("deliveries", 0),
                "failed": d.get("failed", 0),
                "successRate": d.get("success_rate", 0.0),
                "avgMinutes": d.get("avg_minutes"),
                "acceptanceRate": d.get("acceptance_rate", 0.0),
                # collections
                "collectionsAssigned": c.get("assigned", 0),
                "collected": c.get("collected", 0),
                "recoveredAmount": c.get("recoveredAmount", 0.0),
                "recoveryRate": c.get("recoveryRate", 0.0),
            })
        # Best first: deliveries completed, then recovery.
        rows.sort(key=lambda r: (r["deliveries"], r["recoveredAmount"]), reverse=True)
        return Response(rows)
