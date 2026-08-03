"""Store POS drafts — park a cart with the "Draft" button and resume it later.

Store-scoped and session-independent (a draft survives a till close/reopen), so a
cashier can hold a sale, serve the next customer, then reload the parked cart.
"""
from rest_framework import status as http
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit

from .io_utils import field
from .models import POSDraft
from .permissions import StoreScopedMixin


def _draft_row(d):
    payload = d.payload or {}
    items = payload.get("items") or []
    return {
        "id": str(d.id),
        "label": d.label or "",
        "customerName": (d.customer.name or d.customer.phone) if d.customer_id else None,
        "itemCount": sum(int(i.get("qty") or 1) for i in items),
        "total": payload.get("total"),
        "createdAt": d.created_at,
    }


class StorePOSDraftListView(StoreScopedMixin, APIView):
    """GET → this store's parked carts; POST → save the current cart as a draft."""

    store_permission = "pos.operate"

    def get(self, request):
        drafts = POSDraft.objects.filter(store=self.store).select_related("customer")[:100]
        return Response([_draft_row(d) for d in drafts])

    def post(self, request):
        from accounts.models import User

        payload = field(request.data, "payload") or {}
        if not (payload.get("items")):
            from rest_framework.exceptions import ValidationError

            raise ValidationError({"payload": ["The cart is empty."]})
        customer = None
        cid = (payload.get("customerId") or field(request.data, "customerId"))
        if cid:
            customer = User.objects.filter(pk=cid).first()
        draft = POSDraft.objects.create(
            store=self.store, created_by=request.user, customer=customer,
            label=field(request.data, "label", "") or "", payload=payload,
        )
        record_audit(request.user, "store_pos.draft_save", target=draft)
        return Response(_draft_row(draft), status=http.HTTP_201_CREATED)


class StorePOSDraftDetailView(StoreScopedMixin, APIView):
    """GET → full payload to rehydrate the cart; DELETE → discard the draft."""

    store_permission = "pos.operate"

    def _draft(self, draft_id):
        return get_object_or_404(POSDraft, pk=draft_id, store=self.store)

    def get(self, request, draft_id):
        d = self._draft(draft_id)
        return Response({**_draft_row(d), "payload": d.payload or {}})

    def delete(self, request, draft_id):
        d = self._draft(draft_id)
        d.delete()
        record_audit(request.user, "store_pos.draft_delete", target=None)
        return Response(status=http.HTTP_204_NO_CONTENT)
