from django.urls import path

from .views import (
    NotificationListView,
    NotificationPreferenceView,
    NotificationReadAllView,
    NotificationReadView,
)

urlpatterns = [
    path("notifications", NotificationListView.as_view()),
    path("notifications/preferences", NotificationPreferenceView.as_view()),
    path("notifications/read-all", NotificationReadAllView.as_view()),
    path("notifications/<int:pk>/read", NotificationReadView.as_view()),
]
