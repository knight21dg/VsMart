import re

from rest_framework import serializers

from .models import AccountDeletionRequest, User

PHONE_RE = re.compile(r"^\+?\d{10,15}$")


def normalize_phone(phone: str) -> str:
    phone = phone.strip().replace(" ", "")
    if not PHONE_RE.match(phone):
        raise serializers.ValidationError("Enter a valid mobile number.")
    if not phone.startswith("+"):
        phone = "+91" + phone[-10:]  # default India
    return phone


class UserSerializer(serializers.ModelSerializer):
    # App's UserModel expects `id` as a String.
    id = serializers.CharField(read_only=True)

    class Meta:
        model = User
        fields = [
            "id",
            "phone",
            "name",
            "email",
            "role",
            "avatar_url",
            "gender",
            "date_of_birth",
            "kyc_status",
            "credit_enabled",
            "created_at",
        ]
        read_only_fields = ["id", "phone", "role", "kyc_status", "credit_enabled",
                            "created_at"]


class SendOtpSerializer(serializers.Serializer):
    phone = serializers.CharField()

    def validate_phone(self, value):
        return normalize_phone(value)


class VerifyOtpSerializer(serializers.Serializer):
    phone = serializers.CharField()
    otp = serializers.CharField(min_length=4, max_length=8)
    verification_id = serializers.CharField()

    def validate_phone(self, value):
        return normalize_phone(value)


class RegisterSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120)
    email = serializers.EmailField(required=False, allow_blank=True)


class DeviceTokenSerializer(serializers.Serializer):
    token = serializers.CharField()
    platform = serializers.ChoiceField(choices=["android", "ios", "web"])


# ── Email + password (staff/admin web login) ──
class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField()


class ForgotPasswordSerializer(serializers.Serializer):
    phone = serializers.CharField()

    def validate_phone(self, value):
        return normalize_phone(value)


class ResetPasswordSerializer(serializers.Serializer):
    phone = serializers.CharField()
    verification_id = serializers.CharField()
    code = serializers.CharField(min_length=4, max_length=8)
    new_password = serializers.CharField(min_length=8)

    def validate_phone(self, value):
        return normalize_phone(value)


class ChangePasswordSerializer(serializers.Serializer):
    """A signed-in password change.

    ``confirm_password`` is validated here rather than only in the browser: the
    endpoint is reachable without the form, and a typo silently locking someone
    out of the console is not a failure worth risking on client-side checks.
    """

    current_password = serializers.CharField()
    new_password = serializers.CharField(min_length=8)
    confirm_password = serializers.CharField(required=False, allow_blank=True)

    def validate(self, attrs):
        new = attrs["new_password"]
        confirm = attrs.get("confirm_password")
        if confirm and confirm != new:
            raise serializers.ValidationError(
                {"confirm_password": ["The two passwords don't match."]}
            )
        if new == attrs["current_password"]:
            raise serializers.ValidationError(
                {"new_password": ["Choose a password different from your current one."]}
            )
        return attrs

    def validate_new_password(self, value):
        """Run Django's configured password validators (length, common-password,
        numeric-only, similarity) so a console password is held to the same
        standard as one set through the reset flow."""
        from django.contrib.auth.password_validation import validate_password
        from django.core.exceptions import ValidationError as DjangoValidationError

        try:
            validate_password(value)
        except DjangoValidationError as exc:
            raise serializers.ValidationError(list(exc.messages))
        return value


# ── Account deletion ──
class DeletionRequestSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    contact = serializers.CharField(max_length=120)
    reason = serializers.CharField(required=False, allow_blank=True)


class DeletionRequestAdminSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = AccountDeletionRequest
        fields = ["id", "name", "contact", "reason", "status", "note",
                  "created_at", "processed_at"]
