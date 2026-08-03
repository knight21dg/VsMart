from django.db.models import Q
from rest_framework.generics import ListAPIView, RetrieveAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Area, District, GeoZone, State, Village, Warehouse
from .serializers import (
    AreaSerializer,
    DistrictSerializer,
    GeoZoneSerializer,
    StateSerializer,
    VillageSerializer,
    WarehouseSerializer,
)


class StateListView(ListAPIView):
    pagination_class = None
    serializer_class = StateSerializer

    def get_queryset(self):
        return State.objects.all()


class DistrictListView(ListAPIView):
    pagination_class = None
    serializer_class = DistrictSerializer

    def get_queryset(self):
        qs = District.objects.all()
        state = self.request.query_params.get("state")
        if state:
            qs = qs.filter(state_id=state)
        return qs


class GeoZoneListView(ListAPIView):
    pagination_class = None
    serializer_class = GeoZoneSerializer

    def get_queryset(self):
        qs = GeoZone.objects.all()
        district = self.request.query_params.get("district")
        if district:
            qs = qs.filter(district_id=district)
        return qs


class AreaListView(ListAPIView):
    pagination_class = None
    serializer_class = AreaSerializer

    def get_queryset(self):
        qs = Area.objects.all()
        zone = self.request.query_params.get("zone")
        if zone:
            qs = qs.filter(zone_id=zone)
        q = self.request.query_params.get("q")
        if q:
            qs = qs.filter(Q(name__icontains=q) | Q(code__icontains=q))
        return qs


class VillageListView(ListAPIView):
    pagination_class = None
    serializer_class = VillageSerializer

    def get_queryset(self):
        qs = Village.objects.all()
        area = self.request.query_params.get("area")
        if area:
            qs = qs.filter(area_id=area)
        return qs


class StoreListView(ListAPIView):
    pagination_class = None
    serializer_class = WarehouseSerializer

    def get_queryset(self):
        return Warehouse.objects.filter(is_active=True)


class StoreDetailView(RetrieveAPIView):
    serializer_class = WarehouseSerializer
    queryset = Warehouse.objects.all()


class ServiceableView(APIView):
    def get(self, request):
        pincode = request.query_params.get("pincode", "").strip()
        warehouse = None
        if pincode:
            for wh in Warehouse.objects.filter(is_active=True):
                pincodes = [str(p) for p in (wh.serviceable_pincodes or [])]
                if pincode in pincodes:
                    warehouse = wh
                    break
        return Response(
            {
                "serviceable": warehouse is not None,
                "warehouse": warehouse.name if warehouse else None,
            }
        )
