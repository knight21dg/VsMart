"""Agent login — phone + OTP, gated to registered agents.

Unlike the customer OTP flow (which creates an account for any number), an OTP is
only sent if the phone already belongs to an ACTIVE agent that a store onboarded.
Unknown numbers are rejected up front, so agents can only sign in with credentials
the store panel provisioned.
"""
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts import otp
from accounts.models import User
from accounts.serializers import normalize_phone
from accounts.services import issue_tokens
from core.app_errors import AppError, ok
from core.renderers import SnakeEnvelopeJSONRenderer


def _active_agent(phone: str):
    return User.objects.filter(phone=phone, role="agent", is_active=True).first()


class AgentSendOtpView(APIView):
    """POST /agents/auth/send-otp {phone} → send OTP only to a registered agent."""

    permission_classes = [AllowAny]
    authentication_classes = []
    renderer_classes = [SnakeEnvelopeJSONRenderer]
    throttle_scope = "otp"

    def post(self, request):
        phone = normalize_phone(str(request.data.get("phone", "")))
        if not _active_agent(phone):
            raise AppError("AGENT_NOT_REGISTERED")
        vid = otp.generate_and_send(phone, purpose="agent_login")
        return Response(ok("OTP_SENT", data={"verification_id": vid}))


class AgentVerifyOtpView(APIView):
    """POST /agents/auth/verify-otp {phone, otp, verification_id} → JWT tokens."""

    permission_classes = [AllowAny]
    authentication_classes = []
    renderer_classes = [SnakeEnvelopeJSONRenderer]

    def post(self, request):
        # CamelCaseJSONParser snake_cases incoming keys (verificationId → verification_id).
        phone = normalize_phone(str(request.data.get("phone", "")))
        vid = str(request.data.get("verification_id", ""))
        code = str(request.data.get("otp", ""))
        if not otp.verify(vid, phone, code):
            raise AppError("OTP_INVALID")
        user = _active_agent(phone)
        if not user:
            raise AppError("AGENT_NOT_REGISTERED")
        return Response(ok("LOGIN_OK", data=issue_tokens(user)))
