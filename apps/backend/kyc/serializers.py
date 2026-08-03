from rest_framework import serializers

from .models import KycApplication, KycDocument, KycVerification, VerificationStep


class VerificationSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = KycVerification
        fields = ["id", "kind", "status", "verified_name", "verified_dob",
                  "id_masked", "name_match", "reference_id", "redirect_url",
                  "error_code", "provider", "consent", "verified_at", "created_at"]


class StepSerializer(serializers.ModelSerializer):
    class Meta:
        model = VerificationStep
        fields = ["step", "status", "note"]


class DocumentSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    # Working URL to the stored file (absolute when the request is in context),
    # or null for legacy JSON-only documents with no uploaded file.
    url = serializers.SerializerMethodField()
    # API-relative path to the *permission-gated* file endpoint (DocumentFileView
    # re-checks owner-or-reviewer on every fetch). This — not `url`, which is the
    # raw MEDIA path — is what a reviewer UI should load the image bytes from, the
    # same way field-verification evidence is served.
    file_url = serializers.SerializerMethodField()

    class Meta:
        model = KycDocument
        fields = ["id", "type", "number_masked", "status", "url", "file_url",
                  "latitude", "longitude"]

    def get_url(self, obj):
        if not obj.file:
            return None
        request = self.context.get("request")
        return request.build_absolute_uri(obj.file.url) if request else obj.file.url

    def get_file_url(self, obj):
        return f"/kyc/documents/{obj.pk}/file" if obj.file else None


class KycApplicationSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    steps = StepSerializer(many=True, read_only=True)
    documents = DocumentSerializer(many=True, read_only=True)

    class Meta:
        model = KycApplication
        fields = ["id", "status", "submitted_at", "reviewed_at",
                  "rejection_reason", "steps", "documents"]


class AdminKycApplicationSerializer(KycApplicationSerializer):
    """Adds applicant identity — and the gov-source verification results — for the
    admin verification queue.

    ``verifications`` is what makes the queue reviewable: it carries the name the
    government source returned, the verified DOB, the name-match flag and the
    provider, so the reviewer can compare the *declared* identity against the
    *verified* one instead of approving on a masked number alone.
    """

    user_id = serializers.CharField(source="user.id", read_only=True)
    user_name = serializers.CharField(source="user.name", read_only=True)
    user_phone = serializers.CharField(source="user.phone", read_only=True)
    verifications = VerificationSerializer(many=True, read_only=True)

    class Meta(KycApplicationSerializer.Meta):
        fields = KycApplicationSerializer.Meta.fields + [
            "user_id", "user_name", "user_phone", "verifications",
        ]


class SubmitSerializer(serializers.Serializer):
    documents = serializers.ListField(child=serializers.DictField(), required=False)


class ReviewSerializer(serializers.Serializer):
    step = serializers.CharField(required=False, allow_blank=True)
    decision = serializers.ChoiceField(choices=["approve", "reject"])
    note = serializers.CharField(required=False, allow_blank=True)

    def validate(self, attrs):
        """A rejection must carry a reason.

        The note is persisted as ``KycApplication.rejection_reason`` and shown to
        the customer — it is the only thing telling them what to fix. A blank
        rejection used to be accepted, leaving the customer with a failed KYC and
        no explanation and no way to act on it.
        """
        if attrs.get("decision") == "reject" and not (attrs.get("note") or "").strip():
            raise serializers.ValidationError(
                {"note": ["A reason is required when rejecting — the customer sees it."]}
            )
        return attrs
