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

    def validate_code(self, value):
        """Normalise a blank code to NULL.

        ``code`` is ``unique=True, null=True``. SQL lets any number of rows hold
        NULL, but an empty *string* is a value — so the second zone saved with a
        blank code collided on the unique index and surfaced as a raw integrity
        error rather than anything the operator could act on.
        """
        value = (value or "").strip()
        return value or None

    def validate_name(self, value):
        """Refuse a second zone with the same name.

        Nothing stopped this before: ``name`` carries no unique constraint, so
        re-submitting the zone form (or a double-clicked Save) quietly created a
        duplicate "Kakinada", and serviceability then resolved a point to
        whichever of the two won on priority — a coin toss between two different
        stores. Matching is case- and whitespace-insensitive because
        "kakinada " and "Kakinada" are the same place to everyone but the DB.
        """
        name = (value or "").strip()
        if not name:
            raise serializers.ValidationError("A zone name is required.")
        clash = Zone.objects.filter(name__iexact=name)
        if self.instance is not None:
            clash = clash.exclude(pk=self.instance.pk)
        existing = clash.first()
        if existing is not None:
            raise serializers.ValidationError(
                f"{existing.name} zone already exists. Edit that zone instead of "
                f"creating a second one with the same name."
            )
        return name

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

    def validate_code(self, value):
        """Store codes are unique and are typed by hand, so a clash is likely.
        Say which store already owns the code instead of letting DRF's stock
        "store with this code already exists." leave the operator guessing."""
        code = (value or "").strip()
        if not code:
            raise serializers.ValidationError("A store code is required.")
        clash = Store.objects.filter(code__iexact=code)
        if self.instance is not None:
            clash = clash.exclude(pk=self.instance.pk)
        existing = clash.first()
        if existing is not None:
            raise serializers.ValidationError(
                f"Code “{existing.code}” is already used by {existing.name}. "
                f"Pick a different code."
            )
        return code

    def validate_name(self, value):
        name = (value or "").strip()
        if not name:
            raise serializers.ValidationError("A store name is required.")
        return name


class ExpansionRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExpansionRequest
        fields = [
            "id", "name", "mobile", "village", "area", "pincode",
            "latitude", "longitude", "created_at",
        ]
        read_only_fields = ["id", "created_at"]
