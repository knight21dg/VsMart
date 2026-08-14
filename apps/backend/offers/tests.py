import io
import tempfile
from datetime import timedelta
from decimal import Decimal

from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product
from inventory.models import StockItem, Warehouse
from offers.models import BannerEvent, Coupon, Offer
from stores.models import Store
from system.models import FeatureFlag
from zones.models import Zone


def _data(resp):
    body = resp.json()["data"]
    return body["results"] if isinstance(body, dict) and "results" in body else body


def _titles(resp):
    return {o["title"] for o in _data(resp)}


def _png_bytes(w=2400, h=1200, color=(20, 120, 80)):
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (w, h), color).save(buf, "PNG")
    return buf.getvalue()


class BannerFeedTests(TestCase):
    """Public feed: scheduling window + state + zone/store targeting + in-stock drop."""

    def setUp(self):
        self.client = APIClient()
        self.now = timezone.now()

    def _banner(self, title, **kw):
        kw.setdefault("type", Offer.Type.BANNER)
        kw.setdefault("placement", Offer.Placement.TOP)
        kw.setdefault("state", Offer.State.ACTIVE)
        return Offer.objects.create(title=title, **kw)

    def test_active_in_window_shown(self):
        self._banner("Live")
        self.assertIn("Live", _titles(self.client.get("/api/v1/offers?type=banner")))

    def test_expired_hidden(self):
        self._banner("Gone", valid_to=self.now - timedelta(days=1))
        self.assertNotIn("Gone", _titles(self.client.get("/api/v1/offers?type=banner")))

    def test_future_scheduled_hidden(self):
        self._banner("Soon", state=Offer.State.SCHEDULED,
                     valid_from=self.now + timedelta(days=1))
        self.assertNotIn("Soon", _titles(self.client.get("/api/v1/offers?type=banner")))

    def test_scheduled_within_window_shown(self):
        # SCHEDULED + start already passed → auto-publishes without the sweep running.
        self._banner("Auto", state=Offer.State.SCHEDULED,
                     valid_from=self.now - timedelta(minutes=5))
        self.assertIn("Auto", _titles(self.client.get("/api/v1/offers?type=banner")))

    def test_draft_paused_archived_hidden(self):
        for st in (Offer.State.DRAFT, Offer.State.PAUSED, Offer.State.ARCHIVED):
            self._banner(f"X-{st}", state=st)
        self.assertEqual(_titles(self.client.get("/api/v1/offers?type=banner")), set())

    def test_global_shown_without_location(self):
        self._banner("Global")
        self.assertIn("Global", _titles(self.client.get("/api/v1/offers?type=banner")))

    def test_store_specific_not_leaked_without_location(self):
        wh = Warehouse.objects.create(code="W1", name="WH1", is_default=True)
        store = Store.objects.create(code="S1", name="S1", warehouse=wh)
        self._banner("StoreOnly", store=store)
        self._banner("Global")
        titles = _titles(self.client.get("/api/v1/offers?type=banner"))
        self.assertIn("Global", titles)
        self.assertNotIn("StoreOnly", titles)  # no leak to other areas

    def test_store_specific_shown_and_ranked_first(self):
        wh = Warehouse.objects.create(code="W1", name="WH1", is_default=True)
        store = Store.objects.create(code="S1", name="S1", warehouse=wh)
        Zone.objects.create(name="Z1", code="Z1", store=store, pincodes=["500001"])
        self._banner("Global", sort_order=0)
        self._banner("StoreOnly", store=store, sort_order=5)
        data = _data(self.client.get("/api/v1/offers?type=banner&pincode=500001"))
        titles = [o["title"] for o in data]
        self.assertIn("StoreOnly", titles)
        self.assertIn("Global", titles)
        self.assertLess(titles.index("StoreOnly"), titles.index("Global"))  # specificity

    def test_product_banner_dropped_when_not_carried(self):
        FeatureFlag.objects.create(key="zone_store_visibility", enabled=True)
        cat = Category.objects.create(name="Grocery")
        wh = Warehouse.objects.create(code="W1", name="WH1", is_default=True)
        store = Store.objects.create(code="S1", name="S1", warehouse=wh)
        Zone.objects.create(name="Z1", code="Z1", store=store, pincodes=["500001"])
        carried = Product.objects.create(name="Rice", price=Decimal("50"),
                                         mrp=Decimal("60"), category=cat)
        absent = Product.objects.create(name="Oil", price=Decimal("50"),
                                        mrp=Decimal("60"), category=cat)
        StockItem.objects.create(product=carried, warehouse=wh, quantity=10)
        StockItem.objects.create(product=absent, warehouse=wh, quantity=0)
        self._banner("DeadTap", action=Offer.Action.PRODUCT,
                     payload={"product_id": absent.id})
        self._banner("Plain")
        titles = _titles(self.client.get("/api/v1/offers?type=banner&pincode=500001"))
        self.assertNotIn("DeadTap", titles)   # product not carried → dropped
        self.assertIn("Plain", titles)


class BannerAdminTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919888880001", name="A", role="admin")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def _create(self, **body):
        body.setdefault("type", "banner")
        body.setdefault("title", "B")
        return self.client.post("/api/v1/admin/marketing/offers", body, format="json")

    def test_create_sets_created_by_and_publishes_from_is_active(self):
        r = self._create(isActive=True)
        self.assertEqual(r.status_code, 201)
        offer = Offer.objects.get(id=int(_data(r)["id"]))
        self.assertEqual(offer.created_by_id, self.admin.id)
        self.assertEqual(offer.state, Offer.State.ACTIVE)  # legacy toggle drives state

    def test_workflow_submit_approve(self):
        r = self._create(state="draft")
        oid = int(_data(r)["id"])
        s = self.client.post(f"/api/v1/admin/marketing/offers/{oid}/submit", {}, format="json")
        self.assertEqual(_data(s)["state"], "pending")
        a = self.client.post(f"/api/v1/admin/marketing/offers/{oid}/approve", {}, format="json")
        self.assertEqual(_data(a)["state"], "active")
        self.assertEqual(Offer.objects.get(id=oid).approved_by_id, self.admin.id)

    def test_workflow_reject_then_pause_resume_archive(self):
        oid = int(_data(self._create(state="draft"))["id"])
        self.client.post(f"/api/v1/admin/marketing/offers/{oid}/submit", {}, format="json")
        rej = self.client.post(f"/api/v1/admin/marketing/offers/{oid}/reject",
                               {"reason": "off-brand"}, format="json")
        self.assertEqual(_data(rej)["state"], "draft")
        self.assertEqual(Offer.objects.get(id=oid).rejection_reason, "off-brand")
        # publish, then pause/resume/archive
        Offer.objects.filter(id=oid).update(state=Offer.State.ACTIVE)
        self.assertEqual(
            _data(self.client.post(f"/api/v1/admin/marketing/offers/{oid}/pause", {}, format="json"))["state"],
            "paused")
        self.assertEqual(
            _data(self.client.post(f"/api/v1/admin/marketing/offers/{oid}/resume", {}, format="json"))["state"],
            "active")
        self.assertEqual(
            _data(self.client.post(f"/api/v1/admin/marketing/offers/{oid}/archive", {}, format="json"))["state"],
            "archived")

    def test_invalid_transition_rejected(self):
        oid = int(_data(self._create(state="draft"))["id"])
        # can't approve a draft (must submit first)
        r = self.client.post(f"/api/v1/admin/marketing/offers/{oid}/approve", {}, format="json")
        self.assertEqual(r.status_code, 409)

    def test_state_not_writable_via_crud(self):
        # A direct PATCH must NOT publish — state is workflow-only (no approval bypass).
        oid = int(_data(self._create(state="draft"))["id"])
        Offer.objects.filter(id=oid).update(state=Offer.State.DRAFT)
        self.client.patch(f"/api/v1/admin/marketing/offers/{oid}",
                          {"state": "active", "title": "X"}, format="json")
        self.assertEqual(Offer.objects.get(id=oid).state, Offer.State.DRAFT)

    def test_expired_can_be_republished(self):
        oid = int(_data(self._create(state="draft"))["id"])
        Offer.objects.filter(id=oid).update(state=Offer.State.EXPIRED)
        a = self.client.post(f"/api/v1/admin/marketing/offers/{oid}/approve", {}, format="json")
        self.assertEqual(_data(a)["state"], "active")  # no valid_to → re-publishes live


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class BannerImageTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919888880002", name="A", role="admin")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)
        self.offer = Offer.objects.create(title="Img", type=Offer.Type.BANNER)

    def _upload(self, content, name="b.png", **extra):
        from django.core.files.uploadedfile import SimpleUploadedFile

        f = SimpleUploadedFile(name, content, content_type="image/png")
        return self.client.post(
            f"/api/v1/admin/marketing/offers/{self.offer.id}/image",
            {"file": f, **extra}, format="multipart",
        )

    def _variant_dir(self):
        from pathlib import Path

        from django.conf import settings

        return (Path(settings.MEDIA_ROOT) / "banners"
                / str(self.offer.image_uuid) / f"v{self.offer.image_version}")

    def test_upload_generates_webp_variants(self):
        r = self._upload(_png_bytes(), focusX="0.4", focusY="0.6")
        self.assertEqual(r.status_code, 200)
        self.offer.refresh_from_db()
        self.assertIsNotNone(self.offer.image_uuid)
        self.assertEqual(self.offer.focus_x, 0.4)
        from offers.specs import sizes_for

        base = self._variant_dir()
        for name in sizes_for(self.offer.placement):
            self.assertTrue((base / f"{name}.webp").exists())

    def test_variants_match_the_placement_ratio(self):
        """The whole point of PLACEMENT_SPECS: a `top` banner is stored at 16:10
        so the home hero never has to crop it a second time."""
        from PIL import Image

        from offers.specs import spec_for

        self._upload(_png_bytes(2400, 2400))   # square source, tall for 16:10
        self.offer.refresh_from_db()
        spec = spec_for(Offer.Placement.TOP)
        with Image.open(self._variant_dir() / "large.webp") as img:
            self.assertEqual(img.size, tuple(spec["master"]))
            self.assertAlmostEqual(img.size[0] / img.size[1], spec["ratio"], places=2)

    def test_middle_placement_stores_16_9(self):
        from PIL import Image

        self.offer.placement = Offer.Placement.MIDDLE
        self.offer.save(update_fields=["placement"])
        self._upload(_png_bytes(2400, 2400))
        self.offer.refresh_from_db()
        with Image.open(self._variant_dir() / "large.webp") as img:
            self.assertEqual(img.size, (1440, 810))

    def test_crop_rect_is_honoured_and_persisted(self):
        import json

        r = self._upload(_png_bytes(2400, 2400),
                         cropRect=json.dumps({"x": 0.0, "y": 0.0, "w": 0.5, "h": 0.3125}))
        self.assertEqual(r.status_code, 200)
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.crop_rect["w"], 0.5)
        # Output is still the exact placement master size regardless of rect size.
        from PIL import Image

        with Image.open(self._variant_dir() / "large.webp") as img:
            self.assertEqual(img.size, (1600, 1000))

    def test_degenerate_crop_rect_falls_back_to_focal(self):
        import json

        r = self._upload(_png_bytes(2400, 2400),
                         cropRect=json.dumps({"x": 0.5, "y": 0.5, "w": 0, "h": 0}))
        self.assertEqual(r.status_code, 200)
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.crop_rect, {})

    def test_spotlight_accepts_a_square_source(self):
        # 1:1 placement — an 800×800 upload is the master, not "too small".
        self.offer.placement = Offer.Placement.SPOTLIGHT
        self.offer.save(update_fields=["placement"])
        r = self._upload(_png_bytes(800, 800))
        self.assertEqual(r.status_code, 200)

    def test_reupload_bumps_version(self):
        self._upload(_png_bytes())
        self._upload(_png_bytes())
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.image_version, 2)

    def test_rejects_small_image(self):
        r = self._upload(_png_bytes(800, 400))
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["code"], "IMAGE_INVALID")

    def test_rejects_bad_type(self):
        r = self._upload(b"not an image", name="x.gif")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["code"], "UNSUPPORTED_IMAGE_TYPE")

    def test_rejects_too_large(self):
        # >3 MB is rejected by the size gate before any decode.
        r = self._upload(b"\x89PNG\r\n" + b"0" * (3 * 1024 * 1024 + 1))
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["code"], "IMAGE_TOO_LARGE")

    def test_rejects_png_extension_but_gif_content(self):
        # Content sniff: a real GIF named .png is rejected by format check.
        import io
        from PIL import Image

        buf = io.BytesIO()
        Image.new("RGB", (2400, 1200)).save(buf, "GIF")
        r = self._upload(buf.getvalue(), name="fake.png")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["code"], "UNSUPPORTED_IMAGE_TYPE")


class BannerEventTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.offer = Offer.objects.create(title="E", type=Offer.Type.BANNER,
                                          state=Offer.State.ACTIVE)

    def test_events_increment_counters(self):
        r = self.client.post("/api/v1/offers/events", {"events": [
            {"offer_id": self.offer.id, "kind": "impression"},
            {"offer_id": self.offer.id, "kind": "impression"},
            {"offer_id": self.offer.id, "kind": "click"},
            {"offer_id": 999999, "kind": "click"},      # unknown → skipped
            {"offer_id": self.offer.id, "kind": "bogus"},  # bad kind → skipped
        ]}, format="json")
        self.assertEqual(r.status_code, 200)
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.impressions, 2)
        self.assertEqual(self.offer.clicks, 1)
        self.assertEqual(BannerEvent.objects.filter(offer=self.offer).count(), 3)

    def test_malformed_click_id_does_not_crash(self):
        # A non-UUID click_id must not 500 the public endpoint or drop the batch.
        r = self.client.post("/api/v1/offers/events", {"events": [
            {"offer_id": self.offer.id, "kind": "click", "click_id": "not-a-uuid"},
        ]}, format="json")
        self.assertEqual(r.status_code, 200)
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.clicks, 1)
        self.assertIsNone(BannerEvent.objects.get(offer=self.offer).click_id)


class CouponEngineTests(TestCase):
    """Coupon integrity: expiry + global/per-user usage limits enforced, and a
    redemption is recorded at checkout. Concurrent redemptions are serialised by the
    select_for_update lock in redeem_coupon (validated here sequentially)."""

    def setUp(self):
        self.user = User.objects.create(phone="+919000000400", name="C")
        self.today = timezone.localdate()

    def _coupon(self, **kw):
        from offers.models import Coupon
        defaults = dict(code="SAVE10", discount_type=Coupon.DiscountType.FLAT,
                        value=Decimal("10"), is_active=True)
        defaults.update(kw)
        return Coupon.objects.create(**defaults)

    # ── resolve (preview) ──
    def test_expired_coupon_gives_no_discount(self):
        from offers.services import resolve_coupon
        self._coupon(valid_to=self.today - timedelta(days=1))
        coupon, discount, _ = resolve_coupon("SAVE10", Decimal("100"))
        self.assertIsNone(coupon)
        self.assertEqual(discount, Decimal("0.00"))

    def test_inactive_coupon_invalid(self):
        from offers.services import resolve_coupon
        self._coupon(is_active=False)
        coupon, _, _ = resolve_coupon("SAVE10", Decimal("100"))
        self.assertIsNone(coupon)

    def test_min_order_not_met(self):
        from offers.services import resolve_coupon
        self._coupon(min_order=Decimal("500"))
        coupon, _, _ = resolve_coupon("SAVE10", Decimal("100"))
        self.assertIsNone(coupon)

    def test_percent_capped_by_max_discount(self):
        from offers.models import Coupon
        from offers.services import resolve_coupon
        self._coupon(code="P50", discount_type=Coupon.DiscountType.PERCENT,
                     value=Decimal("50"), max_discount=Decimal("30"))
        _, discount, _ = resolve_coupon("P50", Decimal("200"))  # 50%=100, capped to 30
        self.assertEqual(discount, Decimal("30.00"))

    # ── redeem (checkout enforcement) ──
    def test_redeem_records_redemption(self):
        from offers.models import CouponRedemption
        from offers.services import redeem_coupon
        self._coupon()
        redeem_coupon("SAVE10", self.user, order_code="ORD1", amount=Decimal("10"))
        self.assertEqual(CouponRedemption.objects.count(), 1)

    def test_global_usage_limit_enforced(self):
        from offers.services import CouponError, redeem_coupon
        self._coupon(usage_limit=1)
        redeem_coupon("SAVE10", self.user, order_code="ORD1", amount=Decimal("10"))
        other = User.objects.create(phone="+919000000401", name="C2")
        with self.assertRaises(CouponError) as cm:
            redeem_coupon("SAVE10", other, order_code="ORD2", amount=Decimal("10"))
        self.assertEqual(cm.exception.code, "COUPON_LIMIT_REACHED")

    def test_per_user_limit_enforced(self):
        from offers.services import CouponError, redeem_coupon
        self._coupon(per_user_limit=1)
        redeem_coupon("SAVE10", self.user, order_code="ORD1", amount=Decimal("10"))
        with self.assertRaises(CouponError) as cm:
            redeem_coupon("SAVE10", self.user, order_code="ORD2", amount=Decimal("10"))
        self.assertEqual(cm.exception.code, "COUPON_ALREADY_USED")
        other = User.objects.create(phone="+919000000401", name="C2")
        redeem_coupon("SAVE10", other, order_code="ORD3", amount=Decimal("10"))  # ok

    def test_redeem_expired_raises(self):
        from offers.services import CouponError, redeem_coupon
        self._coupon(valid_to=self.today - timedelta(days=1))
        with self.assertRaises(CouponError) as cm:
            redeem_coupon("SAVE10", self.user, order_code="ORD1", amount=Decimal("10"))
        self.assertEqual(cm.exception.code, "COUPON_EXPIRED")


class BannerSpecEndpointTests(TestCase):
    def test_specs_are_public_and_describe_every_placement(self):
        r = self.client.get("/api/v1/offers/specs")
        self.assertEqual(r.status_code, 200)
        rows = {e["placement"]: e for e in r.json()["data"]["placements"]}
        for placement in Offer.Placement.values:
            self.assertIn(placement, rows, f"{placement} missing from the spec table")
            self.assertIn("ratio", rows[placement])
            self.assertIn("large", {s["name"] for s in rows[placement]["sizes"]})
        self.assertEqual(rows["top"]["aspect"], "16:10")
        self.assertEqual(rows["middle"]["aspect"], "16:9")
        self.assertEqual(rows["top"]["master"], {"width": 1600, "height": 1000})

    def test_placement_keys_survive_the_camelcase_renderer(self):
        """Regression: the envelope renderer camelCases dict keys, so the spec
        table must not be keyed by placement (product_list -> productList)."""
        r = self.client.get("/api/v1/offers/specs")
        self.assertIn("product_list", {e["placement"] for e in r.json()["data"]["placements"]})

    def test_ladder_preserves_the_master_aspect(self):
        from offers.specs import sizes_for

        for placement in Offer.Placement.values:
            sizes = sizes_for(placement)
            master_w, master_h = sizes["large"]
            for name, (w, h) in sizes.items():
                self.assertAlmostEqual(w / h, master_w / master_h, places=2,
                                       msg=f"{placement}/{name} drifted from the master ratio")


class BannerActionValidationTests(TestCase):
    """A published banner must not dead-end. `action` and `payload` are validated
    together so a PATCH of one can't desync the pair."""

    def setUp(self):
        self.admin = User.objects.create(phone="+919888880003", name="A", role="admin")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)
        self.cat = Category.objects.create(name="Snacks")
        self.product = Product.objects.create(name="Chips", category=self.cat,
                                              price=Decimal("10"), mrp=Decimal("12"))

    def _create(self, **kw):
        body = {"title": "B", "type": "banner", "placement": "top", **kw}
        return self.client.post("/api/v1/admin/marketing/offers", body, format="json")

    def test_product_action_without_payload_is_rejected(self):
        r = self._create(action="product", payload={})
        self.assertEqual(r.status_code, 400)

    def test_product_action_with_unknown_product_is_rejected(self):
        r = self._create(action="product", payload={"productId": 999999})
        self.assertEqual(r.status_code, 400)

    def test_product_action_with_real_product_is_accepted(self):
        r = self._create(action="product", payload={"productId": self.product.id})
        self.assertEqual(r.status_code, 201)

    def test_snake_case_payload_is_normalized_to_camel(self):
        r = self._create(action="product", payload={"product_id": self.product.id})
        self.assertEqual(r.status_code, 201)
        offer = Offer.objects.get(id=r.json()["data"]["id"])
        self.assertEqual(offer.payload, {"productId": self.product.id})

    def test_external_requires_https(self):
        self.assertEqual(self._create(action="external",
                                      payload={"url": "http://x.com"}).status_code, 400)
        self.assertEqual(self._create(action="external",
                                      payload={"url": "javascript:alert(1)"}).status_code, 400)
        self.assertEqual(self._create(action="external",
                                      payload={"url": "https://thevsmart.com/x"}).status_code, 201)

    @override_settings(BANNER_EXTERNAL_HOST_ALLOWLIST=["thevsmart.com"])
    def test_external_host_allowlist_is_enforced_when_set(self):
        self.assertEqual(self._create(action="external",
                                      payload={"url": "https://evil.example/x"}).status_code, 400)
        self.assertEqual(self._create(action="external",
                                      payload={"url": "https://cdn.thevsmart.com/x"}).status_code, 201)

    def test_actions_without_a_target_need_no_payload(self):
        for action in ("none", "home", "cart", "credit", "offers", "profile"):
            self.assertEqual(self._create(action=action).status_code, 201, action)

    def test_patching_action_alone_revalidates_against_stored_payload(self):
        created = self._create(action="none")
        offer_id = created.json()["data"]["id"]
        r = self.client.patch(f"/api/v1/admin/marketing/offers/{offer_id}",
                              {"action": "product"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_accent_color_must_be_hex(self):
        self.assertEqual(self._create(accent_color="green").status_code, 400)
        self.assertEqual(self._create(accent_color="#16A34A").status_code, 201)

    def test_schedule_end_must_follow_its_start(self):
        now = timezone.now()
        r = self._create(valid_from=now.isoformat(), valid_to=(now - timedelta(days=1)).isoformat())
        self.assertEqual(r.status_code, 400)


class BannerDeleteTests(TestCase):
    """Deleting a banner must not silently destroy campaign reporting."""

    def setUp(self):
        self.admin = User.objects.create(phone="+919888880004", name="A", role="admin")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def _banner(self, **kw):
        kw.setdefault("type", Offer.Type.BANNER)
        kw.setdefault("state", Offer.State.ACTIVE)
        return Offer.objects.create(title="Del", **kw)

    # These assert 200 + a coded body rather than a bare 204. The console has to
    # tell the operator WHICH of the two happened — an archived banner is still
    # in the list, and "Banner deleted." over it reads as a failed delete. A 204
    # carries no outcome, so the console was left re-deriving the archive rule
    # from `impressions > 0`, which disagreed with the server on a banner
    # archived for its clicks or events.
    def test_unserved_banner_is_really_deleted(self):
        offer = self._banner(state=Offer.State.DRAFT)
        r = self.client.delete(f"/api/v1/admin/marketing/offers/{offer.id}")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.json()["code"], "RECORD_DELETED")
        self.assertFalse(Offer.objects.filter(id=offer.id).exists())

    def test_served_banner_is_archived_not_erased(self):
        offer = self._banner(impressions=120, clicks=9)
        r = self.client.delete(f"/api/v1/admin/marketing/offers/{offer.id}")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.json()["code"], "RECORD_ARCHIVED")
        offer.refresh_from_db()
        self.assertEqual(offer.state, Offer.State.ARCHIVED)
        self.assertFalse(offer.is_active)
        self.assertIsNotNone(offer.deleted_at)
        # The history the archive exists to protect is still there.
        self.assertEqual(offer.impressions, 120)

    def test_banner_with_events_is_archived_and_events_survive(self):
        offer = self._banner()
        BannerEvent.objects.create(offer=offer, kind=BannerEvent.Kind.IMPRESSION)
        self.client.delete(f"/api/v1/admin/marketing/offers/{offer.id}")
        offer.refresh_from_db()
        self.assertEqual(offer.state, Offer.State.ARCHIVED)
        self.assertEqual(BannerEvent.objects.filter(offer=offer).count(), 1)

    def test_archived_banners_are_hidden_from_the_admin_grid(self):
        """Regression: archived rows stayed in the list, so archiving looked
        like a no-op and admins reported that delete didn't work."""
        live = self._banner()
        gone = self._banner(state=Offer.State.ARCHIVED)
        rows = _data(self.client.get("/api/v1/admin/marketing/offers"))
        ids = {str(o["id"]) for o in rows}
        self.assertIn(str(live.id), ids)
        self.assertNotIn(str(gone.id), ids)

    def test_archived_can_be_listed_explicitly(self):
        gone = self._banner(state=Offer.State.ARCHIVED)
        rows = _data(self.client.get(
            "/api/v1/admin/marketing/offers?includeArchived=1"))
        self.assertIn(str(gone.id), {str(o["id"]) for o in rows})

    def test_a_deleted_banner_stops_serving_to_customers(self):
        offer = self._banner(impressions=5)
        self.client.delete(f"/api/v1/admin/marketing/offers/{offer.id}")
        public = _data(APIClient().get("/api/v1/offers?type=banner"))
        self.assertNotIn(str(offer.id), {str(o["id"]) for o in public})


class AdminCouponDeleteContractTests(TestCase):
    """Deleting a coupon reports what actually happened.

    A redeemed coupon is deactivated (CouponRedemption cascades off it, and
    accounting reconciles discounts against those rows), an unredeemed one is
    really deleted. A bare 204 could not tell the two apart — and the console's
    fetch client could not read a 204 at all, so a successful delete surfaced as
    "Empty response from server." with the row still on screen.
    """

    def setUp(self):
        from rest_framework.test import APIClient

        from accounts.models import User

        self.admin = User.objects.create(
            phone="+919000000701", name="Admin", role="admin"
        )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def _coupon(self, code="SAVE50"):
        return Coupon.objects.create(
            code=code, discount_type="flat", value=Decimal("50"), is_active=True
        )

    def test_unredeemed_coupon_is_really_deleted(self):
        coupon = self._coupon()
        r = self.client.delete(f"/api/v1/admin/marketing/coupons/{coupon.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["code"], "RECORD_DELETED")
        self.assertIn("SAVE50", body["message"])
        self.assertFalse(Coupon.objects.filter(pk=coupon.pk).exists())

    def test_redeemed_coupon_is_deactivated_and_history_survives(self):
        from accounts.models import User

        from .models import CouponRedemption

        coupon = self._coupon("USED10")
        customer = User.objects.create(
            phone="+919000000702", name="Cust", role="customer"
        )
        CouponRedemption.objects.create(coupon=coupon, user=customer,
                                        amount=Decimal("50"))

        r = self.client.delete(f"/api/v1/admin/marketing/coupons/{coupon.id}")
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["code"], "RECORD_DEACTIVATED")
        self.assertIn("deactivated", body["message"].lower())
        coupon.refresh_from_db()
        self.assertFalse(coupon.is_active)
        self.assertEqual(coupon.redemptions.count(), 1)

    def test_store_panel_sees_coupons_read_only(self):
        """The store list endpoint existed but nothing rendered it; the panel
        now shows it, so the contract needs a test."""
        from storeops.tests import client_for, mk_staff, mk_store

        self._coupon("SHOWN5")
        Coupon.objects.create(code="HIDDEN", discount_type="flat",
                              value=Decimal("5"), is_active=False)
        staff = client_for(mk_staff(mk_store(), "manager"))
        r = staff.get("/api/v1/store/marketing/coupons")
        self.assertEqual(r.status_code, 200, r.content)
        codes = {c["code"] for c in r.json()["data"]}
        self.assertIn("SHOWN5", codes)
        self.assertNotIn("HIDDEN", codes)  # inactive codes are not quotable
