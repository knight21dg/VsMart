from rest_framework import serializers

from .models import Area, District, GeoZone, State, Village, Warehouse


class StateSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = State
        fields = ["id", "name", "code"]


class DistrictSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    state_id = serializers.CharField(read_only=True)

    class Meta:
        model = District
        fields = ["id", "state_id", "name", "code"]


class GeoZoneSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    district_id = serializers.CharField(read_only=True)

    class Meta:
        model = GeoZone
        fields = ["id", "district_id", "name", "code"]


class AreaSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    zone_id = serializers.CharField(read_only=True)

    class Meta:
        model = Area
        fields = ["id", "zone_id", "name", "code"]


class VillageSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    area_id = serializers.CharField(read_only=True)

    class Meta:
        model = Village
        fields = ["id", "area_id", "name", "code"]


class WarehouseSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    area_id = serializers.CharField(read_only=True, allow_null=True)

    class Meta:
        model = Warehouse
        fields = [
            "id",
            "name",
            "code",
            "area_id",
            "latitude",
            "longitude",
            "serviceable_pincodes",
            "is_active",
        ]
