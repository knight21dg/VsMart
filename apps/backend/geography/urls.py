from django.urls import path

from .views import (
    AreaListView,
    DistrictListView,
    GeoZoneListView,
    ServiceableView,
    StateListView,
    StoreDetailView,
    StoreListView,
    VillageListView,
)

urlpatterns = [
    path("geography/states", StateListView.as_view()),
    path("geography/districts", DistrictListView.as_view()),
    path("geography/zones", GeoZoneListView.as_view()),
    path("geography/areas", AreaListView.as_view()),
    path("geography/villages", VillageListView.as_view()),
    path("geography/stores", StoreListView.as_view()),
    path("geography/stores/<int:pk>", StoreDetailView.as_view()),
    path("geography/serviceable", ServiceableView.as_view()),
]
