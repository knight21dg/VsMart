from django.urls import path

from .admin_views import (
    AdminReferralListView,
    AdminReferralSummaryView,
    AdminReferrerDetailView,
    AdminReferrerListView,
)
from .views import ReferralApplyView, ReferralView

urlpatterns = [
    path("referrals", ReferralView.as_view()),
    path("referrals/apply", ReferralApplyView.as_view()),

    # ── Referrals admin ──────────────────────────────────────
    path("admin/referrals/summary", AdminReferralSummaryView.as_view()),
    path("admin/referrals", AdminReferralListView.as_view()),
    # One row per inviter ("this user invited this many"), then the tree beneath one.
    path("admin/referrers", AdminReferrerListView.as_view()),
    path("admin/referrers/<int:user_id>", AdminReferrerDetailView.as_view()),
]
