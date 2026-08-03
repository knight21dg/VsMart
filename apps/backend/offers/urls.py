from django.urls import path

from .admin_views import (
    AdminCouponDetailView,
    AdminCouponListCreateView,
    AdminOfferDetailView,
    AdminOfferImageView,
    AdminOfferListCreateView,
    BannerSpecView,
    BannerStateView,
    NotificationCampaignView,
)
from .views import BannerEventView, CouponValidateView, CouponWalletView, OfferListView

urlpatterns = [
    path("offers", OfferListView.as_view()),
    # NOTE: literal /offers/* routes must precede nothing here (no /offers/<pk>),
    # but keep them grouped so a future detail route lands after them.
    path("offers/specs", BannerSpecView.as_view()),
    path("offers/events", BannerEventView.as_view()),
    path("coupons/wallet", CouponWalletView.as_view()),
    path("coupons/validate", CouponValidateView.as_view()),
    # ── Marketing admin (M18) ────────────────────────────────
    path("admin/marketing/offers", AdminOfferListCreateView.as_view()),
    # NOTE: keep the literal /image route before the generic /<action> route.
    path("admin/marketing/offers/<int:pk>/image", AdminOfferImageView.as_view()),
    path("admin/marketing/offers/<int:pk>/<str:action>", BannerStateView.as_view()),
    path("admin/marketing/offers/<int:pk>", AdminOfferDetailView.as_view()),
    path("admin/marketing/coupons", AdminCouponListCreateView.as_view()),
    path("admin/marketing/coupons/<int:pk>", AdminCouponDetailView.as_view()),
    path("admin/marketing/notify", NotificationCampaignView.as_view()),
]
