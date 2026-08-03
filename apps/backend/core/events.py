"""Analytics / realtime event emission. A thin, failure-isolated seam: callers fire
events without caring where they go. Today they persist to `ops.AnalyticsEvent` (polled
via `/pos/events`); a websocket/queue transport can be added here without touching callers.
"""
import json


def _json_safe(value):
    return json.loads(json.dumps(value or {}, default=str))


def record_event(event_type, payload=None, actor=None):
    """Append an event. Never raises into the caller's transaction-critical path."""
    try:
        from ops.models import AnalyticsEvent

        return AnalyticsEvent.objects.create(
            type=event_type, payload=_json_safe(payload), actor=actor
        )
    except Exception:
        return None
