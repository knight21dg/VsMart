"""Support admin (spec §MODULE 19): the agent/admin ticket queue — list all tickets,
reply, change status/priority, assign, escalate."""
from rest_framework import serializers
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.services import record_audit
from core.permissions import IsAdmin
from reports.filters import user_store_zone_map

from .models import SupportTicket, TicketMessage


class AdminTicketSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    user_name = serializers.CharField(source="user.name", read_only=True)
    user_phone = serializers.CharField(source="user.phone", read_only=True)
    assigned_to_name = serializers.CharField(source="assigned_to.name", read_only=True, default=None)

    class Meta:
        model = SupportTicket
        fields = [
            "id", "code", "category", "priority", "subject", "status", "order_code",
            "user_name", "user_phone", "assigned_to_name", "created_at",
        ]


class AdminTicketMessageSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    sender_name = serializers.CharField(source="sender.name", read_only=True)
    sender_role = serializers.CharField(source="sender.role", read_only=True)

    class Meta:
        model = TicketMessage
        fields = ["id", "body", "sender_name", "sender_role", "created_at"]


class AdminTicketListView(APIView):
    """All tickets, attributed to the customer's serving store + zone, with status/
    priority/category/store/zone filters and a status summary."""

    permission_classes = [IsAdmin]

    def get(self, request):
        umap = user_store_zone_map()
        qs = SupportTicket.objects.select_related("user", "assigned_to").all()
        for field in ("status", "priority", "category"):
            v = request.query_params.get(field)
            if v:
                qs = qs.filter(**{field: v})
        q = request.query_params.get("q")
        if q:
            qs = qs.filter(subject__icontains=q)
        store = request.query_params.get("store")
        zone = request.query_params.get("zone")
        if store or zone:
            allowed = {
                uid for uid, m in umap.items()
                if (not store or str(m.get("store_id")) == store) and (not zone or str(m.get("zone_id")) == zone)
            }
            qs = qs.filter(user_id__in=allowed)

        rows = []
        for t in qs:
            d = AdminTicketSerializer(t).data
            loc = umap.get(t.user_id, {})
            d["storeName"] = loc.get("store__name")
            d["zoneName"] = loc.get("zone__name")
            rows.append(d)

        # Status summary across the unfiltered ticket set (for the header counters).
        summary = {
            s: SupportTicket.objects.filter(status=s).count()
            for s in ["open", "in_progress", "resolved", "closed"]
        }
        return Response({"tickets": rows, "summary": summary})


class AdminTicketDetailView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, code):
        ticket = get_object_or_404(SupportTicket.objects.select_related("user", "assigned_to"), code=code)
        data = AdminTicketSerializer(ticket).data
        data["messages"] = AdminTicketMessageSerializer(
            ticket.messages.select_related("sender").all(), many=True
        ).data
        return Response(data)


class AdminTicketReplyView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, code):
        ticket = get_object_or_404(SupportTicket, code=code)
        body = (request.data.get("body") or "").strip()
        if not body:
            return Response(
                {"error": {"code": "bad_request", "message": "Message is required.", "fields": {}}},
                status=400,
            )
        msg = TicketMessage.objects.create(ticket=ticket, sender=request.user, body=body)
        if ticket.status == SupportTicket.Status.OPEN:
            ticket.status = SupportTicket.Status.IN_PROGRESS
            ticket.save(update_fields=["status", "updated_at"])
        return Response(AdminTicketMessageSerializer(msg).data, status=201)


class AdminTicketUpdateView(APIView):
    permission_classes = [IsAdmin]

    def patch(self, request, code):
        ticket = get_object_or_404(SupportTicket, code=code)
        data = request.data
        fields = []
        if "status" in data:
            ticket.status = data["status"]
            fields.append("status")
        if "priority" in data:
            ticket.priority = data["priority"]
            fields.append("priority")
        assignee = data.get("assigned_to") or data.get("assignedTo")
        if assignee is not None:
            ticket.assigned_to = User.objects.filter(pk=assignee).first() if assignee else None
            fields.append("assigned_to")
        if fields:
            fields.append("updated_at")
            ticket.save(update_fields=fields)
            record_audit(request.user, "support.update", target=ticket,
                         after={k: data.get(k) for k in ("status", "priority")})
        return Response(AdminTicketSerializer(ticket).data)
