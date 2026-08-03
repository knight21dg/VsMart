from django.urls import path

from .views import ConfigView, PublicSupportContactView

urlpatterns = [
    path("admin/config", ConfigView.as_view()),
    path("support/contact", PublicSupportContactView.as_view()),
]
