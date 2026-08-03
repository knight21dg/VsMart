from django.utils import timezone
from rest_framework import status as http
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.services import record_audit
from core.app_errors import ok
from core.audit import write_audit
from core.permissions import IsAdmin
from core.response_codes import CATALOG
from orders.models import Order

from . import admin_service, services
from .models import DeliveryTask


class AdminDeliveryDashboardView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(admin_service.delivery_dashboard())


class AdminDeliveryListView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        p = request.query_params
        limit = min(int(p.get("limit", 200) or 200), 500)
        return Response(admin_service.delivery_list(p, limit=limit))


class AdminDeliveryAgentsView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(admin_service.agent_load())


class AdminDeliveryReassignView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        task = get_object_or_404(DeliveryTask, pk=pk)
        agent_id = request.data.get("agent_id") or request.data.get("agentId")
        agent = get_object_or_404(User, pk=agent_id, role="agent")
        new_task = services.reassign(task, agent, by=request.user,
                                     reason=request.data.get("reason", "Admin reassign"))
        record_audit(request.user, "delivery.reassign", target=task,
                     after={"agent": str(agent.id)})
        return Response(ok("AGENT_ASSIGNED",
                           data={"taskId": new_task.id, "agent": agent.name}))


class AdminDeliveryAssignView(APIView):
    """Manually assign an order to a specific agent (overrides auto-assignment)."""

    permission_classes = [IsAdmin]

    def post(self, request):
        code = request.data.get("order_code") or request.data.get("orderCode")
        agent_id = request.data.get("agent_id") or request.data.get("agentId")
        order = get_object_or_404(Order, code=code)
        agent = get_object_or_404(User, pk=agent_id, role="agent")
        task = services.manual_assign(order, agent, by=request.user,
                                      reason=request.data.get("reason", ""))
        return Response(ok("DELIVERY_ASSIGNED",
                           data={"taskId": task.id, "agent": agent.name}))


class AdminReattemptQueueView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        tasks = DeliveryTask.objects.filter(
            status=DeliveryTask.Status.FAILED
        ).select_related("order", "agent")[:200]
        return Response([
            {"id": t.id, "orderCode": t.order.code, "agent": getattr(t.agent, "name", None),
             "attemptNo": t.attempt_no, "reason": t.failure_reason, "note": t.failure_note,
             "failedAt": t.failed_at} for t in tasks
        ])


class AdminReattemptView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        task = get_object_or_404(DeliveryTask, pk=pk)
        mode = request.data.get("mode", "today")  # today|tomorrow|reassign|return
        agent = None
        if mode == "reassign":
            agent = get_object_or_404(
                User, pk=request.data.get("agent_id") or request.data.get("agentId"),
                role="agent")
        result = services.reattempt(task, mode=mode, by=request.user, agent=agent)
        record_audit(request.user, "delivery.reattempt", target=task, after={"mode": mode})
        return Response(ok("REATTEMPT_SCHEDULED", data={"taskId": result.id}))


class AdminReturnToStoreView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        task = get_object_or_404(DeliveryTask, pk=pk)
        services.return_to_store(task, by=request.user)
        record_audit(request.user, "delivery.return_to_store", target=task)
        return Response(ok("RETURN_TO_STORE", data={"orderCode": task.order.code}))


class AdminManualVerifyView(APIView):
    """Override an OTP lockout after store-side manual verification of the customer."""

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        task = get_object_or_404(DeliveryTask, pk=pk)
        task.otp_verified = True
        task.manual_verification_required = False
        task.save(update_fields=["otp_verified", "manual_verification_required", "updated_at"])
        write_audit("DELIVERY_OTP_VERIFIED", CATALOG["DELIVERY_OTP_VERIFIED"],
                    actor=request.user, success=True, entity_type="delivery_task",
                    entity_id=task.id, message="Manual verification override")
        record_audit(request.user, "delivery.manual_verify", target=task)
        return Response(ok("DELIVERY_OTP_VERIFIED", data={"taskId": task.id}))


class AdminAgentPerformanceView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        agent = get_object_or_404(
            User, pk=request.query_params.get("agent_id"), role="agent")
        return Response(services.agent_performance(agent))


class AdminCommandCenterView(APIView):
    """Super-admin live fleet view: KPIs + active deliveries + per-zone breakdown."""

    permission_classes = [IsAdmin]

    def get(self, request):
        active_states = ["assigned", "accepted", "picked_up", "out_for_delivery", "reached"]
        today = timezone.localdate()
        all_today = DeliveryTask.objects.filter(created_at__date=today)
        delivered = all_today.filter(status="delivered").count()
        failed = all_today.filter(status="failed").count()
        total_today = all_today.count()
        active = list(
            DeliveryTask.objects.filter(status__in=active_states)
            .select_related("order", "order__tracking", "order__zone", "agent")[:200]
        )
        durations = [
            (t.delivered_at - t.out_for_delivery_at).total_seconds() / 60
            for t in all_today.filter(status="delivered")
            if t.delivered_at and t.out_for_delivery_at
        ]
        zones = {}
        rows = []
        for t in active:
            z = getattr(t.order.zone, "name", None) if t.order.zone_id else None
            zones[z or "Unzoned"] = zones.get(z or "Unzoned", 0) + 1
            tr = getattr(t.order, "tracking", None)
            rows.append({
                "id": t.id, "orderCode": t.order.code, "status": t.status,
                "agent": getattr(t.agent, "name", None),
                "zone": z,
                # Live rider position (updated by the agent's GPS pings) + destination.
                "lat": float(tr.latitude) if (tr and tr.latitude is not None) else None,
                "lng": float(tr.longitude) if (tr and tr.longitude is not None) else None,
                "eta": getattr(tr, "eta", "") if tr else "",
                "destLat": float(t.dest_lat) if t.dest_lat is not None else None,
                "destLng": float(t.dest_lng) if t.dest_lng is not None else None,
                "address": (t.order.address_snapshot or {}).get("formatted", ""),
            })
        return Response({
            "kpis": {
                "successRate": round(delivered / total_today * 100, 1) if total_today else 0.0,
                "avgMinutes": round(sum(durations) / len(durations), 1) if durations else None,
                "activeDeliveries": len(active),
                "deliveredToday": delivered,
                "failedToday": failed,
                "reattemptRate": round(failed / total_today * 100, 1) if total_today else 0.0,
            },
            "active": rows,
            "zones": [{"zone": k, "active": v} for k, v in zones.items()],
        })


class AdminDeliveryStatusView(APIView):
    permission_classes = [IsAdmin]

    # "started" isn't a real DeliveryTask.Status value — it's a UI-only alias
    # the frontend's "Mark Out for Delivery" button sends, which
    # admin_service.set_status() translates into the order-level
    # out_for_delivery transition. Excluding it from the allowlist meant that
    # button had 400'd unconditionally since it was added — found while
    # testing this session's "delivered" guard (below).
    VALID_STATUSES = frozenset(DeliveryTask.Status.values) | {"started"}

    def post(self, request, pk):
        task = get_object_or_404(DeliveryTask, pk=pk)
        status = request.data.get("status")
        if status not in self.VALID_STATUSES:
            return Response(
                {"error": {"code": "bad_status", "message": f"Invalid status '{status}'", "fields": {}}},
                status=http.HTTP_400_BAD_REQUEST,
            )
        admin_service.set_status(task, status, by=request.user)
        record_audit(request.user, "delivery.status", target=task, after={"status": status})
        return Response({"status": task.status})
