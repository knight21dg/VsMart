"""Agent-side batch operations — accept a planned trip, do the store pickup
handoff, and read the sequenced route. Per-stop actions (arrive / OTP / POD /
deliver, and collect) reuse the existing single-task + collection agent endpoints,
so this layer is thin: it drives the batch envelope and derives progress from the
underlying tasks/collections.
"""
from django.db import transaction
from django.utils import timezone

from .models import BatchStop, DeliveryBatch, DeliveryTask
from .services import accept as task_accept
from .services import out_for_delivery as task_out_for_delivery
from .services import pick_up as task_pick_up

ACTIVE = ["assigned", "accepted", "picked_up", "in_progress"]
_DONE_DELIVERY = {"delivered"}
_FAIL_DELIVERY = {"failed", "returned_to_store", "cancelled", "rejected"}
_DONE_COLLECTION = {"collected", "partially_collected"}
_FAIL_COLLECTION = {"failed", "cancelled"}


def agent_current_batch(agent):
    """The agent's one active batch (if any)."""
    return (
        DeliveryBatch.objects.filter(agent=agent, status__in=ACTIVE)
        .order_by("-created_at")
        .first()
    )


def _stop_status(stop):
    if stop.kind == BatchStop.Kind.DELIVERY:
        st = stop.task.status if stop.task_id and stop.task else None
        if st in _DONE_DELIVERY:
            return "done"
        if st in _FAIL_DELIVERY:
            return "failed"
        if st == "reached":
            return "reached"
        return "pending"
    st = stop.collection.status if stop.collection_id and stop.collection else None
    if st in _DONE_COLLECTION:
        return "done"
    if st in _FAIL_COLLECTION:
        return "failed"
    return "pending"


def serialize_batch(batch):
    stops = []
    for s in batch.stops.all().select_related("task__order", "collection__user").order_by("sequence"):
        status = _stop_status(s)
        row = {
            "sequence": s.sequence,
            "kind": s.kind,
            "label": s.label,
            "status": status,
            "lat": float(s.latitude) if s.latitude is not None else None,
            "lng": float(s.longitude) if s.longitude is not None else None,
            "amount": float(s.amount or 0),
        }
        if s.kind == BatchStop.Kind.DELIVERY and s.task_id:
            row["taskId"] = s.task_id
            row["orderCode"] = s.task.order.code if s.task.order else None
            row["phone"] = (s.task.order.user.phone if s.task.order and s.task.order.user else None)
            row["address"] = (s.task.order.address_snapshot or {}).get("formatted", "")
        elif s.kind == BatchStop.Kind.COLLECTION and s.collection_id:
            row["collectionId"] = s.collection_id
            row["phone"] = s.collection.user.phone if s.collection.user else None
        stops.append(row)
    done = sum(1 for s in stops if s["status"] in ("done", "failed"))
    return {
        "id": batch.id,
        "status": batch.status,
        "priority": batch.priority,
        # NB: pickup_code is intentionally NOT exposed here — the store shows it on
        # the dispatch board and the agent enters it to confirm the handoff.
        "encodedPolyline": batch.encoded_polyline,
        "totalDistanceKm": float(batch.total_distance_km or 0),
        "etaMinutes": round((batch.estimated_duration_secs or 0) / 60),
        "store": {"name": batch.store.name, "address": batch.store.address,
                  "lat": float(batch.store.latitude) if batch.store.latitude is not None else None,
                  "lng": float(batch.store.longitude) if batch.store.longitude is not None else None},
        "progress": {"done": done, "total": len(stops)},
        "stops": stops,
    }


@transaction.atomic
def batch_accept(batch, agent):
    if batch.agent_id != agent.id:
        raise PermissionError("Not your batch.")
    if batch.status not in ("queued", "assigned"):
        return batch
    for task in batch.tasks.filter(status=DeliveryTask.Status.ASSIGNED):
        task_accept(task, agent)
    batch.status = DeliveryBatch.Status.ACCEPTED
    batch.accepted_at = timezone.now()
    batch.save(update_fields=["status", "accepted_at"])
    return batch


@transaction.atomic
def batch_pickup(batch, agent, code):
    """Store↔agent handoff: verify the pickup OTP, then move every delivery task to
    picked-up + out-for-delivery (which generates each customer's delivery OTP)."""
    if batch.agent_id != agent.id:
        raise PermissionError("Not your batch.")
    if (code or "").strip() != batch.pickup_code:
        raise ValueError("Invalid pickup code.")
    if batch.status in DeliveryBatch.TERMINAL:
        raise ValueError("Batch already closed.")
    for task in batch.tasks.all():
        if task.status == DeliveryTask.Status.ACCEPTED:
            task_pick_up(task, agent)
        if task.status == DeliveryTask.Status.PICKED_UP:
            task_out_for_delivery(task, agent)
    batch.status = DeliveryBatch.Status.IN_PROGRESS
    batch.picked_up_at = timezone.now()
    batch.save(update_fields=["status", "picked_up_at"])
    return batch


def maybe_complete_batch(batch):
    """Close the batch once every stop is terminal (called after any stop action)."""
    if batch.status in DeliveryBatch.TERMINAL:
        return batch
    stops = list(batch.stops.select_related("task", "collection").all())
    if stops and all(_stop_status(s) in ("done", "failed") for s in stops):
        batch.status = DeliveryBatch.Status.COMPLETED
        batch.completed_at = timezone.now()
        batch.save(update_fields=["status", "completed_at"])
    return batch
