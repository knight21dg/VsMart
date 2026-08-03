from django.urls import path

from .admin_views import (
    AdminTicketDetailView,
    AdminTicketListView,
    AdminTicketReplyView,
    AdminTicketUpdateView,
)
from .views import (
    FaqListView,
    TicketCloseView,
    TicketDetailView,
    TicketListView,
    TicketMessageView,
)

urlpatterns = [
    # ── Support admin (M19) — register before the customer <code> route ──
    path("admin/support/tickets", AdminTicketListView.as_view()),
    path("admin/support/tickets/<str:code>", AdminTicketDetailView.as_view()),
    path("admin/support/tickets/<str:code>/reply", AdminTicketReplyView.as_view()),
    path("admin/support/tickets/<str:code>/status", AdminTicketUpdateView.as_view()),
    path("support/tickets", TicketListView.as_view()),
    path("support/tickets/<str:code>", TicketDetailView.as_view()),
    path("support/tickets/<str:code>/messages", TicketMessageView.as_view()),
    path("support/tickets/<str:code>/close", TicketCloseView.as_view()),
    path("support/faqs", FaqListView.as_view()),
]
