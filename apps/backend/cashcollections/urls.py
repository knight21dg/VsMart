from django.urls import path

from .admin_views import (
    AdminCollectionAgentsView,
    AdminCollectionAssignView,
    AdminCollectionManualVerifyView,
    AdminCollectionAutoAssignView,
    AdminCollectionCommandCenterView,
    AdminCollectionDunningView,
    AdminCollectionListView,
    AdminCollectionMetricsView,
    AdminCollectionPerformanceView,
    AdminCollectionUpdateView,
)
from .views import (
    AssignedCollectionsView,
    CollectionAcceptView,
    CollectionCollectView,
    CollectionDetailView,
    CollectionDisputeView,
    CollectionEnRouteView,
    CollectionFailView,
    CollectionHistoryView,
    CollectionOtpVerifyView,
    CollectionReachView,
    CollectionReceiptsView,
    CollectionRejectView,
    CollectionRequestOtpView,
    CustomerCollectionConfirmView,
    PendingCollectionsView,
)

urlpatterns = [
    # ── Collections admin / super-admin (M08) ────────────────
    path("admin/collections", AdminCollectionListView.as_view()),
    path("admin/collections/metrics", AdminCollectionMetricsView.as_view()),
    path("admin/collections/agents", AdminCollectionAgentsView.as_view()),
    path("admin/collections/auto-assign", AdminCollectionAutoAssignView.as_view()),
    path("admin/collections/dunning", AdminCollectionDunningView.as_view()),
    path("admin/collections/performance", AdminCollectionPerformanceView.as_view()),
    path("admin/collections/command-center", AdminCollectionCommandCenterView.as_view()),
    path("admin/collections/<int:pk>", AdminCollectionUpdateView.as_view()),
    path("admin/collections/<int:pk>/assign", AdminCollectionAssignView.as_view()),
    path("admin/collections/<int:pk>/manual-verify",
         AdminCollectionManualVerifyView.as_view()),
    # ── customer ──
    # Customer-facing: view the in-app confirmation OTP for an active collection.
    path("collections/confirm", CustomerCollectionConfirmView.as_view()),
    path("collections/pending", PendingCollectionsView.as_view()),
    path("collections/history", CollectionHistoryView.as_view()),
    path("collections/receipts", CollectionReceiptsView.as_view()),
    # ── agent (scoped to the assigned agent) ──
    path("collections/assigned", AssignedCollectionsView.as_view()),
    path("collections/<int:pk>", CollectionDetailView.as_view()),
    path("collections/<int:pk>/accept", CollectionAcceptView.as_view()),
    path("collections/<int:pk>/reject", CollectionRejectView.as_view()),
    path("collections/<int:pk>/en-route", CollectionEnRouteView.as_view()),
    path("collections/<int:pk>/reach", CollectionReachView.as_view()),
    path("collections/<int:pk>/request-otp", CollectionRequestOtpView.as_view()),
    path("collections/<int:pk>/otp", CollectionOtpVerifyView.as_view()),
    path("collections/<int:pk>/collect", CollectionCollectView.as_view()),
    path("collections/<int:pk>/dispute", CollectionDisputeView.as_view()),
    path("collections/<int:pk>/fail", CollectionFailView.as_view()),
]
