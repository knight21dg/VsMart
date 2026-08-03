"""WebSocket URL routes for the Store panel's real-time channels."""
from django.urls import path

from .consumers import StoreOrdersConsumer

websocket_urlpatterns = [
    path("ws/store/orders", StoreOrdersConsumer.as_asgi()),
]
