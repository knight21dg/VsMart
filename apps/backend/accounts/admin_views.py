"""Employee/HR admin (spec §MODULE 15): the staff directory (super-admins, admins,
agents) with today's on-duty status for field agents."""
from rest_framework.response import Response
from rest_framework.views import APIView

from core.permissions import IsAdmin

from .models import Role, User


class AdminEmployeesView(APIView):
    """GET /admin/employees — all non-customer staff with role + today's duty status."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from django.utils import timezone

        staff = list(
            User.objects.exclude(role=Role.CUSTOMER).order_by("role", "name")
        )
        # On-duty map for agents (today).
        on_duty = {}
        try:
            from agents.models import AgentAttendance

            today = timezone.localdate()
            for a in AgentAttendance.objects.filter(date=today, on_duty=True).values_list(
                "agent_id", flat=True
            ):
                on_duty[a] = True
        except Exception:
            pass

        # Zone assignments per agent (where each agent works).
        zone_map = {}
        try:
            from zones.models import ZoneAgent

            for za in ZoneAgent.objects.select_related("zone").values("agent_id", "zone__name"):
                zone_map.setdefault(za["agent_id"], []).append(za["zone__name"])
        except Exception:
            pass

        role = request.query_params.get("role")
        rows = []
        # Keyed by ROLE, which is data — and the renderer camelCases every key it
        # sees, so a `store_staff` bucket left here goes out as `storeStaff` and
        # the console's "Store Staff" tile read undefined and showed 0 forever.
        # Building the wire name here means what this code says is what ships.
        summary = {"superadmin": 0, "admin": 0, "agent": 0, "storeStaff": 0, "total": 0}
        wire = {Role.STORE_STAFF: "storeStaff"}
        for u in staff:
            bucket = wire.get(u.role, u.role)
            summary[bucket] = summary.get(bucket, 0) + 1
            summary["total"] += 1
            if role and u.role != role:
                continue
            rows.append(
                {
                    "id": str(u.id),
                    "name": u.name or u.phone,
                    "phone": u.phone,
                    "email": u.email or "",
                    "role": u.role,
                    "isActive": u.is_active,
                    "onDuty": bool(on_duty.get(u.id)) if u.role == Role.AGENT else None,
                    "zones": zone_map.get(u.id, []) if u.role == Role.AGENT else [],
                    "createdAt": u.created_at,
                }
            )
        return Response({"employees": rows, "summary": summary})


class AdminDeletionRequestsView(APIView):
    """GET /admin/deletion-requests — list account-deletion requests (optionally ?status=)."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from .models import AccountDeletionRequest
        from .serializers import DeletionRequestAdminSerializer

        qs = AccountDeletionRequest.objects.all()
        status_f = request.query_params.get("status")
        if status_f:
            qs = qs.filter(status=status_f)
        return Response({"requests": DeletionRequestAdminSerializer(qs, many=True).data})


class AdminDeletionRequestDetailView(APIView):
    """PATCH /admin/deletion-requests/<id> — update status/note (approve/reject/complete)."""

    permission_classes = [IsAdmin]

    def patch(self, request, pk):
        from django.utils import timezone

        from core.app_errors import AppError

        from .models import AccountDeletionRequest
        from .serializers import DeletionRequestAdminSerializer

        req = AccountDeletionRequest.objects.filter(pk=pk).first()
        if not req:
            raise AppError("NOT_FOUND")
        new_status = request.data.get("status")
        valid = {c[0] for c in AccountDeletionRequest.Status.choices}
        if new_status in valid:
            req.status = new_status
            if new_status in ("completed", "rejected"):
                req.processed_at = timezone.now()
                req.processed_by = request.user
        if "note" in request.data:
            req.note = request.data.get("note", "")
        req.save()
        return Response(DeletionRequestAdminSerializer(req).data)
