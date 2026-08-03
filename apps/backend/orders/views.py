from django.db import IntegrityError
from rest_framework import status as http
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from addresses.models import Address
from cart.services import cart_bill, get_cart
from core.app_errors import AppError, ok
from core.permissions import IsAgent
from offers.services import coupon_discount

from .models import DeliveryAssignment, Order, OrderTracking
from .serializers import (
    CheckoutSerializer,
    DeliveryStatusSerializer,
    OrderDetailSerializer,
    OrderListSerializer,
    TrackingSerializer,
)
from .services import (
    CheckoutError,
    advance_status,
    cancel_order,
    place_order,
    reorder_into_cart,
    reorder_plan,
)


class CheckoutView(APIView):
    throttle_scope = "checkout"

    def post(self, request):
        s = CheckoutSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        address = get_object_or_404(
            Address, pk=s.validated_data["address_id"], user=request.user
        )
        # Resolve the coupon discount server-side from the cart subtotal so the order
        # total reflects the same discount the client previewed via /coupons/validate.
        code = s.validated_data.get("coupon_code", "")
        discount = 0
        if code:
            subtotal = cart_bill(get_cart(request.user))["subtotal"]
            # Pass the buyer so a personal (loyalty-issued) coupon resolves for
            # its owner and is rejected for anyone else.
            discount = coupon_discount(code, subtotal, user=request.user)
        idem = request.headers.get("Idempotency-Key", "")
        try:
            order = place_order(
                request.user,
                address=address,
                payment_method=s.validated_data["payment_method"],
                delivery_slot=s.validated_data.get("delivery_slot", ""),
                coupon_discount=discount,
                coupon_code=code,
                credit_plan=s.validated_data.get("credit_plan", ""),
                idempotency_key=idem,
            )
        except IntegrityError:
            # A concurrent double-submit with the same key won the race and committed
            # first; the unique constraint rolled THIS attempt back. Return the order
            # that did land so the customer sees one order, not an error.
            order = Order.objects.filter(
                user=request.user, idempotency_key=idem
            ).first() if idem else None
            if order is None:
                raise
        except CheckoutError as e:
            # The delivery address moved into a different store's zone: clear the now-
            # invalid cart server-side (place_order rolled back, so this commits in the
            # view's own transaction) so the customer rebuilds it for their new area.
            if e.code == "STORE_CHANGED":
                cart = get_cart(request.user)
                cart.items.all().delete()
                cart.store = None
                cart.save(update_fields=["store"])
            # Re-raise as an actionable, catalog-coded error (KYC_REQUIRED,
            # LIMIT_EXCEEDED, OUT_OF_STOCK, OUTSIDE_SERVICE_AREA, STORE_CHANGED, …).
            raise AppError(e.code, message=str(e))
        return Response(
            ok("ORDER_ACCEPTED", data=OrderDetailSerializer(order).data),
            status=http.HTTP_201_CREATED,
        )


class OrderListView(ListAPIView):
    # Full detail (items + timeline) so the app renders order cards and history
    # rails in a single call; prefetch keeps it to a fixed number of queries.
    serializer_class = OrderDetailSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Order.objects.none()
        qs = (
            Order.objects.filter(user=self.request.user)
            .prefetch_related("items", "timeline")
        )
        status_q = self.request.query_params.get("status")
        if status_q == "active":
            # In-flight orders the customer should still see on the "active" tab.
            # Mirrors orders.models.ACTIVE_STATUSES (incl. placed + ready_for_dispatch),
            # which were previously omitted and hid those orders.
            qs = qs.filter(status__in=[
                "placed", "pending", "confirmed", "packed",
                "ready_for_dispatch", "out_for_delivery",
            ])
        elif status_q:
            qs = qs.filter(status=status_q)
        return qs


def _get_order(request, code):
    return get_object_or_404(Order, code=code, user=request.user)


class OrderDetailView(APIView):
    def get(self, request, code):
        return Response(OrderDetailSerializer(_get_order(request, code)).data)


def _customer_delivery_otp(order) -> str:
    """The active handover code for `order`, or "".

    Only from the order's CURRENT task while it's out_for_delivery/reached, and
    only while the code is still spendable (unverified, not locked out).
    """
    task = (
        order.delivery_tasks
        .filter(status__in=["out_for_delivery", "reached"])
        .order_by("-attempt_no", "-id")
        .first()
    )
    otp = getattr(task, "delivery_otp", None) if task is not None else None
    if otp is None or otp.verified or otp.locked:
        return ""
    return otp.code


class OrderTrackingView(APIView):
    def get(self, request, code):
        """Read-only. Returns an unsaved row when the order has no tracking yet.

        This used to ``get_or_create``, so merely opening the tracking sheet — or
        the app's poll doing so every few seconds — wrote a row for every order
        ever viewed, including cancelled and long-delivered ones. A GET must not
        persist; the row is created when a delivery agent is actually assigned
        (``delivery.services._seed_tracking_identity``).
        """
        order = _get_order(request, code)
        tracking = OrderTracking.objects.filter(order=order).first()
        if tracking is None:
            # Unsaved instance: the serializer needs `.order` for the store/dest
            # coordinates, and the customer still gets the route endpoints and
            # order status before a rider is assigned.
            tracking = OrderTracking(order=order)
        data = TrackingSerializer(tracking).data
        # The handover OTP, for the CUSTOMER's own eyes. It used to reach them
        # only as an in-app notification — buried in the inbox at the exact
        # moment a rider was standing at the door asking for it. Present only
        # while a rider is genuinely out with the parcel and the code is still
        # usable; empty otherwise (this endpoint is already owner-scoped).
        data["delivery_otp"] = _customer_delivery_otp(order)
        return Response(data)


class OrderInvoiceView(APIView):
    """Customer-facing branded PDF invoice for the user's own order."""

    def get(self, request, code):
        from django.http import HttpResponse

        from .invoice import build_invoice_pdf

        order = get_object_or_404(
            Order.objects.select_related("store").prefetch_related("items"),
            code=code, user=request.user,
        )
        # A tax invoice exists only for a DELIVERED and PAID order. Anything
        # earlier would document a sale that hasn't happened (undelivered) or
        # money never received (unpaid) — both wrong paper.
        if order.status != "delivered" or order.payment_status != "paid":
            raise AppError(
                "CONFLICT",
                message="The invoice is available once the order is "
                        "delivered and paid.",
            )
        pdf = build_invoice_pdf(order)
        resp = HttpResponse(pdf, content_type="application/pdf")
        resp["Content-Disposition"] = f'inline; filename="invoice-{order.code}.pdf"'
        return resp


class OrderCancelView(APIView):
    def post(self, request, code):
        order = _get_order(request, code)
        try:
            order = cancel_order(order)
        except CheckoutError as e:
            raise AppError(e.code, message=str(e))
        return Response(
            ok("ORDER_CANCELLED", data=OrderDetailSerializer(order).data))


def _reorder_line_payload(line):
    """Customer-facing shape for one planned reorder line."""
    product = line["product"]
    variant = line["variant"]
    # Carries everything a client needs to build a cart line itself, so the app
    # doesn't have to re-fetch each product one at a time to reorder.
    return {
        "product_id": str(product.id) if product is not None else None,
        "variant_id": str(variant.id) if variant is not None else None,
        "name": line["name"],
        "brand": product.brand if product is not None else "",
        "unit": product.unit if product is not None else "",
        "quantity": line["quantity"],
        "price": line["price"],
        "mrp": line["mrp"],
        "image_url": (
            (variant.image_url if variant is not None and variant.image_url else "")
            or (product.image_url if product is not None else "")
        ),
        "available": line["available"],
        "reason": line["reason"],
    }


class OrderReorderPreviewView(APIView):
    """What "Reorder" would put in the cart, without touching it.

    Reorder used to mutate the cart on a single tap and say nothing about the lines
    it dropped. This backs a review step so the customer sees what's coming back,
    at today's prices, and what is no longer available — before they commit.
    """

    def get(self, request, code):
        order = _get_order(request, code)
        lines = reorder_plan(order, request.user)
        return Response({
            "items": [_reorder_line_payload(line) for line in lines],
            "available_count": sum(1 for line in lines if line["available"]),
            "unavailable_count": sum(1 for line in lines if not line["available"]),
        })


class OrderReorderView(APIView):
    def post(self, request, code):
        order = _get_order(request, code)
        cart, lines = reorder_into_cart(order, request.user)
        from cart.views import _cart_payload

        payload = _cart_payload(cart)
        # Report what could NOT be added. Previously these were skipped in silence,
        # so a five-item reorder could quietly become a two-item cart.
        payload["skipped"] = [
            _reorder_line_payload(line) for line in lines if not line["available"]
        ]
        payload["added_count"] = sum(1 for line in lines if line["available"])
        return Response(payload, status=http.HTTP_201_CREATED)


# ── Agent ────────────────────────────────────────────────
class AgentDeliveriesView(ListAPIView):
    serializer_class = OrderListSerializer
    permission_classes = [IsAgent]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Order.objects.none()
        return Order.objects.filter(delivery__agent=self.request.user)


class AgentDeliveryStatusView(APIView):
    """Legacy agent status endpoint, kept for older builds.

    It used to write ``DeliveryAssignment.status`` and call ``advance_status``
    directly, which skipped EVERY gate in :func:`delivery.services.complete_delivery`
    — the reached-location precondition, the delivery OTP, and the mandatory
    proof-of-delivery photo. An agent could mark an order delivered from home, and
    because it never touched ``DeliveryTask`` the two state machines were left
    permanently disagreeing (order delivered, task still out_for_delivery), with no
    audit row, no realtime broadcast, and no earnings computed.

    It now delegates to the guarded delivery services, so there is exactly one way
    to complete a delivery. When the order has no active DeliveryTask there is
    nothing to guard with, and completing is refused rather than done unguarded.
    """

    permission_classes = [IsAgent]

    def post(self, request, code):
        from delivery.models import DeliveryTask
        from delivery.services import complete_delivery, fail_delivery

        order = get_object_or_404(Order, code=code, delivery__agent=request.user)
        s = DeliveryStatusSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        new = s.validated_data["status"]

        task = (
            DeliveryTask.objects.filter(order=order, agent=request.user)
            .exclude(status__in=["delivered", "failed", "reassigned", "cancelled"])
            .order_by("-id")
            .first()
        )
        if task is None:
            raise AppError(
                "DELIVERY_TASK_REQUIRED",
                message="This delivery isn't assigned to you as an active task.",
            )

        if new == "delivered":
            complete_delivery(task, request.user)
        elif new == "picked":
            # Mirrors the guarded pick-up transition; the order follows from it.
            from delivery.services import pick_up

            pick_up(task, request.user)
        elif new == "failed":
            # Previously a silent no-op: the assignment said failed while the order
            # stayed "out for delivery" forever and the response reported success.
            fail_delivery(task, request.user, reason_code="agent_reported")

        order.refresh_from_db()
        DeliveryAssignment.objects.filter(order=order).update(status=new)
        return Response({"status": order.status})
