from decimal import Decimal

from django.db import transaction
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError, ok
from mediastore.models import MediaAsset
from mediastore.serving import serve_storage_key
from orders.models import Order, OrderStatus
from storeops.io_utils import field

from . import pickup_services
from .models import ReturnEvidence, ReturnItem, ReturnRequest
from .serializers import ReturnCreateSerializer, ReturnRequestSerializer

ZERO = Decimal("0.00")


class OrderReturnCreateView(APIView):
    """Raise a return/refund for a delivered order.

    Photos are mandatory — they're the evidence the pickup agent inspects the
    goods against at the door. Accepts multipart (`photos` files + `items` as a
    JSON string) or JSON. On success a pickup task is created and auto-assigned
    to a field agent immediately, so a return never waits on a human to dispatch.
    """

    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request, code):
        order = get_object_or_404(Order, code=code, user=request.user)
        if order.status != OrderStatus.DELIVERED:
            raise AppError("RETURN_NOT_ELIGIBLE",
                           message="Only delivered orders can be returned.")

        s = ReturnCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        items = s.validated_data.get("items") or []
        # getlist keeps every file when the client sends repeated `photos` parts;
        # the serializer's ListField only sees the last one under multipart.
        photos = request.FILES.getlist("photos") or []
        if not photos:
            photos = [f for f in (s.validated_data.get("photos") or [])]
        if not photos:
            raise AppError("RETURN_PHOTOS_REQUIRED")

        refund_amount = sum(
            (Decimal(str(field(it, "amount", 0) or 0)) for it in items), ZERO
        )
        if not items:
            refund_amount = order.total

        with transaction.atomic():
            ret = ReturnRequest.objects.create(
                user=request.user,
                order=order,
                reason=s.validated_data["reason"],
                description=s.validated_data.get("description", ""),
                refund_amount=refund_amount,
            )
            for it in items:
                ReturnItem.objects.create(
                    return_request=ret,
                    product_name=field(it, "productName", "") or "",
                    quantity=field(it, "quantity", 0) or 0,
                    amount=Decimal(str(field(it, "amount", 0) or 0)),
                )
            for photo in photos:
                pickup_services.add_evidence(
                    ret, request.user, photo=photo,
                    source=ReturnEvidence.Source.CUSTOMER,
                )

        # Dispatch outside the creation transaction: a notification or ranking
        # hiccup must never roll back the customer's return.
        task = pickup_services.create_pickup(ret, by=request.user)

        code_out = ("RETURN_PICKUP_ASSIGNED" if task.agent_id
                    else "RETURN_PICKUP_UNASSIGNED")
        return Response(
            ok(code_out, data=ReturnRequestSerializer(ret).data),
            status=201,
        )


def _customer_returns_qs(user):
    return (
        ReturnRequest.objects.filter(user=user)
        .select_related("order")
        .prefetch_related("items", "evidence", "pickup_tasks__agent")
    )


class ReturnListView(ListAPIView):
    serializer_class = ReturnRequestSerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return ReturnRequest.objects.none()
        return _customer_returns_qs(self.request.user)


class ReturnDetailView(APIView):
    def get(self, request, code):
        ret = get_object_or_404(_customer_returns_qs(request.user), code=code)
        return Response(ReturnRequestSerializer(ret).data)


class ReturnPhotoView(APIView):
    """Stream a return photo (medium variant) only to people allowed to see it:
    the return's customer, the assigned pickup agent, staff, or an active staff
    member of the order's OWN serving store. Everyone else gets 403."""

    def get(self, request, pk):
        try:
            ev = ReturnEvidence.objects.select_related(
                "return_request__order").get(pk=pk)
        except (ReturnEvidence.DoesNotExist, ValueError, TypeError):
            raise AppError("NOT_FOUND")

        ret = ev.return_request
        user = request.user
        is_staff = getattr(user, "role", "") in ("admin", "superadmin")
        is_customer = ret.user_id == user.id
        is_agent = ret.pickup_tasks.filter(agent=user).exists()
        is_store_staff = False
        store_id = getattr(ret.order, "store_id", None)
        if not (is_staff or is_customer or is_agent) and store_id:
            from storeops.models import StoreStaff

            is_store_staff = StoreStaff.objects.filter(
                user=user, store_id=store_id, is_active=True
            ).exists()
        if not (is_staff or is_customer or is_agent or is_store_staff):
            raise AppError("INSUFFICIENT_PERMISSIONS")

        try:
            asset = MediaAsset.objects.get(pk=ev.file_key)
        except (MediaAsset.DoesNotExist, ValueError, TypeError):
            raise AppError("NOT_FOUND")
        resp = serve_storage_key(asset.variant_key("medium"),
                                 content_type=asset.content_type)
        resp["Cache-Control"] = "private, max-age=60"
        return resp
