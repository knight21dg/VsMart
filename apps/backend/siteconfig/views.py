from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.permissions import IsAdmin, IsSuperAdmin

from .models import PlatformConfig
from .serializers import PlatformConfigSerializer


class ConfigView(APIView):
    """Read by admin; edit by superadmin only (money levers are superadmin-gated)."""

    def get_permissions(self):
        return [IsSuperAdmin()] if self.request.method == "PATCH" else [IsAdmin()]

    def get(self, request):
        return Response(PlatformConfigSerializer(PlatformConfig.load()).data)

    def patch(self, request):
        config = PlatformConfig.load()
        before = PlatformConfigSerializer(config).data
        s = PlatformConfigSerializer(config, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        s.save()
        record_audit(request.user, "config.update", target=config,
                     before=before, after=s.data)
        return Response(s.data)


class PublicSupportContactView(APIView):
    """The fallback support phone/email for Help & Support — public (no auth,
    every customer needs it, including a signed-out one) and deliberately
    narrow: PlatformConfig also holds real business levers (fees, credit
    limits) that must stay admin-only, so this exposes only the two contact
    fields, not the whole config."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        config = PlatformConfig.load()
        return Response({
            "supportPhone": config.support_phone,
            "supportEmail": config.support_email,
        })
