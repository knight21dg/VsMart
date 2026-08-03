from rest_framework import status as http
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import Product

from .models import Review
from .serializers import ReviewCreateSerializer, ReviewSerializer
from .services import submit_review, summary, visible_reviews


class ProductReviewsView(APIView):
    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAuthenticated()]
        return [AllowAny()]

    def get_authenticators(self):
        # Allow unauthenticated GET; POST still requires auth via permissions.
        if getattr(self.request, "method", None) == "GET":
            return []
        return super().get_authenticators()

    def get(self, request, pk):
        product = get_object_or_404(Product, pk=pk)
        # Approved only — a pending or rejected review is never public.
        return Response(
            {
                "reviews": ReviewSerializer(
                    visible_reviews(product), many=True
                ).data,
                "summary": summary(product),
            }
        )

    def post(self, request, pk):
        product = get_object_or_404(Product, pk=pk)
        s = ReviewCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        # Auto-approves a verified purchase; otherwise queues for moderation.
        review = submit_review(
            request.user, product,
            rating=s.validated_data["rating"],
            title=s.validated_data.get("title", ""),
            body=s.validated_data.get("body", ""),
        )
        return Response(
            ReviewSerializer(review).data, status=http.HTTP_201_CREATED
        )


class MyReviewsView(ListAPIView):
    """The customer's own reviews — including pending/rejected, so they can see
    a review is awaiting approval rather than silently vanishing."""

    serializer_class = ReviewSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Review.objects.none()
        return Review.objects.filter(user=self.request.user)
