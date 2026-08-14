"""Agent-facing delivery API. Every action is delegated to delivery.services so the
state machine, geofence, OTP lockout, completion guard, audit and analytics are
enforced in one place. Views never mutate status directly."""
import mimetypes

from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError, ok
from core.permissions import IsAgent
from mediastore.models import MediaAsset
from mediastore.serving import serve_storage_key

from . import services
from .models import DeliveryTask
from .serializers import (
    ArriveSerializer,
    DeliveryTaskSerializer,
    FailSerializer,
    LocationSerializer,
    OtpSerializer,
    PhotoSerializer,
)


def _task(request, pk):
    return get_object_or_404(DeliveryTask, pk=pk, agent=request.user)


def _data(task):
    return DeliveryTaskSerializer(task).data


class AssignedDeliveriesView(ListAPIView):
    serializer_class = DeliveryTaskSerializer
    permission_classes = [IsAgent]
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return DeliveryTask.objects.none()
        from django.db.models import Q

        # The agent's PENDING work. Closed tasks drop off (including `failed`,
        # which only the store can move on) — with one exception:
        # a delivered COD order whose cash hasn't been confirmed is still an open
        # action (the money is in nobody's book yet), so it stays on the list
        # until Collect Cash is done.
        return DeliveryTask.objects.filter(agent=self.request.user).filter(
            ~Q(status__in=DeliveryTask.CLOSED_FOR_AGENT)
            | (Q(status="delivered")
               & Q(order__payment_method="cod")
               & ~Q(order__payment_status="paid"))
        )


class DeliveryDetailView(APIView):
    permission_classes = [IsAgent]

    def get(self, request, pk):
        return Response(_data(_task(request, pk)))


class DeliveryAcceptView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = services.accept(_task(request, pk), request.user)
        return Response(ok("AGENT_ASSIGNED", data=_data(task)))


class DeliveryRejectView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = services.reject(_task(request, pk), request.user,
                               reason=request.data.get("reason", ""))
        return Response(_data(task))


class DeliveryPickupView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = services.pick_up(_task(request, pk), request.user)
        return Response(ok("PICKED_UP", data=_data(task)))


class DeliveryOutForDeliveryView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = services.out_for_delivery(_task(request, pk), request.user)
        return Response(ok("OUT_FOR_DELIVERY", data=_data(task)))


class DeliveryStartView(APIView):
    """Legacy combined step: pickup → out-for-delivery (kept for the existing app)."""

    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = _task(request, pk)
        if task.status == DeliveryTask.Status.ACCEPTED:
            services.pick_up(task, request.user)
        task = services.out_for_delivery(task, request.user)
        return Response(ok("OUT_FOR_DELIVERY", data=_data(task)))


class DeliveryArriveView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        s = ArriveSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        task = services.arrive(_task(request, pk), request.user,
                               s.validated_data["latitude"], s.validated_data["longitude"])
        return Response(ok("REACHED_LOCATION", data=_data(task)))


class DeliveryOtpView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        s = OtpSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        task = services.verify_otp(_task(request, pk), request.user, s.validated_data["otp"])
        return Response(ok("DELIVERY_OTP_VERIFIED", data=_data(task)))


class DeliveryPhotoView(APIView):
    """Submit proof-of-delivery evidence. Accepts a multipart `photo` image file
    (routed through the self-hosted media engine → stored as a private POD asset,
    its MediaAsset id saved into photo_key) OR a legacy JSON `photo_key` string.
    JSON-only callers keep working unchanged."""

    permission_classes = [IsAgent]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request, pk):
        s = PhotoSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        services.add_evidence(
            _task(request, pk), request.user,
            d.get("photo_key", "") or "", photo=d.get("photo"),
            lat=d.get("latitude"), lng=d.get("longitude"))
        return Response(ok("MEDIA_UPLOADED", data=_data(_task(request, pk))))


class DeliveryProofPhotoView(APIView):
    """Stream a proof-of-delivery photo (medium variant) only to people allowed to
    see it: the order's customer, the delivering agent, staff (admin/superadmin),
    or an active staff member of the order's OWN serving store. Everyone else gets
    403; a task with no stored photo gives 404. The photo_key on the task is a
    private MediaAsset UUID written by the media engine."""

    def get(self, request, pk):
        try:
            task = DeliveryTask.objects.select_related("order").get(pk=pk)
        except DeliveryTask.DoesNotExist:
            raise AppError("NOT_FOUND")

        user = request.user
        is_staff = getattr(user, "role", "") in ("admin", "superadmin")
        is_agent = task.agent_id == user.id
        is_customer = getattr(task.order, "user_id", None) == user.id
        is_store_staff = False
        if not (is_staff or is_agent or is_customer) and task.order.store_id:
            from storeops.models import StoreStaff

            is_store_staff = StoreStaff.objects.filter(
                user=user, store_id=task.order.store_id, is_active=True
            ).exists()
        if not (is_staff or is_agent or is_customer or is_store_staff):
            raise AppError("INSUFFICIENT_PERMISSIONS")

        if not task.photo_key:
            raise AppError("NOT_FOUND")
        try:
            asset = MediaAsset.objects.get(pk=task.photo_key)
        except (MediaAsset.DoesNotExist, ValueError, TypeError):
            # photo_key isn't a resolvable MediaAsset (e.g. a legacy loose string).
            raise AppError("NOT_FOUND")

        resp = serve_storage_key(asset.variant_key("medium"), content_type=asset.content_type)
        resp["Cache-Control"] = "private, max-age=60"
        return resp


class DeliveryCompleteView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = services.complete_delivery(_task(request, pk), request.user)
        return Response(ok("DELIVERY_COMPLETED", data=_data(task)))


class DeliveryFailView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        s = FailSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        task = services.fail_delivery(
            _task(request, pk), request.user, reason_code=d["reason_code"],
            note=d.get("note", ""), photo_key=d.get("photo_key", ""),
            lat=d.get("latitude"), lng=d.get("longitude"))
        return Response(_data(task))


class DeliveryLocationView(APIView):
    permission_classes = [IsAgent]

    def post(self, request):
        s = LocationSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        task = None
        tid = s.validated_data.get("task_id")
        if tid:
            task = DeliveryTask.objects.filter(pk=tid, agent=request.user).first()
        services.log_location(
            request.user, s.validated_data["latitude"], s.validated_data["longitude"],
            task=task, accuracy=s.validated_data.get("accuracy_m"))
        return Response({"status": "ok"})


class DeliveryReturnInitiateView(APIView):
    """Agent starts bringing failed goods back to the store. The store confirms
    physical receipt from its panel, which is when stock restores and the order
    closes — the two halves of the handover are deliberately separate people."""

    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = services.initiate_return(_task(request, pk), request.user)
        return Response(ok("DELIVERY_FAILED", data=_data(task)))


class DeliveryCollectCodView(APIView):
    """Agent confirms the customer's COD cash after handover: order → PAID and
    the notes enter the cash book (they show in the agent's in-hand figure and
    flow through the deposit → finance-verification chain)."""

    permission_classes = [IsAgent]

    def post(self, request, pk):
        from django.db.models import Sum as _Sum

        from payments.cashbook_services import undeposited_collections

        task = _task(request, pk)
        services.collect_cod_cash(
            task, request.user,
            reference=str(request.data.get("reference") or ""))
        in_hand = (
            undeposited_collections(agent=request.user)
            .aggregate(s=_Sum("collected_amount"))["s"] or 0
        )
        data = _data(task)
        data["cashInHand"] = in_hand
        return Response(ok("PAYMENT_RECEIVED", data=data))


class AgentCashInHandView(APIView):
    """The physical cash this agent is carrying (collected, not yet deposited)."""

    permission_classes = [IsAgent]

    def get(self, request):
        from django.db.models import Count as _Count, Sum as _Sum

        from payments.cashbook_services import undeposited_collections

        agg = undeposited_collections(agent=request.user).aggregate(
            amount=_Sum("collected_amount"), count=_Count("id"))
        return Response({
            "in_hand": agg["amount"] or 0,
            "collections": agg["count"] or 0,
        })
