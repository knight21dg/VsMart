"""Best-effort real-time fan-out for delivery events.

Pushes a delivery's live position/status to the customer's order-tracking socket
(group ``order_<code>``) and the admin dispatch board (group ``dispatch``). All
sends are wrapped so a missing/misconfigured channel layer can never break the
delivery transaction — the REST polling endpoints remain the source of truth.
"""


def _payload(task):
    """Build the wire payload for a DeliveryTask (position + status + ETA)."""
    order = task.order
    t = getattr(order, "tracking", None)
    agent = getattr(task, "agent", None)
    return {
        "id": task.id,
        "orderCode": order.code,
        "status": task.status,
        "agent": agent.name if agent else None,
        "agentName": (t.agent_name if t else None) or (agent.name if agent else None),
        "agentPhone": (t.agent_phone if t else None) or (agent.phone if agent else None),
        "agentPhotoUrl": (t.agent_photo_url if t else None)
        or (getattr(agent, "avatar_url", None) if agent else None),
        "latitude": float(t.latitude) if t and t.latitude is not None else None,
        "longitude": float(t.longitude) if t and t.longitude is not None else None,
        "eta": t.eta if t else None,
        "destLat": float(task.dest_lat) if task.dest_lat is not None else None,
        "destLng": float(task.dest_lng) if task.dest_lng is not None else None,
    }


def broadcast(task):
    """Fan out ``task``'s current state to its customer + the dispatch board."""
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer

        layer = get_channel_layer()
        if layer is None:
            return
        data = _payload(task)
        async_to_sync(layer.group_send)(
            f"order_{task.order.code}",
            {"type": "delivery.update", "data": data},
        )
        async_to_sync(layer.group_send)(
            "dispatch",
            {"type": "dispatch.update", "data": data},
        )
    except Exception:  # pragma: no cover — realtime must never break delivery flow
        pass
