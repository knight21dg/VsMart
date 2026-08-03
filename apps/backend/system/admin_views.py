"""Super-admin runtime settings: view/edit integration credentials (SMS/OTP, SMTP,
Razorpay, FCM) from the panel. Secrets are never returned in clear text — only a
`<field>_set` boolean — and a blank value on PATCH leaves an existing secret intact.
"""
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core import runtime_settings as rt
from core.permissions import IsSuperAdmin


class IntegrationSettingsView(APIView):
    """GET/PATCH /admin/settings/integrations — super-admin only."""

    permission_classes = [IsSuperAdmin]

    def _serialize(self, obj):
        data = {}
        for f in rt.SEED:
            if f in rt.SECRET_FIELDS:
                data[f + "_set"] = bool(getattr(obj, f))
            else:
                data[f] = getattr(obj, f)
        data["updated_at"] = obj.updated_at
        return data

    def get(self, request):
        return Response(self._serialize(rt.get_obj()))

    def patch(self, request):
        obj = rt.get_obj()
        body = request.data
        changed = []
        for f in rt.SEED:
            if f not in body:
                continue
            val = body[f]
            if f in rt.SECRET_FIELDS and (val is None or val == ""):
                continue  # blank → keep the existing secret
            if f == "email_port":
                try:
                    val = int(val)
                except (TypeError, ValueError):
                    continue
            elif f == "email_use_tls":
                val = val if isinstance(val, bool) else str(val).lower() in (
                    "1", "true", "yes", "on")
            setattr(obj, f, val)
            changed.append(f)
        obj.updated_by = request.user if request.user.is_authenticated else None
        obj.save()
        rt.invalidate()
        record_audit(request.user, "settings.integrations.update", target=obj,
                     after={"fields": changed})
        return Response(self._serialize(obj))
