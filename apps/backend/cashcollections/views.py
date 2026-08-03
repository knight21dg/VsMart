"""Collections API. Customer views list their pending dues + receipts; agent views
drive the recovery state machine via cashcollections.services (scoped to the
assigned agent — never the whole pool)."""
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import ok
from core.permissions import IsAgent, IsCustomer
from payments.models import CashCollection, Payment
from payments.serializers import CashCollectionSerializer, PaymentSerializer

from . import services
from .serializers import (
    CollectionOtpSerializer,
    CollectSerializer,
    CollectionTaskSerializer,
    FailCollectionSerializer,
)


# ── Customer ─────────────────────────────────────────────
class PendingCollectionsView(ListAPIView):
    serializer_class = CashCollectionSerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return CashCollection.objects.none()
        return CashCollection.objects.filter(user=self.request.user).exclude(
            status__in=CashCollection.TERMINAL)


class CollectionHistoryView(ListAPIView):
    serializer_class = CashCollectionSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return CashCollection.objects.none()
        return CashCollection.objects.filter(
            user=self.request.user,
            status__in=["collected", "partially_collected"])


class CollectionReceiptsView(ListAPIView):
    serializer_class = PaymentSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Payment.objects.none()
        return Payment.objects.filter(
            user=self.request.user, method="cash", purpose="repayment")


# ── Agent (scoped to the assigned agent) ─────────────────
def _coll(request, pk):
    return get_object_or_404(CashCollection, pk=pk, agent=request.user)


def _data(coll):
    return CollectionTaskSerializer(coll).data


class AssignedCollectionsView(ListAPIView):
    serializer_class = CollectionTaskSerializer
    permission_classes = [IsAgent]
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return CashCollection.objects.none()
        return CashCollection.objects.filter(agent=self.request.user).exclude(
            status__in=CashCollection.TERMINAL).select_related("user")


class CollectionDetailView(APIView):
    permission_classes = [IsAgent]

    def get(self, request, pk):
        return Response(_data(_coll(request, pk)))


class CollectionAcceptView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        return Response(ok("COLLECTION_ACCEPTED",
                           data=_data(services.accept(_coll(request, pk), request.user))))


class CollectionRejectView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        coll = services.reject(_coll(request, pk), request.user,
                               reason=request.data.get("reason", ""))
        return Response(_data(coll))


class CollectionEnRouteView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        return Response(ok("COLLECTION_EN_ROUTE",
                           data=_data(services.en_route(_coll(request, pk), request.user))))


class CollectionReachView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        return Response(ok("COLLECTION_REACHED",
                           data=_data(services.reach(_coll(request, pk), request.user))))


class CollectionRequestOtpView(APIView):
    """Agent enters the amount being collected → send an amount-bound OTP to the
    customer to confirm exactly that figure."""

    permission_classes = [IsAgent]

    def post(self, request, pk):
        coll = services.request_collection_otp(
            _coll(request, pk), request.user, request.data.get("amount"))
        return Response(ok("COLLECTION_OTP_SENT", data=_data(coll)))


class CustomerCollectionConfirmView(APIView):
    """CUSTOMER-facing: the pending in-app confirmation for the signed-in customer.
    Returns the amount the agent is collecting and the OTP to read out — shown on
    a screen inside the app, never sent over SMS."""

    permission_classes = [IsCustomer]

    def get(self, request):
        coll = (
            CashCollection.objects.filter(user=request.user, status="reached")
            .select_related("agent", "collection_otp")
            .order_by("-updated_at")
            .first()
        )
        otp = getattr(coll, "collection_otp", None) if coll else None
        if (coll is None or otp is None or otp.verified or otp.locked
                or otp.amount is None):
            return Response({"pending": None})
        return Response({"pending": {
            "collectionId": str(coll.id),
            "amount": str(otp.amount),
            "otp": otp.code,
            "agentName": getattr(coll.agent, "name", "") or "The agent",
        }})


class CollectionOtpVerifyView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        s = CollectionOtpSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        coll = services.verify_otp(_coll(request, pk), request.user, s.validated_data["otp"])
        return Response(ok("COLLECTION_OTP_VERIFIED", data=_data(coll)))


class CollectionCollectView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        s = CollectSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        coll = services.collect(_coll(request, pk), request.user,
                                amount=s.validated_data.get("amount"))
        code = "COLLECTION_COMPLETED" if coll.status == "collected" else "PARTIAL_PAYMENT"
        return Response(ok(code, data=_data(coll)))


class CollectionDisputeView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        coll = services.dispute(_coll(request, pk), request.user,
                                note=request.data.get("note", ""))
        return Response(_data(coll))


class CollectionFailView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        s = FailCollectionSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        coll = services.fail(_coll(request, pk), request.user,
                             reason_code=s.validated_data["reason_code"],
                             note=s.validated_data.get("note", ""))
        return Response(_data(coll))
