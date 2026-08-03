# VS Mart — Customer App ↔ Backend Integration Plan

_Audit date: 2026-06-23 · Scope: `apps/user_app` (Flutter) vs `apps/backend` (Django/DRF, contract `/api/v1`)_

## 0. The real picture (read this first)

The app is **not "so back"** at the wiring level — that perception is mostly outdated. An evidence-based audit (endpoint calls + field-level contract diff) shows:

- **~13 of ~17 active modules are genuinely WIRED** to the real backend and **contract-match**: catalog, search, orders, checkout, offers/coupons, wishlist, reviews, returns, subscriptions, address, serviceability/zones, loyalty, referral, notifications, support, content, system, credit (read path), auth.
- Backend casing is bridged automatically (`core/renderers.py` camelCases responses; `CamelCaseJSONParser` underscoreizes requests), so most "snake vs camel" worries are non-issues. Money arrives as rupee numbers (`COERCE_DECIMAL_TO_STRING=False`).
- Newer backend capabilities are **already surfaced**: zone/store routing (store id flows from serviceability into catalog), real inventory/stock (in/low/out badges, checkout blocks), serviceability gating, zone credit gate.

So this is **not a rebuild**. It's a focused punch-list. The genuine gaps cluster into four buckets:

1. **Money flows that are fake or unintegrated** — cart bill is local math (too low), Razorpay is not integrated at all, credit repayment/collection writes go to local storage only.
2. **KYC is non-functional end-to-end** — no document bytes are uploaded (both sides JSON-metadata-only), response parser reads wrong casing, and one screen shows hardcoded "verified" data.
3. **Correctness defects** — orders show 6/13 statuses as "Pending", credit ledger mislabels fees, catalog silently truncates at 100 items.
4. **Demo/placeholder cleanup** — latent auth backdoors, empty stub feature folders, a few hardcoded lists, legal screens not using the CMS.

Plus one **business/compliance track** that is unbuilt on *both* sides: the RBI NBFC/LSP lending-partner model.

---

## 1. Priority tiers & recommended sequence

| Tier | Theme | Modules | Why first |
|------|-------|---------|-----------|
| **P0** | Money & functional integrity | Cart bill, Payments/Razorpay, Billing writes, KYC upload | Real users / real money break or get wrong numbers |
| **P1** | Correctness (wrong data shown) | Orders status, Credit ledger, Catalog pagination, Auth role, error envelopes, stock accuracy | App shows incorrect info but doesn't crash |
| **P2** | Demo/placeholder cleanup | Auth backdoors, empty stubs, hardcoded lists, legal CMS, tracking coords, dead code | Tech debt + demo leftovers |
| **P3** | Business/compliance track | Credit LSP/NBFC model | Needs legal/partner decisions; runs in parallel |

Recommended order: **P0 → P1 → P2**, with **P3** as a parallel business workstream. Within P0, do **Cart bill + Orders status first** (fastest, highest user-visible impact), then **Billing writes**, then **Payments**, then **KYC** (largest, needs backend work too).

Legend for the per-module sections: **Side** = where the work lives (App / Backend / Both). **Effort** = S (<½ day), M (½–2 days), L (>2 days).

---

## 2. P0 — Money & functional integrity

### M1 · Cart — show the real, authoritative bill
- **Status:** DEMO/MOCK display. Cart is local Hive (`cart/data/repositories/cart_repository_impl.dart`). The displayed bill is on-device math with hardcoded constants: GST `0.18` and delivery `45/499` (`cart/presentation/providers/cart_providers.dart:14-15,105,113`).
- **Gap (significant):** App total **omits platform/handling/small-cart/surge fees** and ignores zone delivery overrides that the backend applies (`core/pricing.py:62-69`). The cart total shown to the user can be **lower than what's charged at checkout** → trust-breaking surprise on the payment screen.
- **Fix:** Stop computing the bill on-device. Source it from the backend pricing engine. Two viable paths:
  - **(a) Server cart of record** — push cart mutations to `POST/PATCH/DELETE /cart/items` and render the bill from `GET /cart` (backend already returns subtotal, gst, deliveryFee, platformFee, handlingFee, couponDiscount, total). Best long-term (cross-device cart), more wiring.
  - **(b) Quote endpoint (lighter)** — keep local cart, add `POST /cart/quote {items}` returning the same bill breakdown; call it on cart change + on the checkout screen. Smaller change.
  - Recommended: **(a)** since the backend cart API already exists and is only used at checkout today.
- **Also:** add `variantId` to the app `CartItem` (backend cart items carry `variant_id`, `cart/serializers.py:37-42`).
- **Side:** App (path a is app-only; path b needs a small backend endpoint). **Effort:** M.

### M2 · Payments — integrate Razorpay (currently not integrated at all)
- **Status:** IGNORED. No `razorpay_flutter` in `pubspec.yaml`; zero gateway code; app never calls `POST /payments/start`. Checkout just posts `POST /checkout` with a `payment_method` radio + a mock OTP screen. The `features/payments/` folder is **empty (0 files)**.
- **Why it "works" today:** the backend mock gateway auto-settles in DEBUG (`payments/services.py:39-41`). Against a **live** Razorpay deployment, app-initiated payments would stick `PENDING` with no client to complete checkout.
- **Fix (App):**
  1. Add `razorpay_flutter` dependency.
  2. On "Pay": call `POST /payments` (purpose `order_payment` / `credit_repayment`), receive the Razorpay order (`gateway_order_id`, amount, currency, key).
  3. Open the Razorpay checkout sheet; on success, let the backend `WebhookView` settle (HMAC-verified, `payments/views.py:73-109`) and poll/refresh order/payment status.
  4. Remove the placebo "Secure payments powered by VS Mart" note + mock OTP screen (`payments/.../payment_screen.dart:253`).
- **Fix (Backend):** surface `key_id` and `currency` in the payment-initiate response (a real client needs them; `payments/serializers.py:6-13` currently omits `key_id`).
- **Side:** Both (mostly App). **Effort:** L.

### M3 · Billing — make repayment & cash-collection real writes
- **Status:** PARTIAL — reads are real, **writes are fake**. `makeRepayment` fabricates a `PAY<timestamp>` id into Hive and **never POSTs** (`billing/data/repositories/billing_repository_impl.dart:128-162`). `requestCollection` fabricates a `COL<timestamp>` record into Hive, no backend call (`:175-193`).
- **Gap (critical, financial):** Repayments and collection requests are **not recorded server-side**. The ledger, outstanding balance, and collection queue never see them.
- **Fix:** Wire `makeRepayment` → `POST /credit/repay` (and route the actual money movement through M2 Razorpay for online repayment). Wire `requestCollection` → `POST /credit/cash-collection`. Remove the synthetic-id Hive fakes; treat Hive as cache only.
- **Note:** the credit datasource already has a `/credit/repay` call with an `Idempotency-Key` (`credit/data/credit_backend_data_source.dart:80`) — the billing repository just isn't using it. Also promote `/credit/ledger` and `/credit/repay` from inline string literals into `api_constants.dart`.
- **Side:** App. **Effort:** M.

### M4 · KYC — make it functional end-to-end
- **Status:** SIGNIFICANT MISMATCH + DEMO. Three distinct problems:
  1. **No document bytes are uploaded.** `verification/data/datasources/verification_backend_data_source.dart:20-38` sends only `{type, number_masked}` as JSON; captured selfie/aadhaar/PAN images live in local Hive and are **dropped at submit**. The residence photo never even reaches the draft (`residence_verification_screen.dart:49-53`). The backend mirrors this — `kyc/serializers.py:44-45` accepts JSON dicts and `DocumentUrlView` is a stub (`kyc/views.py:35-38`). **Neither side ever stores a real document.**
  2. **Wrong-casing parser** — backend emits snake (`submitted_at`, `rejection_reason`) but the app reads `j['submittedAt']`/`j['rejectionReason']` (`verification_backend_data_source.dart:57,59`). Result: submit date falls back to `now()`, and the rejection reason **never displays** (`kyc_dashboard_screen.dart:241-249`).
  3. **Hardcoded fake KYC screen** — `kyc/presentation/screens/kyc_details_screen.dart:15-48` shows static "XXXX XXXX 4921 / ABCDE1234F / Completed on 12 Oct 2023", all forced "Verified", ignoring real status.
- **Fix (App):** capture → compress → **multipart upload** the actual image bytes (via `POST /uploads` then attach keys, or multipart `kyc/submit`); fix the response keys to snake_case; drop phantom `under_review`/`draft` status branches (backend has only `not_started/pending/verified/rejected`, `kyc/models.py:22-26`); render real `documents[]`/`steps[]`; replace `kyc_details_screen` hardcoded data with `GET /kyc/status`.
- **Fix (Backend):** accept real file uploads on `kyc/submit` (multipart), persist to storage, implement `DocumentUrlView` to return signed URLs.
- **Side:** Both. **Effort:** L. _(Gates credit eligibility — prioritize within P0 if KYC-gated credit is going live.)_

---

## 3. P1 — Correctness (app shows wrong data)

### M5 · Orders — map all status values
- **Gap:** App maps only 7 of 13 backend `OrderStatus` values (`orders/data/datasources/order_remote_datasource.dart:191-199` vs `orders/models.py:12-25`). These 6 **fall through to "Pending"**: `draft`, `placed`, `ready_for_dispatch`, `rejected`, `partially_returned`, `failed_delivery`. A **rejected order displays as Pending** — actively misleading.
- **Fix:** Complete the status map (all 13) with correct labels/colors; also widen the "active" filter (`orders/views.py:71` omits `ready_for_dispatch`).
- **Side:** App (+ tiny backend filter). **Effort:** S.

### M6 · Credit — fix ledger labels & surface dropped fields
- **Gaps:** (a) `fee` and positive `adjustment` ledger entries default to **"purchase"** (mislabeled), `order_remote`/credit translation layer. (b) Dropped fields: account `status` (frozen/closed → app shows it active), `nextDueAmount` (shows due date but not amount), `balanceAfter` (running balance). (c) `billingCycle` hardcoded `monthly` (`credit/data/credit_backend_data_source.dart:36`) — weekly cycles render wrong.
- **Fix:** Add `fee`/`adjustment`/`refund` to the ledger type mapping; read and surface `status`, `nextDueAmount`, `balanceAfter`; source `billingCycle` from the backend (or remove the assumption).
- **Side:** App (confirm backend sends `billingCycle` on dashboard; add if missing). **Effort:** S–M.

### M7 · Catalog — follow pagination (stop truncating at 100)
- **Gap:** App hardcodes `page_size:100` and never reads `meta` pagination → any category/search with >100 products **silently truncates** (`backend_catalog_data_source.dart`).
- **Fix:** Implement infinite scroll / "load more" using `meta.page`/`total_pages`.
- **Side:** App. **Effort:** M.

### M8 · Auth — small contract fixes
- **Gaps:** `role` field returned by backend (`accounts/serializers.py:30`) is dropped on `UserModel`; `verification_id` is omitted from the verify request when empty → latent **400** (backend requires it, `accounts/serializers.py:48-50`).
- **Fix:** Add `role` to the user model; always send `verification_id`.
- **Side:** App. **Effort:** S.

### M9 · Error-envelope handling (loyalty, referral)
- **Gap:** `/loyalty/redeem` and `/referrals/apply` return `{error:{code,message}}` on failure, but the app checks `success==false` (`loyalty_data.dart:111`, `referral_data.dart:74`) → an insufficient-points failure shows **"Points redeemed"**.
- **Fix:** Read the `error` envelope on these (and audit other POSTs for the same pattern).
- **Side:** App. **Effort:** S.

### M10 · Stock accuracy
- **Gap:** App keys low/out-of-stock off `stock_count` and **ignores `availableQuantity`** (on-hand − reserved) that the backend computes (`catalog/serializers.py`). Overselling edge during high reservation.
- **Fix:** Parse and prefer `availableQuantity` for stock badges and checkout validation.
- **Side:** App. **Effort:** S.

---

## 4. P2 — Demo / placeholder cleanup

### M11 · Remove latent auth backdoors
- `auth/presentation/providers/auth_provider.dart:129-177,251-257` — `_acceptAnyCredentials` demo path + `_demoUser` + master OTP `123456` (flag-gated **off**, but present).
- `auth/presentation/providers/session_provider.dart:100-108` — `_devUser` (verified KYC, credit enabled) behind `DEV_BYPASS_AUTH`.
- **Fix:** Strip these from release builds (compile-time exclusion / `kReleaseMode` guard) or delete. A flipped bool currently re-enables full demo login. **Side:** App. **Effort:** S.

### M12 · Delete empty stub feature folders
- Empty/dead scaffolding: `features/categories/**`, `features/products/**`, `features/addresses/**` (plural; the real one is singular `address/`), `features/home/data/**`, `features/payments/**` (until M2 fills it).
- Stale "fixture phase" comments in `catalog_repository_impl.dart:13`, `credit_repository_impl.dart:14` (both are actually backend-wired). Dead `VerificationFixtureDataSource` (`verification_data_source.dart:14-46`). Unused `PendingScreen` (`shared/widgets/pending_screen.dart`). Dead `creditServiceableProvider`.
- **Fix:** Remove dead code; update misleading comments. **Side:** App. **Effort:** S.

### M13 · Backend-drive a few hardcoded lists
- `support/.../raise_ticket_screen.dart:33-38` — hardcoded demo order list (`VS-10245`, …). **Should list the user's real orders** from `GET /orders`.
- `search/.../search_providers.dart:53-62` — hardcoded "trending searches". Source from backend (or a config endpoint) if available; otherwise acceptable as static.
- `settings/.../notification_settings_screen.dart:17-61` — hardcoded categories/channels; cross-check against `GET /notifications/preferences` shape so toggles map to real keys.
- **Side:** App (mostly). **Effort:** S–M.

### M14 · Legal screens → use the wired CMS
- `legal/.../privacy_policy_screen.dart` & `terms_screen.dart` render static `const` text while a **working** `content` module exists (`GET /content/pages/{slug}`, already wired). Point legal screens at `terms`/`privacy` slugs so legal copy is editable server-side. **Side:** App. **Effort:** S.

### M15 · Order tracking — real coordinates
- `orders/.../order_tracking_screen.dart:34-36` uses **hardcoded store coords** `LatLng(17.4435,78.3772)` + a hash-derived destination. Backend `GET /orders/{code}/tracking` returns real agent lat/lng. Single-product fetch also doesn't pass `?store=`.
- **Fix:** Use the tracking endpoint's real coordinates; wire Google Directions for the route (needs the Maps API key in `AndroidManifest`, already flagged in memory). **Side:** App. **Effort:** M.

### M16 · Misc
- `settings/.../about_screen.dart:84` — hardcoded `Version 1.0.0`; pull from package info / `GET /app-config`. **Effort:** S.

---

## 5. P3 — Business / compliance track (parallel)

### M17 · Credit as NBFC/LSP lending-partner model
- **Status:** IGNORED on **both** sides. Backend `CreditAccountSerializer` exposes only `credit_limit/outstanding/available/vs_score/status` — **no** `lender`, `partner`, `loan_account`, `interest_rate`, `apr`, `sanction` (`credit/serializers.py:6-11`). App UI is pure first-party "VS Credit / powered by VS Mart" (`credit_apply_card.dart:41-44`).
- **Per the RBI constraint memory:** VS Mart cannot lend on its own books — it must operate via an RBI-registered NBFC under the LSP (Lending Service Provider) model. The current product models direct first-party lending, which is the compliance gap.
- **This is a business/legal decision first** (partner selection, agreements, FLDG terms), then a backend data-model change (lender entity, loan account, sanction/disbursement, interest), then app UI (lender disclosures, KFS/sanction letter, partner branding). Keep it as a separate workstream — it does **not** block P0–P2.
- **Side:** Both + legal. **Effort:** L (multi-sprint).

---

## 6. One-page punch list

| ID | Module | Bucket | Side | Effort | One-liner |
|----|--------|--------|------|--------|-----------|
| M1 | Cart | P0 money | App | M | Render backend bill (real fees/zone), not local math |
| M2 | Payments | P0 money | Both | L | Integrate Razorpay; call `/payments`; complete checkout |
| M3 | Billing | P0 money | App | M | POST `/credit/repay` & `/credit/cash-collection` (stop fake writes) |
| M4 | KYC | P0 func | Both | L | Real multipart doc upload; fix casing; kill hardcoded screen |
| M5 | Orders | P1 correctness | App | S | Map all 13 statuses (rejected ≠ Pending) |
| M6 | Credit | P1 correctness | App | S–M | Fix fee labels; surface status/dueAmount/balanceAfter |
| M7 | Catalog | P1 correctness | App | M | Pagination / infinite scroll (no 100-item truncation) |
| M8 | Auth | P1 correctness | App | S | Add `role`; always send `verification_id` |
| M9 | Loyalty/Referral | P1 correctness | App | S | Read `{error:{…}}` envelope on failures |
| M10 | Stock | P1 correctness | App | S | Use `availableQuantity` for badges/validation |
| M11 | Auth backdoors | P2 cleanup | App | S | Strip demo login / dev user from release |
| M12 | Empty stubs | P2 cleanup | App | S | Delete dead feature folders + stale comments |
| M13 | Hardcoded lists | P2 cleanup | App | S–M | Real orders in ticket picker; backend-driven lists |
| M14 | Legal | P2 cleanup | App | S | Use `content` CMS for terms/privacy |
| M15 | Tracking | P2 cleanup | App | M | Real tracking coords + Directions |
| M16 | About/version | P2 cleanup | App | S | Version from app-config/package info |
| M17 | Credit LSP | P3 business | Both | L | NBFC/LSP lending-partner model (compliance) |

_Most work is App-side and additive (read more fields, call existing endpoints). The only modules needing meaningful backend work are M2 (key_id/currency), M4 (multipart upload + storage), and M17 (lending-partner data model)._
