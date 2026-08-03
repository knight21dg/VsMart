from django.urls import path

from .admin_views import AdminPageDetailView, AdminPageListCreateView
from .views import PageDetailView, PageListView

urlpatterns = [
    path("content/pages", PageListView.as_view()),
    path("content/pages/<slug:slug>", PageDetailView.as_view()),
    # super-admin CMS (edit pages)
    path("admin/pages", AdminPageListCreateView.as_view()),
    path("admin/pages/<slug:slug>", AdminPageDetailView.as_view()),
]
