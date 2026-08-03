from django.urls import path

from .accounting_views import (
    AccountingByStoreView,
    AccountingCashflowView,
    AccountingSettlementsView,
    AccountingSummaryView,
)
from .views import DashboardView, ReportExportView, ReportView

urlpatterns = [
    # ── Accounting (M14) ─────────────────────────────────────
    path("admin/accounting/summary", AccountingSummaryView.as_view()),
    path("admin/accounting/cashflow", AccountingCashflowView.as_view()),
    path("admin/accounting/by-store", AccountingByStoreView.as_view()),
    path("admin/accounting/settlements", AccountingSettlementsView.as_view()),
    path("reports/export", ReportExportView.as_view()),
    path("reports/dashboard", DashboardView.as_view()),
    path("reports/<str:name>", ReportView.as_view()),
]
