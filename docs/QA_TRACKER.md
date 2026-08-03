# VS Mart — Master QA Tracker

Single source of truth for production-readiness. One row per test case. A sprint is
**done** only when it has **zero open P0/P1** rows.

**Status:** `Pass` (verified) · `Fail` (open bug) · `TODO` (not yet run) · `N/A`
**Auto** = covered by an automated test (file::Class.test shown in Notes).
**Manual** = needs a human/QA on a device (I can't tap devices, measure FPS, or run beta).
**Priority:** P0 (blocker) · P1 (major) · P2 (minor) · P3 (cosmetic)

> Maintenance: when a flow is audited, add/update its rows here. Mark `Pass` only
> with a named automated test or a confirmed manual check — never optimistically.

## Sprint status

| # | Sprint | Open P0/P1 | State |
|---|--------|-----------|-------|
| 1 | Authentication & Startup | 0 | 🟢 audited; auto-tested |
| P2-1 | **App: Cart & Checkout UI** | 0 | ✅ COMPLETE (automatable) — 32 Flutter tests: cart logic, checkout controller, placeOrder double-tap/retry, validation, payment-selector + empty-cart + offline-banner widget tests. Remaining = U-17 device integration only |
| 2 | Home | 0 | 🟡 audited (state handling correct: shimmer/offline/empty→shrink/error→shrink); widget tests for skeleton + category tile (full-screen render deferred — initState location/address plugins + network images need override harness) |
| 3 | Search | 0 | 🟡 recent-searches logic tested (dedup/cap-8/order/persist/empty-ignore); 5 tests |
| 4 | Product | 0 | 🟡 stock-status derivation (in/low@≤5/out) + add-to-cart mapping tested; 7 tests |
| 5 | Cart | — | ⚪ not started |
| 6 | Checkout + Payment | 0 | 🟡 dup-order + payment-integrity P0s fixed/tested; inventory + live-gateway next |
| 7 | Orders | 0 | 🟡 status classification (active/completed/cancelled partition + progress + labels) tested; **fixed cancel-eligibility drift** (app offered Cancel on `packed`, backend rejects); 6 tests |
| 8 | Profile | — | ⚪ not started |
| 9 | Notifications | — | ⚪ not started |
| 10 | Dynamic Content | — | ⚪ not started |
| 11 | Performance | — | ⚪ not started (manual/device) |
| 12 | Security | — | ⚪ partial (auth done) |
| 13 | Regression Suite (CI) | 0 | 🟢 `scripts/release_gate.sh` — 5 hard gates green (verified); wire into CI |
| 14 | Production Readiness | — | ⚪ ops checklist |

---

## Sprint 1 — Authentication & Startup

| ID | Module | Test Case | Expected | Auto | Manual | Status | Pri | Notes |
|----|--------|-----------|----------|------|--------|--------|-----|-------|
| A-01 | OTP | Send OTP returns verification_id | 200 + verification_id | ✅ | ☐ | Pass | P0 | `accounts.tests.AuthOtpTests.test_send_returns_verification_id` |
| A-02 | OTP | Wrong OTP rejected, no user created | code `OTP_INVALID`, no account | ✅ | ☐ | Pass | P0 | `..test_wrong_otp_is_rejected_and_creates_no_user` |
| A-03 | OTP | Valid OTP issues tokens + creates customer | 200 + access/refresh + is_new_user | ✅ | ☐ | Pass | P0 | `..test_verify_issues_tokens_and_creates_customer` (bypass) |
| A-04 | OTP | Lockout after 5 wrong attempts | further attempts fail | ✅ | ☐ | Pass | P1 | `..test_otp_locks_out_after_max_attempts` (OTP_MAX_ATTEMPTS=5) |
| A-05 | Token | Refresh rotates + blacklists old token | replay old → 401; new works | ✅ | ☐ | Pass | P0 | `AuthRefreshRotationTests.test_refresh_rotates_and_blacklists_old_token` — replay protection CONFIRMED |
| A-06 | Token | Garbage refresh token → 401 | 401 | ✅ | ☐ | Pass | P1 | `..test_garbage_refresh_token_is_401` |
| A-07 | Token | Missing refresh token → 400 | 400 | ✅ | ☐ | Pass | P2 | `..test_missing_refresh_token_is_400` |
| A-08 | App refresh | Concurrent 401s trigger ONE refresh | no rotating-token storm | ☐ | ☐ | Pass | P0 | code-audited: `auth_interceptor._inFlightRefresh` dedupes |
| A-09 | App refresh | Second 401 after retry doesn't loop | no infinite refresh loop | ☐ | ☐ | Pass | P1 | code-audited: `_retriedFlag` guard |
| A-10 | App refresh | Multipart upload replayed after 401 | body intact on replay | ☐ | ☐ | TODO | P2 | RISK: FormData is single-use; `_bare.fetch(req)` may send empty body on a 401 mid-upload (KYC/avatar). Verify + fix if repro. |
| A-11 | App refresh | Refresh fails for N concurrent reqs | logout/onUnauthorized fires once | ☐ | ☐ | TODO | P2 | minor: `onUnauthorized` called per-failed-request, not deduped |
| A-12 | Config | JWT signing key length | SECRET_KEY ≥ 32 bytes in prod | ☐ | ☐ | TODO | P2 | dev key is 23 bytes (InsecureKeyLengthWarning). Verify prod SECRET_KEY length. |
| A-13 | Startup | Cold start restores session | lands on Home, no flash of login | ☐ | ✅ | TODO | P0 | manual/device |
| A-14 | Startup | Offline launch with valid session | app opens, shows cached/offline UI | ☐ | ✅ | TODO | P1 | manual/device |
| A-15 | Startup | Language + theme restore on relaunch | persisted locale/theme applied | ☐ | ✅ | TODO | P2 | manual/device |
| A-16 | Startup | Kill app mid-login / rotate during OTP | no crash, resumes cleanly | ☐ | ✅ | TODO | P1 | manual/device |

**Sprint 1 result:** auth backend was previously **untested** (only live smoke scripts) — now 7 automated tests, all green. App interceptor audited (refresh dedup + loop-guard solid). No P0/P1 open. Remaining = manual device cases + 3 P2 hardening items.

---

## Sprint 6 — Checkout (partial — money path)

| ID | Module | Test Case | Expected | Auto | Manual | Status | Pri | Notes |
|----|--------|-----------|----------|------|--------|--------|-----|-------|
| C-01 | Checkout | Double-tap Pay | exactly one order | ✅ | ☐ | Pass | P0 | FIXED: app sync `placing`+key guard; backend `uniq_order_idempotency` constraint |
| C-02 | Checkout | Same Idempotency-Key retry | returns same order | ✅ | ☐ | Pass | P0 | `orders.tests.ZoneRoutingTests.test_checkout_is_idempotent_on_key` |
| C-03 | Checkout | Concurrent same-key submit (race) | DB rejects 2nd, one order | ✅ | ☐ | Pass | P0 | `orders.tests.CheckoutIdempotencyConstraintTests` (3 tests) |
| C-04 | Checkout | Bill matches server quote (no local math) | total == `/cart/quote` | ✅ | ☐ | Pass | P1 | `CartBillDataSource.quote` is authoritative |
| C-05 | Payment | finalize settles exactly once (dup callback/webhook) | one settle, no overwrite | ✅ | ☐ | Pass | P0 | `payments.tests.PaymentIntegrityTests.test_finalize_settles_exactly_once` — `select_for_update` + status guard |
| C-06 | Payment | Duplicate webhook → one settlement, one event | order PAID once | ✅ | ☐ | Pass | P0 | `..test_duplicate_webhook_finalizes_once` |
| C-07 | Payment | start_payment retry with same key | one Payment record | ✅ | ☐ | Pass | P0 | `..test_start_payment_idempotent_on_key` |
| C-08 | Payment | Concurrent same-key start (race) | DB rejects 2nd | ✅ | ☐ | Pass | P0 | FIXED: `uniq_payment_idempotency` constraint + IntegrityError catch in `start_payment` |
| C-09 | Payment | Order created but payment fails | order stays unpaid, payment FAILED | ✅ | ☐ | Pass | P1 | `..test_failed_webhook_marks_failed_not_paid` |
| C-10 | Payment | Gateway timeout / server restart mid-pay | order+payment recoverable (PENDING), webhook settles later | ☐ | ✅ | TODO | P1 | architecture sound (PENDING persists); needs live-gateway/manual check |
| C-11 | Payment | App killed during payment, resume | recoverable from My Orders | ☐ | ✅ | TODO | P1 | manual/device |
| C-12 | Payment | Real gateway wired (Razorpay/Cashfree) | live UPI/card settles via signed webhook | ☐ | ☐ | TODO | P0 | GAP not BUG: app-side gateway still mock ([[vsmart-app-backend-integration-plan]]); user has Cashfree PG keys |
| C-13 | Inventory | Two users buy last item (service) | last unit reserved once | ✅ | ☐ | Pass | P0 | `inventory.tests.OversellGuardTests.test_last_unit_cannot_be_reserved_twice` |
| C-14 | Inventory | Two users CHECKOUT last unit (e2e) | 1st reserves, 2nd blocked, no phantom order | ✅ | ☐ | Pass | P0 | `orders.tests.ZoneRoutingTests.test_two_checkouts_for_last_unit_block_oversell` |
| C-15 | Inventory | Qty=2, three users | serve 2, reject 3rd | ✅ | ☐ | Pass | P0 | `OversellGuardTests.test_two_units_serve_two_then_reject_third` |
| C-16 | Inventory | Cancel/timeout → stock restored | released unit reservable again | ✅ | ☐ | Pass | P0 | `OversellGuardTests.test_reserve_then_release...` + `orders ReservationTTLTests` (TTL release) |
| C-17 | Inventory | reserve never drops on-hand | on-hand stable until fulfilment | ✅ | ☐ | Pass | P1 | `inventory ReservationTests.test_reserve_drops_available_not_on_hand` |
| C-18 | Inventory | Mechanism: row lock + unique row | concurrent reserves serialise | ☐ | ☐ | Pass | P0 | CODE-AUDITED: `StockItem` unique(product,warehouse) + `reserve()` `@atomic` + `select_for_update` + check-after-lock. NB: true threaded proof needs Postgres (sqlite test DB no-ops the lock) |
| C-19 | Inventory | Admin stock edit / OOS / variant / deleted mid-cart | never sell unavailable | ☐ | ☐ | TODO | P1 | follow-up: admin-edit-during-reservation + cart-stale-stock cases |
| CP-01 | Coupon | Expired coupon | no discount / rejected | ✅ | ☐ | Pass | P1 | FIXED: `resolve_coupon` now checks `valid_to` — was IGNORED (expired coupons applied) |
| CP-02 | Coupon | Inactive / invalid code | no discount | ✅ | ☐ | Pass | P2 | `CouponEngineTests.test_inactive_coupon_invalid` |
| CP-03 | Coupon | Min order not met | no discount | ✅ | ☐ | Pass | P2 | `..test_min_order_not_met` |
| CP-04 | Coupon | Percent capped by max_discount | discount ≤ cap | ✅ | ☐ | Pass | P2 | `..test_percent_capped_by_max_discount` |
| CP-05 | Coupon | Global usage_limit | reject past limit | ✅ | ☐ | Pass | P1 | FIXED: `usage_limit` was UNENFORCED — now `redeem_coupon` counts under lock → COUPON_LIMIT_REACHED |
| CP-06 | Coupon | Per-user limit / one-time | same user blocked, others ok | ✅ | ☐ | Pass | P1 | FIXED: `per_user_limit` was UNENFORCED → COUPON_ALREADY_USED |
| CP-07 | Coupon | Concurrent redemption of last coupon | one redemption only | ✅ | ☐ | Pass | P0 | `redeem_coupon` `select_for_update` on Coupon row + count-under-lock (sqlite no-ops lock; logic validated) |
| CP-08 | Coupon | Redemption recorded at checkout | `CouponRedemption` row created | ✅ | ☐ | Pass | P1 | FIXED: was NEVER written — now `place_order` calls `redeem_coupon` in its atomic block |
| CP-09 | Coupon | Coupon removed/invalid after cart change | discount recomputed from server quote | ☐ | ☐ | TODO | P2 | preview path; checkout re-resolves server-side |
| CR-01 | Credit | Purchase cannot exceed limit (concurrent) | outstanding ≤ limit, available ≥ 0 | ✅ | ☐ | Pass | P0 | FIXED: limit check was OUTSIDE the lock → 2×₹800 on ₹1000 → −₹600. Now `_post(enforce_limit)` re-checks under `select_for_update`. `credit.tests.test_purchase_cannot_exceed_limit` |
| CR-02 | Credit | Available never negative | clamp at limit | ✅ | ☐ | Pass | P0 | `..test_available_never_negative` |
| CR-03 | Credit | Outstanding == Purchases − Repayments | cache == Σ ledger | ✅ | ☐ | Pass | P0 | `..test_outstanding_equals_purchases_minus_repayments` |
| CR-04 | Credit | Append-only ledger | UPDATE/DELETE blocked | ✅ | ☐ | Pass | P0 | `..test_ledger_is_append_only` |
| CR-05 | Credit | Refund → ↓outstanding, ↑available, ledger row | reconciles | ✅ | ☐ | Pass | P1 | `..test_refund_decreases_outstanding_and_writes_ledger` |
| CR-06 | Credit | Overpayment clamps at 0 | no negative outstanding | ✅ | ☐ | Pass | P1 | `..test_overpayment_clamps_outstanding_at_zero` |
| CR-07 | Credit | reconcile() rebuilds from ledger | cache repaired | ✅ | ☐ | Pass | P1 | `..test_reconcile_rebuilds_outstanding_from_ledger` |
| CR-08 | Credit | Ineligible (KYC/unverified) blocked | CreditError | ✅ | ☐ | Pass | P1 | `..test_ineligible_user_cannot_purchase` |
| CR-09 | Credit | Duplicate repayment webhook → one repayment | one ledger entry | ✅ | ☐ | Pass | P0 | via payments layer: `finalize_payment` idempotent → `apply_repayment` once (`payments.tests`) |
| CR-10 | Credit | Overdue blocks new credit order | OVERDUE_PAYMENT at checkout | ☐ | ☐ | TODO | P1 | logic exists in place_order; add a test |
| CR-11 | Credit | Cancellation releases credit | apply_refund posted | ✅ | ☐ | Pass | P1 | `orders ZoneRoutingTests.test_cancel_credit_order_reverses_outstanding_via_ledger` |

## Financial Reconciliation — reversal path (cancel/return/refund)

| ID | Module | Test Case | Expected | Auto | Manual | Status | Pri | Notes |
|----|--------|-----------|----------|------|--------|--------|-----|-------|
| RC-01 | Cancel | Cancel reserved order releases stock | exactly one release, available restored | ✅ | ☐ | Pass | P0 | `test_cancel_cod_order_releases_reserved_stock` |
| RC-02 | Cancel | Cancel credit order reverses outstanding | refund ledger entry, outstanding→0, purchase NOT deleted | ✅ | ☐ | Pass | P0 | `test_cancel_credit_order_reverses_outstanding_via_ledger` |
| RC-03 | Cancel | Atomicity + race-safety | all-or-nothing; double-cancel can't double-reverse | ✅ | ☐ | Pass | P0 | FIXED: `cancel_order` now `@atomic` + `select_for_update` re-read. `test_double_cancel_is_rejected_no_double_reversal` |
| RC-04 | Cancel | Cancel after delivered rejected | ORDER_NOT_CANCELLABLE (return flow) | ✅ | ☐ | Pass | P1 | `test_cannot_cancel_delivered_order` |
| RC-05 | Cancel | Cancel fulfilled/shipped order | stock back via ORDER_CANCEL ledger row | ☐ | ☐ | TODO | P1 | code path exists; add a test (stock_state=FULFILLED) |
| RC-06 | Refund | Online-paid order cancelled → gateway refund + refund Payment row | one refund, money returned | ☐ | ☐ | TODO | P0 | GAP: cancel reverses CREDIT but NOT online-paid (UPI/card) — no refund Payment created. Needs live gateway ([[vsmart-app-backend-integration-plan]]) + bookkeeping |
| RC-07 | Returns | Return refunded → credit reversed via new ledger entry | reconciles | ✅ | ☐ | Pass | P1 | `returns.tests.test_refund_posts_credit_refund_ledger_entry` |
| RC-07b | Returns | Duplicate refund (double-click/retry) rejected | exactly one reversal | ✅ | ☐ | Pass | P0 | FIXED: `set_return_status` was re-runnable on `refunded` (status==status skipped the guard) → double credit+restock. Now `@atomic` + `select_for_update` + terminal-state guard. `test_double_refund_is_rejected_no_double_reversal` |
| RC-07c | Returns | Damaged return → quarantine vs resellable restock | damaged not added to sellable | ☐ | ☐ | TODO | P1 | GAP: `_process_refund` always restocks to sellable; no condition/quarantine routing (DAMAGE ledger type exists) |
| RC-10 | Ops | `reconcile_finance` command | PASS, or ERROR list w/ exit 1 | ✅ | ☐ | Pass | P1 | NEW: `system/management/commands/reconcile_finance.py` checks credit==ledger, inventory==ledger, redemptions<=limit, orphan reservations. `--fix` repairs caches. (Found real dev-data stock drift on first run.) |
| RC-08 | Coupon | Cancel restores redemption (if policy) | per policy | ☐ | ☐ | TODO | P2 | POLICY: currently NOT restored on cancel (anti-abuse default) — confirm intended |
| RC-09 | Invariant | Σ reservations == Σ releases+consumptions | no orphan holds | ☐ | ☐ | TODO | P1 | add a ledger-reconcile assertion / nightly check |

---

## Phase 2 · Sprint 1 — Cart & Checkout UI (started 2026-06-28)

**Flutter test infrastructure now exists** (`test/helpers/fake_cart_repository.dart` + `ProviderContainer`-override pattern — reusable for every feature; was only the default stub before).

| ID | Module | Test Case | Expected | Auto | Manual | Status | Pri | Notes |
|----|--------|-----------|----------|------|--------|--------|-----|-------|
| U-01 | Cart | Empty cart | empty-state CTA | ☐ | ☐ | Pass | P1 | audited: `cart.isEmpty → VSEmptyCart` |
| U-02 | Cart | Offline | offline banner, cart still usable | ☐ | ☐ | Pass | P1 | audited: `VSOfflineBanner` |
| U-03 | Cart | Bill falls back to on-device estimate (offline / quote fails) | `isEstimate` bill, no crash | ✅ | ☐ | Pass | P1 | `cart_logic_test` — `cartSummaryProvider` null-backend path |
| U-04 | Cart | add / increment / decrement / decrement-to-0 / clear | quantity correct, line removed at 0 | ✅ | ☐ | Pass | P1 | `cart_logic_test CartController mutations` |
| U-05 | Cart | Free-delivery threshold + GST estimate | delivery+gst+total correct | ✅ | ☐ | Pass | P1 | `cart_logic_test` (517 below / 590 free) |
| U-06 | Checkout | Double-tap Place Order | one order | ✅ | ☐ | Pass | P0 | app guard (C-01) + backend constraint |
| U-07 | Checkout | Actionable errors (KYC/zone/credit/coupon) | navigate/dialog/retry | ☐ | ☐ | Pass | P1 | audited: `payment_screen` routes via `presentFailure` |
| U-08 | Checkout | Coupon expired / already-used at checkout | coded error, removable | ☐ | ☐ | TODO | P1 | backend enforces (CP-01/06); add app widget test |
| U-09 | Cart | Price/stock changed mid-cart | re-validate, inform user (never silently re-price) | ✅ | ☐ | Pass | P1 | `cart_validation_test` — OOS/qty-exceeds blocking; price-change advisory |
| U-10 | Checkout | Payment cancelled / failed / retry / app-killed-resume | recoverable, one order | ☐ | ✅ | TODO | P0 | needs live gateway + device (RC-06 gap) |
| U-11 | Checkout | Draft persists/loads (payment method, coupon) | resumes after kill | ✅ | ☐ | Pass | P1 | `checkout_controller_test` — Hive draft round-trip (FakeHiveService) |
| U-12 | Checkout | grandTotal subtracts coupon + clamps at 0 | never negative payable | ✅ | ☐ | Pass | P1 | `checkout_controller_test` (590−50=540; clamp 0) |
| U-13 | Checkout | selectPaymentMethod persists | survives resume | ✅ | ☐ | Pass | P2 | `checkout_controller_test` |
| U-14 | Checkout | removeCoupon clears discount | bill recomputed | ✅ | ☐ | Pass | P2 | `checkout_controller_test` |
| U-15 | Checkout | placeOrder: double-tap / placing-guard / retry-reuses-key / success-clears / failure-keeps-draft / analytics-once / not-serviceable | one order, key reused, recoverable | ✅ | ☐ | Pass | P0 | `place_order_test` (5 tests) — full controller harness (fake order-repo + serviceability + validation + counting analytics). The P0 double-submit guard is now regression-locked end-to-end |
| U-16 | Checkout | Payment selector renders 4 methods + single-select; tap selects | render + interaction | ✅ | ☐ | Pass | P2 | `payment_screen_test` (2) via `widget_harness` (real theme+l10n, container-readable) |
| U-16b | Cart | Empty cart renders empty state | VSEmptyCart shown | ✅ | ☐ | Pass | P2 | `cart_screen_test` |
| U-16c | Cart | Offline banner shows offline / hidden online | cloud-off when offline | ✅ | ☐ | Pass | P2 | `cart_screen_test VSOfflineBanner` (2) |
| U-17 | Checkout | Full happy-path integration (add→coupon→address→pay→success→Orders) | end-to-end | ☐ | ✅ | TODO | P1 | `integration_test/` — needs device/emulator |

## Sprints 2–5, 7–14 — backlog (to populate as each sprint runs)

Seed cases from the sprint plan; mark `TODO` until verified.

- **S2 Home:** ✅ audited (state handling correct) + widget tests: `home_widgets_test` (VSHomeShimmer skeleton, VSCategoryCard label/icon/tap). Full-screen render deferred (initState location/address plugin calls + VSNetworkImage secure-storage need an override harness); state branches (banner empty/loading/error, offline, shimmer) are code-audited-correct. Remaining backend banner targeting already covered by `offers.tests`.
- **S3 Search:** ✅ recent-searches logic tested (`recent_searches_test`: dedup case-insensitive, most-recent-first, cap 8, empty/whitespace ignored, persist across rebuilds, remove/clear). Remaining: search-results widget tests (no-result/loading) — need catalog-search provider override harness (next pass).
- **S4 Product:** ✅ domain logic tested (`product_logic_test`: stockStatus in/low(≤5 boundary)/out + inStock-flag + unknown-count; `cartItemFrom` field+quantity mapping). Remaining: image slider / variant selector / reviews widget tests — need screen render harness + VSNetworkImage override (next pass).
- **S5 Cart:** add/remove/inc/dec, rapid tap, variant switch, coupon, fees, zone change, store closed, product removed, OOS, price changed, min/max order, server mismatch, restore, offline/reconnect.
- **S7 Orders:** ✅ status logic tested (`order_status_test`: every status labelled, active/completed/cancelled is an exact partition, progress∈[0,1], delivered=1.0/cancelled=0.0) + **BUG FIX: `OrderStatus.isCancellable`** added (pending|confirmed, mirrors backend) — order_details `_cancellable` no longer offers Cancel on `packed` (backend rejected it). OPEN BUSINESS Q: should `packed` orders be cancellable? (would need a backend change). Remaining: order-list/timeline/invoice widget tests (need render harness).
- **S8 Profile:** addresses, photo, notifications, language, delete account, terms/privacy/about, referral.
- **S9 Notifications:** fg/bg/killed, tap, deep link, duplicate, grouping, wrong route/order/customer, expired, logo/icon, Android channels.
- **S10 Dynamic content:** admin product/category/banner/coupon/offer/store-hours/delivery-charge/campaign changes reflect in app; image cache + deletion + cleanup.
- **S11 Performance:** backend N+1 audit ✅ — list endpoints already use `select_related`/`prefetch_related` (orders prefetch items+timeline, billing items, catalog category/gallery/variants, cart product, delivery order); `LedgerEntrySerializer` is scalar-only (no FK traversal) → no N+1. Device-side (cold/warm start, FPS, memory, image cache) still needs an emulator/profiler. Targets: cold <2.5s, warm <1s, home API <500ms, search <300ms, add-to-cart <250ms, checkout <3s, 60 FPS, no 30-min memory growth.
- **S12 Security:** JWT expiry+rotation ✅(A-05) · **IDOR/object-ownership ✅** — audited customer API (orders/payments/notifications/returns/KYC all `user=request.user`-scoped; `PrivateMediaView` owner-gated) + regression tests `orders.tests.ObjectOwnershipSecurityTests` (cross-user read/invoice/tracking/cancel → 404; anon → 401/403). **File-upload sanitization ✅** — KYC uploads now validated via `mediastore.pipeline.validate_image_upload` (size + real-image format); `kyc.tests.KycUploadValidationTests` (non-image→UNSUPPORTED_MEDIA_TYPE, valid→201). Avatars/POD already used the validated `store_image` pipeline. Remaining: rate-limit verification, SQLi/XSS pass (ORM-only confirmed; spot-check raw SQL), secure-headers, audit-log coverage.
- **S13 Regression suite:** ✅ `scripts/release_gate.sh` runs django check + no-missing-migrations + backend tests + `flutter analyze` + `flutter test` (hard gates) + `reconcile_finance` (informational). Verified PASS (305 backend + 27 Flutter). TODO: wire into CI (GitHub Actions / GitLab) on every merge; add a device-driven login→checkout→track integration_test later.
- **S14 Production readiness (ops):** crash reporting, monitoring, DB + media backups, log rotation, Redis persistence, TLS validity, disk alerts, push tested, real-time tested, analytics verified.
