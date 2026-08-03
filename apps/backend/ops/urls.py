from django.urls import path

from .views import (
    AdminCreditFreezeView,
    AdminCreditView,
    AnalyticsOverviewView,
    AuditLogDetailView,
    AuditLogListView,
    CustomerDetailView,
    CustomerListView,
    DashboardView,
    InventoryView,
    SalesSeriesView,
    StaffDetailView,
    StaffView,
    StockAdjustView,
    TopProductsView,
    ZoneSalesView,
)

urlpatterns = [
    path("admin/dashboard", DashboardView.as_view()),
    path("admin/staff", StaffView.as_view()),
    path("admin/staff/<int:pk>", StaffDetailView.as_view()),
    path("admin/customers", CustomerListView.as_view()),
    path("admin/customers/<int:pk>", CustomerDetailView.as_view()),
    # analytics
    path("admin/analytics/overview", AnalyticsOverviewView.as_view()),
    path("admin/analytics/sales", SalesSeriesView.as_view()),
    path("admin/analytics/top-products", TopProductsView.as_view()),
    path("admin/analytics/zones", ZoneSalesView.as_view()),
    # inventory
    path("admin/inventory", InventoryView.as_view()),
    path("admin/inventory/<int:product_id>/adjust", StockAdjustView.as_view()),
    # credit controls
    path("admin/credit/<int:user_id>", AdminCreditView.as_view()),
    path("admin/credit/<int:user_id>/freeze", AdminCreditFreezeView.as_view()),
    # audit
    path("audit/logs", AuditLogListView.as_view()),
    path("audit/logs/<int:pk>", AuditLogDetailView.as_view()),
]
