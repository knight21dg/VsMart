from decimal import Decimal

from rest_framework import serializers

from .models import CashCollection, Payment


class PaymentSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    order_id = serializers.CharField(source="order.code", read_only=True, default=None)
    # Razorpay client config so the mobile SDK can open checkout from this one
    # response. key_id is the public Razorpay key (mock value when no real key is
    # configured, mirroring the mock-gateway fallback). currency defaults to INR.
    key_id = serializers.SerializerMethodField()
    currency = serializers.SerializerMethodField()

    class Meta:
        model = Payment
        fields = ["id", "purpose", "amount", "method", "gateway", "gateway_order_id",
                  "gateway_payment_id", "gateway_refund_id",
                  "status", "order_id", "created_at", "key_id", "currency"]

    def get_key_id(self, obj):
        from .gateway import get_public_key_id

        return get_public_key_id()

    def get_currency(self, obj):
        from django.conf import settings

        return getattr(settings, "PAYMENT_CURRENCY", "INR")


class StartPaymentSerializer(serializers.Serializer):
    purpose = serializers.ChoiceField(choices=["order", "repayment"])
    order_id = serializers.CharField(required=False, allow_blank=True)
    statement_id = serializers.IntegerField(required=False)
    # Accepted but NOT trusted for an order payment — the view derives the amount
    # from the order itself (see StartPaymentView). Kept in the contract because
    # the app still sends it and repayments legitimately choose an amount.
    amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, min_value=Decimal("0.01")
    )
    method = serializers.ChoiceField(choices=["upi", "card", "netbanking"])


class RepaySerializer(serializers.Serializer):
    # A repayment amount IS the customer's choice (part-payments are allowed), but
    # it must be a positive sum of money.
    amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, min_value=Decimal("0.01")
    )
    statement_id = serializers.IntegerField(required=False)
    method = serializers.ChoiceField(choices=["upi", "card", "netbanking"], default="upi")


class ConfirmPaymentSerializer(serializers.Serializer):
    """The Razorpay Checkout success triple, as the mobile SDK returns it."""

    razorpay_order_id = serializers.CharField()
    razorpay_payment_id = serializers.CharField()
    razorpay_signature = serializers.CharField()


class CashCollectionSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    customer = serializers.CharField(source="user.name", read_only=True)
    customer_phone = serializers.CharField(source="user.phone", read_only=True)

    class Meta:
        model = CashCollection
        fields = ["id", "amount", "status", "customer", "customer_phone",
                  "collected_at", "created_at"]
