from rest_framework import status as http
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Faq, SupportTicket, TicketMessage
from .serializers import (
    FaqSerializer,
    MessageCreateSerializer,
    MessageSerializer,
    TicketCreateSerializer,
    TicketDetailSerializer,
    TicketListSerializer,
)


class TicketListView(APIView):
    def get(self, request):
        tickets = SupportTicket.objects.filter(user=request.user)
        return Response(TicketListSerializer(tickets, many=True).data)

    def post(self, request):
        s = TicketCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        ticket = SupportTicket.objects.create(
            user=request.user,
            category=s.validated_data["category"],
            priority=s.validated_data.get("priority", SupportTicket.Priority.MEDIUM),
            subject=s.validated_data["subject"],
            order_code=s.validated_data.get("order_code", ""),
        )
        return Response(
            TicketDetailSerializer(ticket).data, status=http.HTTP_201_CREATED
        )


def _get_ticket(request, code):
    return get_object_or_404(SupportTicket, code=code, user=request.user)


class TicketDetailView(APIView):
    def get(self, request, code):
        return Response(TicketDetailSerializer(_get_ticket(request, code)).data)


class TicketCloseView(APIView):
    """Let the ticket owner close their own ticket. Idempotent — closing an
    already-closed ticket is a no-op that still returns the ticket. 404 if the
    ticket isn't the caller's (scoped through ``_get_ticket``)."""

    def post(self, request, code):
        ticket = _get_ticket(request, code)
        if ticket.status != SupportTicket.Status.CLOSED:
            ticket.status = SupportTicket.Status.CLOSED
            ticket.save(update_fields=["status", "updated_at"])
        return Response(TicketDetailSerializer(ticket).data)


class TicketMessageView(APIView):
    def post(self, request, code):
        ticket = _get_ticket(request, code)
        s = MessageCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        message = TicketMessage.objects.create(
            ticket=ticket,
            sender=request.user,
            body=s.validated_data["body"],
            attachments=s.validated_data.get("attachments"),
        )
        return Response(
            MessageSerializer(message).data, status=http.HTTP_201_CREATED
        )


class FaqListView(ListAPIView):
    serializer_class = FaqSerializer
    permission_classes = [AllowAny]
    authentication_classes = []
    pagination_class = None

    def get_queryset(self):
        return Faq.objects.filter(is_active=True)
