from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

from rest_framework import serializers

from .models import Address

#: Storage precision for coordinates. 6dp ≈ 11 cm — far finer than any consumer
#: GPS fix, so rounding to it loses nothing real.
_COORD_QUANT = Decimal("0.000001")


class CoordinateField(serializers.DecimalField):
    """A lat/lng that *rounds* excess precision instead of rejecting it.

    Device GPS routinely reports 7+ decimal places (e.g. 16.9890751). The model
    stores 6, and a plain DecimalField answers that with "Ensure that there are
    no more than 6 decimal places" — a 400 on both coordinates that made saving
    an address impossible for anyone who pinned a location, while the exact same
    address saved fine without coordinates.

    Extra precision is noise, not user error, so we quantize it and accept.
    """

    def to_internal_value(self, data):
        if isinstance(data, (int, float, str)) and str(data).strip() != "":
            try:
                data = Decimal(str(data)).quantize(
                    _COORD_QUANT, rounding=ROUND_HALF_UP
                )
            except (InvalidOperation, ValueError):
                pass  # let the parent raise the normal, clearer error
        return super().to_internal_value(data)


class AddressSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    formatted = serializers.CharField(read_only=True)
    latitude = CoordinateField(
        max_digits=9, decimal_places=6, required=False, allow_null=True
    )
    longitude = CoordinateField(
        max_digits=9, decimal_places=6, required=False, allow_null=True
    )

    class Meta:
        model = Address
        fields = [
            "id", "label", "name", "phone", "line1", "village", "area", "landmark",
            "city", "district", "state", "pincode", "latitude", "longitude",
            "is_default", "formatted",
        ]
