"""Agent-facing batch (guided-route) API. The batch envelope: read the current
trip, accept it, and do the store pickup handoff. Per-stop actions (arrive / OTP /
POD / deliver, and collect) stay on the existing single-task + collection endpoints
— the serialized stops carry each `taskId` / `collectionId`."""
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError, ok
from core.permissions import IsAgent

from . import assignment_engine, batch_services
from .models import DeliveryBatch


class AgentBatchCurrentView(APIView):
    permission_classes = [IsAgent]

    def get(self, request):
        b = batch_services.agent_current_batch(request.user)
        return Response(ok("OK", data=(batch_services.serialize_batch(b) if b else None)))


class AgentBatchDetailView(APIView):
    permission_classes = [IsAgent]

    def get(self, request, batch_id):
        b = get_object_or_404(DeliveryBatch, pk=batch_id, agent=request.user)
        batch_services.maybe_complete_batch(b)
        b.refresh_from_db()
        return Response(ok("OK", data=batch_services.serialize_batch(b)))


class AgentBatchAcceptView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, batch_id):
        b = get_object_or_404(DeliveryBatch, pk=batch_id, agent=request.user)
        try:
            batch_services.batch_accept(b, request.user)
        except PermissionError:
            raise AppError("INSUFFICIENT_PERMISSIONS")
        b.refresh_from_db()
        return Response(ok("OK", data=batch_services.serialize_batch(b)))


class AgentBatchPickupView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, batch_id):
        b = get_object_or_404(DeliveryBatch, pk=batch_id, agent=request.user)
        code = request.data.get("code") or request.data.get("pickupCode") or ""
        try:
            batch_services.batch_pickup(b, request.user, code)
        except PermissionError:
            raise AppError("INSUFFICIENT_PERMISSIONS")
        except ValueError as e:
            raise AppError("VALIDATION_ERROR", message=str(e))
        b.refresh_from_db()
        return Response(ok("OK", data=batch_services.serialize_batch(b)))


class AgentBatchAbandonView(APIView):
    """Agent rejects (pre-pickup) or reports a mid-route issue (breakdown). Unfinished
    stops go back to the queue and are immediately reassigned to other agents."""

    permission_classes = [IsAgent]

    def post(self, request, batch_id):
        b = get_object_or_404(DeliveryBatch, pk=batch_id, agent=request.user)
        if b.status in DeliveryBatch.TERMINAL:
            raise AppError("VALIDATION_ERROR", message="This trip is already closed.")
        reason = (request.data.get("reason") or "agent_abandoned").strip()
        assignment_engine.reassign_batch(
            b, reason=reason, by=request.user, exclude_agent_ids=[request.user.id]
        )
        return Response(ok("OK", data=None))
