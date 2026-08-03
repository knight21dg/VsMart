from rest_framework import serializers

from stores.models import Store

from .models import ExpansionRequest, Zone


class ZoneSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    store_name = serializers.CharField(source="store.name", read_only=True)

    class Meta:
        model = Zone
        fields = [
            "id", "name", "code", "polygon_geojson",
            "center_lat", "center_lng", "radius_km", "pincodes",
            "store", "store_name", "is_active", "credit_enabled",
            "estimated_delivery_minutes", "priority",
            "delivery_fee", "free_delivery_threshold", "min_order",
            "platform_fee_value",
        ]

    def validate_polygon_geojson(self, value):
        """Accept a Feature / FeatureCollection / bare geometry, but require a
        Polygon or MultiPolygon so the serviceability engine can resolve it."""
        if value in (None, "", {}):
            return None
        from .serviceability import _geometry

        geom = _geometry(value)
        if not isinstance(geom, dict) or geom.get("type") not in ("Polygon", "MultiPolygon"):
            raise serializers.ValidationError(
                "polygon_geojson must be a GeoJSON Polygon or MultiPolygon (or a "
                "Feature wrapping one)."
            )
        coords = geom.get("coordinates")
        if not coords:
            raise serializers.ValidationError("polygon_geojson has no coordinates.")
        return value


class StoreSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Store
        fields = [
            "id", "code", "name", "address", "latitude", "longitude",
            "phone", "gstin", "status", "warehouse",
            "accepting_orders", "opens_at", "closes_at", "daily_order_capacity",
        ]


class ExpansionRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExpansionRequest
        fields = [
            "id", "name", "mobile", "village", "area", "pincode",
            "latitude", "longitude", "created_at",
        ]
        read_only_fields = ["id", "created_at"]
