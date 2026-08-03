from django.urls import path

from .views import MediaUploadView, PrivateMediaView, PublicMediaView

urlpatterns = [
    path("media", MediaUploadView.as_view()),
    # Public route first so the literal "public" segment can't be parsed as a UUID.
    path("media/public/<uuid:pk>/<str:variant>", PublicMediaView.as_view()),
    path("media/<uuid:pk>/<str:variant>", PrivateMediaView.as_view()),
]
