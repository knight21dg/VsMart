from django.urls import path

from .views import (
    Customer360View,
    CustomerActionView,
    CustomerAnalyticsView,
    CustomerBulkView,
    CustomerExportView,
    CustomerNotesView,
    CustomerSearchView,
    CustomerTimelineView,
)

# Namespaced under /admin/crm/ — the Customer-360 domain. (The basic
# /admin/customers list/detail lives in the ops app; this is the rich CRM.)
urlpatterns = [
    path("admin/crm/customers", CustomerSearchView.as_view()),
    path("admin/crm/customers/analytics", CustomerAnalyticsView.as_view()),
    path("admin/crm/customers/export", CustomerExportView.as_view()),
    path("admin/crm/customers/bulk", CustomerBulkView.as_view()),
    path("admin/crm/customers/<int:pk>", Customer360View.as_view()),
    path("admin/crm/customers/<int:pk>/timeline", CustomerTimelineView.as_view()),
    path("admin/crm/customers/<int:pk>/notes", CustomerNotesView.as_view()),
    path("admin/crm/customers/<int:pk>/actions", CustomerActionView.as_view()),
]
