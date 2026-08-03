from django.urls import path

from .admin_views import IntegrationSettingsView
from .geo_views import GeoPlaceDetailView, GeoPlacesAutocompleteView, GeoReverseView
from .maps_views import (
    GeoDistanceMatrixView,
    GeoGeolocateView,
    GeoRouteView,
    GeoSnapToRoadsView,
    GeoValidateAddressView,
)
from .views import (
    AppConfigView,
    FeatureFlagsView,
    FeedbackView,
    GlobalSearchView,
    MaintenanceStatusView,
    ResponseCodesView,
    UploadView,
    VersionView,
)

urlpatterns = [
    path("version", VersionView.as_view()),
    path("app-config", AppConfigView.as_view()),
    path("maintenance-status", MaintenanceStatusView.as_view()),
    path("feature-flags", FeatureFlagsView.as_view()),
    path("response-codes", ResponseCodesView.as_view()),
    path("uploads", UploadView.as_view()),
    path("search/global", GlobalSearchView.as_view()),
    path("feedback", FeedbackView.as_view()),
    # reverse geocoding (lat/lng -> address) via the admin-managed Google Maps key
    path("geo/reverse", GeoReverseView.as_view()),
    # places search (autocomplete + detail) for the location picker
    path("geo/places/autocomplete", GeoPlacesAutocompleteView.as_view()),
    path("geo/places/detail", GeoPlaceDetailView.as_view()),
    # routing / ETA / address-quality / roads (Maps Platform proxies)
    path("geo/route", GeoRouteView.as_view()),
    path("geo/distance-matrix", GeoDistanceMatrixView.as_view()),
    path("geo/validate-address", GeoValidateAddressView.as_view()),
    path("geo/geolocate", GeoGeolocateView.as_view()),
    path("geo/snap-to-roads", GeoSnapToRoadsView.as_view()),
    # super-admin runtime integration credentials
    path("admin/settings/integrations", IntegrationSettingsView.as_view()),
]
