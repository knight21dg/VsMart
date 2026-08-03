"""WebSocket consumers for real-time delivery tracking.

Two channels, both fed by :func:`delivery.realtime.broadcast` (called from the
delivery services on every GPS ping + status change):

* ``OrderTrackingConsumer`` (``ws/orders/<code>/tracking``) — a customer watching
  their in-flight order. Joins group ``order_<code>``; receives live agent
  position + ETA + status. Auth: the order's owner (or an admin).
* ``DispatchConsumer`` (``ws/admin/delivery/command-center``) — the super-admin
  dispatch board. Joins group ``dispatch``; receives every active delivery's
  position/status update. Auth: admin / superadmin.

The existing REST polling stays as the initial load + fallback; these just push
deltas in between so the map moves smoothly.
"""
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer


def _resolve_order(qs, ident):
    """Resolve an Order by its code (VSORD…) or, failing that, its numeric pk —
    the app uses the order id in the tracking path while the route is named code."""
    order = qs.filter(code=ident).first()
    if order is None and str(ident).isdigit():
        order = qs.filter(pk=int(ident)).first()
    return order


class OrderTrackingConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.ident = self.scope["url_route"]["kwargs"]["code"]
        user = self.scope.get("user")
        # _check resolves the order, verifies ownership, and returns its canonical
        # code (the group key the broadcaster targets) or None.
        canonical = (
            await self._check(user, self.ident)
            if (user and user.is_authenticated)
            else None
        )
        if canonical is None:
            await self.close(code=4403)
            return
        self.group = f"order_{canonical}"
        await self.channel_layer.group_add(self.group, self.channel_name)
        await self.accept()
        snapshot = await self._snapshot(self.ident)
        if snapshot:
            await self.send_json({"type": "tracking", "data": snapshot})

    async def disconnect(self, code):
        if getattr(self, "group", None):
            await self.channel_layer.group_discard(self.group, self.channel_name)

    # Channel-layer event handler (type "delivery.update").
    async def delivery_update(self, event):
        await self.send_json({"type": "tracking", "data": event["data"]})

    @database_sync_to_async
    def _check(self, user, ident):
        from orders.models import Order

        order = _resolve_order(Order.objects.only("user_id", "code", "store_id"), ident)
        if order is None:
            return None
        if order.user_id == user.id or user.role in ("admin", "superadmin"):
            return order.code
        # A store-admin panel dialog tracks its OWN store's deliveries — the
        # same live position the customer sees, scoped so a store can never
        # watch another store's order just by guessing its code.
        if user.role == "store_staff":
            from storeops.permissions import get_membership

            membership = get_membership(user)
            if (membership and membership.store_id == order.store_id
                    and membership.has_perm("delivery.view")):
                return order.code
        return None

    @database_sync_to_async
    def _snapshot(self, ident):
        from orders.models import Order

        order = _resolve_order(
            Order.objects.select_related("tracking").prefetch_related("delivery_tasks__agent"),
            ident,
        )
        if order is None:
            return None
        t = getattr(order, "tracking", None)
        # `order.delivery` resolves to `orders.DeliveryAssignment` — an old,
        # unrelated model nothing populates anymore (see the dead-module
        # sweep). It silently returned None here, so every field below that
        # fell back to it (agent name/phone/photo, destLat/destLng) stayed
        # empty on the very first snapshot a subscriber gets, until a live
        # `delivery.update` push (which correctly takes its `task` straight
        # from the caller, never through this relation) happened to arrive.
        # The real, current delivery lives on `delivery.DeliveryTask`.
        tasks = list(order.delivery_tasks.all())  # prefetched — no extra query
        d = tasks[0] if tasks else None
        return {
            "orderCode": order.code,
            "status": order.status,
            "deliveryStatus": d.status if d else None,
            "agentName": (t.agent_name if t else None)
            or (d.agent.name if d and d.agent else None),
            "agentPhone": (t.agent_phone if t else None)
            or (d.agent.phone if d and d.agent else None),
            "agentPhotoUrl": (t.agent_photo_url if t else None)
            or (getattr(d.agent, "avatar_url", None) if d and d.agent else None),
            "latitude": float(t.latitude) if t and t.latitude is not None else None,
            "longitude": float(t.longitude) if t and t.longitude is not None else None,
            "eta": t.eta if t else None,
            "destLat": float(d.dest_lat) if d and d.dest_lat is not None else None,
            "destLng": float(d.dest_lng) if d and d.dest_lng is not None else None,
        }


class DispatchConsumer(AsyncJsonWebsocketConsumer):
    GROUP = "dispatch"

    async def connect(self):
        user = self.scope.get("user")
        if not (user and user.is_authenticated) or user.role not in ("admin", "superadmin"):
            await self.close(code=4403)
            return
        await self.channel_layer.group_add(self.GROUP, self.channel_name)
        await self.accept()

    async def disconnect(self, code):
        await self.channel_layer.group_discard(self.GROUP, self.channel_name)

    # Channel-layer event handler (type "dispatch.update").
    async def dispatch_update(self, event):
        await self.send_json({"type": "dispatch", "data": event["data"]})
