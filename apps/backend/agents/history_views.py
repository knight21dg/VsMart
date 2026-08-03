"""Agent task history — the closed work that has left an agent's active queues.

The three agent queues (`/deliveries/assigned`, `/collections/assigned`,
`/verification/tasks`) all exclude finished work by design, so a task simply
vanished from the agent's phone the moment it completed. That left an agent
unable to answer "what did I do yesterday?" or "how much did I collect?" from
the app, and gave them no record of their own work to check a payout against.

This view is the exact complement of those three queues: whatever leaves the
active list appears here. Defining it as the complement (rather than a
hand-written status list) means the two views cannot drift apart and start
showing a task twice or losing one between them.

Read-only. It reports work; it never changes it.
"""
from datetime import datetime, time
from decimal import Decimal

from django.db.models import Sum
from django.utils import timezone
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError, ok
from core.permissions import IsAgent
from delivery.models import DeliveryTask
from payments.models import CashCollection
from verification.models import VerificationTask
from verification.views import OPEN_STATUSES as VERIFICATION_OPEN

# Kinds a caller may filter to. "all" (the default) merges every kind.
KINDS = ("delivery", "collection", "verification")

DEFAULT_LIMIT = 20
MAX_LIMIT = 100

# Outcome buckets, so the app can colour a row without having to know each
# module's own status vocabulary.
SUCCESS = "success"
PARTIAL = "partial"
FAILED = "failed"

_DELIVERY_OUTCOME = {
    "delivered": SUCCESS,
    "rejected": FAILED,
    "returned_to_store": FAILED,
    "reassigned": FAILED,
    "cancelled": FAILED,
}
_COLLECTION_OUTCOME = {
    "collected": SUCCESS,
    "partially_collected": PARTIAL,
    "cancelled": FAILED,
}
_VERIFICATION_OUTCOME = {
    "approved": SUCCESS,
    "submitted": SUCCESS,   # the agent's part is done; the reviewer decides next
    "rejected": FAILED,
}


def _parse_date(raw, *, field, end_of_day=False):
    """Parse a YYYY-MM-DD bound into an aware datetime, or None if absent."""
    if not raw:
        return None
    try:
        day = datetime.strptime(str(raw).strip(), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        raise AppError("VALIDATION_ERROR", message=f"{field} must be YYYY-MM-DD.")
    stamp = datetime.combine(day, time.max if end_of_day else time.min)
    return timezone.make_aware(stamp, timezone.get_current_timezone())


def _parse_int(raw, default, *, field, low, high):
    if raw in (None, ""):
        return default
    try:
        value = int(raw)
    except (TypeError, ValueError):
        raise AppError("VALIDATION_ERROR", message=f"{field} must be a number.")
    if value < low or value > high:
        raise AppError(
            "VALIDATION_ERROR",
            message=f"{field} must be between {low} and {high}.",
        )
    return value


def _window(qs, start, end):
    """Constrain a queryset to the requested date window.

    Filtered on `created_at` — the one timestamp every task type is guaranteed
    to carry. The per-module completion stamps are nullable (a cancelled
    collection never gets a `collected_at`), so filtering on those would
    silently drop rows from the window.
    """
    if start:
        qs = qs.filter(created_at__gte=start)
    if end:
        qs = qs.filter(created_at__lte=end)
    return qs


def _money(value):
    return f"{value:.2f}" if value is not None else None


def _delivery_qs(agent, start, end):
    return _window(
        DeliveryTask.objects.filter(
            agent=agent, status__in=DeliveryTask.TERMINAL
        ).select_related("order"),
        start, end,
    )


def _delivery_row(task):
    snap = task.order.address_snapshot or {}
    return {
        "type": "delivery",
        "id": str(task.pk),
        "reference": task.order.code,
        "title": f"Order {task.order.code}",
        "subtitle": snap.get("formatted", ""),
        "customerName": snap.get("name", ""),
        "status": task.status,
        "outcome": _DELIVERY_OUTCOME.get(task.status, FAILED),
        "amount": _money(task.order.total),
        "failureReason": task.failure_reason or "",
        "attemptNo": task.attempt_no,
        # delivered_at is absent on the non-delivered terminals (rejected,
        # returned, reassigned), so fall back to when the row last moved.
        "closedAt": (task.delivered_at or task.updated_at).isoformat(),
    }


def _collection_qs(agent, start, end):
    return _window(
        CashCollection.objects.filter(
            agent=agent, status__in=CashCollection.TERMINAL
        ).select_related("user"),
        start, end,
    )


def _collection_row(coll):
    return {
        "type": "collection",
        "id": str(coll.pk),
        "reference": f"COL{coll.pk}",
        "title": f"Collected ₹{_money(coll.collected_amount)}",
        "subtitle": coll.user.name or coll.user.phone,
        "customerName": coll.user.name or "",
        "status": coll.status,
        "outcome": _COLLECTION_OUTCOME.get(coll.status, FAILED),
        "amount": _money(coll.collected_amount),
        "amountDue": _money(coll.amount),
        "failureReason": coll.failure_reason or "",
        "attemptNo": coll.attempt_no,
        # Set on collect(); cancelled rows never get one.
        "closedAt": (coll.collected_at or coll.updated_at).isoformat(),
    }


def _verification_qs(agent, start, end):
    return _window(
        VerificationTask.objects.filter(agent=agent)
        .exclude(status__in=VERIFICATION_OPEN)
        .select_related("customer"),
        start, end,
    )


def _verification_row(task):
    return {
        "type": "verification",
        "id": str(task.pk),
        "reference": f"VER{task.pk}",
        "title": f"{task.get_type_display()} verification",
        "subtitle": task.customer.name or task.customer.phone,
        "customerName": task.customer.name or "",
        "status": task.status,
        "outcome": _VERIFICATION_OUTCOME.get(task.status, FAILED),
        "amount": None,
        "recommendation": task.recommendation or "",
        "note": task.note or "",
        "closedAt": (task.submitted_at or task.updated_at).isoformat(),
    }


_SOURCES = {
    "delivery": (_delivery_qs, _delivery_row),
    "collection": (_collection_qs, _collection_row),
    "verification": (_verification_qs, _verification_row),
}


class AgentHistoryView(APIView):
    """GET /agents/history — closed tasks for the signed-in agent.

    Query: ?type=all|delivery|collection|verification &from=YYYY-MM-DD
           &to=YYYY-MM-DD &limit=1..100 &offset=0

    Scoped to `request.user` at the queryset level — an agent cannot read
    another agent's history by passing an id, because no id is accepted.
    """

    permission_classes = [IsAgent]

    def get(self, request):
        kind = (request.query_params.get("type") or "all").strip().lower()
        if kind != "all" and kind not in KINDS:
            raise AppError(
                "VALIDATION_ERROR",
                message=f"type must be one of: all, {', '.join(KINDS)}.",
            )

        start = _parse_date(request.query_params.get("from"), field="from")
        end = _parse_date(
            request.query_params.get("to"), field="to", end_of_day=True
        )
        if start and end and start > end:
            raise AppError("VALIDATION_ERROR", message="'from' must precede 'to'.")

        limit = _parse_int(
            request.query_params.get("limit"), DEFAULT_LIMIT,
            field="limit", low=1, high=MAX_LIMIT,
        )
        offset = _parse_int(
            request.query_params.get("offset"), 0,
            field="offset", low=0, high=1_000_000,
        )

        wanted = KINDS if kind == "all" else (kind,)
        querysets = {
            name: _SOURCES[name][0](request.user, start, end) for name in wanted
        }

        # Counts and the money total come from the DB over the WHOLE filtered
        # set — deriving them from the page below would make them shrink as the
        # agent scrolls, which is worse than not showing them at all.
        counts = {name: qs.count() for name, qs in querysets.items()}
        total = sum(counts.values())
        collected = Decimal("0.00")
        if "collection" in querysets:
            collected = querysets["collection"].aggregate(
                s=Sum("collected_amount")
            )["s"] or Decimal("0.00")

        # Each source only needs to yield enough rows to cover the requested
        # page after the merge — anything deeper can never surface. Keeps the
        # query bounded no matter how long an agent has been on the road.
        cap = offset + limit
        rows = []
        for name, qs in querysets.items():
            build = _SOURCES[name][1]
            rows.extend(build(obj) for obj in qs.order_by("-created_at")[:cap])

        rows.sort(key=lambda r: r["closedAt"], reverse=True)

        return Response(ok("OK", data={
            "items": rows[offset:offset + limit],
            "counts": counts,
            "total": total,
            "collectedTotal": f"{collected:.2f}",
            "hasMore": total > offset + limit,
            "limit": limit,
            "offset": offset,
        }))
