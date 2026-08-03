from django.urls import path

from .views import (
    EvidencePhotoView,
    GpsView,
    PhotoView,
    TaskDetailView,
    TaskListView,
    TaskStartView,
    TaskSubmitView,
)

urlpatterns = [
    path("verification/tasks", TaskListView.as_view()),
    path("verification/tasks/<int:pk>", TaskDetailView.as_view()),
    path("verification/tasks/<int:pk>/start", TaskStartView.as_view()),
    path("verification/tasks/<int:pk>/submit", TaskSubmitView.as_view()),
    path("verification/photo", PhotoView.as_view()),
    path("verification/evidence/<int:pk>/photo", EvidencePhotoView.as_view()),
    path("verification/gps", GpsView.as_view()),
]
