"""Store-scoped marketing — send a push+inbox notification to THIS store's own
customers (users who have ordered from the store). Branded with the VS Mart logo
(or a per-campaign hero image) so the notification bubble carries the brand.
"""
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit

from .permissions import StoreScopedMixin
from .views import _store_customer_ids


class StoreNotifyImageView(StoreScopedMixin, APIView):
    """Upload a campaign hero image to the VS Mart media engine → public URL to use
    as the notification image. Field: ``file``."""

    store_permission = "marketing.send"
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        from mediastore.pipeline import ingest_public_image

        upload = request.FILES.get("file") or request.FILES.get("image")
        if upload is None:
            raise ValidationError({"file": ["An image file is required."]})
        url = ingest_public_image(upload, owner=request.user, category="marketing")
        return Response({"url": url}, status=201)


class StoreNotifyView(StoreScopedMixin, APIView):
    """GET → audience size; POST → send a notification to the store's customers."""

    store_permission = "marketing.send"

    def get(self, request):
        return Response({"customerCount": len(_store_customer_ids(self.store))})

    def post(self, request):
        from accounts.models import User

        from notifications.services import broadcast

        from .io_utils import field

        title = (field(request.data, "title") or "").strip()
        body = (field(request.data, "body") or "").strip()
        image = (field(request.data, "imageUrl") or "").strip()
        if not title:
            raise ValidationError({"title": ["A title is required."]})
        ids = _store_customer_ids(self.store)
        data = {"route": "offers", "storeId": str(self.store.id)}
        if image:
            data["image"] = image
        users = User.objects.filter(id__in=ids, is_active=True).only("id")
        # Inbox rows + real FCM push (branded), fired on commit.
        sent = broadcast(users, type="promo", title=title, body=body, data=data)
        record_audit(request.user, "store_marketing.notify", after={"count": sent})
        return Response({"sent": sent})
