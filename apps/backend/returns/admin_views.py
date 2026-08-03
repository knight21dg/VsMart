from rest_framework import status as http
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.pagination import EnvelopePagination
from core.permissions import IsAdmin

from . import admin_service
from .models import ReturnRequest


class ReturnsPagination(EnvelopePagination):
    """Standard envelope pagination for the returns queue.

    The page size was temporarily pinned to the old 200-row hard cap while the
    console still rendered no pager — dropping to the default then would have
    *reduced* what an operator could see. The page now sends ``?page=`` and
    renders a footer, so this is back to a normal working page size.
    """

    page_size = 50


class AdminReturnListView(APIView):
    """Admin returns/refunds queue — PAGINATED.

    Emits the standard ``{data, meta:{page,total,totalPages}}`` envelope via
    :class:`core.pagination.EnvelopePagination`. It previously returned a hard
    ``[:200]`` slice with no offset, so return 201 onwards was unreachable and
    nothing signalled the cut-off. ``data`` is still the row array, so existing
    callers keep working.

    A caller may still pass ``limit`` for a legacy unpaginated slice.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        p = request.query_params
        qs = admin_service.list_returns_qs(p.get("status"))
        # Legacy escape hatch: an explicit ?limit= returns a bare list as before.
        if p.get("limit"):
            limit = min(int(p["limit"] or 200), 200)
            return Response(admin_service.return_rows(qs[:limit]))
        paginator = ReturnsPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response(admin_service.return_rows(page))


class AdminReturnDetailView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, code):
        ret = get_object_or_404(
            ReturnRequest.objects.select_related("user", "order").prefetch_related("items"),
            code=code,
        )
        return Response(admin_service.return_detail(ret))


class AdminReturnStatusView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, code):
        ret = get_object_or_404(ReturnRequest, code=code)
        status = request.data.get("status")
        try:
            admin_service.set_return_status(ret, status, by=request.user)
        except ValueError as e:
            return Response(
                {"error": {"code": "bad_transition", "message": str(e), "fields": {}}},
                status=http.HTTP_400_BAD_REQUEST,
            )
        record_audit(request.user, "return.status", target=ret, after={"status": status})
        ret = ReturnRequest.objects.select_related("user", "order").prefetch_related("items").get(pk=ret.pk)
        return Response(admin_service.return_detail(ret))
