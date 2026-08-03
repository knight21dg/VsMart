import importlib.util
from unittest import mock, skipUnless

from django.test import TestCase, override_settings

_HAS_FIREBASE = importlib.util.find_spec("firebase_admin") is not None

from accounts.models import DeviceToken, User
from stores.models import Store
from storeops.models import StoreStaff

from .models import Notification
from .push import send_push
from .services import _push, notify, notify_store_staff


class PushTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000000771", name="Push Tester")
        DeviceToken.objects.create(user=self.user, token="good1", platform="android")
        DeviceToken.objects.create(user=self.user, token="dead1", platform="android")

    def test_notify_writes_inbox_row(self):
        notify(self.user, type="order", title="Order placed", body="VSORD1")
        self.assertEqual(
            Notification.objects.filter(user=self.user, type="order").count(), 1
        )

    @override_settings(FIREBASE_CREDENTIALS="")
    def test_send_push_is_noop_without_credentials(self):
        # No credentials → no Firebase app → no-op, no dead tokens.
        # `override_settings` makes this HERMETIC: it used to read whatever the
        # environment had, so it passed in dev (unset) and FAILED on prod, where
        # credentials ARE configured and send_push correctly sends. The test's
        # subject is the no-credentials branch, so it must pin that itself.
        self.assertEqual(send_push(["good1"], "t", "b", {"route": "orders"}), [])

    @mock.patch("notifications.push.send_push", return_value=["dead1"])
    def test_dead_tokens_are_deactivated(self, mock_send):
        _push(self.user, "Title", "Body", {"route": "orders"})
        mock_send.assert_called_once()
        sent_tokens = set(mock_send.call_args.args[0])
        self.assertEqual(sent_tokens, {"good1", "dead1"})
        self.assertFalse(DeviceToken.objects.get(token="dead1").is_active)
        self.assertTrue(DeviceToken.objects.get(token="good1").is_active)

    @mock.patch("notifications.push.send_push", return_value=[])
    def test_live_tokens_kept(self, _mock_send):
        _push(self.user, "Title", "Body", {})
        self.assertTrue(DeviceToken.objects.get(token="good1").is_active)
        self.assertTrue(DeviceToken.objects.get(token="dead1").is_active)

    @mock.patch("notifications.push.send_push")
    def test_no_tokens_skips_send(self, mock_send):
        DeviceToken.objects.filter(user=self.user).update(is_active=False)
        _push(self.user, "Title", "Body", {})
        mock_send.assert_not_called()


class StoreStaffNotifyTests(TestCase):
    def setUp(self):
        self.store = Store.objects.create(code="ST-PUSH", name="Push Store")
        self.manager = User.objects.create(phone="+919000000781", name="Mgr")
        self.cashier = User.objects.create(phone="+919000000782", name="Cash")
        self.former = User.objects.create(phone="+919000000783", name="Gone")
        StoreStaff.objects.create(
            user=self.manager, store=self.store, staff_role="manager"
        )
        StoreStaff.objects.create(
            user=self.cashier, store=self.store, staff_role="cashier"
        )
        StoreStaff.objects.create(
            user=self.former, store=self.store, staff_role="cashier", is_active=False
        )

    def test_fans_out_to_active_staff_only(self):
        notify_store_staff(
            self.store, type="order", title="New Order", body="VSORD9 · ₹500"
        )
        self.assertEqual(Notification.objects.filter(user=self.manager).count(), 1)
        self.assertEqual(Notification.objects.filter(user=self.cashier).count(), 1)
        self.assertEqual(Notification.objects.filter(user=self.former).count(), 0)

    def test_none_store_is_noop(self):
        notify_store_staff(None, type="order", title="x")
        self.assertEqual(Notification.objects.count(), 0)


class BroadcastImageTests(TestCase):
    """broadcast() writes inbox rows and pushes with the brand logo (or a hero
    image) so the notification bubble is always branded."""

    def setUp(self):
        self.u1 = User.objects.create(phone="+919000000901", name="A")
        self.u2 = User.objects.create(phone="+919000000902", name="B")
        DeviceToken.objects.create(user=self.u1, token="tok-a", platform="android")

    def test_broadcast_creates_inbox_and_pushes_with_image(self):
        from .services import broadcast

        with mock.patch("notifications.push.send_push", return_value=[]) as sp:
            with self.captureOnCommitCallbacks(execute=True):
                sent = broadcast(
                    [self.u1, self.u2], type="promo", title="Deal", body="20% off",
                    data={"image": "https://cdn/hero.webp"},
                )
        self.assertEqual(sent, 2)
        self.assertEqual(Notification.objects.filter(type="promo").count(), 2)
        # Push fired once (batched) to the one device; the hero image is carried.
        self.assertTrue(sp.called)
        _tokens, _title, _body, data = sp.call_args.args
        self.assertEqual(data["image"], "https://cdn/hero.webp")

    @skipUnless(_HAS_FIREBASE, "firebase-admin not installed (prod-only dep)")
    def test_send_push_carries_no_image_without_one_explicitly_given(self):
        # A plain text notification (no data.image) must NOT carry any image —
        # this used to default to the static VS Mart logo on every single
        # push, including one-line text messages, wasting a re-download and
        # re-render for an image that told the user nothing.
        fake_msg = mock.MagicMock()
        captured = {}

        def _capture(**kwargs):
            captured.update(kwargs)
            return fake_msg

        import firebase_admin.messaging  # ensure the submodule attr exists to patch

        with mock.patch("notifications.push._firebase_app", return_value=object()):
            with mock.patch("firebase_admin.messaging") as m:
                m.MulticastMessage.side_effect = _capture
                m.send_each_for_multicast.return_value = mock.MagicMock(responses=[])
                send_push(["tok"], "Hi", "there", {})
        self.assertTrue(m.AndroidNotification.called)
        kwargs = m.AndroidNotification.call_args.kwargs
        self.assertIsNone(kwargs.get("image"))

    @skipUnless(_HAS_FIREBASE, "firebase-admin not installed (prod-only dep)")
    def test_send_push_still_carries_an_explicit_image(self):
        fake_msg = mock.MagicMock()
        import firebase_admin.messaging  # ensure the submodule attr exists to patch

        with mock.patch("notifications.push._firebase_app", return_value=object()):
            with mock.patch("firebase_admin.messaging") as m:
                m.MulticastMessage.side_effect = lambda **kw: fake_msg
                m.send_each_for_multicast.return_value = mock.MagicMock(responses=[])
                send_push(["tok"], "Deal", "20% off", {"image": "https://cdn/hero.webp"})
        kwargs = m.AndroidNotification.call_args.kwargs
        self.assertEqual(kwargs.get("image"), "https://cdn/hero.webp")


class UrgentAssignmentPushTests(TestCase):
    """A new delivery/collection assignment (`kind` = delivery_assignment /
    collection_assignment) goes out DATA-ONLY so the agent app's own
    full-screen alert is the only notification shown — a normal
    Android-auto-displayed tray notification alongside it would double-notify
    the agent for one assignment."""

    @skipUnless(_HAS_FIREBASE, "firebase-admin not installed (prod-only dep)")
    def test_urgent_kind_sends_no_notification_block(self):
        fake_msg = mock.MagicMock()
        captured = {}

        def _capture(**kwargs):
            captured.update(kwargs)
            return fake_msg

        import firebase_admin.messaging  # ensure the submodule attr exists to patch

        with mock.patch("notifications.push._firebase_app", return_value=object()):
            with mock.patch("firebase_admin.messaging") as m:
                m.MulticastMessage.side_effect = _capture
                m.send_each_for_multicast.return_value = mock.MagicMock(responses=[])
                send_push(["tok"], "New delivery assigned", "Order VS1 — 1 MG Road",
                           {"kind": "delivery_assignment", "taskId": "9"})
        self.assertIsNone(captured["notification"])
        self.assertEqual(captured["data"]["title"], "New delivery assigned")
        self.assertEqual(captured["data"]["body"], "Order VS1 — 1 MG Road")
        m.AndroidNotification.assert_not_called()

    @skipUnless(_HAS_FIREBASE, "firebase-admin not installed (prod-only dep)")
    def test_ordinary_kind_still_sends_a_notification_block(self):
        fake_msg = mock.MagicMock()
        import firebase_admin.messaging  # ensure the submodule attr exists to patch

        with mock.patch("notifications.push._firebase_app", return_value=object()):
            with mock.patch("firebase_admin.messaging") as m:
                m.MulticastMessage.side_effect = lambda **kw: fake_msg
                m.send_each_for_multicast.return_value = mock.MagicMock(responses=[])
                send_push(["tok"], "Delivered", "Order VS1 is delivered", {"kind": "delivery_status"})
        m.AndroidNotification.assert_called_once()
        m.Notification.assert_called_once()
