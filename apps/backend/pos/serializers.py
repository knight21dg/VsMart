from rest_framework import serializers

from accounts.models import User
from catalog.models import Product, ProductVariant
from inventory.models import Warehouse

from .models import (
    CashDrawer,
    DayClosing,
    HeldCart,
    POSPayment,
    POSRefund,
    POSSession,
    POSTransaction,
    POSTransactionItem,
)


# ── Reads ────────────────────────────────────────────────
class POSSessionSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    cashier_id = serializers.CharField(read_only=True)
    warehouse_id = serializers.CharField(read_only=True)

    class Meta:
        model = POSSession
        fields = [
            "id", "cashier_id", "warehouse_id", "status", "terminal", "opening_cash",
            "opened_at", "closed_at",
        ]


class POSTransactionItemSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)
    variant_id = serializers.CharField(read_only=True, allow_null=True)

    class Meta:
        model = POSTransactionItem
        fields = [
            "id", "product_id", "variant_id", "name", "quantity", "unit_price",
            "discount", "tax", "line_total",
        ]


class POSPaymentSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = POSPayment
        fields = ["id", "method", "amount", "reference", "created_at"]


class POSRefundSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = POSRefund
        fields = ["id", "method", "amount", "reference", "created_at"]


class POSTransactionSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    session_id = serializers.CharField(read_only=True)
    customer_id = serializers.CharField(read_only=True, allow_null=True)
    original_id = serializers.CharField(read_only=True, allow_null=True)
    items = POSTransactionItemSerializer(many=True, read_only=True)
    payments = POSPaymentSerializer(many=True, read_only=True)
    refunds = POSRefundSerializer(many=True, read_only=True)

    class Meta:
        model = POSTransaction
        fields = [
            "id", "code", "type", "session_id", "customer_id", "original_id",
            "subtotal", "tax", "discount", "total", "credit_used", "change_due",
            "payment_status", "is_voided", "voided_at", "note", "items", "payments",
            "refunds", "created_at",
        ]


class CashDrawerSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = CashDrawer
        fields = ["id", "type", "amount", "note", "created_at"]


class DayClosingSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    session_id = serializers.CharField(read_only=True)

    class Meta:
        model = DayClosing
        fields = [
            "id", "session_id", "opening_cash", "cash_sales", "cash_refunds",
            "cash_in", "cash_out", "upi_sales", "card_sales", "credit_sales",
            "expected_cash", "counted_cash", "variance", "total_sales",
            "transaction_count", "notes", "closed_at",
        ]


class HeldCartSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    session_id = serializers.CharField(read_only=True)
    customer_id = serializers.CharField(read_only=True, allow_null=True)

    class Meta:
        model = HeldCart
        fields = ["id", "session_id", "customer_id", "label", "payload", "created_at"]


# ── Inputs ───────────────────────────────────────────────
class SessionOpenSerializer(serializers.Serializer):
    warehouse = serializers.PrimaryKeyRelatedField(
        queryset=Warehouse.objects.all(), required=False
    )
    opening_cash = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, default=0
    )


class SessionCloseSerializer(serializers.Serializer):
    counted_cash = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, allow_null=True
    )
    notes = serializers.CharField(required=False, allow_blank=True)


class CashMovementSerializer(serializers.Serializer):
    type = serializers.ChoiceField(choices=["pay_in", "pay_out", "drop"])
    amount = serializers.DecimalField(max_digits=12, decimal_places=2)
    note = serializers.CharField(required=False, allow_blank=True)


class CheckoutLineSerializer(serializers.Serializer):
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    variant_id = serializers.PrimaryKeyRelatedField(
        source="variant", queryset=ProductVariant.objects.all(),
        required=False, allow_null=True,
    )
    qty = serializers.IntegerField(min_value=1)
    discount = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, default=0
    )


class PaymentInputSerializer(serializers.Serializer):
    method = serializers.ChoiceField(choices=["cash", "upi", "card", "credit"])
    amount = serializers.DecimalField(max_digits=12, decimal_places=2)
    reference = serializers.CharField(required=False, allow_blank=True)


class CheckoutSerializer(serializers.Serializer):
    customer_id = serializers.PrimaryKeyRelatedField(
        source="customer", queryset=User.objects.all(),
        required=False, allow_null=True,
    )
    items = CheckoutLineSerializer(many=True)
    payments = PaymentInputSerializer(many=True, required=False)
    discount = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, default=0
    )
    note = serializers.CharField(required=False, allow_blank=True)
    allow_oversell = serializers.BooleanField(required=False, default=False)


class ReturnLineSerializer(serializers.Serializer):
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    qty = serializers.IntegerField(min_value=1)


class ReturnSerializer(serializers.Serializer):
    original_id = serializers.PrimaryKeyRelatedField(
        source="original", queryset=POSTransaction.objects.all()
    )
    items = ReturnLineSerializer(many=True)
    reason = serializers.CharField(required=False, allow_blank=True)
    refund_method = serializers.ChoiceField(
        choices=["cash", "upi", "card", "credit"], required=False, allow_null=True
    )


class RefundSerializer(serializers.Serializer):
    transaction_id = serializers.PrimaryKeyRelatedField(
        source="transaction", queryset=POSTransaction.objects.all()
    )
    method = serializers.ChoiceField(choices=["cash", "upi", "card", "credit"])
    amount = serializers.DecimalField(max_digits=12, decimal_places=2)
    reference = serializers.CharField(required=False, allow_blank=True)


class VoidSerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True)


class HoldCartSerializer(serializers.Serializer):
    label = serializers.CharField(required=False, allow_blank=True)
    customer_id = serializers.PrimaryKeyRelatedField(
        source="customer", queryset=User.objects.all(),
        required=False, allow_null=True,
    )
    items = CheckoutLineSerializer(many=True)
