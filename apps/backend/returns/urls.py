from django.urls import path

from .admin_views import (
    AdminReturnDetailView,
    AdminReturnListView,
    AdminReturnStatusView,
)
from .agent_views import (
    AgentReturnPickupAcceptView,
    AgentReturnPickupCompleteView,
    AgentReturnPickupDeclineView,
    AgentReturnPickupDetailView,
    AgentReturnPickupEnRouteView,
    AgentReturnPickupHistoryView,
    AgentReturnPickupListView,
    AgentReturnPickupPhotoView,
    AgentReturnPickupReachView,
    AgentReturnPickupRejectView,
    AgentReturnPickupRescheduleView,
)
from .views import (
    OrderReturnCreateView,
    ReturnDetailView,
    ReturnListView,
    ReturnPhotoView,
)

urlpatterns = [
    path("orders/<str:code>/returns", OrderReturnCreateView.as_view()),
    # admin returns/refunds workflow
    path("admin/returns", AdminReturnListView.as_view()),
    path("admin/returns/<str:code>", AdminReturnDetailView.as_view()),
    path("admin/returns/<str:code>/status", AdminReturnStatusView.as_view()),
    # customer
    path("returns", ReturnListView.as_view()),
    path("returns/<str:code>", ReturnDetailView.as_view()),
    path("returns/photos/<str:pk>", ReturnPhotoView.as_view()),
    # field agent — return pickups
    path("agent/return-pickups", AgentReturnPickupListView.as_view()),
    path("agent/return-pickups/history", AgentReturnPickupHistoryView.as_view()),
    path("agent/return-pickups/<str:pk>", AgentReturnPickupDetailView.as_view()),
    path("agent/return-pickups/<str:pk>/accept", AgentReturnPickupAcceptView.as_view()),
    path("agent/return-pickups/<str:pk>/decline", AgentReturnPickupDeclineView.as_view()),
    path("agent/return-pickups/<str:pk>/en-route", AgentReturnPickupEnRouteView.as_view()),
    path("agent/return-pickups/<str:pk>/reach", AgentReturnPickupReachView.as_view()),
    path("agent/return-pickups/<str:pk>/photo", AgentReturnPickupPhotoView.as_view()),
    path("agent/return-pickups/<str:pk>/complete", AgentReturnPickupCompleteView.as_view()),
    path("agent/return-pickups/<str:pk>/reject", AgentReturnPickupRejectView.as_view()),
    path("agent/return-pickups/<str:pk>/reschedule", AgentReturnPickupRescheduleView.as_view()),
]
