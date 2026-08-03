"""FCM push via the **HTTP v1 API** (firebase-admin).

The old legacy endpoint (`fcm.googleapis.com/fcm/send` + `Authorization: key=…`)
was shut down by Google in June 2024, so the previous implementation never
delivered. This sends through firebase-admin's multicast, authenticated by a
service account.

Credential-gated: until ``settings.FIREBASE_CREDENTIALS`` points at a service
account (a JSON file path, or the JSON itself), :func:`send_push` is a clean
no-op — so dev/CI never need Firebase. ``send_push`` returns the tokens FCM
reports as dead so callers can deactivate them.
"""
import json
import threading

_lock = threading.Lock()
_app = None
_init_done = False

# --- Branding & channels -----------------------------------------------------
# Android renders background/terminated notifications itself (our Dart handler
# only runs in the foreground), so the channel + branding for those must travel
# inside the FCM message. These IDs MUST match the channels the app creates in
# push_controller.dart, and the icon/color must exist in the app's Android res.
NOTIFICATION_ICON = "ic_notification"  # white silhouette in res/drawable
ACCENT_COLOR = "#16A34A"  # VS Mart brand green (AppColors.vsGreen)

DEFAULT_CHANNEL = "vsmart_support"

# `kind` values that mean "a brand-new task just landed on this agent" — the
# agent app answers these with a full-screen, vibrating alert instead of a
# normal tray notification (see agent_app's push_routing.dart / push_service.dart).
# Sent DATA-ONLY (no `notification` block) so Android never also auto-displays
# its own plain tray notification alongside the one the app builds itself with
# `fullScreenIntent: true` — sending both would double-notify the agent.
URGENT_KINDS = {"delivery_assignment", "collection_assignment"}

# notify(type=...) value -> Android notification channel id.
CHANNEL_BY_TYPE = {
    "order": "vsmart_orders",
    "delivery": "vsmart_delivery",
    "payment": "vsmart_credit",
    "credit": "vsmart_credit",
    "offer": "vsmart_offers",
    "promo": "vsmart_offers",
    "admin": DEFAULT_CHANNEL,
    "support": DEFAULT_CHANNEL,
}


def channel_for(notif_type) -> str:
    """Resolve a notify() type to a notification channel id (falls back to the
    general 'support' channel for unknown/blank types)."""
    return CHANNEL_BY_TYPE.get((notif_type or "").strip().lower(), DEFAULT_CHANNEL)


def _firebase_app():
    """Lazily build the firebase-admin app from the configured service account,
    or return None when none is configured (push becomes a no-op)."""
    global _app, _init_done
    if _init_done:
        return _app
    with _lock:
        if _init_done:
            return _app
        _init_done = True
        try:
            from django.conf import settings

            raw = (getattr(settings, "FIREBASE_CREDENTIALS", "") or "").strip()
            if not raw:
                _app = None
                return None
            import firebase_admin
            from firebase_admin import credentials

            cert = credentials.Certificate(
                json.loads(raw) if raw.startswith("{") else raw
            )
            _app = firebase_admin.initialize_app(cert, name="vsmart-push")
        except Exception:  # bad creds / lib missing → stay a no-op, never crash
            _app = None
        return _app


def send_push(tokens, title, body, data=None) -> list[str]:
    """Send a notification+data message to ``tokens`` via FCM v1.

    Returns the subset of ``tokens`` that FCM reports as unregistered/invalid
    (so the caller can deactivate them). Returns ``[]`` (no-op) without creds.
    """
    tokens = [t for t in (tokens or []) if t]
    if not tokens:
        return []
    app = _firebase_app()
    if app is None:
        return []
    data = dict(data or {})
    channel_id = channel_for(data.get("type"))
    # Echo the resolved channel so the foreground (Dart) handler renders on the
    # same channel the system uses for background notifications.
    data.setdefault("channel", channel_id)
    # Per-campaign hero image ONLY when the caller explicitly supplied one —
    # this used to also fall back to the static VS Mart logo for EVERY push,
    # including plain one-line text notifications, which meant every single
    # message re-downloaded and re-rendered the same image for no reason.
    from django.conf import settings

    image = (data.get("image") or "").strip() or None
    # Web push (the store-admin panel) has its own config block — Android's
    # config is silently ignored by a browser token and vice versa, so both
    # can ride the same MulticastMessage safely.
    route = str(data.get("route") or "/")
    link = getattr(settings, "STORE_ADMIN_URL", "").rstrip("/") + route

    urgent = (data.get("kind") or "") in URGENT_KINDS
    if urgent:
        # The background isolate that builds the full-screen alert has no
        # `message.notification` to read (there isn't one) — carry the text
        # through `data` instead.
        data.setdefault("title", title)
        data.setdefault("body", body or "")

    try:
        from firebase_admin import messaging

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=None if urgent
            else messaging.Notification(title=title, body=body or None, image=image),
            data={k: str(v) for k, v in data.items()},
            android=messaging.AndroidConfig(
                notification=None if urgent else messaging.AndroidNotification(
                    channel_id=channel_id,
                    icon=NOTIFICATION_ICON,
                    color=ACCENT_COLOR,
                    image=image,
                    default_sound=True,
                ),
                priority="high" if urgent else None,
            ),
            webpush=messaging.WebpushConfig(
                notification=messaging.WebpushNotification(
                    icon=f"{getattr(settings, 'STORE_ADMIN_URL', '').rstrip('/')}/icon-192.png",
                    image=image,
                    require_interaction=True,
                ),
                fcm_options=messaging.WebpushFCMOptions(link=link),
            ),
        )
        resp = messaging.send_each_for_multicast(message, app=app)
    except Exception:
        return []

    dead: list[str] = []
    for tok, r in zip(tokens, resp.responses):
        if r.success:
            continue
        exc = r.exception
        name = type(exc).__name__ if exc is not None else ""
        # Unregistered device / wrong sender / malformed token → drop it.
        if name in ("UnregisteredError", "SenderIdMismatchError") or (
            exc is not None and "not a valid FCM registration" in str(exc)
        ):
            dead.append(tok)
    return dead
