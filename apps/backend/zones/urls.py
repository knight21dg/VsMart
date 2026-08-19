from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import (
    AdminExpansionRequestListView,
    AdminStoreAdminResetView,
    AdminStoreAdminView,
    AdminStoreInventoryView,
    AdminStoreViewSet,
    AdminZoneAgentsView,
    AdminZoneOrdersExportView,
    AdminZoneStatsView,
    AdminZoneViewSet,
    ExpansionRequestCreateView,
    ServiceabilityCheckView,
    ZoneCheckView,
)

router = SimpleRouter(trailing_slash=False)
router.register("admin/zones", AdminZoneViewSet, basename="admin-zone")
router.register("admin/stores", AdminStoreViewSet, basename="admin-store")

urlpatterns = [
    path("serviceability/check", ServiceabilityCheckView.as_view()),
    path("serviceability/expansion-request", ExpansionRequestCreateView.as_view()),
    path("admin/expansion-requests", AdminExpansionRequestListView.as_view()),
    path("admin/stores/<int:store_id>/inventory", AdminStoreInventoryView.as_view()),
    path("admin/stores/<int:store_id>/admin", AdminStoreAdminView.as_view()),
    path("admin/stores/<int:store_id>/admin/reset-password", AdminStoreAdminResetView.as_view()),
    path("admin/zones/stats", AdminZoneStatsView.as_view()),
    path("admin/zones/<int:zone_id>/orders/export", AdminZoneOrdersExportView.as_view()),
    path("admin/zones/<int:zone_id>/agents", AdminZoneAgentsView.as_view()),
    path("admin/zones/<int:zone_id>/agents/<int:agent_id>", AdminZoneAgentsView.as_view()),
    path("zones/check", ZoneCheckView.as_view()),
] + router.urls
