import json
from datetime import datetime, timezone as _utc

from rest_framework_simplejwt.tokens import RefreshToken

from .models import AuditLog, User


def _json_safe(value):
    """Coerce arbitrary data (Decimals, dates, etc.) into JSON-serializable form
    for the audit JSONField."""
    if value is None:
        return None
    return json.loads(json.dumps(value, default=str))


def issue_tokens(user: User) -> dict:
    """Create an access+refresh pair carrying the user's role claim. Keys are
    snake_case to match the Flutter AuthTokenModel (access_token/refresh_token/expires_at)."""
    refresh = RefreshToken.for_user(user)
    refresh["role"] = user.role
    access = refresh.access_token
    exp = access.payload.get("exp")
    return {
        "access_token": str(access),
        "refresh_token": str(refresh),
        "expires_at": datetime.fromtimestamp(exp, tz=_utc.utc).isoformat() if exp else None,
    }


def get_or_create_customer(phone: str) -> tuple[User, bool]:
    user, created = User.objects.get_or_create(
        phone=phone, defaults={"role": "customer"}
    )
    return user, created


def record_audit(actor, action, target=None, before=None, after=None, ip=None):
    AuditLog.objects.create(
        actor=actor,
        action=action,
        target_type=target.__class__.__name__.lower() if target else "",
        target_id=str(getattr(target, "pk", "")) if target else "",
        before=_json_safe(before),
        after=_json_safe(after),
        ip=ip,
    )
