"""Authentication helpers."""
from rest_framework_simplejwt.authentication import JWTAuthentication


class OptionalJWTAuthentication(JWTAuthentication):
    """JWT auth that never blocks a public endpoint.

    A valid bearer token populates ``request.user`` (so views can personalise — e.g.
    resolve a customer's serving store from their saved address), but a missing,
    malformed, or expired token falls through to ``AnonymousUser`` instead of raising
    401. Use on ``AllowAny`` endpoints that want to *use* the user when present without
    *requiring* sign-in."""

    def authenticate(self, request):
        try:
            return super().authenticate(request)
        except Exception:  # invalid/expired token on a public endpoint → treat as anon
            return None
