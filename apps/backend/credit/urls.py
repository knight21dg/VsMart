from django.urls import path

from .application_views import (
    AdminCreditApplicationDetailView,
    AdminCreditApplicationListView,
    AdminCreditDecisionView,
    AdminCreditLimitView,
    CreditApplicationWithdrawView,
    CreditApplyView,
)
from .views import (
    AdminCibilView,
    BillsView,
    CibilCheckView,
    CibilLatestView,
    DashboardView,
    FamilyMemberView,
    FamilyView,
    LedgerView,
    OutstandingView,
    PosCreditConfirmView,
    ScoreView,
    StatementDetailView,
    StatementPdfView,
    StatementListView,
)

urlpatterns = [
    path("credit/dashboard", DashboardView.as_view()),
    # Credit application (apply -> admin review -> limit granted)
    path("credit/apply", CreditApplyView.as_view()),
    path("credit/application", CreditApplyView.as_view()),
    path("credit/application/withdraw", CreditApplicationWithdrawView.as_view()),
    path("admin/credit/applications", AdminCreditApplicationListView.as_view()),
    path("admin/credit/applications/<int:pk>",
         AdminCreditApplicationDetailView.as_view()),
    path("admin/credit/applications/<int:pk>/decision",
         AdminCreditDecisionView.as_view()),
    path("admin/credit/users/<int:user_id>/limit", AdminCreditLimitView.as_view()),
    path("credit/score", ScoreView.as_view()),
    # CIBIL / credit-bureau score
    path("credit/cibil", CibilLatestView.as_view()),
    path("credit/cibil/check", CibilCheckView.as_view()),
    path("admin/credit/cibil/<int:user_id>", AdminCibilView.as_view()),
    path("credit/ledger", LedgerView.as_view()),
    path("credit/statements", StatementListView.as_view()),
    path("credit/statements/<int:pk>", StatementDetailView.as_view()),
    path("credit/statements/<int:pk>/pdf", StatementPdfView.as_view()),
    path("credit/bills/weekly", BillsView.as_view(period="weekly")),
    path("credit/bills/monthly", BillsView.as_view(period="monthly")),
    path("credit/outstanding", OutstandingView.as_view()),
    # In-app 2FA for a POS credit sale (customer reads the code back to the cashier).
    path("credit/pos-confirm", PosCreditConfirmView.as_view()),
    path("credit/family", FamilyView.as_view()),
    path("credit/family/members", FamilyView.as_view()),
    path("credit/family/members/<int:pk>", FamilyMemberView.as_view()),
]
