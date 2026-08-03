from django.urls import path

from .views import (
    AdminAccountLedgerView,
    AdminAccountListView,
    AdminBalanceSheetView,
    AdminJournalListView,
    AdminJournalPostView,
    AdminJournalReverseView,
    AdminProfitLossView,
    AdminTrialBalanceView,
)

urlpatterns = [
    # Reports first — literal segments must not be captured as ids.
    path("admin/accounting/trial-balance", AdminTrialBalanceView.as_view()),
    path("admin/accounting/pnl", AdminProfitLossView.as_view()),
    path("admin/accounting/balance-sheet", AdminBalanceSheetView.as_view()),
    path("admin/accounting/accounts", AdminAccountListView.as_view()),
    path("admin/accounting/accounts/<int:pk>/ledger", AdminAccountLedgerView.as_view()),
    path("admin/accounting/journal", AdminJournalListView.as_view()),
    path("admin/accounting/journal/post", AdminJournalPostView.as_view()),
    path("admin/accounting/journal/<int:pk>/reverse", AdminJournalReverseView.as_view()),
]
