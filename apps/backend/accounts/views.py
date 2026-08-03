from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from core.app_errors import AppError, ok
from core.renderers import SnakeEnvelopeJSONRenderer

from . import otp
from .models import AccountDeletionRequest, DeviceToken, Role, User
from .serializers import (
    DeletionRequestSerializer,
    DeviceTokenSerializer,
    ForgotPasswordSerializer,
    LoginSerializer,
    RegisterSerializer,
    ResetPasswordSerializer,
    SendOtpSerializer,
    UserSerializer,
    VerifyOtpSerializer,
)
from .services import get_or_create_customer, issue_tokens


class SendOtpView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []
    renderer_classes = [SnakeEnvelopeJSONRenderer]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "otp"

    def post(self, request):
        s = SendOtpSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        phone = s.validated_data["phone"]
        verification_id = otp.generate_and_send(phone, purpose="login")
        return Response({"verification_id": verification_id})


class VerifyOtpView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []
    renderer_classes = [SnakeEnvelopeJSONRenderer]

    def post(self, request):
        s = VerifyOtpSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        data = s.validated_data
        if not otp.verify(data["verification_id"], data["phone"], data["otp"]):
            from core.app_errors import AppError

            raise AppError(
                "OTP_INVALID",
                message="That code is invalid or has expired. Please request a new one.",
            )
        user, created = get_or_create_customer(data["phone"])
        tokens = issue_tokens(user)
        return Response(
            {
                **tokens,
                "is_new_user": created or not user.has_profile,
                "user": UserSerializer(user).data,
            }
        )


class LoginView(APIView):
    """Email + password sign-in for staff/admin (store-admin & super-admin consoles)."""

    permission_classes = [AllowAny]
    authentication_classes = []
    renderer_classes = [SnakeEnvelopeJSONRenderer]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "otp"

    def post(self, request):
        from core.app_errors import AppError

        s = LoginSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        email = s.validated_data["email"].strip().lower()
        password = s.validated_data["password"]
        user = User.objects.filter(email__iexact=email).first()
        if not user or not user.has_usable_password() or not user.check_password(password):
            raise AppError("INVALID_CREDENTIALS")
        if not user.is_active:
            raise AppError("ACCOUNT_DISABLED")
        tokens = issue_tokens(user)
        return Response({
            **tokens,
            "is_new_user": False,
            "user": UserSerializer(user).data,
        })


class ForgotPasswordView(APIView):
    """Start a password reset: SMS a one-time OTP to the account's phone."""

    permission_classes = [AllowAny]
    authentication_classes = []
    renderer_classes = [SnakeEnvelopeJSONRenderer]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "otp"

    def post(self, request):
        from core.app_errors import ok

        s = ForgotPasswordSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        phone = s.validated_data["phone"]
        verification_id = otp.generate_and_send(phone, purpose="password_reset")
        return Response(ok("PASSWORD_RESET_SENT", data={"verificationId": verification_id}))


class ResetPasswordView(APIView):
    """Complete a password reset with the texted OTP + a new password."""

    permission_classes = [AllowAny]
    authentication_classes = []
    renderer_classes = [SnakeEnvelopeJSONRenderer]

    def post(self, request):
        from core.app_errors import AppError, ok

        s = ResetPasswordSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        data = s.validated_data
        if not otp.verify(data["verification_id"], data["phone"], data["code"]):
            raise AppError("INVALID_RESET_CODE")
        # Only email+password login roles (staff/admin) may reset this way. Customer/
        # agent accounts are phone-OTP-only and are created with no password at all —
        # has_usable_password() can't be trusted to gate this: Django treats an unset
        # (blank) password as "usable" unless set_unusable_password() was called, which
        # nothing in the customer/agent creation path ever does.
        user = User.objects.filter(phone=data["phone"]).first()
        if not user or user.role not in (Role.SUPERADMIN, Role.ADMIN, Role.STORE_STAFF):
            raise AppError("INVALID_RESET_CODE")
        user.set_password(data["new_password"])
        user.save(update_fields=["password"])
        return Response(ok("PASSWORD_RESET_OK"))


class AccountDeletionRequestView(APIView):
    """Public account/data deletion request (Play Store compliance)."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "otp"

    def post(self, request):
        from core.app_errors import ok

        s = DeletionRequestSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        contact = s.validated_data["contact"].strip()
        user = (User.objects.filter(email__iexact=contact).first()
                or User.objects.filter(phone=contact).first())
        AccountDeletionRequest.objects.create(
            user=user,
            name=s.validated_data.get("name", ""),
            contact=contact,
            reason=s.validated_data.get("reason", ""),
        )
        return Response(ok("DELETION_REQUEST_RECEIVED"))


class RegisterView(APIView):
    """Completes the profile (name/email) right after first OTP login."""

    permission_classes = [IsAuthenticated]
    renderer_classes = [SnakeEnvelopeJSONRenderer]

    def post(self, request):
        s = RegisterSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = request.user
        user.name = s.validated_data["name"]
        if s.validated_data.get("email"):
            user.email = s.validated_data["email"]
        user.save(update_fields=["name", "email"])
        return Response(UserSerializer(user).data)


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        DeviceToken.objects.filter(user=request.user).update(is_active=False)
        # Revoke the refresh token so it can't mint new access tokens after logout.
        token = request.data.get("refresh") or request.data.get("refresh_token")
        if token:
            try:
                RefreshToken(token).blacklist()
            except Exception:
                pass  # already invalid/expired — nothing to revoke
        return Response({"status": "logged_out"})


class MeView(APIView):
    permission_classes = [IsAuthenticated]
    renderer_classes = [SnakeEnvelopeJSONRenderer]

    def get(self, request):
        return Response(UserSerializer(request.user).data)

    def patch(self, request):
        s = UserSerializer(request.user, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        s.save()
        return Response(s.data)


class AvatarUploadView(APIView):
    """Authenticated multipart avatar upload. Ingests the image through the
    self-hosted media engine as a PUBLIC asset (avatars render without auth),
    points the user's avatar_url at the served medium variant, and returns it."""

    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]
    renderer_classes = [SnakeEnvelopeJSONRenderer]

    def post(self, request):
        from mediastore.pipeline import store_image

        upload = request.FILES.get("file") or request.FILES.get("avatar")
        if upload is None:
            raise AppError("VALIDATION_ERROR", fields={"file": ["A file is required."]})
        asset = store_image(
            upload,
            category="avatar",
            owner=request.user,
            visibility="public",
            original_name=getattr(upload, "name", ""),
        )
        request.user.avatar_url = f"/api/v1/media/public/{asset.id}/medium"
        request.user.save(update_fields=["avatar_url"])
        return Response(
            ok("MEDIA_UPLOADED", data={"avatar_url": request.user.avatar_url}),
            status=201,
        )


class DeviceTokenView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        s = DeviceTokenSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        DeviceToken.objects.update_or_create(
            user=request.user,
            token=s.validated_data["token"],
            defaults={"platform": s.validated_data["platform"], "is_active": True},
        )
        return Response({"status": "registered"})


class RefreshTokenView(APIView):
    """Exchange a refresh token for a new access token, returning snake_case keys
    (access_token/refresh_token) to match the app's AuthTokenModel."""

    permission_classes = [AllowAny]
    authentication_classes = []
    renderer_classes = [SnakeEnvelopeJSONRenderer]

    def post(self, request):
        token = request.data.get("refresh") or request.data.get("refresh_token")
        if not token:
            return Response(
                {"error": {"code": "bad_request", "message": "refresh token required",
                           "fields": {}}}, status=status.HTTP_400_BAD_REQUEST)
        try:
            old = RefreshToken(token)
        except Exception:
            return Response(
                {"error": {"code": "invalid_token", "message": "Invalid or expired token",
                           "fields": {}}}, status=status.HTTP_401_UNAUTHORIZED)
        user = User.objects.filter(pk=old.get("user_id"), is_active=True).first()
        if user is None:
            return Response(
                {"error": {"code": "invalid_token", "message": "Invalid or expired token",
                           "fields": {}}}, status=status.HTTP_401_UNAUTHORIZED)
        # NO rotation. This used to blacklist the presented refresh token and mint
        # a fresh pair on EVERY 30-min refresh — if the app process died (or secure
        # storage hiccupped) before the new pair was persisted, the only surviving
        # token was already blacklisted and the customer was force-signed-out
        # mid-session ("authentication credentials were not provided" storms).
        # The refresh token now stays valid for its full lifetime; explicit logout
        # still blacklists it (LogoutView above).
        access = old.access_token
        access["role"] = user.role
        return Response({
            "access_token": str(access),
            "refresh_token": str(old),
        })
