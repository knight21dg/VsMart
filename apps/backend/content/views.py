from rest_framework.generics import ListAPIView
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Page
from .serializers import PageSerializer


class PageListView(ListAPIView):
    serializer_class = PageSerializer
    permission_classes = [AllowAny]
    authentication_classes = []
    pagination_class = None

    def get_queryset(self):
        qs = Page.objects.filter(is_active=True)
        page_type = self.request.query_params.get("type")
        if page_type:
            qs = qs.filter(type=page_type)
        return qs


class PageDetailView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request, slug):
        page = Page.objects.filter(slug=slug, is_active=True).first()
        if page is None:
            return Response(
                {
                    "error": {
                        "code": "not_found",
                        "message": "Page not found",
                        "fields": {},
                    }
                },
                status=404,
            )
        return Response(PageSerializer(page).data)
