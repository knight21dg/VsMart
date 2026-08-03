"""Collections admin (spec §MODULE 8): credit-recovery operations — due queue,
assign/reassign agents, mark priority, recovery metrics. Every record is attributed
to the customer's serving store + zone (recovery is geographic)."""
from decimal import Decimal

from django.db.models import Sum
from django.utils import timezone
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.services import record_audit
from core.pagination import EnvelopePagination
from core.permissions import IsAdmin
from payments.models import CashCollection
from reports.filters import user_store_zone_map

class CollectionsPagination(EnvelopePagination):
    """Standard envelope pagination for the recovery queue.

    The page size was temporarily pinned to the old 300-row hard cap while the
    console still rendered no pager — dropping to the default then would have
    *reduced* what a recovery operator could see. The page now sends ``?page=``
    and renders a footer, so this is back to a normal working page size.
    """

    page_size = 50


ZERO = Decimal("0.00")
OPEN = [s for s in CashCollection.Status.values if s not in CashCollection.TERMINAL]
#: Money was recovered in both of these — a partial recovery is still a recovery.
COLLECTED_STATUSES = (
    CashCollection.Status.COLLECTED,
    CashCollection.Status.PARTIALLY_COLLECTED,
)


def _row(c, umap):
    loc = umap.get(c.user_id, {})
    return {
        "id": str(c.id),
        "userName": c.user.name or c.user.phone,
        "userPhone": c.user.phone,
        "storeName": loc.get("store__name"),
        "zoneName": loc.get("zone__name"),
        "amount": c.amount,
        "status": c.status,
        "isPriority": c.is_priority,
        "agentId": str(c.agent_id) if c.agent_id else None,
        "agentName": c.agent.name if c.agent_id else None,
        "collectedAt": c.collected_at,
        "createdAt": c.created_at,
    }


def _scoped_users(umap, store, zone):
    """user_ids whose serving store/zone matches the filter."""
    return {
        uid for uid, m in umap.items()
        if (not store or str(m.get("store_id")) == store) and (not zone or str(m.get("zone_id")) == zone)
    }


class AdminCollectionListView(APIView):
    """Admin cash-collection queue — PAGINATED.

    Emits the standard ``{data, meta:{page,total,totalPages}}`` envelope via
    :class:`core.pagination.EnvelopePagination`. It previously returned a hard
    ``[:300]`` slice with no offset, so collection 301 onwards was unreachable and
    the operator was never told the queue had been truncated — dangerous on a
    recovery queue, where the unseen tail is money nobody is chasing. ``data`` is
    still the row array, so existing callers keep working.

    A caller may still pass ``limit`` for a legacy unpaginated slice.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        umap = user_store_zone_map()
        qs = CashCollection.objects.select_related("user", "agent").all()
        status = request.query_params.get("status")
        if status == "open":
            qs = qs.filter(status__in=OPEN)
        elif status:
            qs = qs.filter(status=status)
        store = request.query_params.get("store")
        zone = request.query_params.get("zone")
        if store or zone:
            qs = qs.filter(user_id__in=_scoped_users(umap, store, zone))
        if request.query_params.get("priority") in ("1", "true"):
            qs = qs.filter(is_priority=True)
        qs = qs.order_by("-is_priority", "-created_at")
        # Legacy escape hatch: an explicit ?limit= returns a bare list as before.
        if request.query_params.get("limit"):
            limit = min(int(request.query_params["limit"] or 300), 300)
            return Response([_row(c, umap) for c in qs[:limit]])
        paginator = CollectionsPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response([_row(c, umap) for c in page])


class AdminCollectionMetricsView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        today = timezone.localdate()
        umap = user_store_zone_map()
        # Recovery figures must sum what was actually RECOVERED
        # (`collected_amount`), not the debt that was chased (`amount`), and must
        # include partials — a ₹200 recovery against a ₹500 debt used to report
        # ₹500, or be dropped from the report entirely.
        collected_today = CashCollection.objects.filter(
            status__in=COLLECTED_STATUSES, collected_at__date=today
        ).aggregate(s=Sum("collected_amount"))["s"] or ZERO
        pending = CashCollection.objects.filter(status__in=OPEN).aggregate(s=Sum("amount"))["s"] or ZERO
        pending_count = CashCollection.objects.filter(status__in=OPEN).count()
        priority_count = CashCollection.objects.filter(status__in=OPEN, is_priority=True).count()
        from credit.models import Statement

        overdue = Statement.objects.filter(status="overdue").aggregate(s=Sum("closing_balance"))["s"] or ZERO

        rows = (
            CashCollection.objects.filter(
                status__in=COLLECTED_STATUSES, agent__isnull=False)
            .values("agent_id", "agent__name")
            .annotate(total=Sum("collected_amount"))
            .order_by("-total")[:10]
        )
        agents = [{"agentId": str(r["agent_id"]), "name": r["agent__name"], "collected": r["total"]} for r in rows]

        # Per-zone recovery breakdown (collected vs pending), attributed via umap.
        zone_agg = {}
        for c in CashCollection.objects.values(
                "user_id", "status", "amount", "collected_amount"):
            z = umap.get(c["user_id"], {}).get("zone__name") or "Unzoned"
            b = zone_agg.setdefault(z, {"zone": z, "collected": ZERO, "pending": ZERO})
            if c["status"] in COLLECTED_STATUSES:
                b["collected"] += c["collected_amount"]
            elif c["status"] in OPEN:
                b["pending"] += c["amount"]
        by_zone = sorted(zone_agg.values(), key=lambda r: r["collected"] + r["pending"], reverse=True)

        return Response({
            "collectedToday": collected_today,
            "pendingAmount": pending,
            "pendingCount": pending_count,
            "priorityCount": priority_count,
            "overdueAmount": overdue,
            "agentPerformance": agents,
            "byZone": by_zone,
        })


class AdminCollectionAgentsView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        rows = User.objects.filter(role="agent", is_active=True).values("id", "name", "phone")
        return Response([{"id": str(r["id"]), "name": r["name"] or r["phone"]} for r in rows])


class AdminCollectionUpdateView(APIView):
    permission_classes = [IsAdmin]

    def patch(self, request, pk):
        c = get_object_or_404(CashCollection.objects.select_related("user", "agent"), pk=pk)
        data = request.data
        fields = []
        assignee = data.get("agent_id") or data.get("agentId")
        if "agentId" in data or "agent_id" in data:
            c.agent = User.objects.filter(pk=assignee, role="agent").first() if assignee else None
            if c.agent and c.status == CashCollection.Status.REQUESTED:
                c.status = CashCollection.Status.ASSIGNED
                fields.append("status")
            fields.append("agent")
        if "isPriority" in data or "is_priority" in data:
            c.is_priority = bool(data.get("isPriority", data.get("is_priority")))
            fields.append("is_priority")
        if "status" in data:
            c.status = data["status"]
            fields.append("status")
        if fields:
            fields.append("updated_at")
            c.save(update_fields=list(set(fields)))
            record_audit(request.user, "collection.update", target=c,
                         after={"status": c.status, "priority": c.is_priority})
        return Response(_row(c, user_store_zone_map()))


# ── Production recovery operations (state machine + dunning) ──────────
class AdminCollectionAutoAssignView(APIView):
    """Auto-assign every unassigned collection to the lowest-load available agent."""

    permission_classes = [IsAdmin]

    def post(self, request):
        from cashcollections import services
        from core.app_errors import ok

        pk = request.data.get("id") or request.data.get("collection_id")
        if pk:
            c = get_object_or_404(CashCollection, pk=pk)
            services.auto_assign(c, by=request.user)
            return Response(ok("COLLECTION_ASSIGNED", data={"id": str(c.id)}))
        assigned = 0
        for c in CashCollection.objects.filter(status=CashCollection.Status.REQUESTED)[:200]:
            if services.auto_assign(c, by=request.user):
                assigned += 1
        return Response(ok("COLLECTION_ASSIGNED", data={"assigned": assigned}))


class AdminCollectionAssignView(APIView):
    """Manually (re)assign a collection to a specific agent."""

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        from cashcollections import services
        from core.app_errors import ok

        c = get_object_or_404(CashCollection, pk=pk)
        agent = get_object_or_404(
            User, pk=request.data.get("agent_id") or request.data.get("agentId"),
            role="agent")
        services.manual_assign(c, agent, by=request.user,
                               reason=request.data.get("reason", ""))
        return Response(ok("COLLECTION_ASSIGNED", data={"id": str(c.id), "agent": agent.name}))


class AdminCollectionDunningView(APIView):
    """Aging buckets (0-30/31-60/61-90/90+) + a dunning sweep to escalate aged dues."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from cashcollections import services

        return Response({"aging": services.aging_buckets()})

    def post(self, request):
        from cashcollections import services

        return Response({"escalated": services.run_dunning()})


class AdminCollectionPerformanceView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        from cashcollections import services

        agent = get_object_or_404(
            User, pk=request.query_params.get("agent_id"), role="agent")
        return Response(services.agent_performance(agent))


class AdminCollectionCommandCenterView(APIView):
    """Super-admin recovery command center: KPIs + aging buckets + active list."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from cashcollections import services

        today = timezone.localdate()
        collected_today = CashCollection.objects.filter(
            status__in=["collected", "partially_collected"], collected_at__date=today
        ).aggregate(s=Sum("collected_amount"))["s"] or ZERO
        open_qs = CashCollection.objects.exclude(status__in=CashCollection.TERMINAL)
        pending_amount = sum((c.remaining for c in open_qs), ZERO)
        return Response({
            "kpis": {
                "collectedToday": float(collected_today),
                "pendingAmount": float(pending_amount),
                "openCount": open_qs.count(),
                "disputed": open_qs.filter(status="disputed").count(),
                "escalated": open_qs.filter(escalated=True).count(),
            },
            "aging": services.aging_buckets(),
        })
