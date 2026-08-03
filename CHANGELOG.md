# Changelog

All notable engineering changes to VS Mart. Newest first.

## [Unreleased] — Zone scoping edge cases + tracking gated on dispatch (2026-07-21)

### Zone / location
- **Category tiles that opened empty listings.** `/categories` and
  `/categories/<id>/sub-categories` returned the whole company tree while
  `/products` was already store-scoped — so a customer saw departments their store
  carries nothing in. Both are now scoped to categories the serving store can
  actually fill (`scoped_category_ids`), and take optional auth so a signed-in
  customer's saved address resolves their store. Unscoped deployments are
  unaffected: the helper returns None and the tree is untouched.
- **`/products/suggest` leaked another store's categories** despite a docstring
  claiming it was scoped. Now filtered like the products and terms beside it.
- **`/coupons/wallet` returned every active coupon**, including other customers'
  PERSONAL loyalty vouchers (`Coupon.owner`) and expired ones — a straight
  disclosure of someone else's code, value and expiry. Now public codes plus the
  requesting user's own, unexpired.
- **Offers ignored GPS and manual pins.** The provider read only the saved address,
  so a new user, a guest, or any GPS-only session sent no location and got the
  GLOBAL banner set — promotions for other cities, deals on products their store
  doesn't stock. Both catalog and offers now read one shared `locationScopeProvider`
  (manual pin → saved address → live fix), and the offers cache is namespaced by
  serving store like the catalog's (its keys were `banners`/`deals`/`coupons`, so
  changing zone kept showing the previous zone's promotions for the whole TTL).
- **A zone with no store now reads as NOT serviceable.** It answered
  `serviceable: true` with `store_id: null`, so the app unlocked the storefront and
  then every catalog call returned empty — a working-looking app with nothing in it.
  The customer now gets the not-serviceable screen with change-location and
  notify-me. Reverses `zones.tests.test_inactive_store_hides_store_but_zone_still_serviceable`,
  which locked in the old behaviour; the test now documents why it flipped.

### Cart → order → invoice → tracking
- **Live tracking is gated on dispatch.** New `isTrackable` / `isDispatched` /
  `isFailed` / `isPreparing` on `OrderStatus`. Every guard had used `isActive`,
  which is true for `draft`, `pending`, `placed` and `failedDelivery` — so an order
  placed thirty seconds ago opened a full-screen map with a *locally simulated*
  rider driving toward the customer. Before hand-off the screen now shows the
  preparation state; the map appears at `ready_for_dispatch`/`out_for_delivery`.
- **The rider row and call button require an actual rider** (`isDispatched`). They
  appeared from any snapshotted agent name, so a customer could phone a rider about
  an order still on the packing bench.
- **A finished order redirects to its details.** Delivered, partially returned,
  cancelled, rejected, returned and failed-delivery orders no longer render a
  tracking map — including via push deep links and stale back-stack entries, which
  bypass every widget-level guard. `_DeliveredSummary`'s Reorder moved to the order
  details screen so the capability followed the journey rather than being lost.
- **Cancelled orders showed a fully-ticked "Delivered" timeline.** `done` compared
  enum ORDINALS, and the terminal failure states are declared after `delivered`, so
  every step satisfied it. Now compares position in the delivery flow, and uses the
  backend's real event timestamps instead of the promised ETA.
- **The 12s poll never stopped** on `failedDelivery` (it is `isActive`) or on a hard
  error (`valueOrNull` is null in both). Both now terminate it.
- The tracking WebSocket is only subscribed once a rider is actually moving.

### Tests
- Backend **813** green (9 new: department/subcategory scoping, out-of-area empty
  tree, suggest categories, global mode unchanged, cross-user and expired coupons,
  no-store serviceability both ways).
- Flutter **122** green (9 new covering every status against the four new gates).

## [Unreleased] — Store-scoped catalog cache + global-product purge tool (2026-07-21)

### Fixed
- **Changing location kept showing the previous store's products.** The catalog is
  store-scoped server-side (verified: Store A's customer sees A's items, B's sees
  B's, cross-store private products stay hidden, no store → empty), but NO cache
  key included the store. So after a location change the app served the previous
  store's catalog out of Hive for the whole 5-minute TTL — and indefinitely while
  offline. Every key is now namespaced by a `catalogScopeProvider` (resolved store
  id → pincode → coarse 2-dp lat/lng), so a location change is a cache miss and
  refetches, while returning to a known store is still instant.

### Added
- **`purge_global_products`** management command — deletes products with
  `origin_store IS NULL`. Dry-run by default; `--apply` required; reports the full
  cascade via Django's own `NestedObjects` collector before touching anything.

### Important finding — a hard delete is mostly impossible by design
Dry run against the dev DB: of **99 global products, only 6 can be deleted**.
**93 are PROTECT-blocked by `InventoryLedger`** (the append-only stock audit
record) and 26 by `POSTransactionItem` (real till sales). Django raises
`ProtectedError` for those, and in one transaction that means *nothing* is
removed — so a naive `.delete()` would silently accomplish nothing. The command
skips and reports them instead, naming which relation blocks what, and
`--deactivate-protected` takes them out of the catalog (`is_active=False`) while
keeping the accounting history intact.

### Tests
- Backend **794** green (6 new: dry run changes nothing, cascades, order lines
  survive via SET_NULL, PROTECT skipped rather than fatal, deactivate path).
- Flutter **113** green (4 new: a new store misses the cache, a known store still
  hits it, the offline fallback is scoped, categories/store-tree scoped too).

## [Unreleased] — Fix: saving an address landed on a blank page (2026-07-21)

Reported as "address doesn't save, goes to another page which is blank".

### Fixed
- **An actionable failure `push`ed its destination instead of `go`ing to it.**
  `presentFailure`'s `navigate` case called `context.pushNamed`, but half the
  targets `_mapTarget` returns (`/home`, `/cart`, `/credit`) are
  `StatefulShellRoute` branches and `/login` is an entry route the redirect
  rewrites to `/home`. Pushing a shell branch imperatively onto the root navigator
  renders blank. So a save that failed with `AUTH_REQUIRED` (expired session — the
  refresh token had also expired, so the session was correctly torn down) pushed
  `/login`, the redirect turned it into `/home`, and the customer got an empty
  screen with the address unsaved and no error shown. Now uses `goNamed`: an
  actionable error is a destination change, not a drill-down.
- **`context.pop()` sat inside the save's `try`.** `pop()` throws when there's
  nothing to pop, which landed in `catch` *after* the address had been created —
  reporting a failure for a save that worked, and arming a Retry that posted a
  duplicate. Moved out of the `try`.
- **Editing an address wiped its village.** The form has no village input, so
  `_save` built the entity without one; it defaulted to `''` and the PATCH sent
  that. The stored value is now carried through.
- **The serviceability gate could evict a half-filled address form.**
  `/addresses` wasn't exempt, so a verdict change while typing replaced the stack
  with `/not-serviceable`. Exempt now — the gate's own remedy is "change your
  location", which means managing addresses, so gating them was circular.

### Verified
- The backend was NOT at fault: `POST /api/v1/addresses` with the app's exact body
  (including 7-decimal GPS) returns 201 and persists correctly — confirmed against
  a live DB, not just by reading the serializer.
- Flutter **105** tests green (2 new, asserting a navigate action leaves exactly
  one route on the stack and that a plain validation failure never navigates);
  `flutter analyze` clean.

## [Unreleased] — Order lifecycle, refunds & payment recovery (2026-07-21)

Second pass on the commerce audit: closes the money path end-to-end and gives the
order lifecycle a real state machine.

### Money
- **Cancelling a paid order now refunds it.** `cancel_order` only ever reversed the
  VS Credit leg — a customer who paid ₹2,000 by UPI and cancelled a confirmed order
  had the order cancelled, the stock returned, and the money kept, with
  `payment_status` still reading "paid". `refund_payment` had existed the whole
  time; nothing outside the returns flow called it. Refunds are keyed on the order
  code so a concurrent customer+admin cancel settles to one refund, and the amount
  is what was actually *collected* (`collected_amount`), not `order.total`, which
  would over-refund a part-credit order.
- **A partial refund no longer retires the whole original payment.** A ₹200 return
  against a ₹2,000 order marked the ₹2,000 payment REFUNDED, dropping the full
  amount out of collected revenue in the admin ledger. The original flips only once
  refunds cover it.
- **Interrupted payments are recovered.** New `reconcile_payments` command +
  `RazorpayGateway.fetch_order_payment`: for each stale PENDING gateway payment, ask
  the gateway what actually happened. `release_expired_reservations` now reconciles
  first and skips orders with an unresolved gateway payment — it used to cancel
  orders whose money had already been captured (app killed before the callback,
  webhook lost). Wired into the scheduler every ~10 minutes.
- **The app's payment callback is verified server-side.** New
  `POST /payments/<id>/confirm` re-computes the HMAC over `order_id|payment_id`;
  the app now forwards the signature instead of discarding it, and no longer claims
  success on the client SDK callback alone. The signed order id must match the one
  we created, so a valid triple from another of our orders can't be replayed.

### Order lifecycle
- **`advance_status` enforces a state machine.** It used to assign whatever it was
  handed (`LIFECYCLE` was declared and never consulted), so an agent could mark a
  cancelled or never-paid order "delivered" — fulfilling its stock and awarding
  loyalty points. Expressed as rules, not an edge table, because stores legitimately
  skip rungs: forward-only, nothing leaves a terminal state, and **delivered is
  reachable only from out_for_delivery**. Also now atomic, so an order can't commit
  as delivered with its fulfilment half-applied.
- **The legacy agent status endpoint no longer bypasses the delivery guards.** It
  wrote the order directly, skipping the reached-location precondition, the delivery
  OTP and the mandatory proof-of-delivery photo, and left `DeliveryTask` and `Order`
  permanently disagreeing. It now delegates to `complete_delivery` / `fail_delivery`,
  and refuses when there is no active task to guard with. Its `failed` branch was
  also a silent no-op — the customer saw "out for delivery" forever.

### Stock & coupons
- **`failed_delivery` and `rejected` release their reservation.** Only `cancel_order`
  ever released stock and it refuses anything outside pending/confirmed, so every
  failed delivery permanently shrank sellable stock with no reachable path to free
  it. Idempotent, so a re-attempted delivery can't double-release.
- **Cancelling gives the coupon back.** Redemptions are what `usage_limit` /
  `per_user_limit` count, and nothing deleted them — a single-use coupon was burned
  by an abandoned payment the customer never completed.
- `InventoryService.release` still clamps at zero (an unwind must not fail half-way)
  but now logs the underflow. Silently absorbing it is what made reserve drift
  invisible.

### Tests
- Backend **768** green (+33: cancel refunds, collected-amount vs credit leg, partial
  refunds, the transition rules, illegal-move rejection, reconciliation outcomes,
  expiry-job interaction, reservation release/idempotency, coupon release,
  confirm-endpoint verification/replay/ownership). `flutter analyze` clean.

## [Unreleased] — Commerce flow audit: payment & cart integrity (2026-07-21)

Audit of cart → payment → order → tracking. The P0 money/security defects are
fixed; the ranked remainder is tracked (cancel-without-refund, order state machine,
callback verification, reconciliation, stock/coupon unwind, tracking).

### Security / money (P0 — exploitable)
- **An order could be paid for with any amount the client chose.** `StartPaymentView`
  passed the request's `amount` straight through and `finalize_payment` marked the
  order PAID regardless — `{"order_id": "VS123", "amount": 1}` opened a real ₹1
  gateway order for a ₹5,000 basket and shipped it. The amount is now derived from
  `order.total`, an already-paid order is refused, and `finalize_payment` asserts the
  gateway's settled amount (leaving the payment PENDING on mismatch, since real money
  may have moved and a FAILED row would hide it).
- **A missing SDK downgraded live payments to a gateway that trusts every webhook.**
  `get_gateway()` caught bare `Exception` and returned `MockGateway`, whose
  `verify_webhook` returned `True` unconditionally — and the webhook endpoint is
  unauthenticated by design, so anyone could mark arbitrary orders paid, with
  `signature_ok=True` recorded in the audit trail. Configured keys now fail closed.
  The mock's blanket trust is additionally gated on `PAYMENTS_TRUST_MOCK_GATEWAY`
  (dev True / prod False) — a settings-module flag rather than `DEBUG`, because
  Django's test runner forces `DEBUG=False` and so it cannot distinguish CI from
  production.
- **The webhook parsed a payload Razorpay never sends.** It read flat `event_id` /
  `gateway_order_id` / `status == "success"`; the real body is nested under
  `payload.payment.entity` with the event id in the `X-Razorpay-Event-Id` header. In
  production the first live webhook stored a blank `event_id` (a unique column — so
  every later event answered "already_processed" forever), matched the most recent
  *cash* payment on a blank order id, and marked it FAILED, while the genuinely paid
  order stayed pending. `parse_webhook` now handles both shapes, converts paise, and
  rejects an unidentifiable event with 400 instead of poisoning the unique slot.
- **A cart line's price could be set by the caller.** `variant_id` accepted any
  variant in the catalog while the line priced as `product.price + variant.price_delta`
  — pairing a ₹2,000 product with another product's −₹1,900 variant charged ₹100, and
  it was invisible in the UI because `/cart/quote` and `/cart/validate` both scope the
  variant correctly and kept showing the honest bill.

### Fixed
- Partial credit repayment marked the entire statement PAID and wrote a fabricated
  full receipt (₹1 against ₹8,000 stopped dunning and desynced the ledger by ₹7,999).
  Payments now accumulate and settle the statement only once covered.
- Cart quantities are bounded (`MAX_LINE_QUANTITY = 99`), clamped on the accumulating
  POST as well — a per-request cap alone can't bound an endpoint that adds.

### Tests
- Backend **727** green (24 new across `payments/test_integrity.py` and
  `cart/test_integrity.py`: amount substitution, short settlement, already-paid,
  cross-user, both webhook shapes, blank/unknown event ids, gateway fail-closed,
  mock trust gating, statement part-payment, variant injection, quantity bounds).

## [Unreleased] — Deep links (2026-07-20)

Shared product links now open the app. `ShareService` had been building
`https://thevsmart.com/products/<shareToken>` since the share feature shipped, with
a comment anticipating this work; nothing was wired on either side.

### Added
- **`resolveDeepLink`** (`core/services/deep_link.dart`) — an allowlist mapping an
  incoming URL to an in-app route. Host must be `thevsmart.com`/`www.`, scheme
  `https` (or the `vsmart://` custom scheme); only `/products/<id>` and its legacy
  `/product/<id>` alias are accepted; encoded separators and `..` are rejected and
  the identifier is re-encoded so it can't split into a second segment. Anything
  else is ignored and the app opens normally.
- **Deferred link replay** — `PendingDeepLink` + `DeepLinkController` (`app_links`).
  A link is parked, not navigated to: the router's 250 ms splash hold rewrites any
  location to `/splash` and drops it, the auth gate bounces unauthenticated users to
  `/login`, and the serviceability gate forces `/not-serviceable` on a fresh install
  while the first GPS verdict resolves. The redirect now consumes the parked link at
  the one point every gate has already allowed the location, so a shared link
  survives a cold start, onboarding and a sign-in. `take()` clears on first attempt
  so a still-gated target can't loop into go_router's redirect limit.
- **Android App Links** — `VIEW`/`BROWSABLE` intent-filter with `autoVerify`,
  path-scoped to `/products/` and `/product/` so marketing, `/privacy` and `/terms`
  stay in the browser. `flutter_deeplinking_enabled=false` set explicitly so
  `app_links` is the single delivery path and Flutter's built-in handling can't race
  it into the gates.
- **`/.well-known/assetlinks.json` and `/.well-known/apple-app-site-association`**
  as Next.js Route Handlers on the landing site — required because the AASA file has
  no extension and static serving would return `application/octet-stream`, which
  Apple rejects. Both read env per request, so rotating a fingerprint is a restart
  rather than a rebuild, and both 404 with an explanatory message until configured.
- `ios/Runner/Runner.entitlements` with `applinks:thevsmart.com`, and
  `docs/DEEPLINKS.md` covering the flow, the security model and activation.

### Tests
- Flutter **97** green (17 new: lookalike hosts, unpublished sections, bare and
  over-long paths, smuggled `%2F`, duplicate launch-link delivery, one-shot take).
  `flutter analyze` clean; landing site builds with both routes as dynamic.
- Endpoints exercised against a running server: both return
  `Content-Type: application/json` with correct bodies when configured, and 404 with
  a message when not.

### Blocked on values not in the repo
- **Android**: `ANDROID_SHA256_CERT_FINGERPRINTS` must be the Play **app-signing**
  SHA-256 (Play Console → Setup → App integrity). `PLAY_CONSOLE_VSMART.md` documents
  the *upload* key, which would fail verification on every Play-installed build.
- **iOS**: no `DEVELOPMENT_TEAM` exists anywhere, so `APPLE_APP_ID` is unknown and
  Associated Domains must be enabled once in Xcode (deliberately not hand-edited
  into `project.pbxproj`, which can't be built or verified from this machine).

## [Unreleased] — Invoices for store sales (2026-07-20)

### Fixed (invoice correctness)
- **The order invoice's totals column did not add up to its own Grand Total.**
  `compute_bill` levies GST on the full subtotal and subtracts the discount at the
  end, but the PDF printed `Taxable Value = subtotal − discount` *and* listed
  Discount again as a separate deduction — so the column summed to `total − discount`.
  A ₹1,000 order with 5% GST and a ₹200 coupon printed rows totalling ₹650 against a
  Grand Total of ₹850. Taxable Value is now the actual taxable base and Discount is
  listed once; verified from the rendered PDF: 1,000 + 25 + 25 − 200 = 850.
- **The printed GST rate was derived from the wrong base**, so the same order showed
  `CGST @ 3.13%` for a 2.5% half-rate. Now `CGST @ 2.5%`. The POS invoice had a
  milder form of the same bug (its bill-level discount is applied after tax).
- **A fabricated GSTIN was printed on documents headed "TAX INVOICE".** Any store
  without a GSTIN got the hardcoded `36ABCDE1234F1Z5`. Seller identity now resolves
  store → `PlatformConfig` → nothing; with no GSTIN the line is omitted, the document
  is titled "INVOICE", and tax is shown as a single line rather than a CGST/SGST split
  presented as recoverable.
- **Every product without an HSN was invoiced as `2106` (instant food)** — which is
  most store-created private products, since HSN is optional in the store panel's
  add-product form. Blank now prints as "—".

### Added
- **`GET /api/v1/store/orders/<code>/invoice`** — store staff can pull an online
  order's invoice (`orders.view`, scoped `store=self.store`, `?inline=1` to render in
  browser). Previously only the customer and a super-admin could; the store selling
  the goods could not.
- **Download invoice** button in the store panel's order detail sheet, plus
  `lib/pdf.ts` — one shared blob-download helper now used by POS sales and orders
  instead of a third copy of the same fetch/objectURL dance.

### Tests
- Backend **612** green (14 new: seller resolution, tax-invoice eligibility, totals
  reconciliation, rate base, PDF builds for a store-private product with neither HSN
  nor GSTIN; store-scoped endpoint incl. cross-store 404, permission and anonymous
  rejection). `store-admin` typecheck + production build clean.

### Known gap
- Invoice numbering is still `order.code` / `INV{10000+pk}` — not a per-supplier,
  per-financial-year consecutive GST series. A store issuing invoices for its own
  products needs its own series; assigning it belongs at order confirmation, not at
  PDF render (a GET must not mutate).

## [Unreleased] — Store-private category browsing + share links (2026-07-20)

### Fixed
- **Share links used the sequential product id on every card.** `ProductSerializer`
  emitted `share_token`, but `ProductListSerializer` (grids, rails, search) did not,
  so the app's share sheet silently fell back to `/products/<id>` — the enumerable
  id a store-private product must never leak. Added `share_token` to the list
  payload; all share surfaces now emit the unguessable token.
- **Category images were missing on three surfaces.** The home rail never passed
  `imageUrl` to `VSCategoryCard`; the sub-category banner passed a numeric
  `departmentId` where an icon *token* was expected (so every banner drew the same
  generic icon); search suggestion chips ignored both image and icon. All three now
  render the category image with the data-driven icon as fallback, and an empty
  `imageUrl` degrades to the icon instead of a broken image.

### Added
- **Store-private category tree** (`GET /api/v1/store-categories?parent=<id>`) — one
  level at a time, listing only categories that hold the serving store's OWN
  products (`Product.origin_store`), each with a subtree `productCount` and a
  `hasChildren` flag. Strictly scoped: no serving store → empty, never a fallback to
  the company-wide catalog.
- **`GET /api/v1/products?scope=private`** — the tree's leaf grid; the serving
  store's own products only, bypassing the global-catalog fallback.
- **Category image fallback** — a category with no artwork of its own borrows a photo
  from a product inside it, so store-created categories render real images without
  staff curating any.
- **Recursive Categories tab** (`CategoriesScreen`) — one two-pane layout reused at
  every depth: left rail = the categories at this level, right pane = the selected
  entry's children, or its products once it's a leaf. Tapping a child pushes the next
  level (rail becomes its siblings); Back walks the stack up before leaving the tab.

### Tests
- Backend **574** tests green (14 new in `catalog/test_store_tree.py`: tree shape,
  drill-down, subtree counts, cross-store isolation, company-wide exclusion, hidden
  products, image fallback, `scope=private`, share-token in list + search payloads).
- Flutter **75** tests green; `flutter analyze` clean.

## [Unreleased] — Stabilization & hardening (2026-06-27 → 28)

### Fixed (commerce correctness — P0/P1)
- **Orders:** duplicate-order race — added partial `UniqueConstraint(user, idempotency_key)` (`uniq_order_idempotency`) + app-side synchronous `placing`+key guard. A double-tap Pay now yields exactly one order.
- **Payments:** duplicate payment-record race — `uniq_payment_idempotency` constraint + `start_payment` returns the winner on conflict. `finalize_payment` confirmed idempotent (row-lock + status guard) → duplicate webhooks/callbacks settle once.
- **Coupons:** the engine was **unenforced** — expiry, `usage_limit`, `per_user_limit` were ignored and redemptions never recorded. Added expiry check + race-safe `redeem_coupon` (row-locked count + records `CouponRedemption`), wired into checkout.
- **VS Credit:** credit-limit check moved **inside** the account row lock (`_post(enforce_limit=True)`) — concurrent purchases can no longer exceed the limit (available never negative).
- **Cancel:** `cancel_order` made `@transaction.atomic` + row-locked — no partial unwind, no double release/refund on concurrent cancel.
- **Returns:** `set_return_status` could re-run a refund on an already-refunded return (double credit reversal + double restock) — now atomic + locked + terminal-state guard.
- **App↔backend drift:** order Cancel button was shown on `packed` orders the backend rejects — added `OrderStatus.isCancellable` (pending|confirmed), single source of truth.

### Added
- **KYC gov-source verification** — swappable provider adapter (Signzy primary, Setu + Cashfree + mock), PAN/Aadhaar-OTP/DigiLocker/bank, DPDP consent capture, salted-hash duplicate-fraud detection, customer endpoints + Flutter wiring. Mock-tested; live keys pending.
- **`reconcile_finance`** management command — audits credit/inventory/coupon/orphan invariants; `--fix` repairs caches.
- **`scripts/release_gate.sh`** — CI gate: django check + no-missing-migrations + backend tests + flutter analyze + flutter test.
- **Flutter test infrastructure** — reusable fakes (cart repo, Hive, checkout deps, catalog, API client) + widget-render harness; 56 tests across cart/checkout/home/search/product/orders/wishlist.

### Security
- **Upload sanitization** — KYC document uploads bypassed image validation (raw `ImageField.save`). Added `mediastore.pipeline.validate_image_upload` (size cap + real-image-of-allowed-format, reused from `store_image`) and applied it in `KycSubmitView` → non-images / oversized files rejected (`UNSUPPORTED_MEDIA_TYPE` / `FILE_TOO_LARGE`) before persistence.
- **IDOR audit** of the customer API — confirmed object-ownership scoping (`user=request.user`) across orders/payments/notifications/returns/KYC + `PrivateMediaView` owner gate. Added regression tests proving cross-user order access is rejected (404) and anonymous is rejected (401/403).

### Tests
- Backend: **312** Django tests (was ~262). Flutter: **56** tests. Both suites green; `flutter analyze` clean.

### Ops
- Backend redeployed to production VPS (`thevsmart.com`) with DB backup + `.env`-safe sync; all migrations applied (`DEBUG=False`, prod settings); all endpoints HTTP 200.

### Docs
- Added `PROJECT_STATUS.md`, `docs/QA_TRACKER.md`, `docs/ASSUMPTIONS.md`, `.claude/skills/vs-mart-engineering/`.
