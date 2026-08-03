"""Admin accounts-payable API: supplier invoices, payments and aging."""
from django.shortcuts import get_object_or_404
from rest_framework import serializers
from rest_framework.generics import ListCreateAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.app_errors import AppError, ok
from core.permissions import IsAdmin

from .ap_services import (
    approve_invoice,
    cancel_invoice,
    payables_aging,
    record_payment,
)
from .models import PurchaseInvoice, VendorPayment


class VendorPaymentSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    created_by_name = serializers.CharField(
        source="created_by.name", read_only=True, default=None
    )

    class Meta:
        model = VendorPayment
        fields = ["id", "amount", "method", "paid_on", "reference", "notes",
                  "created_by_name", "created_at"]


class PurchaseInvoiceSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    supplier_id = serializers.PrimaryKeyRelatedField(
        source="supplier", queryset=PurchaseInvoice._meta.get_field("supplier").related_model.objects.all()
    )
    supplier_name = serializers.CharField(source="supplier.name", read_only=True)
    balance_due = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )

    class Meta:
        model = PurchaseInvoice
        fields = [
            "id", "supplier_id", "supplier_name", "grn_id", "purchase_order_id",
            "store_id", "invoice_number", "invoice_date", "due_date",
            "subtotal", "tax", "total", "amount_paid", "balance_due",
            "status", "notes", "created_at",
        ]
        read_only_fields = ["status", "amount_paid", "created_at"]

    def validate(self, attrs):
        total = attrs.get("total", getattr(self.instance, "total", None))
        if total is not None and total <= 0:
            raise serializers.ValidationError(
                {"total": "An invoice total must be greater than zero."}
            )
        due = attrs.get("due_date", getattr(self.instance, "due_date", None))
        dated = attrs.get("invoice_date", getattr(self.instance, "invoice_date", None))
        if due and dated and due < dated:
            raise serializers.ValidationError(
                {"due_date": "The due date can't precede the invoice date."}
            )
        return attrs


class AdminPurchaseInvoiceListView(ListCreateAPIView):
    """GET/POST /admin/procurement/invoices"""

    permission_classes = [IsAdmin]
    serializer_class = PurchaseInvoiceSerializer

    def get_queryset(self):
        qs = PurchaseInvoice.objects.select_related("supplier")
        p = self.request.query_params
        status = p.get("status")
        if status == "outstanding":
            qs = qs.filter(status__in=[PurchaseInvoice.Status.AWAITING,
                                       PurchaseInvoice.Status.PARTIAL])
        elif status:
            qs = qs.filter(status=status)
        if p.get("supplier"):
            qs = qs.filter(supplier_id=p["supplier"])
        if p.get("store"):
            qs = qs.filter(store_id=p["store"])
        search = (p.get("search") or "").strip()
        if search:
            from django.db.models import Q

            qs = qs.filter(Q(invoice_number__icontains=search)
                           | Q(supplier__name__icontains=search))
        return qs

    def perform_create(self, serializer):
        invoice = serializer.save(created_by=self.request.user)
        record_audit(self.request.user, "ap.invoice.create", target=invoice,
                     after={"total": str(invoice.total)})


class AdminPurchaseInvoiceDetailView(APIView):
    """GET /admin/procurement/invoices/<pk> — invoice + its payment history."""

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        invoice = get_object_or_404(
            PurchaseInvoice.objects.select_related("supplier"), pk=pk
        )
        data = PurchaseInvoiceSerializer(invoice).data
        data["payments"] = VendorPaymentSerializer(
            invoice.payments.select_related("created_by"), many=True
        ).data
        return Response(ok("OK", data=data))


class AdminInvoiceActionView(APIView):
    """POST /admin/procurement/invoices/<pk>/<action> — approve | cancel."""

    permission_classes = [IsAdmin]

    def post(self, request, pk, action):
        invoice = get_object_or_404(PurchaseInvoice, pk=pk)
        if action == "approve":
            invoice = approve_invoice(invoice, request.user)
        elif action == "cancel":
            invoice = cancel_invoice(invoice, request.user)
        else:
            raise AppError("VALIDATION_ERROR",
                           message="action must be 'approve' or 'cancel'.")
        record_audit(request.user, f"ap.invoice.{action}", target=invoice,
                     after={"status": invoice.status})
        return Response(ok("OK", data=PurchaseInvoiceSerializer(invoice).data))


class AdminVendorPaymentView(APIView):
    """POST /admin/procurement/invoices/<pk>/payments — pay a supplier."""

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        invoice = get_object_or_404(PurchaseInvoice, pk=pk)
        payment = record_payment(
            invoice,
            amount=request.data.get("amount"),
            method=(request.data.get("method") or "bank"),
            paid_on=request.data.get("paidOn") or request.data.get("paid_on"),
            reference=request.data.get("reference") or "",
            notes=request.data.get("notes") or "",
            actor=request.user,
        )
        invoice.refresh_from_db()
        record_audit(request.user, "ap.payment", target=invoice,
                     after={"amount": str(payment.amount)})
        return Response(ok("OK", data={
            "payment": VendorPaymentSerializer(payment).data,
            "invoice": PurchaseInvoiceSerializer(invoice).data,
        }), status=201)


class AdminPayablesAgingView(APIView):
    """GET /admin/procurement/payables — outstanding balance, bucketed."""

    permission_classes = [IsAdmin]

    def get(self, request):
        p = request.query_params
        return Response(ok("OK", data=payables_aging(
            store=p.get("store") or None,
            supplier=p.get("supplier") or None,
        )))
