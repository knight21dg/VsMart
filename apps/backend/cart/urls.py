from django.urls import path

from .views import (
    CartItemDetailView,
    CartItemsView,
    CartQuoteView,
    CartValidateView,
    CartView,
    WishlistItemView,
    WishlistView,
)

urlpatterns = [
    path("cart", CartView.as_view()),
    path("cart/quote", CartQuoteView.as_view()),
    path("cart/validate", CartValidateView.as_view()),
    path("cart/items", CartItemsView.as_view()),
    path("cart/items/<int:pk>", CartItemDetailView.as_view()),
    path("wishlist", WishlistView.as_view()),
    path("wishlist/<int:product_id>", WishlistItemView.as_view()),
]
