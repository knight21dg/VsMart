"""Super-admin runtime settings: view/edit every integration credential from the panel.

⚠️ SECRETS ARE RETURNED IN CLEAR TEXT to super-admins. This is a deliberate owner
decision (2026-08-11) so the platform can be handed over with its credentials
visible and changeable by the receiving operator, rather than write-only values
nobody can read back or verify. It is a real reduction in blast radius on a
compromised super-admin session — the previous behaviour returned only a
`<field>_set` boolean. Anyone tightening this again should restore that flag and
add a reveal-on-demand endpoint rather than silently blanking the panel.

Both the field list and the secret list come from `runtime_settings.SEED` /
`SECRET_FIELDS`, so a newly added integration shows up here automatically. It used
to be that only the client knew which fields existed, and the Payon credit-bureau
key sat in the model for weeks with nowhere in the UI to put it.
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
            # The EFFECTIVE value, not just the stored one: `cfg()` falls back to
            # the env/settings seed when the DB column is blank. Reading the column
            # alone made a key that was working from env display as "Not set",
            # which is exactly backwards for someone auditing the handover.
            data[f] = rt.cfg(f)
            if f in rt.SECRET_FIELDS:
                data[f + "_set"] = bool(data[f])
        # Let the client mark the sensitive ones without keeping its own copy of
        # the list — that copy is how the two drift apart.
        data["secret_fields"] = sorted(rt.SECRET_FIELDS)
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
            # Blank used to mean "keep the existing secret", because the field was
            # write-only and the form could not show what was already there. Now
            # that the panel renders real values, a cleared box means the operator
            # meant to clear it — silently restoring the old key would leave a
            # credential live that they believe they removed. Fields absent from
            # the body are still untouched (see the `not in body` skip above).
            #
            # NB: clearing writes "" to the column, and `cfg()` then falls back to
            # the env/settings seed — so a key that also exists in env will still
            # be reported as effective. That is the truth, not a bug: removing it
            # for real means removing it from the environment too.
            if f == "email_port":
                try:
                    val = int(val)
                except (TypeError, ValueError):
                    continue
            elif f == "email_use_tls":
                val = val if isinstance(val, bool) else str(val).lower() in (
                    "1", "true", "yes", "on")
            else:
                # Every other column is a non-null CharField. A JSON null would
                # raise IntegrityError on save; the intent is "empty".
                val = "" if val is None else str(val)
            setattr(obj, f, val)
            changed.append(f)
        obj.updated_by = request.user if request.user.is_authenticated else None
        obj.save()
        rt.invalidate()
        record_audit(request.user, "settings.integrations.update", target=obj,
                     after={"fields": changed})
        return Response(self._serialize(obj))
