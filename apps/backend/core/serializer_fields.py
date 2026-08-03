"""Shared DRF field types."""
from rest_framework import serializers


class CoordinateField(serializers.DecimalField):
    """A GPS coordinate from a device.

    Location APIs (Android/iOS) hand the app full-precision doubles —
    ``17.092308765432198`` — and a strict ``DecimalField(decimal_places=6)``
    REJECTED them, so a rider standing at the customer's door was told
    "the information entered isn't valid" when they pressed I've Arrived.
    Precision beyond 6 dp is ~11 cm — noise, not information. Quantize it
    instead of refusing the delivery over it. Junk input (non-numeric) still
    falls through to the normal DecimalField error.
    """

    def __init__(self, **kwargs):
        kwargs.setdefault("max_digits", 9)
        kwargs.setdefault("decimal_places", 6)
        super().__init__(**kwargs)

    def to_internal_value(self, data):
        try:
            data = format(round(float(data), 6), ".6f")
        except (TypeError, ValueError):
            pass  # let DecimalField raise its own, well-worded error
        return super().to_internal_value(data)
