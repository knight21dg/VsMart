from rest_framework import status as http
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.services import record_audit
from core.pagination import EnvelopePagination
from core.permissions import IsAdmin

from . import admin_service
from .models import Order, OrderStatus


def _order(code):
    return get_object_or_404(Order, code=code)


class AdminOrderDashboardView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(admin_service.order_dashboard())


class AdminOrderListView(APIView):
    """Filterable/sortable admin orders list — PAGINATED.

    Emits the standard ``{data, meta:{page,total,totalPages}}`` envelope via
    :class:`core.pagination.EnvelopePagination`, so the console can page through
    every match. It previously sliced to a hard ``limit`` (max 300) with no
    offset, which made every order past that limit unreachable.

    A caller may still pass ``limit`` for a legacy unpaginated slice.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        p = request.query_params
        qs = admin_service.search_orders_qs(p)
        # Legacy escape hatch: an explicit ?limit= returns a bare list as before.
        if p.get("limit"):
            limit = min(int(p["limit"] or 100), 300)
            return Response(admin_service.summarize_orders(qs[:limit]))
        paginator = EnvelopePagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response(
            admin_service.summarize_orders(page)
        )


class AdminOrderQueuesView(APIView):
    """Packing / dispatch board — orders bucketed by operational stage."""

    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(admin_service.order_queues(request.query_params.get("store")))


class AdminOrderDetailView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, code):
        order = (
            Order.objects.select_related("user", "store", "zone", "delivery", "delivery__agent")
            .prefetch_related("items", "timeline")
            .filter(code=code)
            .first()
        )
        if not order:
            return Response(
                {"error": {"code": "not_found", "message": "Order not found", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        return Response(admin_service.order_detail(order))


class AdminOrderStatusView(APIView):
    """Every status EXCEPT the two that have their own guarded subsystem.

    "delivered" only means something once the assigned agent has proved it —
    reached the location, verified the OTP, attached a photo
    (`delivery.services.complete_delivery`). Writing it here used to skip all
    of that (and, now that delivery is what triggers the credit-ledger debit
    and stock fulfilment, would let staff charge a customer and release stock
    for a delivery nobody actually proved happened). "returned"/
    "partially_returned" have their own subsystem too (`returns.admin_service`
    — refund + inventory reversal); writing the status directly here creates
    an order that LOOKS returned with no return record and no refund at all.
    Both must go through their real flow, not this raw status write.
    """

    permission_classes = [IsAdmin]

    BLOCKED = {
        "delivered": (
            "An order can only be marked delivered by the assigned agent's "
            "own OTP + photo verification. If the OTP is genuinely stuck, use "
            "the delivery's Manual Verify override — not this control."
        ),
        "returned": (
            "Process this as a return (Returns & Refunds) so the refund and "
            "stock reversal actually happen — setting the status alone does "
            "neither."
        ),
        "partially_returned": (
            "Process this as a return (Returns & Refunds) so the refund and "
            "stock reversal actually happen — setting the status alone does "
            "neither."
        ),
    }

    def post(self, request, code):
        order = _order(code)
        status = request.data.get("status")
        if status not in OrderStatus.values:
            return Response(
                {"error": {"code": "bad_status", "message": f"Invalid status '{status}'", "fields": {}}},
                status=http.HTTP_400_BAD_REQUEST,
            )
        if status in self.BLOCKED:
            return Response(
                {"error": {"code": "status_requires_guarded_flow",
                           "message": self.BLOCKED[status], "fields": {}}},
                status=http.HTTP_400_BAD_REQUEST,
            )
        from .services import CheckoutError

        try:
            admin_service.set_order_status(
                order, status, by=request.user, note=request.data.get("note", "")
            )
        except CheckoutError as e:
            return Response(
                {"error": {"code": "cannot_transition", "message": str(e), "fields": {}}},
                status=http.HTTP_409_CONFLICT,
            )
        record_audit(request.user, "order.status", target=order, after={"status": status})
        return Response(admin_service.order_detail(order))


class AdminOrderInvoiceView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, code):
        from django.http import HttpResponse

        from .invoice import build_invoice_pdf

        order = (
            Order.objects.select_related("store").prefetch_related("items")
            .filter(code=code).first()
        )
        if not order:
            return Response(
                {"error": {"code": "not_found", "message": "Order not found", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        pdf = build_invoice_pdf(order)
        resp = HttpResponse(pdf, content_type="application/pdf")
        disposition = "inline" if request.query_params.get("inline") else "attachment"
        resp["Content-Disposition"] = f'{disposition}; filename="invoice-{order.code}.pdf"'
        return resp


class AdminOrderAssignAgentView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, code):
        order = _order(code)
        agent_id = request.data.get("agent_id") or request.data.get("agentId")
        agent = get_object_or_404(User, pk=agent_id, role="agent")
        admin_service.assign_agent(order, agent, by=request.user)
        record_audit(request.user, "order.assign_agent", target=order,
                     after={"agent": str(agent.id)})
        return Response(admin_service.order_detail(order))
