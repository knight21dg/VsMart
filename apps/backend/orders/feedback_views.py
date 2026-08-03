"""Order feedback — the customer rates a delivered order.

VS Mart deliberately shows no ratings on PRODUCTS (for groceries they add
nothing), so feedback is captured per ORDER instead: how the delivery went, not
what the apple was like.

The row already existed and was already raised on delivery
(`delivery.services` → `DeliveryRating`, `requested_at` stamped) — there was
simply no way to fill one in. Every rating request sat unanswered forever, and
`agent_performance`'s `rating__isnull=False` therefore always matched zero.
"""
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from rest_framework.generics import get_object_or_404
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from delivery.models import DeliveryRating

from .models import Order


def _payload(r: DeliveryRating | None):
    if r is None:
        return {"available": False, "rated": False}
    return {
        "available": True,
        "rated": r.rating is not None,
        "rating": r.rating,
        "feedback": r.feedback or "",
        "agentName": (r.agent.name or r.agent.phone) if r.agent_id else None,
        "requestedAt": r.requested_at,
        "ratedAt": r.rated_at,
    }


class OrderFeedbackView(APIView):
    """GET  /orders/<code>/feedback — is feedback open, and what was said?
    POST /orders/<code>/feedback — {rating: 1..5, feedback?: str}

    Scoped to the caller's own order. Re-submitting overwrites (a customer is
    allowed to change their mind); `rated_at` tracks the latest.
    """

    permission_classes = [IsAuthenticated]

    def _order(self, request, code):
        # Own order only — never rate someone else's delivery.
        return get_object_or_404(Order, code=code, user=request.user)

    def get(self, request, code):
        order = self._order(request, code)
        return Response(_payload(
            DeliveryRating.objects.select_related("agent").filter(order=order).first()
        ))

    def post(self, request, code):
        order = self._order(request, code)
        row = DeliveryRating.objects.select_related("agent").filter(order=order).first()
        if row is None:
            # Only a delivered order has something to rate.
            raise ValidationError(
                {"rating": ["This order isn't delivered yet."]})

        raw = request.data.get("rating")
        try:
            rating = int(raw)
        except (TypeError, ValueError):
            raise ValidationError({"rating": ["Give a rating from 1 to 5."]})
        if not 1 <= rating <= 5:
            raise ValidationError({"rating": ["Give a rating from 1 to 5."]})

        row.rating = rating
        row.feedback = str(request.data.get("feedback") or "").strip()[:300]
        row.rated_at = timezone.now()
        row.save(update_fields=["rating", "feedback", "rated_at", "updated_at"])
        return Response(_payload(row))
