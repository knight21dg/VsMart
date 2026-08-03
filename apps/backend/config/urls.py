"""Root URL configuration. Everything customer-facing lives under /api/v1/."""
from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import (
    SpectacularAPIView,
    SpectacularRedocView,
    SpectacularSwaggerView,
)

api_v1 = [
    path("", include("core.urls")),
    path("", include("accounts.urls")),
    path("", include("catalog.urls")),
    path("", include("addresses.urls")),
    path("", include("cart.urls")),
    path("", include("orders.urls")),
    path("", include("credit.urls")),
    path("", include("payments.urls")),
    path("", include("kyc.urls")),
    path("", include("mediastore.urls")),
    path("", include("offers.urls")),
    path("", include("notifications.urls")),
    path("", include("support.urls")),
    path("", include("referrals.urls")),
    path("", include("siteconfig.urls")),
    path("", include("zones.urls")),
    path("", include("geography.urls")),
    path("", include("inventory.urls")),
    path("", include("accounting.urls")),
    path("", include("delivery.urls")),
    path("", include("verification.urls")),
    path("", include("billing.urls")),
    path("", include("cashcollections.urls")),
    path("", include("agents.urls")),
    path("", include("system.urls")),
    path("", include("reports.urls")),
    path("", include("ops.urls")),
    path("", include("pos.urls")),
    path("", include("content.urls")),
    path("", include("reviews.urls")),
    path("", include("returns.urls")),
    path("", include("loyalty.urls")),
    path("", include("crm.urls")),
    path("", include("storeops.urls")),
]

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include((api_v1, "v1"))),
    # OpenAPI schema + interactive docs
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema"), name="swagger-ui"),
    path("api/redoc/", SpectacularRedocView.as_view(url_name="schema"), name="redoc"),
]

# Serve user-uploaded media in dev (DEBUG). In prod the object store / CDN serves it.
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
