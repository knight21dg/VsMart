"""Super-admin CMS: create / update legal & content pages (privacy, terms, etc.).

Public reads stay in views.py (PageListView / PageDetailView). These admin
endpoints let the super-admin console edit page content that the landing site
and apps render.
"""
from django.utils.text import slugify
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError
from core.permissions import IsAdmin

from .models import Page
from .serializers import PageAdminSerializer, PageWriteSerializer


class AdminPageListCreateView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        pages = Page.objects.all().order_by("type", "sort_order", "slug")
        return Response({"pages": PageAdminSerializer(pages, many=True).data})

    def post(self, request):
        s = PageWriteSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        data = s.validated_data
        slug = data.get("slug") or slugify(data["title"])
        page, _created = Page.objects.update_or_create(
            slug=slug,
            defaults={
                "title": data["title"],
                "body": data.get("body", ""),
                "type": data.get("type", "generic"),
                "is_active": data.get("is_active", True),
                "sort_order": data.get("sort_order", 0),
            },
        )
        return Response(PageAdminSerializer(page).data)


class AdminPageDetailView(APIView):
    permission_classes = [IsAdmin]

    def _get(self, slug):
        page = Page.objects.filter(slug=slug).first()
        if not page:
            raise AppError("NOT_FOUND", message="Page not found.")
        return page

    def get(self, request, slug):
        return Response(PageAdminSerializer(self._get(slug)).data)

    def patch(self, request, slug):
        page = self._get(slug)
        s = PageWriteSerializer(data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        for field in ("title", "body", "type", "is_active", "sort_order"):
            if field in s.validated_data:
                setattr(page, field, s.validated_data[field])
        page.save()
        return Response(PageAdminSerializer(page).data)
