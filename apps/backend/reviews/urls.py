from django.urls import path

from .admin_views import AdminReviewListView, AdminReviewModerateView
from .views import MyReviewsView, ProductReviewsView

urlpatterns = [
    path("products/<pk>/reviews", ProductReviewsView.as_view()),
    path("reviews/mine", MyReviewsView.as_view()),
    # ── Moderation ──
    path("admin/reviews", AdminReviewListView.as_view()),
    path("admin/reviews/<int:pk>/moderate", AdminReviewModerateView.as_view()),
]
