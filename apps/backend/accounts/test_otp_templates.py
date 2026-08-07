"""DLT template wiring for OTP SMS.

The message body sent to smslogin.co must match the DLT-registered text exactly
or the gateway rejects it — and it rejects with HTTP 200, so a mismatch shows up
as "customers never receive OTPs" rather than an error. These tests pin the
approved text as single literals (independent of how `DLT_TEMPLATES` builds it)
so any accidental edit to the wording, spacing or URL fails loudly here.
"""
from unittest import mock

from django.test import TestCase

from accounts import otp
from core import runtime_settings as rt

# Exactly as approved on the DLT portal (2026-08-05). Do not reformat.
APPROVED = {
    "login": (
        "1777178591139204185",
        "{code} is your VS Mart login OTP. Valid for 5 minutes. Do not share this code with anyone.https://thevsmart.com/login",  # noqa: E501
    ),
    "agent_login": (
        "1777178591135927753",
        "{code} is your VS Mart Partner App login OTP. Valid for 5 minutes. Do not share this code with anyone.https://thevsmart.com/login",  # noqa: E501
    ),
    "kyc_credit": (
        "1777178591129663873",
        "{code} is your OTP to verify your mobile number for a VS Mart credit check. Valid for 5 minutes. Do not share this code with anyone.https://thevsmart.com/login",  # noqa: E501
    ),
}


class DltTemplateTests(TestCase):
    def test_registered_templates_match_the_approved_text_exactly(self):
        for purpose, (template_id, body) in APPROVED.items():
            with self.subTest(purpose=purpose):
                self.assertEqual(otp.template_for(purpose), (template_id, body))

    def test_no_space_before_the_url(self):
        """The approved templates run the URL straight on after "anyone." — a
        stray space would be a different string and get rejected."""
        for purpose in APPROVED:
            _, body = otp.template_for(purpose)
            self.assertIn("anyone.https://thevsmart.com/", body)

    def test_every_purpose_has_a_distinct_template_id(self):
        ids = [tid for tid, _ in otp.DLT_TEMPLATES.values()]
        self.assertEqual(len(ids), len(set(ids)))

    def test_password_reset_uses_the_second_approved_login_template(self):
        """No password-reset-specific template was approved, so it reuses the
        other "VS Mart login OTP" registration — same wording, distinct id, so
        the two stay separable in the gateway's delivery reports."""
        tid, body = otp.template_for("password_reset")
        self.assertEqual(tid, "1777178591167080776")
        self.assertEqual(
            body,
            "{code} is your VS Mart login OTP. Valid for 5 minutes."
            " Do not share this code with anyone.https://thevsmart.com/",
        )
        self.assertNotEqual(tid, otp.DLT_TEMPLATES["login"][0])

    def test_unregistered_purpose_falls_back_to_legacy_config(self):
        obj = rt.get_obj()
        obj.smslogin_template_id = "9999"
        obj.smslogin_otp_message = "{code} is your code."
        obj.save()
        rt.invalidate()
        self.assertEqual(
            otp.template_for("delivery_otp"), ("9999", "{code} is your code."))

    def test_unregistered_purpose_without_fallback_raises_clearly(self):
        obj = rt.get_obj()
        obj.smslogin_template_id = ""
        obj.smslogin_otp_message = ""
        obj.save()
        rt.invalidate()
        with self.assertRaises(RuntimeError) as ctx:
            otp.template_for("delivery_otp")
        self.assertIn("delivery_otp", str(ctx.exception))


class SmsloginSendTests(TestCase):
    """The right template id + rendered body reach the gateway per purpose."""

    def setUp(self):
        obj = rt.get_obj()
        obj.sms_provider = "smslogin"
        obj.smslogin_username = "Vsmart"
        obj.smslogin_api_key = "test-key"
        obj.smslogin_sender_id = "VSMART"
        obj.save()
        rt.invalidate()

    def _send(self, purpose):
        with mock.patch("requests.get") as get:
            get.return_value = mock.Mock(
                text="MessageID: 123", raise_for_status=mock.Mock())
            otp.send_sms("+919876543210", "482913", purpose)
        return get.call_args.kwargs["params"]

    def test_login_uses_its_own_template_and_renders_the_code(self):
        params = self._send("login")
        self.assertEqual(params["templateid"], "1777178591139204185")
        self.assertEqual(
            params["message"],
            "482913 is your VS Mart login OTP. Valid for 5 minutes. Do not share this code with anyone.https://thevsmart.com/login",  # noqa: E501
        )

    def test_agent_login_uses_the_partner_app_template(self):
        params = self._send("agent_login")
        self.assertEqual(params["templateid"], "1777178591135927753")
        self.assertIn("Partner App", params["message"])

    def test_kyc_credit_uses_the_credit_check_template(self):
        params = self._send("kyc_credit")
        self.assertEqual(params["templateid"], "1777178591129663873")
        self.assertIn("credit check", params["message"])

    def test_mobile_is_sent_as_bare_10_digits(self):
        self.assertEqual(self._send("login")["mobile"], "9876543210")

    def test_no_placeholder_survives_into_the_sent_body(self):
        for purpose in ("login", "agent_login", "kyc_credit"):
            with self.subTest(purpose=purpose):
                self.assertNotIn("{code}", self._send(purpose)["message"])
