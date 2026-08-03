from djangorestframework_camel_case.render import CamelCaseJSONRenderer
from rest_framework.renderers import JSONRenderer


def _envelope(data):
    """Wrap a payload in the enterprise envelope:
        success: {success, message, data, meta?}   error: {success, message, error}
    `data` is always present on success (the Flutter app unwraps `data`)."""
    # Already a fully-formed actionable response (core.app_errors.error_body / ok)
    # — pass it through untouched so code/title/action/severity/next_step survive.
    if isinstance(data, dict) and "success" in data and "code" in data:
        return data
    if isinstance(data, dict) and "error" in data:
        err = data["error"]
        out = {
            "success": False,
            "message": err.get("message", "") if isinstance(err, dict) else str(err),
            "error": err,
        }
        # Preserve RFC 9457 problem-details members when the handler supplied them.
        for k in ("type", "title", "status", "detail", "instance"):
            if k in data:
                out[k] = data[k]
        return out
    if isinstance(data, dict) and "data" in data:
        out = {"success": True, "message": data.get("message", ""), "data": data["data"]}
        if "meta" in data:
            out["meta"] = data["meta"]
        return out
    return {"success": True, "message": "", "data": data}


class EnvelopeJSONRenderer(CamelCaseJSONRenderer):
    """Default renderer — envelope + camelCase keys (catalog, cart, orders, …)."""

    def render(self, data, accepted_media_type=None, renderer_context=None):
        return super().render(_envelope(data), accepted_media_type, renderer_context)


class SnakeEnvelopeJSONRenderer(JSONRenderer):
    """Envelope WITHOUT camelCasing — for the auth/user endpoints, whose Flutter
    models use snake_case keys (access_token, refresh_token, kyc_status, …)."""

    def render(self, data, accepted_media_type=None, renderer_context=None):
        return super().render(_envelope(data), accepted_media_type, renderer_context)
