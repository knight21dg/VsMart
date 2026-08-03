"""Field-agent API for return pickups — the doorstep half of a return.

The agent sees the customer's photos, travels out, captures their own condition
photos, and settles the return on the spot: accept (whole or partial), reject
with a reason, or reschedule.
"""
from rest_framework.generics import ListAPIView
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError, ok
from core.permissions import IsAgent

from . import pickup_services
from .models import ReturnEvidence, ReturnPickupTask
from .serializers import (
    AgentPhotoSerializer,
    CompletePickupSerializer,
    RejectPickupSerializer,
    ReschedulePickupSerializer,
    ReturnPickupTaskSerializer,
)


def _base_qs():
    return ReturnPickupTask.objects.select_related(
        "return_request__order", "return_request__user", "agent"
    ).prefetch_related("return_request__items", "return_request__evidence")


def _task(request, pk):
    """Fetch a task the requesting agent owns (404 otherwise — an agent must not
    be able to probe which task ids exist)."""
    try:
        task = _base_qs().get(pk=pk, agent=request.user)
    except (ReturnPickupTask.DoesNotExist, ValueError, TypeError):
        raise AppError("NOT_FOUND")
    return task


def _data(task):
    return ReturnPickupTaskSerializer(task).data


class AgentReturnPickupListView(ListAPIView):
    """Open pickups assigned to this agent."""

    permission_classes = [IsAgent]
    serializer_class = ReturnPickupTaskSerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return ReturnPickupTask.objects.none()
        return _base_qs().filter(agent=self.request.user).exclude(
            status__in=ReturnPickupTask.TERMINAL)


class AgentReturnPickupHistoryView(ListAPIView):
    """Closed pickups this agent handled."""

    permission_classes = [IsAgent]
    serializer_class = ReturnPickupTaskSerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return ReturnPickupTask.objects.none()
        return _base_qs().filter(
            agent=self.request.user, status__in=ReturnPickupTask.TERMINAL)[:100]


class AgentReturnPickupDetailView(APIView):
    permission_classes = [IsAgent]

    def get(self, request, pk):
        return Response(_data(_task(request, pk)))


class AgentReturnPickupAcceptView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = pickup_services.accept(_task(request, pk), request.user)
        return Response(ok("RETURN_PICKUP_ASSIGNED", data=_data(task)))


class AgentReturnPickupDeclineView(APIView):
    """Decline the JOB (not the goods) — it goes back to the assignment pool."""

    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = pickup_services.reject_task(
            _task(request, pk), request.user,
            reason=request.data.get("reason", "") or "")
        return Response(ok("RETURN_PICKUP_RESCHEDULED", data=_data(task)))


class AgentReturnPickupEnRouteView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = pickup_services.en_route(_task(request, pk), request.user)
        return Response(ok("RETURN_PICKUP_ASSIGNED", data=_data(task)))


class AgentReturnPickupReachView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = pickup_services.reach(_task(request, pk), request.user)
        return Response(ok("RETURN_PICKUP_ASSIGNED", data=_data(task)))


class AgentReturnPickupPhotoView(APIView):
    """Capture the agent's own photo of the item's real condition. Required
    before a pickup can be completed."""

    permission_classes = [IsAgent]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request, pk):
        task = _task(request, pk)
        s = AgentPhotoSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        pickup_services.add_evidence(
            task.return_request, request.user,
            photo=d.get("photo"), file_key=d.get("photo_key", "") or "",
            source=ReturnEvidence.Source.AGENT, task=task,
            lat=d.get("latitude"), lng=d.get("longitude"),
        )
        return Response(ok("MEDIA_UPLOADED", data=_data(_task(request, pk))))


class AgentReturnPickupCompleteView(APIView):
    """Accept the return at the door. `decisions` (item id → accepted quantity)
    settles a partial accept; omitted lines settle in full."""

    permission_classes = [IsAgent]

    def post(self, request, pk):
        s = CompletePickupSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        raw = s.validated_data.get("decisions") or {}
        decisions = {}
        for k, v in raw.items():
            try:
                decisions[int(k)] = int(v)
            except (TypeError, ValueError):
                raise AppError("RETURN_QUANTITY_INVALID",
                               message=f"Invalid item id '{k}'.")
        task = pickup_services.complete(
            _task(request, pk), request.user,
            decisions=decisions, note=s.validated_data.get("note", ""))
        return Response(ok("RETURN_PICKUP_COMPLETED", data=_data(task)))


class AgentReturnPickupRejectView(APIView):
    """Refuse the goods at the door — closes the return as rejected."""

    permission_classes = [IsAgent]

    def post(self, request, pk):
        s = RejectPickupSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        task = pickup_services.reject_return(
            _task(request, pk), request.user,
            reason_code=s.validated_data["reason_code"],
            note=s.validated_data.get("note", ""))
        return Response(ok("RETURN_PICKUP_REJECTED", data=_data(task)))


class AgentReturnPickupRescheduleView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        s = ReschedulePickupSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        task = pickup_services.reschedule(
            _task(request, pk), request.user,
            reason_code=s.validated_data.get(
                "reason_code", ReturnPickupTask.ReasonCode.CUSTOMER_UNAVAILABLE),
            note=s.validated_data.get("note", ""),
            at=s.validated_data.get("at"))
        return Response(ok("RETURN_PICKUP_RESCHEDULED", data=_data(task)))
