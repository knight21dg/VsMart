"""POS admin oversight (spec §MODULE 12): walk-in sales across registers, attributed
to the store + terminal that rang them up."""
from rest_framework.response import Response
from rest_framework.views import APIView

from core.permissions import IsAdmin

from .models import POSTransaction


class AdminPosTransactionsView(APIView):
    """GET /admin/pos/transactions?store=&type= — transactions with store + register."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from stores.models import Store

        wh_to_store = {s.warehouse_id: s.name for s in Store.objects.filter(warehouse__isnull=False)}
        qs = POSTransaction.objects.select_related("session").order_by("-created_at")
        t = request.query_params.get("type")
        if t:
            qs = qs.filter(type=t)
        store = request.query_params.get("store")
        if store:
            s = Store.objects.filter(pk=store).select_related("warehouse").first()
            qs = qs.filter(session__warehouse_id=s.warehouse_id) if (s and s.warehouse_id) else qs.none()

        rows = []
        sales_total = 0
        sales_count = 0
        for x in qs[:300]:
            wid = x.session.warehouse_id if x.session_id else None
            if x.type == POSTransaction.Type.SALE and not x.is_voided:
                sales_total += float(x.total)
                sales_count += 1
            rows.append({
                "id": str(x.id),
                "code": x.code,
                "type": x.type,
                "storeName": wh_to_store.get(wid),
                "terminal": x.session.terminal if x.session_id else "",
                "subtotal": x.subtotal,
                "tax": x.tax,
                "discount": x.discount,
                "total": x.total,
                "paymentStatus": x.payment_status,
                "creditUsed": x.credit_used,
                "isVoided": x.is_voided,
                "createdAt": x.created_at,
            })
        return Response({
            "transactions": rows,
            "summary": {"count": len(rows), "salesCount": sales_count, "salesTotal": round(sales_total, 2)},
        })
