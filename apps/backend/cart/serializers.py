from rest_framework import serializers

from catalog.models import Product, ProductVariant

from .models import CartItem

# Per-line ceiling. Generous for a real grocery basket, low enough that a runaway
# stepper or a scripted call can't build an order the store could never fulfil.
MAX_LINE_QUANTITY = 99


class CartItemSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)
    name = serializers.CharField(source="product.name", read_only=True)
    brand = serializers.CharField(source="product.brand", read_only=True)
    unit = serializers.CharField(source="product.unit", read_only=True)
    image_url = serializers.CharField(source="product.image_url", read_only=True)
    price = serializers.DecimalField(
        source="price_snapshot", max_digits=12, decimal_places=2, read_only=True
    )
    mrp = serializers.DecimalField(
        source="product.mrp", max_digits=12, decimal_places=2, read_only=True
    )
    line_total = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )

    class Meta:
        model = CartItem
        fields = [
            "id", "product_id", "name", "brand", "unit", "image_url",
            "price", "mrp", "quantity", "line_total",
        ]


def validate_variant_scope(attrs):
    """A variant must belong to the product it's being added against.

    The variant queryset is every variant in the catalog, and
    ``cart.services.upsert_item`` prices a line as
    ``product.price + variant.price_delta``. Unscoped, that let a caller pair a
    ₹2,000 product with a *different* product's variant carrying a −₹1,900
    delta and have ``place_order`` charge ₹100 — invisible in the UI, because
    /cart/quote and /cart/validate both scope the variant correctly and so
    display the honest bill.

    Shared by the add (POST) and replace (PUT) paths deliberately: two copies of
    a money guard is one copy that drifts.
    """
    variant = attrs.get("variant")
    product = attrs.get("product")
    if variant is not None and product is not None and variant.product_id != product.id:
        raise serializers.ValidationError(
            {"variant_id": ["This option doesn't belong to that product."]}
        )
    return attrs


class AddCartItemSerializer(serializers.Serializer):
    product_id = serializers.PrimaryKeyRelatedField(
        queryset=Product.objects.filter(is_active=True), source="product"
    )
    variant_id = serializers.PrimaryKeyRelatedField(
        queryset=ProductVariant.objects.all(),
        source="variant",
        required=False,
        allow_null=True,
    )
    # A cart line's quantity is a real basket, not an integer field. Unbounded, a
    # held "+" or a scripted call builds qty in the thousands, which every layer
    # accepts until the reserve fails at Pay.
    quantity = serializers.IntegerField(min_value=0, max_value=MAX_LINE_QUANTITY,
                                        default=1)

    def validate(self, attrs):
        return validate_variant_scope(attrs)


class ReplaceCartLineSerializer(serializers.Serializer):
    """One line of a whole-cart PUT. Same shape as an add, but the quantity is
    ABSOLUTE (the cart becomes exactly this) rather than accumulating."""

    product_id = serializers.PrimaryKeyRelatedField(
        queryset=Product.objects.filter(is_active=True), source="product"
    )
    variant_id = serializers.PrimaryKeyRelatedField(
        queryset=ProductVariant.objects.all(),
        source="variant",
        required=False,
        allow_null=True,
    )
    quantity = serializers.IntegerField(min_value=0, max_value=MAX_LINE_QUANTITY)

    def validate(self, attrs):
        return validate_variant_scope(attrs)


class ReplaceCartSerializer(serializers.Serializer):
    items = ReplaceCartLineSerializer(many=True)


class UpdateCartItemSerializer(serializers.Serializer):
    quantity = serializers.IntegerField(min_value=0, max_value=MAX_LINE_QUANTITY)
