"""Best-effort real-time fan-out for the Store panel.

Mirrors delivery.realtime's shape: wrapped so a missing/misconfigured channel
layer can never break checkout — the REST order list remains the source of
truth, this just pushes a live "New Order" alert to any staff with the panel
open (sound + banner is the frontend's job).
"""


def _payload(order):
    return {
        "code": order.code,
        "placedAt": order.placed_at.isoformat() if order.placed_at else None,
        "customer": (order.user.name or order.user.phone) if order.user else None,
        "items": order.items.count(),
        "value": float(order.total),
        "paymentMethod": order.payment_method,
    }


def broadcast_new_order(order):
    """Fan out a just-placed order to its serving store's live panel(s)."""
    if not order.store_id:
        return
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer

        layer = get_channel_layer()
        if layer is None:
            return
        async_to_sync(layer.group_send)(
            f"store_orders_{order.store_id}",
            {"type": "store.new_order", "data": _payload(order)},
        )
    except Exception:  # pragma: no cover — realtime must never break checkout
        pass
