"""WebSocket URL routes for the delivery real-time channels."""
from django.urls import path

from .consumers import DispatchConsumer, OrderTrackingConsumer

websocket_urlpatterns = [
    path("ws/orders/<str:code>/tracking", OrderTrackingConsumer.as_asgi()),
    path("ws/admin/delivery/command-center", DispatchConsumer.as_asgi()),
]
