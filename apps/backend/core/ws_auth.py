"""JWT authentication for Channels WebSocket connections.

Browsers/Flutter can't set Authorization headers on a WebSocket handshake, so the
client passes the access token as a ``?token=`` query param (or the
``Sec-WebSocket-Protocol`` subprotocol). This middleware decodes it with SimpleJWT
and puts the resolved ``User`` on ``scope["user"]`` (AnonymousUser on any failure).
Consumers then enforce their own ownership/role checks.
"""
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from django.contrib.auth.models import AnonymousUser


@database_sync_to_async
def _user_for(user_id):
    from accounts.models import User

    return (
        User.objects.filter(pk=user_id, is_active=True).first() or AnonymousUser()
    )


def _token_from_scope(scope) -> str | None:
    qs = parse_qs((scope.get("query_string") or b"").decode())
    if qs.get("token"):
        return qs["token"][0]
    # Fallback: token passed as a WebSocket subprotocol (["access_token", "<jwt>"]).
    for proto in scope.get("subprotocols", []) or []:
        if proto and proto != "access_token":
            return proto
    return None


class JWTAuthMiddleware(BaseMiddleware):
    """Resolve ``scope["user"]`` from a SimpleJWT access token on the handshake."""

    async def __call__(self, scope, receive, send):
        scope = dict(scope)
        scope["user"] = AnonymousUser()
        token = _token_from_scope(scope)
        if token:
            try:
                from rest_framework_simplejwt.tokens import AccessToken

                access = AccessToken(token)  # validates signature + expiry
                scope["user"] = await _user_for(access.get("user_id"))
            except Exception:
                scope["user"] = AnonymousUser()
        return await super().__call__(scope, receive, send)
