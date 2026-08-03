"""Gated agent login: an OTP is only sent to a phone that belongs to an ACTIVE
agent (provisioned by a store). Unknown / customer / deactivated numbers are
rejected before any OTP goes out."""
from unittest.mock import patch

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User

SEND = "/api/v1/agents/auth/send-otp"
VERIFY = "/api/v1/agents/auth/verify-otp"


class AgentLoginGateTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.agent = User.objects.create(
            phone="+919100000009", name="Ravi", role="agent", is_active=True)

    def test_send_otp_to_registered_agent(self):
        r = self.client.post(SEND, {"phone": "9100000009"}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["code"], "OTP_SENT")
        self.assertTrue(r.json()["data"]["verification_id"])

    def test_rejects_unknown_number(self):
        r = self.client.post(SEND, {"phone": "9000000000"}, format="json")
        self.assertEqual(r.json()["code"], "AGENT_NOT_REGISTERED")

    def test_rejects_customer_number(self):
        User.objects.create(phone="+919111111111", name="Cust", role="customer")
        r = self.client.post(SEND, {"phone": "9111111111"}, format="json")
        self.assertEqual(r.json()["code"], "AGENT_NOT_REGISTERED")

    def test_rejects_deactivated_agent(self):
        User.objects.create(
            phone="+919222222222", name="Old", role="agent", is_active=False)
        r = self.client.post(SEND, {"phone": "9222222222"}, format="json")
        self.assertEqual(r.json()["code"], "AGENT_NOT_REGISTERED")

    def test_verify_issues_tokens(self):
        with patch("accounts.otp.verify", return_value=True):
            r = self.client.post(VERIFY, {
                "phone": "9100000009", "otp": "123456",
                "verificationId": "vid"}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["data"]["access_token"])
        self.assertTrue(r.json()["data"]["refresh_token"])

    def test_verify_bad_otp(self):
        with patch("accounts.otp.verify", return_value=False):
            r = self.client.post(VERIFY, {
                "phone": "9100000009", "otp": "000000",
                "verificationId": "vid"}, format="json")
        self.assertEqual(r.json()["code"], "OTP_INVALID")

    def test_verify_non_agent_blocked_even_with_valid_otp(self):
        User.objects.create(phone="+919333333333", name="C", role="customer")
        with patch("accounts.otp.verify", return_value=True):
            r = self.client.post(VERIFY, {
                "phone": "9333333333", "otp": "123456",
                "verificationId": "vid"}, format="json")
        self.assertEqual(r.json()["code"], "AGENT_NOT_REGISTERED")
