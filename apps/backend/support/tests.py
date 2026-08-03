from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User

from .models import SupportTicket


class TicketCloseTests(TestCase):
    """Customer-facing ticket close: the owner may close their own ticket, the
    call is idempotent, and it is scoped so one customer can't close another's."""

    def setUp(self):
        self.owner = User.objects.create(phone="+919000800001", role="customer")
        self.other = User.objects.create(phone="+919000800002", role="customer")
        self.ticket = SupportTicket.objects.create(
            user=self.owner, category="Order", subject="Order Issue"
        )
        self.client = APIClient()

    def _close(self, user):
        self.client.force_authenticate(user)
        return self.client.post(f"/api/v1/support/tickets/{self.ticket.code}/close")

    def test_owner_can_close_ticket(self):
        r = self._close(self.owner)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["status"], SupportTicket.Status.CLOSED)
        self.ticket.refresh_from_db()
        self.assertEqual(self.ticket.status, SupportTicket.Status.CLOSED)

    def test_close_is_idempotent(self):
        self._close(self.owner)
        r = self._close(self.owner)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["status"], SupportTicket.Status.CLOSED)

    def test_non_owner_gets_404(self):
        r = self._close(self.other)
        self.assertEqual(r.status_code, 404)
        self.ticket.refresh_from_db()
        self.assertEqual(self.ticket.status, SupportTicket.Status.OPEN)


class TicketMessageAttachmentTests(TestCase):
    """The opening message carries the picked-image attachment URLs the app
    uploads to /media first."""

    def setUp(self):
        self.user = User.objects.create(phone="+919000800003", role="customer")
        self.ticket = SupportTicket.objects.create(
            user=self.user, category="Payment", subject="Payment Issue"
        )
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def test_message_persists_attachments(self):
        attachments = [{"name": "receipt.jpg", "url": "/api/v1/media/abc/medium"}]
        r = self.client.post(
            f"/api/v1/support/tickets/{self.ticket.code}/messages",
            {"body": "Charged twice", "attachments": attachments},
            format="json",
        )
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.data["attachments"], attachments)
