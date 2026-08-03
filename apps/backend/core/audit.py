"""Audit trail for actionable responses. Every failure (and any coded business
event you choose to log) writes a row with event_id / timestamp / actor /
source_module / entity_type / entity_id, and mirrors security/risk events to the
analytics stream. Never raises into the caller — auditing must not break a request.
"""
import uuid

from django.utils import timezone

from .events import record_event


def _client_ip(request):
    if request is None:
        return None
    xff = request.META.get("HTTP_X_FORWARDED_FOR")
    if xff:
        return xff.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR")


def write_audit(code, spec, request=None, *, success=False, actor=None,
                entity_type="", entity_id="", fields=None, context=None, message=""):
    """Persist an AuditLog row + emit security/risk events. Returns the event_id.

    `actor` lets service-layer callers (no HTTP request) record who acted; falls
    back to request.user otherwise."""
    event_id = uuid.uuid4().hex
    try:
        from system.models import AuditLog

        if actor is None:
            actor = getattr(request, "user", None)
        if not (actor and getattr(actor, "is_authenticated", False)):
            actor = None

        AuditLog.objects.create(
            event_id=event_id,
            timestamp=timezone.now(),
            actor=actor,
            actor_phone=getattr(actor, "phone", "") or "",
            source_module=spec.get("module", "system"),
            entity_type=entity_type or "",
            entity_id=str(entity_id or ""),
            code=code,
            severity=spec.get("severity", "error"),
            success=success,
            is_security_event=spec.get("security", False),
            is_risk_event=spec.get("risk", False),
            method=getattr(request, "method", "") or "",
            path=getattr(request, "path", "") or "",
            ip=_client_ip(request),
            message=(message or spec.get("message", ""))[:300],
            context=context or (fields and {"fields": fields}) or {},
        )
        if spec.get("security"):
            record_event("security_event",
                         {"code": code, "path": getattr(request, "path", "")}, actor=actor)
        if spec.get("risk"):
            record_event("risk_event", {"code": code}, actor=actor)
    except Exception:
        # Auditing is best-effort and must never break the response.
        pass
    return event_id
