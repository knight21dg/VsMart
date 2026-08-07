"""OTP delivery via smslogin.co.

The gateway is a plain GET that answers HTTP 200 for BOTH a successful send (it
returns a MessageID) and a failure (plain text like "Invalid API Key"). Anything
that doesn't read the body would report "OTP sent" while the customer waits for
an SMS that never arrives.
"""
from unittest import mock

from django.test import TestCase

from accounts import otp


def _cfg(**overrides):
    values = {
        "sms_provider": "smslogin",
        "smslogin_api_key": "test-key",
        "smslogin_username": "Vsmart",
        "smslogin_sender_id": "VSMART",
        "smslogin_template_id": "1234567890",
        "smslogin_otp_message": "{code} is your VS Mart verification code.",
    }
    values.update(overrides)
    return lambda field: values.get(field, "")


class LocalMobileTests(TestCase):
    def test_e164_indian_number_is_reduced_to_ten_digits(self):
        self.assertEqual(otp._local_mobile("+919876543210"), "9876543210")

    def test_plain_ten_digit_number_is_unchanged(self):
        self.assertEqual(otp._local_mobile("9876543210"), "9876543210")

    def test_a_non_indian_number_is_not_mangled(self):
        self.assertEqual(otp._local_mobile("+14155550100"), "14155550100")


class SmsLoginSendTests(TestCase):
    @mock.patch("accounts.otp.runtime.cfg")
    @mock.patch("requests.get")
    def test_successful_send_passes_the_documented_params(self, mock_get, mock_cfg):
        mock_cfg.side_effect = _cfg()
        mock_get.return_value = mock.Mock(
            status_code=200, text="417a3b098442ba35", raise_for_status=mock.Mock())

        otp.send_sms("+919876543210", "482913", "login")

        params = mock_get.call_args.kwargs["params"]
        self.assertEqual(params["username"], "Vsmart")
        self.assertEqual(params["apikey"], "test-key")
        self.assertEqual(params["senderid"], "VSMART")
        # Resolved from the registered DLT map, not the fallback config.
        self.assertEqual(params["templateid"], "1777178591139204185")
        self.assertEqual(params["mobile"], "9876543210")
        # The code is substituted into the DLT body, not sent on its own.
        self.assertEqual(
            params["message"],
            "482913 is your VS Mart login OTP. Valid for 5 minutes."
            " Do not share this code with anyone.https://thevsmart.com/login")

    @mock.patch("accounts.otp.runtime.cfg")
    @mock.patch("requests.get")
    def test_an_invalid_key_reply_raises_instead_of_reporting_success(self, mock_get, mock_cfg):
        mock_cfg.side_effect = _cfg()
        mock_get.return_value = mock.Mock(
            status_code=200, text="Invalid API Key", raise_for_status=mock.Mock())

        with self.assertRaises(RuntimeError):
            otp.send_sms("+919876543210", "482913", "login")

    @mock.patch("accounts.otp.runtime.cfg")
    @mock.patch("requests.get")
    def test_running_out_of_credits_raises(self, mock_get, mock_cfg):
        mock_cfg.side_effect = _cfg()
        mock_get.return_value = mock.Mock(
            status_code=200, text="Insufficient Credits", raise_for_status=mock.Mock())

        with self.assertRaises(RuntimeError):
            otp.send_sms("+919876543210", "482913", "login")

    @mock.patch("accounts.otp.runtime.cfg")
    @mock.patch("requests.get")
    def test_a_credit_balance_reply_is_not_mistaken_for_a_message_id(self, mock_get, mock_cfg):
        """Verified against the live gateway: when the send params aren't
        accepted it answers the BALANCE query instead of erroring, and sends
        nothing. That body has no error keywords, so it would otherwise read as
        a successful send."""
        mock_cfg.side_effect = _cfg()
        mock_get.return_value = mock.Mock(
            status_code=200, text='"{\\"Credits\\":\\"9890\\"}"',
            raise_for_status=mock.Mock())

        with self.assertRaises(RuntimeError):
            otp.send_sms("+919876543210", "482913", "login")

    @mock.patch("accounts.otp.runtime.cfg")
    @mock.patch("requests.get")
    def test_an_invalid_template_reply_raises(self, mock_get, mock_cfg):
        mock_cfg.side_effect = _cfg()
        mock_get.return_value = mock.Mock(
            status_code=200, text='"{\'Error\':\'Invalid Template ID\'}"',
            raise_for_status=mock.Mock())

        with self.assertRaises(RuntimeError):
            otp.send_sms("+919876543210", "482913", "login")

    @mock.patch("accounts.otp.runtime.cfg")
    @mock.patch("requests.get")
    def test_an_empty_body_raises(self, mock_get, mock_cfg):
        mock_cfg.side_effect = _cfg()
        mock_get.return_value = mock.Mock(
            status_code=200, text="", raise_for_status=mock.Mock())

        with self.assertRaises(RuntimeError):
            otp.send_sms("+919876543210", "482913", "login")

    @mock.patch("accounts.otp.runtime.cfg")
    def test_missing_sender_id_or_template_is_named_not_silently_sent(self, mock_cfg):
        mock_cfg.side_effect = _cfg(smslogin_sender_id="")
        with self.assertRaises(RuntimeError) as ctx:
            otp.send_sms("+919876543210", "482913", "login")
        self.assertIn("smslogin_sender_id", str(ctx.exception))

    @mock.patch("accounts.otp.runtime.cfg")
    def test_console_provider_still_short_circuits(self, mock_cfg):
        mock_cfg.side_effect = _cfg(sms_provider="console")
        otp.send_sms("+919876543210", "482913", "login")  # must not raise
