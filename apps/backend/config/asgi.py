"""ASGI entrypoint — HTTP via Django, WebSocket via Channels.

`get_asgi_application()` is called BEFORE importing any consumers so the Django app
registry is ready (avoids AppRegistryNotReady).
"""
import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.prod")

django_asgi_app = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402

from core.ws_auth import JWTAuthMiddleware  # noqa: E402
from delivery.ws_routing import websocket_urlpatterns as delivery_ws_routes  # noqa: E402
from storeops.ws_routing import websocket_urlpatterns as store_ws_routes  # noqa: E402

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": JWTAuthMiddleware(
            URLRouter(delivery_ws_routes + store_ws_routes)
        ),
    }
)
