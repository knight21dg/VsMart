# Banner Spec — sizes, placements and redirection

The contract shared by the backend crop pipeline, the two admin panels and the
Flutter app. **One source of truth**: `offers/specs.py::PLACEMENT_SPECS`, mirrored
client-side by `user_app/lib/features/offers/domain/entities/banner_spec.dart`.
Serve it to any client with `GET /api/v1/offers/specs` (public, unauthenticated).

> **Why this exists.** Before v1.1 the pipeline cropped every banner to a
> universal 2:1 while the app rendered the home hero at 16:10 and the strips at
> 16:9 with `BoxFit.cover`. Every banner was therefore cropped **twice** — once by
> the server around a focal point, again by Flutter — so marketing could never
> predict what the customer would actually see. The crop target is now
> per-placement, and the app renders that exact ratio.

If you change a ratio, change **both** files in the same commit. The Flutter test
`test/features/offers/banner_spec_test.dart` and the Django test
`BannerSpecEndpointTests` both fail loudly when the halves drift.

---

## 1. Placements and upload sizes

| Placement | Where it renders | Aspect | Upload / master | Minimum accepted |
|---|---|---|---|---|
| `top` | Home hero carousel | **16:10** | 1600 × 1000 | 1600 × 1000 |
| `middle` | Home mid strip (below the category rail) | **16:9** | 1440 × 810 | 1440 × 810 |
| `product_list` | Category / product-listing screens | 16:9 | 1440 × 810 | 1440 × 810 |
| `product_detail` | Product detail body (single, no carousel) | 16:9 | 1440 × 810 | 1440 × 810 |
| `cart` | Above the bill summary in the cart | 16:9 | 1440 × 810 | 1440 × 810 |
| `spotlight` | Square product cut-out over a gradient card | 1:1 | 800 × 800 | 800 × 800 |

**Format:** JPEG / PNG / WebP in, **WebP only** out (minSdk 23 — AVIF does not
decode on Android 6–11). Max upload **3 MB**. EXIF orientation is applied then
stripped. The decoded format is content-sniffed, so renaming a `.gif` to `.png`
is rejected.

### Generated ladder

Each upload produces four WebP renditions under
`/media/banners/<uuid>/v<version>/<name>.webp`. Width is scaled then height is
*derived* from the master ratio, so every rung is the same shape.

| Rung | `top` (16:10) | 16:9 placements | `spotlight` (1:1) |
|---|---|---|---|
| `large` | 1600 × 1000 | 1440 × 810 | 800 × 800 |
| `medium` | 1120 × 700 | 1008 × 567 | 560 × 560 |
| `small` | 800 × 500 | 720 × 405 | 400 × 400 |
| `thumb` | 320 × 200 | 288 × 162 | 160 × 160 |

The app picks a rung by device pixel ratio (`BannerImage.best`): `> 1200px` →
`large`, `> 720px` → `medium`, else `small`. `image_version` increments on every
re-upload and sits in the path, so caches bust instantly.

---

## 2. Rendered size on the phone

Height is never hardcoded. It is derived from the screen width:

```
cardWidth = screenWidth × viewportFraction − horizontalInset
height    = clamp(cardWidth ÷ ratio, minHeight, maxHeight)
```

| Placement | viewportFraction | Inset | Clamp | Corner radius |
|---|---|---|---|---|
| `top` | 0.92 | 8 (4 per side) | 180 – 320 | 20 |
| `middle` | 0.86 | 8 | 140 – 220 | 20 |
| `product_list` | 0.92 | 8 + 32 screen padding | 140 – 220 | 20 |
| `product_detail` | 1.0 (single) | 32 screen padding | 140 – 220 | 20 |
| `cart` | 1.0 | 8 + 32 screen padding | 120 – 200 | 20 |

### Actual rendered heights (logical px)

Generated from `BannerSpec.heightFor` — do not hand-compute these, the insets
are easy to get wrong.

| Placement | 320 dp (small) | 360 dp (typical) | 412 dp (large) |
|---|---|---|---|
| `top` | **180** (clamped) | **202** | **232** |
| `middle` | 150 | **170** | 195 |
| `product_list` | 143 | **164** | 191 |
| `product_detail` | 180 | **203** | **220** (clamped) |
| `cart` | 158 | **180** | **200** (clamped) |

Images are drawn with `BoxFit.cover`. Because the stored artwork already matches
the slot ratio, cover is a no-op — nothing is trimmed. Focal alignment still
applies, but only matters for legacy banners stored at the old 2:1.

**Safe area:** keep faces, logos and prices inside the middle ~88% of the frame.
The card is rounded 20px and the overlay copy sits in the bottom third. The crop
tool draws this safe area as a dashed rectangle.

---

## 3. Cropping

Two modes, in priority order:

1. **Explicit crop rect** — the admin/store crop tool posts
   `cropRect = {x, y, w, h}`, normalized 0..1 against the **source** image. The
   server crops the original file to that rect, then snaps it to the exact
   placement ratio. This is the path marketing should always use.
2. **Focal point** — uploads with no rect fall back to a centre crop that keeps
   `(focus_x, focus_y)` inside the frame.

The cropper returns a **rect, not a canvas blob**, on purpose: exporting from
canvas would bake in the ~460px on-screen preview resolution and discard the
source pixels before the server ever saw them. The rect is persisted on
`Offer.crop_rect` so a crop can be reopened and nudged rather than redone.

A degenerate rect (zero area, or one starting outside the image) is ignored and
the focal path is used instead — it never produces a 1px image.

---

## 4. Text, CTA and overlay

| Field | Notes |
|---|---|
| `title`, `title_te`, `title_hi` | Headline. 160 chars. |
| `subtitle`, `subtitle_te`, `subtitle_hi` | 200 chars. |
| `cta_text`, `cta_text_te`, `cta_text_hi` | Button label, 40 chars. **Blank = no button.** |
| `badge` | Small chip above the headline, 40 chars. |
| `text_theme` | `light` (white on dark scrim, default) · `dark` (near-black on light scrim) · `none` |
| `text_position` | `bottom_left` (default) · `bottom_center` · `center` · `top_left` |
| `accent_color` | `#RRGGBB` for the CTA pill and badge. Blank = brand green. Validated server-side. |

`text_theme: none` suppresses the scrim **and** all copy — use it when the artwork
already carries its own message. The scrim direction follows `text_position`, so a
top-anchored block darkens the top rather than the bottom.

Localized fields fall back to English when a translation is blank.

---

## 5. Redirection (tap action)

The app **never parses URLs**. It switches on the `action` enum and reads typed
keys from `payload`. Payload keys are stored camelCase.

| `action` | Required `payload` | Opens |
|---|---|---|
| `none` | — | Linked product, else the offers hub |
| `home` | — | Home |
| `offers` | — | Offers hub |
| `cart` | — | Cart |
| `credit` | — | VS Credit dashboard |
| `profile` | — | Profile |
| `search` | `query` | Search |
| `category` | `categoryId` | Product listing for that category |
| `product` | `productId` | Product detail |
| `order` | `orderId` | Order detail (falls back to the order list) |
| `external` | `url` | System browser |
| `brand`, `store` | — | No dedicated screen yet — falls back |

### Validation (`offers/validators.py`)

Enforced on both the admin and store write paths:

* the required key must be present and non-empty — a banner can no longer ship
  with `action=product` and an empty payload, silently dead-ending on tap;
* `productId` / `categoryId` / `storeId` must reference a row that **exists**;
* `external` URLs must be absolute **`https://`** — `http://`, `javascript:` and
  scheme-less values are rejected. Set `BANNER_EXTERNAL_HOST_ALLOWLIST` in
  settings to additionally pin outbound links to hosts you control;
* snake_case payload keys from older clients are normalized to camelCase.

The app re-checks the `https` scheme before launching, because a cached banner
could predate this validation.

---

## 6. Lifecycle and who can do what

```
draft ──submit──▶ pending ──approve──▶ scheduled ──▶ active ──pause──▶ paused
  ▲                  │                                  │                │
  └──── reject ──────┘                                  └── valid_to ────▶ expired
```

`state` is **not** writable through CRUD — only via
`POST /admin/marketing/offers/<id>/<transition>`, so the approval gate cannot be
bypassed by a crafted PATCH.

| Actor | Can |
|---|---|
| Super-admin (`/admin/marketing`) | Everything: create, target any zone/store or global, approve, reject, pause, archive |
| Store manager (`/marketing/banners`, perm `marketing.banners`) | Create a **draft for their own store**, edit it while draft, upload+crop, and **submit for approval** |
| Store manager | **Cannot** approve, target another store, target a zone, go global, pin, or edit once submitted |

Store ownership is server-forced on write (the request body's `store`/`zone`/
`state` are ignored), and reads are filtered by store — another store's banner
returns 404 rather than leaking its existence.

---

## 7. Endpoints

| Method | Path | Who |
|---|---|---|
| `GET` | `/offers?type=banner&placement=<p>` | Public (customer app) |
| `GET` | `/offers/specs` | Public |
| `POST` | `/offers/events` | Public — impression/click, batched, capped at 500/request |
| `GET POST` | `/admin/marketing/offers` | Admin |
| `GET PATCH DELETE` | `/admin/marketing/offers/<id>` | Admin |
| `POST` | `/admin/marketing/offers/<id>/image` | Admin — multipart `file` + `cropRect` |
| `POST` | `/admin/marketing/offers/<id>/<transition>` | Admin |
| `GET POST` | `/admin/marketing/coupons` | Admin |
| `POST` | `/admin/marketing/notify` | Admin — segment broadcast |
| `GET POST` | `/store/marketing/banners` | Store (`marketing.banners`) |
| `PATCH DELETE` | `/store/marketing/banners/<id>` | Store |
| `POST` | `/store/marketing/banners/<id>/image` | Store |
| `POST` | `/store/marketing/banners/<id>/submit` | Store |
| `GET` | `/store/marketing/coupons` | Store — read-only |
| `GET POST` | `/store/marketing/notify` | Store (`marketing.send`) |

The public feed enforces the schedule window, state, zone/store specificity and
product availability server-side. Clients send location context (`lat`/`lng`/
`pincode`); the server resolves zone and store — targeting is never client-supplied.
