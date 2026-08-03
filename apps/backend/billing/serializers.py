from rest_framework import serializers

from .models import Invoice, InvoiceItem, Receipt


class InvoiceItemSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = InvoiceItem
        fields = ["id", "name", "quantity", "price"]


class InvoiceListSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    order_id = serializers.CharField(source="order.code", read_only=True, default=None)

    class Meta:
        model = Invoice
        fields = ["id", "number", "amount", "gst", "status", "issued_at", "order_id"]


class InvoiceDetailSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    order_id = serializers.CharField(source="order.code", read_only=True, default=None)
    items = InvoiceItemSerializer(many=True, read_only=True)

    class Meta:
        model = Invoice
        fields = [
            "id", "number", "amount", "gst", "status", "issued_at",
            "order_id", "pdf_key", "items", "created_at",
        ]


class ReceiptListSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    payment_id = serializers.CharField(read_only=True, default=None)

    class Meta:
        model = Receipt
        fields = ["id", "number", "amount", "method", "issued_at", "payment_id"]


class ReceiptDetailSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    payment_id = serializers.CharField(read_only=True, default=None)

    class Meta:
        model = Receipt
        fields = [
            "id", "number", "amount", "method", "issued_at",
            "payment_id", "created_at",
        ]
