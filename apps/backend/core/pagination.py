from rest_framework.pagination import CursorPagination, PageNumberPagination
from rest_framework.response import Response


class EnvelopePagination(PageNumberPagination):
    """Returns {"data": [...], "meta": {page, pageSize, total, totalPages}}."""

    page_size_query_param = "page_size"
    max_page_size = 100

    def get_paginated_response(self, data):
        return Response(
            {
                "data": data,
                "meta": {
                    "page": self.page.number,
                    "page_size": self.get_page_size(self.request),
                    "total": self.page.paginator.count,
                    "total_pages": self.page.paginator.num_pages,
                },
            }
        )


class CursorEnvelopePagination(CursorPagination):
    """Keyset/cursor pagination for large, append-heavy lists (ledgers, audit logs,
    search) — stays O(1) on deep pages where offset/page-number degrades. Returns the
    same {"data": [...], "meta": {...}} envelope; clients read `data` and follow the
    opaque `next_cursor`/`previous_cursor` instead of page numbers."""

    page_size = 50
    page_size_query_param = "page_size"
    max_page_size = 200
    ordering = "-id"  # stable, monotonic, indexed (the PK)

    def get_paginated_response(self, data):
        return Response(
            {
                "data": data,
                "meta": {
                    "page_size": self.get_page_size(self.request),
                    "next_cursor": self.get_next_link(),
                    "previous_cursor": self.get_previous_link(),
                },
            }
        )
