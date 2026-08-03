# VS Mart — Banner Management v1.0 Implementation Plan

**Status:** Plan for review — no code written yet.
**Decision (2026-06-27):** Extend the existing `offers` app / `Offer` model. Do **not** build a parallel banner system.
**Source spec:** "Final Production Banner Architecture (VS Mart v1.0)" + review amendments.

---

## 0. Why extend `Offer` (not a new model)

VS Mart already ships banners end-to-end:

- **Backend:** `offers.Offer` (type=banner/deal/coupon) + admin CRUD (`offers/admin_views.py`) + public list (`offers/views.py`).
- **Admin:** `apps/admin/app/(console)/marketing/page.tsx` (Banners/Deals/Coupons/Campaigns tabs).
- **App:** `user_app/lib/features/offers/` — carousel, repository, stale-while-revalidate cache, providers.

A new `Banner` table would orphan all of the above and split marketing analytics across two tables. We extend `Offer` and close the gaps. `Coupon` / `CouponRedemption` are untouched.

### What's already there vs. v1.0 spec

| v1.0 item | Today | Action |
|---|---|---|
| Model + CRUD + public API | ✅ | extend |
| Admin UI | ✅ | add fields + cropper |
| Flutter carousel + cache | ✅ | render images, localize text |
| Category targeting + fallback | ✅ | keep |
| Scheduling fields | ⚠️ stored, **not enforced** | enforce in queryset |
| Image rendering in app | ❌ text-on-gradient only | **render image** |
| Image upload + cropper + focal point | ❌ raw URL paste | **build pipeline** |
| Zone/store targeting | ❌ | **add FKs + serviceability filter** |
| Multilingual te/hi text | ❌ | **add fields** |
| State machine + approval | ❌ `is_active` bool | **add `state` + approval fields** |
| Deep-link enum + payload | ⚠️ product link only | **add `action` + `payload`** |
| Impressions / CTR / conversion | ❌ click event only | **add events + counters** |
| Audience segmentation | ❌ | model now, enforce Phase 2 |
| Product-in-stock validation | ❌ | **validate against serving store** |

---

## 1. Guiding decisions (locked)

1. **App is served WebP only.** `minSdk = 23` (Firebase pin) → AVIF doesn't decode on Android 6–11. AVIF is generated for the **admin/web** only, negotiated by `Accept`. *(Amends spec §13.)*
2. **Backend-only banner selection.** The app sends *context* (resolved `store_id` / `zone_id` / locale), never filters. Server returns only valid, in-window, in-stock, audience-matched banners.
3. **Opaque, versioned image paths.** Keyed by `uuid`, not sequential `id`, so the library can't be scraped. *(Amends spec §12 — uuid not id.)*
4. **Static media served by Caddy** with long immutable cache headers (not proxied per-request through Django — that would bottleneck home loads). Version lives in the **path**, not a query string, so every CDN caches it correctly.
5. **Degrade open.** If the in-stock / serviceability check is slow or errors, still show the banner — a rare dead-tap beats a slow or empty home screen.
6. **Localized text returned as all three short strings** (en/te/hi) so the app's runtime language switch (`localeProvider`, no refetch) stays instant. Festival creatives may override with per-language *images*.

---

## 2. Backend — `apps/backend/offers`

### 2.1 Model changes (`offers/models.py` → migration `0004`)

Add to `Offer`:

```python
# --- State machine (replaces reliance on is_active) ---
class State(models.TextChoices):
    DRAFT = "draft"
    PENDING = "pending"        # submitted, awaiting super-admin approval
    SCHEDULED = "scheduled"    # approved, waiting for start_at
    ACTIVE = "active"
    PAUSED = "paused"          # manual kill-switch, config preserved
    EXPIRED = "expired"        # past end_at (auto)
    ARCHIVED = "archived"      # soft-deleted, kept for analytics
state = models.CharField(max_length=12, choices=State.choices, default=State.DRAFT)

# --- Targeting (reuse the serviceability architecture) ---
zone  = models.ForeignKey("zones.Zone",  on_delete=models.SET_NULL, null=True, blank=True, related_name="offers")
store = models.ForeignKey("stores.Store", on_delete=models.SET_NULL, null=True, blank=True, related_name="offers")
# zone=null & store=null  => GLOBAL (all users)

# --- Multilingual overlay text (title/subtitle remain the en default) ---
title_te = models.CharField(max_length=160, blank=True)
title_hi = models.CharField(max_length=160, blank=True)
subtitle_te = models.CharField(max_length=200, blank=True)
subtitle_hi = models.CharField(max_length=200, blank=True)

# --- Deep link (enum + payload, never parse strings) ---
class Action(models.TextChoices):
    NONE="none"; HOME="home"; CATEGORY="category"; PRODUCT="product"
    BRAND="brand"; SEARCH="search"; CREDIT="credit"; OFFERS="offers"
    CART="cart"; PROFILE="profile"; ORDER="order"; STORE="store"; EXTERNAL="external"
action  = models.CharField(max_length=12, choices=Action.choices, default=Action.NONE)
payload = models.JSONField(default=dict, blank=True)   # {"product_id": 18}

# --- Image pipeline ---
image_uuid    = models.UUIDField(null=True, blank=True, db_index=True)  # folder key
image_version = models.PositiveIntegerField(default=1)                  # cache-bust in path
image_te = models.UUIDField(null=True, blank=True)   # festival per-lang override (nullable)
image_hi = models.UUIDField(null=True, blank=True)
focus_x = models.FloatField(default=0.5)             # 0..1 focal point
focus_y = models.FloatField(default=0.5)
# image_url (existing) kept for legacy pasted-URL banners; new uploads use the pipeline.

# --- Scheduling (fields exist; timezone is informational, all UTC in DB) ---
timezone = models.CharField(max_length=40, default="Asia/Kolkata")

# --- Audience (Phase 2 enforcement; stored from v1) ---
audience = models.JSONField(default=dict, blank=True)
# e.g. {"new_user": true, "credit": "eligible", "platform": "android", "min_app_version": "1.4.0"}

# --- Approval / audit ---
is_pinned   = models.BooleanField(default=False)
created_by  = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="offers_created")
approved_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="offers_approved")
approved_at = models.DateTimeField(null=True, blank=True)
rejection_reason = models.CharField(max_length=200, blank=True)

# --- Denormalized analytics counters (aggregated from BannerEvent) ---
impressions = models.PositiveIntegerField(default=0)
clicks      = models.PositiveIntegerField(default=0)
orders      = models.PositiveIntegerField(default=0)
revenue     = models.DecimalField(max_digits=14, decimal_places=2, default=0)

deleted_at = models.DateTimeField(null=True, blank=True)  # soft delete (=> state ARCHIVED)
```

New ordering: `["-is_pinned", "sort_order", "-id"]` (pinned → priority → newest).

**New model `BannerEvent`** (append-only, source of truth for analytics):

```python
class BannerEvent(TimeStampedModel):
    class Kind(models.TextChoices):
        IMPRESSION="impression"; CLICK="click"; VIEW="view"; ATC="atc"; ORDER="order"
    offer = models.ForeignKey(Offer, on_delete=models.CASCADE, related_name="events")
    kind  = models.CharField(max_length=12, choices=Kind.choices)
    user  = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    store = models.ForeignKey("stores.Store", on_delete=models.SET_NULL, null=True, blank=True)
    zone  = models.ForeignKey("zones.Zone",  on_delete=models.SET_NULL, null=True, blank=True)
    click_id = models.UUIDField(null=True, blank=True, db_index=True)  # threads click → order (Phase 2 revenue)
```

### 2.2 Data migration (`0004`, backfill — zero downtime)

- `state`: `is_active=True` → `ACTIVE`; `is_active=False` → `ARCHIVED`.
- `action`/`payload`: `product` set → `PRODUCT {"product_id": ...}`; else `category` set → `CATEGORY {"category_id": ...}`; else `NONE`.
- `image_uuid`: leave null on legacy rows; serializer falls back to `image_url`.
- Keep `is_active` column for one release (admin still writes it); derive from `state` going forward, drop in a later migration.

### 2.3 Public API — enforce scheduling + targeting + stock

`OfferListView.get_queryset` ([offers/views.py:25](../offers/views.py)) gains, in order:

1. **State + window:** `state="active"` AND (`valid_from` null or ≤ now) AND (`valid_to` null or ≥ now). *(Closes the live scheduling gap.)*
2. **Zone/store:** accept `?store_id=` / `?zone_id=` context (app already resolves these via serviceability). Filter to `store=store_id` OR `zone=zone_id` OR (`store` null AND `zone` null = global). Specificity order: store > zone > global.
3. **Product-in-stock:** for `action=PRODUCT`/deal rows, drop banners whose product isn't visible+in-stock for the resolved store (reuse Z6 `zone_store_visibility` + inventory). Wrapped in try/except → **degrade open**.
4. **Audience (Phase 2):** filter by `audience` against the authenticated user / context.

> **Auth note:** endpoint stays `AllowAny` but now reads `store_id`/`zone_id`/locale context params. When a JWT *is* present, derive audience server-side; for guests, global + zone-by-param only.

A short per-(zone, store, locale) cache (e.g. 60s) keeps the home banner fetch cheap despite the stock join.

### 2.4 Serializers

- **`OfferSerializer`** (public): add `action`, `payload`, `is_pinned`, localized `title_*`/`subtitle_*` (all three), and a computed **`image`** object:
  ```json
  "image": {
    "small":  "/media/banners/<uuid>/v3/small.webp",
    "medium": "/media/banners/<uuid>/v3/medium.webp",
    "large":  "/media/banners/<uuid>/v3/large.webp",
    "focus": {"x": 0.5, "y": 0.4}
  }
  ```
  Falls back to `{ "legacy_url": image_url }` for un-migrated rows. Never returns admin-only fields (state internals, approval, raw counters).
- **`AdminOfferSerializer`**: add all new writable fields; `image` handled by the upload endpoint (below), not raw URL.

### 2.5 Image pipeline (new `offers/imaging.py`)

```
POST /api/v1/admin/marketing/offers/<id>/image   (multipart: file, focus_x, focus_y, crop box)
  → validate: ext in {jpg,jpeg,png,webp}; reject svg/gif/php/exe/zip; ≤3MB; min 2400×1200
  → strip EXIF; apply crop to 2:1; store focus_x/y
  → generate (Pillow + pillow-avif-plugin):
      large  2400×1200   medium 1200×600   small 720×360   thumb 360×180
      formats: webp (q85) for app  +  avif for web
  → write to MEDIA_ROOT/banners/<uuid>/v<version>/<size>.<fmt>
  → bump image_version (cache-bust); set image_uuid
  → record_audit("offer.image", ...)
```

- **Serving:** Caddy serves `/media/banners/**` with `Cache-Control: public, max-age=31536000, immutable` + `ETag`. Versioned path makes this safe. AVIF vs WebP chosen by `Accept` (admin/browser) — app always requests `.webp`.
- **Dependency:** add `pillow-avif-plugin` (or `pillow-heif`) to `requirements`. Confirm in Docker image.

### 2.6 Analytics endpoints

- `POST /api/v1/offers/events` — batched `[{offer_id, kind, click_id?}]` from the app (impression on view, click on tap). Cheap insert into `BannerEvent`.
- Counters (`impressions/clicks/orders/revenue`) aggregated by a periodic task (or `F()` increments on write for impressions/clicks). **Revenue attribution = Phase 2** (thread `click_id` → cart → `Order`).
- Admin read: extend `AdminOfferSerializer` with computed CTR; new `GET /admin/marketing/offers/<id>/analytics`.

### 2.7 State / approval transitions

- `POST /admin/marketing/offers/<id>/submit` (→ pending), `/approve` (→ scheduled/active, sets `approved_by/at`), `/reject` (→ draft + reason), `/pause`, `/resume`, `/archive` (soft delete).
- Store-admins (apps/store-admin) may create store-scoped banners in `draft`/`pending`; only super-admin `approve`s. *(Phase 1 can ship super-admin-only; store-admin submission is a fast follow.)*

### 2.8 Response envelope

New endpoints use the actionable-response framework (`core/response_codes.py`, `AppError`, `ok()`): e.g. `raise AppError("PRODUCT_UNAVAILABLE")`, `AppError("IMAGE_TOO_LARGE")`, `AppError("UNSUPPORTED_IMAGE_TYPE")`. Add any new codes to the catalog.

---

## 3. Admin console — `apps/admin` (super-admin)

`marketing/page.tsx`, Banners/Deals tab:

- **Cropper dialog** (replaces "Image URL" text input): drag-and-drop upload → preview → move/zoom → **focal-point pin** → save. Fixed 2:1 frame. Library: `react-easy-crop` (focal point + zoom, headless). Posts multipart to the image endpoint; shows generated thumbnail.
- **New form fields:** zone (select), store (select, filtered by zone), `action` (enum dropdown) + dynamic payload input, te/hi title/subtitle, pinned toggle, state badge, schedule (start/end + IST note), audience (Phase 2 — collapsible).
- **Grid columns** (per spec §15): Image · Title · Type · Zone · Store · Language · State · Priority · Start · End · Impressions · Clicks · CTR · Actions.
- **Approval controls:** Submit / Approve / Reject / Pause / Resume / Archive buttons gated by RBAC.

---

## 4. Flutter — `user_app/lib/features/offers`

1. **Render the image (the headline gap).** `VSOfferBanner` / `_OfferCarousel` / `PlacementBannerCarousel` currently draw text on a gradient and ignore `image_url`. Switch to `CachedNetworkImage` of the `image.<size>` URL, with:
   - DPR-aware size pick (small/medium/large by `MediaQuery.devicePixelRatio` × width).
   - `BlurHash`/dominant-color placeholder (no grey flash); shimmer skeleton while the provider loads.
   - Gradient scrim **under** the overlay text for legibility; keep text overlay for localized strings.
2. **Localize overlay text.** `Offer` entity gains `titleTe/titleHi/subtitleTe/subtitleHi`; widget picks by `localeProvider` (instant runtime switch, no refetch).
3. **Deep-link enum.** Replace the ad-hoc "product or offers-hub" tap logic with an `action` switch (PRODUCT/CATEGORY/SEARCH/CREDIT/EXTERNAL/...) reading `payload`. External URLs checked against a domain whitelist.
4. **Context params.** `getBanners()` / `getPlacementBanners()` send the resolved `store_id`/`zone_id` (from serviceability) + locale.
5. **Impression + click events.** Fire `POST /offers/events` (batched) — impression when a banner becomes visible, click on tap (carry a `click_id`).
6. **Entity/datasource/serializer** updates to parse the new `image` object + fields; cache layer unchanged (stale-while-revalidate already in place).

---

## 5. Phasing (maps to spec's Phase 1 / Phase 2)

**Phase 1 — P0 launch**
- Migration `0004` (fields + backfill) · scheduling enforcement · zone/store targeting · image pipeline (WebP+AVIF, focal crop) · admin cropper · **Flutter image rendering** · localized overlay text · deep-link enum · impressions+clicks · state machine + super-admin approval · in-stock validation (degrade open).

**Phase 2 — post-launch**
- Audience segmentation enforcement · revenue attribution (click_id → order) · A/B variants · store-admin banner submission UI · animated/Lottie/video banners · heatmaps/advanced analytics.

---

## 6. Testing

- **Backend:** unit tests for queryset window+zone/store+stock filtering (incl. degrade-open); image pipeline (size/format generation, EXIF strip, reject bad types/size); state transitions + approval RBAC; serializer localization. Add a `smoke_banner` suite alongside the existing offers tests.
- **Admin:** cropper upload → generated sizes appear; grid columns; approval buttons by role.
- **App:** image renders on Android API 23 device/emulator (WebP, **no AVIF**); locale switch swaps text live; deep-link enum routes correctly; impression/click events post.

---

## 7. Open questions / risks

1. **Pillow AVIF in Docker** — confirm `pillow-avif-plugin`/libavif builds in the backend image; if painful, ship WebP-only for v1 (app is WebP anyway) and add AVIF for web later.
2. **Guest zone context** — guests have no JWT; rely on serviceability-resolved `zone_id` param. Confirm the home screen has it before first banner fetch (else show global only).
3. **`is_active` deprecation window** — keep one release for admin back-compat, then drop.
4. **Caddy media route** — confirm `/media/banners/**` is served by Caddy with the immutable cache header in the Compose/Caddyfile on the VPS.
5. **Counter write contention** — if impression volume is high, prefer periodic aggregation from `BannerEvent` over per-request `F()` updates.
