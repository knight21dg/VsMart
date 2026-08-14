"""Notification fan-out. `notify()` writes the in-app inbox row and pushes to the
user's registered devices via FCM HTTP v1 (notifications/push.py — a no-op until a
service account is configured). The push fires on transaction commit so it never
blocks or rolls back the caller's work."""
from django.db import transaction

from .models import Notification


def notify(user, *, type, title, body="", data=None, dedupe_key=""):
    """Create an in-app notification for `user` and schedule a device push.

    Pass ``dedupe_key`` to make the send **idempotent for that event**: the key
    identifies the thing that happened ("delivery_assigned:task:412"), not the
    attempt, so replaying the operation is silent — no second inbox row and, more
    importantly, no second buzz in someone's pocket. Nothing deduplicated before,
    so every retried dispatch re-alerted the agent for a task they already had.

    Omit it for messages that are genuinely repeatable (a re-sent OTP, a
    marketing blast) — those must still be able to arrive twice.
    """
    payload = data or {}
    if dedupe_key:
        n, created = Notification.objects.get_or_create(
            user=user,
            dedupe_key=dedupe_key,
            defaults={"type": type, "title": title, "body": body, "data": payload},
        )
        if not created:
            return n  # already delivered for this event — stay silent
    else:
        n = Notification.objects.create(
            user=user, type=type, title=title, body=body, data=payload
        )
    # Carry the notification type into the push so the device can route it to the
    # right (branded) channel — without mutating the stored inbox row's data.
    push_data = {**payload, "type": type}
    transaction.on_commit(lambda: _push(user, title, body, push_data))
    return n


def notify_store_staff(store, *, type, title, body="", data=None, dedupe_key=""):
    """Fan a notification out to a store's active staff (New Order, Delivery
    Failed, Low Stock, …). Each staff member gets their own inbox row + push.
    No-op when the store is None or has no active staff. NOTE: the store-admin
    panel is web, so until it surfaces a notification bell (or a store mobile app
    exists) these land as inbox rows rather than device pushes."""
    if store is None:
        return
    from storeops.models import StoreStaff

    user_ids = list(
        StoreStaff.objects.filter(store=store, is_active=True).values_list(
            "user_id", flat=True
        )
    )
    if not user_ids:
        return
    from accounts.models import User

    for user in User.objects.filter(id__in=user_ids, is_active=True):
        # The key is per-event; each staff member still gets their own copy
        # because `dedupe_key` is unique per (user, key), not globally.
        notify(user, type=type, title=title, body=body, data=data,
               dedupe_key=dedupe_key)


def broadcast(users, *, type, title, body="", data=None):
    """Send one marketing/announcement notification to many customers at once —
    inbox rows in bulk + a batched FCM push to all their active devices (chunked to
    FCM's 500-token multicast limit). Returns the number of recipients. Dead tokens
    reported by FCM are deactivated. The push fires on transaction commit.

    ``data`` may carry an ``image`` (hero) URL; otherwise the push falls back to the
    VS Mart logo (see push.py) so the notification bubble is always branded.
    """
    users = list(users)
    if not users:
        return 0
    payload = data or {}
    Notification.objects.bulk_create(
        [Notification(user=u, type=type, title=title, body=body, data=payload) for u in users],
        batch_size=500,
    )
    push_data = {**payload, "type": type}
    user_ids = [u.id for u in users]
    transaction.on_commit(lambda: _broadcast_push(user_ids, title, body, push_data))
    return len(users)


def _broadcast_push(user_ids, title, body, data):
    """Push to every active device of the given users, in ≤500-token batches."""
    from accounts.models import DeviceToken

    from .push import send_push

    tokens = list(
        DeviceToken.objects.filter(user_id__in=user_ids, is_active=True).values_list(
            "token", flat=True
        )
    )
    for i in range(0, len(tokens), 500):
        batch = tokens[i:i + 500]
        dead = send_push(batch, title, body or "", data)
        if dead:
            DeviceToken.objects.filter(token__in=dead).update(is_active=False)


def _push(user, title, body, data):
    """Send an FCM push to the user's active device tokens (v1 API) and deactivate
    any tokens FCM reports as dead. No-op without configured credentials."""
    from accounts.models import DeviceToken

    tokens = list(
        DeviceToken.objects.filter(user=user, is_active=True).values_list(
            "token", flat=True
        )
    )
    if not tokens:
        return
    from .push import send_push

    dead = send_push(tokens, title, body or "", data)
    if dead:
        DeviceToken.objects.filter(user=user, token__in=dead).update(is_active=False)
