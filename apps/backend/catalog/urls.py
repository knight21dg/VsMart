from django.urls import path

from .admin_views import (
    AdminCategoryDetailView,
    AdminCategoryListCreateView,
    AdminImageUploadView,
    AdminProductDetailView,
    AdminProductVariantsView,
    AdminProductListCreateView,
)
from .home_views import (
    AdminHomeSectionDetailView,
    AdminHomeSectionReorderView,
    AdminHomeSectionView,
    HomeSectionCatalogView,
    HomeSectionView,
)
from .views import (
    CategoryListView,
    ProductDetailView,
    ProductListView,
    ProductSearchView,
    ProductSuggestView,
    StoreCategoryListView,
    SubCategoryListView,
)

urlpatterns = [
    path("categories", CategoryListView.as_view()),
    # One level of the serving store's PRIVATE tree (?parent=<id> to drill in).
    # Declared before the <int:category_id> route so it is never shadowed.
    path("store-categories", StoreCategoryListView.as_view()),
    path("categories/<int:category_id>/sub-categories", SubCategoryListView.as_view()),
    path("products", ProductListView.as_view()),
    path("products/search", ProductSearchView.as_view()),
    path("products/suggest", ProductSuggestView.as_view()),
    # <str:pk> so the detail accepts EITHER a numeric id OR an unguessable share
    # token. (The specific /products/search and /products/suggest routes above win
    # by declaration order, so this catch-all never shadows them.)
    path("products/<str:pk>", ProductDetailView.as_view()),
    # ── Home rails (customer) ────────────────────────────────
    # `sections` is declared before `sections/<str:section>` so the catalogue
    # listing is never swallowed by the per-section route.
    path("home/sections", HomeSectionCatalogView.as_view()),
    path("home/sections/<str:section>", HomeSectionView.as_view()),
    # ── Product Master (admin) ───────────────────────────────
    path("admin/catalog/home-sections", AdminHomeSectionView.as_view()),
    path("admin/catalog/home-sections/reorder", AdminHomeSectionReorderView.as_view()),
    path("admin/catalog/home-sections/<int:pk>", AdminHomeSectionDetailView.as_view()),
    path("admin/catalog/products", AdminProductListCreateView.as_view()),
    path("admin/catalog/products/<int:pk>", AdminProductDetailView.as_view()),
    path("admin/catalog/products/<int:pk>/variants", AdminProductVariantsView.as_view()),
    path("admin/catalog/categories", AdminCategoryListCreateView.as_view()),
    path("admin/catalog/categories/<int:pk>", AdminCategoryDetailView.as_view()),
    path("admin/catalog/image", AdminImageUploadView.as_view()),
]
