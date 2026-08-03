from django.core.exceptions import ValidationError
from django.db.models import Q
from django.utils import timezone
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError
from core.permissions import IsAgent
from mediastore.models import MediaAsset
from mediastore.pipeline import store_image
from mediastore.serving import serve_storage_key

from .models import VerificationEvidence, VerificationTask
from .serializers import (
    EvidenceSerializer,
    GpsSerializer,
    PhotoSerializer,
    SubmitSerializer,
    TaskDetailSerializer,
    TaskListSerializer,
)

OPEN_STATUSES = ["pending", "assigned", "in_progress"]


def _notify_reviewer(task):
    """Tell the store staff who manage this customer that the field visit is in —
    with the agent's recommendation — so a human reviewer decides. Best-effort."""
    app = task.kyc_application
    if app is None:
        return
    try:
        from notifications.services import notify
        from storeops.models import StoreStaff
        from stores.services import resolve_user_store

        store = resolve_user_store(app.user)
        recipients = []
        if store is not None:
            recipients = [
                m.user
                for m in StoreStaff.objects.filter(
                    store=store, is_active=True
                ).select_related("user")
            ]
        rec = task.get_recommendation_display() if task.recommendation else "submitted"
        for user in recipients:
            notify(
                user, type="kyc",
                title="Field verification submitted",
                body=f"{task.customer.name or task.customer.phone}: agent recommends "
                     f"{rec.lower()}. Review to decide.",
                data={"kycAppId": str(app.id), "taskId": str(task.id),
                      "kind": "field_verification_submitted", "route": "verification"},
            )
    except Exception:  # pragma: no cover - notification must never block submit
        pass


class TaskListView(ListAPIView):
    serializer_class = TaskListSerializer
    permission_classes = [IsAgent]
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return VerificationTask.objects.none()
        return VerificationTask.objects.filter(
            Q(agent=self.request.user) | Q(agent__isnull=True),
            status__in=OPEN_STATUSES,
        )


class TaskDetailView(APIView):
    permission_classes = [IsAgent]

    def get(self, request, pk):
        task = get_object_or_404(VerificationTask, pk=pk)
        return Response(TaskDetailSerializer(task).data)


class TaskStartView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = get_object_or_404(VerificationTask, pk=pk)
        task.agent = request.user
        task.status = "in_progress"
        task.save(update_fields=["agent", "status", "updated_at"])
        return Response(TaskDetailSerializer(task).data)


class TaskSubmitView(APIView):
    permission_classes = [IsAgent]

    def post(self, request, pk):
        task = get_object_or_404(VerificationTask, pk=pk)
        s = SubmitSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        # The agent RECOMMENDS; they never approve/reject the KYC themselves. The
        # decision field maps to a recommendation, the task always lands in
        # SUBMITTED, and the store/admin reviewer makes the final call. This closes
        # the loop that used to let a field agent self-adjudicate.
        decision = s.validated_data.get("decision")
        rec_map = {
            "approve": VerificationTask.Recommendation.APPROVE,
            "reject": VerificationTask.Recommendation.REJECT,
        }
        task.recommendation = rec_map.get(
            decision, VerificationTask.Recommendation.INCONCLUSIVE
        )
        task.status = VerificationTask.Status.SUBMITTED
        note = s.validated_data.get("note")
        if note is not None:
            task.note = note
        task.submitted_at = timezone.now()
        task.save(update_fields=[
            "status", "recommendation", "note", "submitted_at", "updated_at",
        ])
        _notify_reviewer(task)
        return Response(TaskDetailSerializer(task).data)


class PhotoView(APIView):
    # Accept a multipart `file`/`photo` image upload (preferred — ingested through
    # the self-hosted media engine) AND/OR the legacy JSON `photo_key` string.
    # JSON-only submits still work; a missing photo is allowed (no-op key).
    permission_classes = [IsAgent]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request):
        s = PhotoSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        task = get_object_or_404(VerificationTask, pk=s.validated_data["task_id"])

        upload = request.FILES.get("file") or request.FILES.get("photo")
        if upload is not None:
            # Owner the asset to the customer being verified so they can fetch it
            # later; the verifying agent / staff are also authorised at serve time.
            asset = store_image(
                upload,
                category="verification",
                owner=task.customer,
                visibility="private",
                original_name=getattr(upload, "name", ""),
            )
            photo_key = str(asset.id)
        else:
            # Backward compatible: no file → fall back to the loose string key
            # (or empty string when neither is supplied).
            photo_key = s.validated_data.get("photo_key", "") or ""

        evidence = VerificationEvidence.objects.create(
            task=task, kind="photo", photo_key=photo_key
        )
        return Response(EvidenceSerializer(evidence).data, status=201)


class EvidencePhotoView(APIView):
    """Stream a field-verification photo only to people allowed to see it: the
    customer being verified, the verifying agent, or staff (admin/superadmin).
    Everyone else gets 403. Resolves the MediaAsset from the evidence's
    ``photo_key`` and serves its ``medium`` variant. 404 if there is no photo."""

    def get(self, request, pk):
        try:
            evidence = VerificationEvidence.objects.select_related(
                "task", "task__customer", "task__agent"
            ).get(pk=pk)
        except VerificationEvidence.DoesNotExist:
            raise AppError("NOT_FOUND")

        task = evidence.task
        user = request.user
        is_staff = getattr(user, "role", "") in ("admin", "superadmin")
        is_customer = task.customer_id == user.id
        is_agent = task.agent_id is not None and task.agent_id == user.id
        if not (is_staff or is_customer or is_agent):
            raise AppError("INSUFFICIENT_PERMISSIONS")

        if not evidence.photo_key:
            raise AppError("NOT_FOUND")
        try:
            asset = MediaAsset.objects.get(pk=evidence.photo_key)
        except (MediaAsset.DoesNotExist, ValueError, ValidationError):
            # Legacy loose-string key that isn't a MediaAsset UUID → nothing to serve.
            raise AppError("NOT_FOUND")

        resp = serve_storage_key(
            asset.variant_key("medium"), content_type=asset.content_type
        )
        resp["Cache-Control"] = "private, max-age=60"
        return resp


class GpsView(APIView):
    permission_classes = [IsAgent]

    def post(self, request):
        s = GpsSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        task = get_object_or_404(VerificationTask, pk=s.validated_data["task_id"])
        evidence = VerificationEvidence.objects.create(
            task=task,
            kind="gps",
            latitude=s.validated_data["latitude"],
            longitude=s.validated_data["longitude"],
        )
        return Response(EvidenceSerializer(evidence).data, status=201)
