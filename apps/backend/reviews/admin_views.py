"""Admin review moderation queue.

Before this there was no takedown path at all: any user could review any product
they had never bought, and it published instantly into the product's rating.
"""
from django.shortcuts import get_object_or_404
from rest_framework import serializers
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.app_errors import AppError, ok
from core.permissions import IsAdmin

from .models import Review
from .services import moderate, moderation_queue


class AdminReviewSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    author_name = serializers.CharField(source="user.name", read_only=True)
    author_phone = serializers.CharField(source="user.phone", read_only=True)
    product_name = serializers.CharField(source="product.name", read_only=True)
    product_id = serializers.CharField(read_only=True)
    order_code = serializers.SerializerMethodField()
    moderated_by_name = serializers.CharField(
        source="moderated_by.name", read_only=True, default=None
    )

    class Meta:
        model = Review
        fields = [
            "id", "product_id", "product_name",
            "author_name", "author_phone",
            "rating", "title", "body",
            "status", "is_verified_purchase", "order_code",
            "moderation_reason", "moderated_by_name", "moderated_at",
            "created_at",
        ]

    def get_order_code(self, obj):
        return getattr(obj.order, "code", None)


class AdminReviewListView(ListAPIView):
    """GET /admin/reviews?status=pending|approved|rejected|all&search="""

    permission_classes = [IsAdmin]
    serializer_class = AdminReviewSerializer

    def get_queryset(self):
        p = self.request.query_params
        return moderation_queue(p.get("status"), p.get("search"))


class AdminReviewModerateView(APIView):
    """POST /admin/reviews/<pk>/moderate — {"decision": "approve"|"reject",
    "reason": "..."}. Rejecting hides the review and pulls it out of the
    product's rating; the row is kept for audit rather than deleted."""

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        review = get_object_or_404(Review, pk=pk)
        decision = (request.data.get("decision") or "").strip().lower()
        if decision not in ("approve", "reject"):
            raise AppError("VALIDATION_ERROR",
                           message="decision must be 'approve' or 'reject'.")
        reason = request.data.get("reason") or ""
        if decision == "reject" and not reason.strip():
            raise AppError("VALIDATION_ERROR",
                           message="A reason is required to reject a review.")

        review = moderate(review, request.user,
                          approve=decision == "approve", reason=reason)
        record_audit(request.user, f"review.{decision}", target=review,
                     after={"status": review.status})
        return Response(ok("OK", data=AdminReviewSerializer(review).data))
