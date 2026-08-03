import csv
import io

from django.http import HttpResponse
from rest_framework.response import Response
from rest_framework.views import APIView

from core.permissions import IsAdmin

from .builders import BUILDERS
from .filters import paginate_sort


def _not_found():
    return Response(
        {"error": {"code": "not_found", "message": "Unknown report", "fields": {}}},
        status=404,
    )


class ReportView(APIView):
    """JSON report: GET /reports/<name> → {title, columns, rows, summary?, charts?}.
    Supports ?date_from&date_to&store&zone filters and ?sort&dir&page&page_size."""

    permission_classes = [IsAdmin]

    def get(self, request, name):
        builder = BUILDERS.get(name)
        if not builder:
            return _not_found()
        params = request.query_params.dict()
        return Response(paginate_sort(builder(params), params))


class DashboardView(APIView):
    """GET /reports/dashboard → executive KPI widgets (single aggregation pass)."""

    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(BUILDERS["dashboard"](request.query_params.dict()))


class ReportExportView(APIView):
    """GET /reports/export?type=<name>&format=csv|excel|pdf → file download."""

    permission_classes = [IsAdmin]

    def get(self, request):
        name = request.query_params.get("type", "sales")
        # `fmt` (not `format` — that's reserved by DRF content negotiation).
        fmt = request.query_params.get("fmt", "csv")
        builder = BUILDERS.get(name)
        if not builder:
            return _not_found()
        report = builder(request.query_params.dict())
        if fmt == "excel":
            return _excel(name, report)
        if fmt == "pdf":
            return _pdf(name, report)
        return _csv(name, report)


def _csv(name, report):
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(report["columns"])
    w.writerows(report["rows"])
    resp = HttpResponse(buf.getvalue(), content_type="text/csv")
    resp["Content-Disposition"] = f'attachment; filename="{name}.csv"'
    return resp


def _excel(name, report):
    from openpyxl import Workbook

    wb = Workbook()
    ws = wb.active
    ws.title = report["title"][:31]
    ws.append(report["columns"])
    for row in report["rows"]:
        ws.append(row)
    buf = io.BytesIO()
    wb.save(buf)
    resp = HttpResponse(
        buf.getvalue(),
        content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )
    resp["Content-Disposition"] = f'attachment; filename="{name}.xlsx"'
    return resp


def _pdf(name, report):
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.platypus import SimpleDocTemplate, Table, TableStyle

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=landscape(A4))
    data = [report["columns"]] + [[str(c) for c in row] for row in report["rows"]]
    table = Table(data, repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1D9E75")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F1EFE8")]),
    ]))
    doc.build([table])
    resp = HttpResponse(buf.getvalue(), content_type="application/pdf")
    resp["Content-Disposition"] = f'attachment; filename="{name}.pdf"'
    return resp
