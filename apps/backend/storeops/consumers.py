"""WebSocket consumer for real-time new-order alerts on the Store panel.

Fed by :func:`storeops.realtime.broadcast_new_order`, called from
`orders.services.place_order` the moment an order is routed to a store.
Store staff get a live "New Order" push while the tab is open (even
backgrounded) — sound + banner is the frontend's job, this just delivers the
event. Auth reuses the same store-membership resolution as the REST API.
"""
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer


class StoreOrdersConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope.get("user")
        store_id = await self._resolve_store(user)
        if store_id is None:
            await self.close(code=4403)
            return
        self.group = f"store_orders_{store_id}"
        await self.channel_layer.group_add(self.group, self.channel_name)
        await self.accept()

    async def disconnect(self, code):
        if getattr(self, "group", None):
            await self.channel_layer.group_discard(self.group, self.channel_name)

    # Channel-layer event handler (type "store.new_order").
    async def store_new_order(self, event):
        await self.send_json({"type": "new_order", "data": event["data"]})

    @database_sync_to_async
    def _resolve_store(self, user):
        if not (user and user.is_authenticated):
            return None
        from .permissions import get_membership

        membership = get_membership(user)
        return str(membership.store_id) if membership else None
