from django.urls import path

from .admin_views import (
    AdminLoyaltySummaryView,
    AdminPointsLedgerView,
    AdminRedemptionListView,
    AdminTopMembersView,
    AdminVoucherOutstandingView,
)
from .views import LoyaltyDashboardView, LoyaltyLedgerView, RedeemView

urlpatterns = [
    path("loyalty", LoyaltyDashboardView.as_view()),
    path("loyalty/ledger", LoyaltyLedgerView.as_view()),
    path("loyalty/redeem", RedeemView.as_view()),

    # ── Loyalty admin ────────────────────────────────────────
    path("admin/loyalty/summary", AdminLoyaltySummaryView.as_view()),
    path("admin/loyalty/ledger", AdminPointsLedgerView.as_view()),
    path("admin/loyalty/members", AdminTopMembersView.as_view()),
    # Redemptions = coupons actually SPENT (the money side).
    path("admin/redemptions", AdminRedemptionListView.as_view()),
    path("admin/redemptions/outstanding", AdminVoucherOutstandingView.as_view()),
]
