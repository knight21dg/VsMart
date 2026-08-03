from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError
from mediastore.serving import serve_storage_key

from .models import Invoice, Receipt
from .services import generate_invoice_pdf
from .serializers import (
    InvoiceDetailSerializer,
    InvoiceListSerializer,
    ReceiptDetailSerializer,
    ReceiptListSerializer,
)


class InvoiceListView(ListAPIView):
    serializer_class = InvoiceListSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Invoice.objects.none()
        return Invoice.objects.filter(user=self.request.user)


class InvoiceDetailView(APIView):
    def get(self, request, pk):
        invoice = get_object_or_404(
            Invoice.objects.prefetch_related("items"), pk=pk, user=request.user
        )
        return Response(InvoiceDetailSerializer(invoice).data)


class InvoicePdfView(APIView):
    """Stream an invoice PDF only to people allowed to see it: the customer who
    owns the invoice, or staff (admin/superadmin). Everyone else gets 403. The
    PDF is served from default_storage via X-Accel-Redirect (prod) / FileResponse
    (dev); the permission check runs before any bytes are released."""

    def get(self, request, pk):
        try:
            invoice = Invoice.objects.get(pk=pk)
        except Invoice.DoesNotExist:
            raise AppError("NOT_FOUND")
        user = request.user
        is_staff = getattr(user, "role", "") in ("admin", "superadmin")
        if not (is_staff or invoice.user_id == user.id):
            raise AppError("INSUFFICIENT_PERMISSIONS")
        # Lazy-generate on first fetch (only reached after the permission gate).
        if not invoice.pdf_key:
            generate_invoice_pdf(invoice)
        resp = serve_storage_key(invoice.pdf_key, content_type="application/pdf")
        resp["Cache-Control"] = "private, max-age=60"
        return resp


class ReceiptListView(ListAPIView):
    serializer_class = ReceiptListSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Receipt.objects.none()
        return Receipt.objects.filter(user=self.request.user)


class ReceiptDetailView(APIView):
    def get(self, request, pk):
        receipt = get_object_or_404(Receipt, pk=pk, user=request.user)
        return Response(ReceiptDetailSerializer(receipt).data)
