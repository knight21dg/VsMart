# VS Mart — QA Sweep Report

Work done against the QA document's findings, plus defects found while tracing
their root causes. Everything below is verified by the checks in
[Verification](#verification); nothing is listed as fixed on inspection alone.

**Test totals after the sweep:** backend 1343 passing (was 1257 — 86 added),
customer app 171 passing, agent app + customer app `flutter analyze` clean, both
Next.js consoles typecheck and `next build` clean.

---

## 1. Critical bugs fixed

### 1.1 Every delete in both web consoles reported "Empty response from server"

**Module:** Admin console + Store panel — shared API client
**Problem:** Delete a store / zone / category / coupon → the row stayed on
screen, an error toast said *"Empty response from server."*, and the record was
only gone after a manual browser refresh.
**Root cause:** A successful `DELETE` returns `204 No Content`. Per the fetch
spec a 204 is a **null-body status**, so `res.json()` rejects on it regardless
of what the server sent. `rawRequest` caught that rejection, collapsed the
envelope to `null`, and then threw on a request that had *succeeded*. Because
the promise rejected, React Query's `onSuccess` never ran — no toast, no
`invalidateQueries`, the confirm dialog stayed open, and the list kept its stale
row until a reload refetched it. One line, reached by every mutation in both
consoles.
**Fix:** New `readBody()` reads the body without ever throwing: it skips
204/205/304 outright, treats an empty body as "no body", and falls back to the
raw text for non-JSON error pages. A 2xx with no body now synthesises
`{success:true, data:undefined}` — a success. Added a status→plain-English
message table (401/403/404/409/422/429/5xx) so a Caddy 502 or an HTML error page
no longer surfaces as `Request failed (502)`, and wrapped `fetch` so a transport
failure becomes a typed `network_error` instead of a raw `TypeError: Failed to
fetch`.
**Files changed:** `apps/admin/lib/api/client.ts`,
`apps/store-admin/lib/api/client.ts`
**API changed:** no · **Database changed:** no
**Test performed:** `apps/backend/zones/tests.py::ZoneStoreDeletionContractTests`
pins the server contract both clients now consume; `npx tsc --noEmit` +
`next build` on both apps.
**Result:** Fixed. This single change repairs *every* delete button in both
consoles — the reported store, zone and category cases and the coupon/offer/
product/inventory ones that share the path.

> Both Flutter clients were checked for the same defect and are **not**
> affected: Dio returns `null` data for a 204, and `net_errors.dart` already
> classifies 5xx/offline/timeout properly.

### 1.2 `ProtectedError` / `IntegrityError` surfaced as HTTP 500

**Module:** Backend — global exception handler
**Problem:** Deleting a record something else depends on told the operator *"We
hit a temporary problem on our end"*.
**Root cause:** Both are Django exceptions, not DRF ones, so they fell straight
past `api_exception_handler` into the unhandled-500 branch.
**Fix:** Mapped to new catalog codes `RECORD_IN_USE` (409, message names the
blockers: *"…because 3 orders, 1 product still depend on it"*) and
`DUPLICATE_RECORD` (409). A non-unique `IntegrityError` stays a 500 — that is a
genuine bug and must not be dressed up as user error.
**Files changed:** `core/exceptions.py`, `core/response_codes.py`
**Test performed:** `core/tests.py::DatabaseIntegrityErrorTests` (6 tests,
including that the raw exception text never leaks to the client).

### 1.3 `CheckoutError` surfaced as HTTP 500 outside the checkout views

**Module:** Backend — order lifecycle
**Problem:** An invalid store-panel status change returned 500 instead of the
reason.
**Root cause:** `CheckoutError` was a plain `Exception` that each view had to
catch and re-raise as an `AppError`. Views that didn't (the store order-status
endpoint) turned *"An order that is delivered cannot become rejected."* into a
generic server error.
**Fix:** `CheckoutError` now **subclasses `AppError`**, so the handler renders
it correctly wherever it is raised. The `(message, code)` signature and all
existing `except CheckoutError` blocks are unchanged.
**Files changed:** `orders/services.py`
**Test performed:** `orders/test_reject.py::…::test_rejecting_an_already_
delivered_order_explains_why` asserts 409 + `ORDER_STATUS_INVALID` + the reason.

---

## 2. CRUD bugs fixed

### 2.1 A "Delete" that silently deactivated

**Problem:** Stores, zones and coupons with trading history are *deactivated*,
not deleted — correct, but the bare 204 could not say so. The operator saw
"deleted" and the row still in the list.
**Fix:** Those three now return **200 + a coded message** naming the real
outcome (`RECORD_DELETED` / `RECORD_DEACTIVATED`) — e.g. *"Busy Store has
orders, products or staff on record, so it was deactivated instead of deleted."*
Simple unambiguous deletes keep their 204 (the client handles both).
**Files changed:** `zones/views.py`, `offers/admin_views.py`,
`core/response_codes.py`
**Test performed:** `zones/tests.py::ZoneStoreDeletionContractTests`,
`offers/tests.py::AdminCouponDeleteContractTests`.

### 2.2 Deleting a zone silently rewrote historical reporting

**Problem:** `Order.zone` is `SET_NULL`, so row-deleting a traded zone stripped
the zone off every historical order — per-zone revenue and delivery-time
reports quietly lost those rows with no hint in the UI.
**Fix:** A zone that has served orders is deactivated (serviceability only
resolves `is_active` zones) and the response says so. A never-used zone is still
really deleted. `ZoneEvent.zone` is `SET_NULL`, so the deletion event now
carries the name/code in its payload or the audit trail would be blank.

### 2.3 Duplicate zones and store codes

**Problem:** Re-submitting the zone form created a second "Kakinada". Nothing
constrained `Zone.name`, so serviceability then resolved a point to whichever
duplicate won on priority — a coin toss between two different stores.
**Fix:** Case/whitespace-insensitive name check → *"Kakinada zone already
exists. Edit that zone instead of creating a second one with the same name."*
Also: a blank `code` now normalises to `NULL` (it is `unique=True, null=True`, so
the *second* blank string collided on the index), and a duplicate store code now
names the store that owns it.
**Files changed:** `zones/serializers.py`

> **Category delete** was already correctly guarded (clear message when products
> or sub-categories remain). Its reported failure was §1.1 — the delete
> succeeded and the client mis-reported it.

---

## 3. State synchronisation bugs fixed

- **§1.1 was the cause of the "only works after refresh" symptom** across all
  modules — `onSuccess` never fired, so `invalidateQueries` never ran.
- Swept all **96** `useApiMutation` call sites in both consoles: 10 lacked
  `invalidate`, 9 correctly (lookups, notification sends, dialogs with explicit
  `onDone` refetches). One was a real bug:
- **Store panel clock-in showed the wrong state.** The topbar held
  `useState(false)` and flipped it on each click, so it showed "Clock in" to
  someone on shift since 08:00 and any navigation reset it. Added
  `GET /store/staff/attendance/me` (no `employees.view` needed — everyone may
  read their own attendance) with a server-derived `clockedIn`; both read and
  write return the same shape, and the button is disabled until it loads so the
  first click can't fire the wrong action.
  **Test:** `storeops/tests.py::…::test_my_attendance_reports_server_truth`, `…::
  test_my_attendance_needs_no_employees_view_permission`.
- Only one `location.reload()` exists in either console, in the service-worker
  update flow, which is its correct use.

---

## 4. Money / commerce fixes

### 4.1 Minimum order value was never enforced — ₹300 orders passed a ₹1,000 zone

**Root cause:** The figure was configured per zone, resolved by
`effective_fees`, and returned on every bill — and **nothing ever compared it to
the cart**. The app parsed `minOrder` into `CartSummary` and never read it.
**Fix, server-side (authoritative):** `place_order` raises
`MIN_ORDER_NOT_MET` with the shortfall spelled out. Measured against the **item
subtotal**, not the total — fees and GST are not goods, so counting them would
clear a ₹1,000 minimum with a ₹900 basket.
**Fix, app-side:** `CartSummary.minOrderShortfall` / `.meetsMinimumOrder`; the
cart shows *"Minimum order is ₹1,000 — add ₹700 more"* and disables the CTA;
checkout gates Place Order the same way (the shopper can remove a line after
arriving there). Neither blocks on the offline estimate, which carries no
minimum.
**Files changed:** `orders/services.py`, `cart_providers.dart`,
`cart_screen.dart`, `checkout_screen.dart`
**Test:** `orders/tests.py::MinimumOrderEnforcementTests` (5),
`cart_logic_test.dart` "minimum order value" (6).

### 4.2 Rejecting an order kept the customer's money

**Root cause:** The rejection path released stock and nothing else. A prepaid
order the store rejected stayed `payment_status: paid` and burned the
customer's single-use coupon — while `cancel_order`, the same unwind under a
different word, refunded and released both.
**Fix:** `advance_status(…, REJECTED)` now also releases the coupon and issues
the refund (last, like the cancel path, so nothing can roll back a refund the
gateway has executed).
**Test:** `orders/test_reject.py::RejectUnwindTests` (5).

### 4.3 GST: two conflicting conventions that crossed at order lines

**Root cause:** `PlatformConfig.gst_rate` is a **fraction** (0.18) — correct for
`compute_bill` and the POS tax split. `OrderItem.gst_rate` is documented as a
**percentage**. `place_order` copied the fraction straight into the percentage
column, so every line without an explicit product rate recorded **0.18 %** tax
instead of 18 %. The admin form was labelled *"GST rate (0–1)"*, so operators
entered fractions on products too, and any decimal (1.8, 180) was accepted.
**Fix — one rule, one place (`core/pricing.py`):** *the API and storage speak
percentages; only the pricing maths uses fractions.*
- `Product.gst_rate` is now a percentage, with a data migration converting
  legacy fractions (`0 < v < 1`) — safe to re-run, since no real slab sits in
  that range.
- Product and platform-settings APIs validate against the statutory slabs
  (0 / 0.25 / 3 / 5 / 12 / 18 / 28) and refuse anything else, with a hint:
  *"Enter 18 for 18%, not 0.18."*
- `/store/settings` and `/config` now report the percentage; the POS page
  divides by 100 for its own maths, and the store settings page no longer
  multiplied an already-percentage value by 100 (it displayed **1800 %**).
- The admin product form is a slab dropdown, not free text.
**Files changed:** `core/pricing.py`, `catalog/models.py`,
`catalog/migrations/0010_…`, `catalog/admin_views.py`, `siteconfig/serializers.py`,
`system/views.py`, `storeops/views.py`, `orders/services.py`, admin catalog +
settings pages, store POS + settings pages
**Test:** `catalog/tests.py::GstPercentageContractTests`, `…::GstUnitHelperTests`,
`…::OrderLineGstSnapshotTests`.

---

## 5. Order lifecycle

**Accepting worked; rejecting did not** — `"rejected"` was missing from both the
store panel's `NEXT_STATUS` list **and** the backend's `ALLOWED_STATUSES`, even
though `can_transition` had always permitted it from placed/pending/confirmed.
A store could accept an order but had no way at all to refuse one it couldn't
fulfil.

- Added to both. Cancel and reject now go through a **confirmation dialog** that
  states what will happen (stock released, coupon returned, money refunded) —
  a dropdown selection must not silently end a live order and trigger a refund.
- The agent's half of the machine stays closed to the store: a store still
  cannot post `delivered` (pinned by test).
- The state machine itself was already sound and is unchanged.

**Files changed:** `storeops/views.py`, `store-admin/lib/orders.ts`,
`store-admin/app/(console)/orders/[code]/page.tsx`
**Test:** `orders/test_reject.py::StoreRejectEndpointTests` (4).

---

## 6. Notification fixes

**Problem:** Repeated notifications, including for orders already accepted.
**Root cause:** No idempotency anywhere. Every `notify()` call created a row and
a push, so each retry re-alerted: the dispatch engine runs on a 120-second loop
and every assignment path funnels through `_notify_agent`, so an agent was
re-buzzed for a delivery already sitting in their list each time anything
touched the task.
**Fix:** `Notification.dedupe_key` identifies the **event**, not the attempt
(`delivery_assigned:task:412:agent:9`), with a partial unique constraint on
`(user, dedupe_key)`. `notify(dedupe_key=…)` becomes get-or-create and a repeat
sends **nothing** — no row, no push. Keys applied to delivery assignment, new
order (store staff), order placed, and order status. Deliberately opt-in:
re-sent OTPs and marketing blasts must still be able to arrive twice.
Reassignment to a *different* agent still notifies them (the key includes the
agent).
**Files changed:** `notifications/models.py` + migration `0003_…`,
`notifications/services.py`, `delivery/services.py`, `orders/services.py`
**Test:** `notifications/test_dedupe.py` (11), including that a repeat schedules
no second push and that a re-attempted delivery doesn't re-announce
"Out For Delivery".

---

## 7. Missing functionality implemented

### 7.1 Customer home content is now admin-managed

**Problem:** "Today Deals" and "Popular Products" could not be managed from
Admin/Store.
**Root cause:** The rails were hardcoded `/products?sort=…` calls **inside the
Flutter app** — `popular` = most-reviewed, `recommended` = best-rated. Purely
algorithmic, with no way for a merchandiser to push a new line or clear a slow
one.
**Fix:** New `catalog.HomeFeature` curation layer, **additive by design** — a
rail with no pins keeps its exact previous algorithmic ordering, so no existing
install changes until someone curates.
- `GET /home/sections` (the rail catalogue, so the client stops hardcoding it)
  and `GET /home/sections/<section>` — store-scoped, so curation can never
  surface a product the serving store doesn't carry, and a thinly-curated rail
  tops up from the algorithm rather than collapsing.
- Admin CRUD: pin / reorder (one atomic call, not N PATCHes) / unpin. Archived
  products are refused — the one failure mode curation has that an algorithm
  doesn't.
- New **Marketing → Home Screen** tab: four rail cards, search-and-pin, move
  up/down, remove, each stating its fallback ordering.
- The app's `getPopular` / `getRecommended` / `getFeatured` now call the new
  endpoint.
- Added a real `top_selling` ordering (units on **delivered** orders, so a
  cancelled order can't inflate a "top seller").
**Files:** `catalog/home.py`, `catalog/home_views.py`, `catalog/models.py` +
migration `0011_…`, `catalog/urls.py`,
`admin/components/marketing/home-screen-tab.tsx`,
`backend_catalog_data_source.dart`
**Test:** `catalog/test_home_sections.py` (16).

### 7.2 Password change (was unavailable anywhere)

**Root cause:** The only route to a new password was the signed-*out*
forgot-password flow, which texts an OTP to the account's registered phone —
useless for a routine rotation, impossible if the phone has changed hands.
**Fix:** `POST /auth/password/change` (authenticated), gated **by role** — not by
`has_usable_password()`, which Django reports as `True` for the blank passwords
customer/agent accounts are created with. Runs Django's password validators,
refuses reuse of the current password, validates the confirmation server-side
(the endpoint is reachable without the form and a typo would lock the operator
out), and audits the change. It deliberately does **not** end the session — a
voluntary rotation shouldn't eject someone mid-task.
Shared `ChangePasswordDialog` added to both consoles' user menus.
**Test:** `accounts/test_change_password.py` (11), including that the new
password actually signs in.

### 7.3 Agent KYC

**Root cause:** The agent app shipped with only the *reviewer* side (the queue of
**customer** applications). An agent whose own KYC was pending or rejected saw
one read-only word on their profile with no route to act on it.
**Fix:** No backend was needed — `/kyc/status` and `/kyc/submit` key on
`request.user` and never cared about role, and an agent's application already
reaches the admin queue (all now pinned by tests so it stays true). Built the
missing app surface: **Profile → My KYC** with per-document camera/gallery
capture (front lens for the selfie, rear for documents), one multipart submit
(the endpoint moves the whole application to `pending`, so per-file submits
would orphan the rest), status explanation with the rejection reason, and a
locked state while a reviewer has it.
**Files:** `agent_app/lib/features/kyc/data/my_kyc_data.dart`,
`…/presentation/my_kyc_screen.dart`, `profile_screen.dart`
**Test:** `kyc/tests.py::AgentSelfKycTests` (3).

### 7.4 Coupons in the store panel

The admin console **already had** full coupon CRUD (Marketing → Coupons — create,
edit, activate/deactivate, delete); its reported failure was §1.1 breaking the
delete. The store panel had an unused read-only endpoint and rendered nothing,
so staff couldn't answer *"does VSNEW100 still work?"* at the counter. Added the
live-codes list, explicitly labelled as centrally managed — coupons are
platform-wide, so a Create button there would only 403.

---

## 8. Other defects found and fixed

- **Delivery proof photo returned 500.** A `MediaAsset` row whose file is missing
  (half-restored backup, cleanup outrunning references) raised `FileNotFoundError`
  out of `serve_storage_key`. A store manager opening delivery proof was told the
  server was broken. Now a 404 *"That image is no longer available."*, logged
  server-side. This also exposed a **weak test** that asserted only `not in (403,
  404)` against an asset with no file — it had never proven proof photos are
  viewable at all. Rewritten to write a real file and assert the bytes come back.
- **Structured failure logging** (§30): request path, method, user id, role, code,
  status. Never the body, the Authorization header, or a token — the endpoints
  involved carry passwords and OTPs. 4xx logs at INFO, 5xx at ERROR with the
  traceback, so client errors don't bury real faults.
- **Fake-button sweep:** no empty `onClick`/`onPressed` handlers remain in either
  console or either app. The store sidebar's "soon" items are already correctly
  non-clickable with a label and tooltip. One no-op found and fixed: the VS
  Credit payment tile at checkout had an empty `onTap` giving it a tap ripple
  that led nowhere; `onTap` is now nullable and omitted when it is the only
  option.

---

## 9. Second pass — the three areas the first report left open

### 9.1 Neither OTP ever expired

**Module:** Delivery + Collections
**Problem:** The QA document lists "OTP expiry" and "Expired OTP" as required
behaviour. Neither existed.
**Root cause:** `generated_at` was written on every delivery **and** collection
OTP and **never read once**. A delivery re-attempted the next day still accepted
yesterday's code; a collection code authorising a specific cash amount stayed
live indefinitely; and a handover credential sat valid in a customer's inbox
forever.
**Fix:** `OTP_TTL_MINUTES` (15, settings-overridable) on both flows, checked
**before** the code comparison so an expired code neither verifies nor burns one
of the three attempts — a slow customer must not be able to lock the agent out.
A NULL `generated_at` counts as not-expired, so rows written before this can't
strand a live handover.
**Files:** `delivery/services.py`, `cashcollections/services.py`,
`core/response_codes.py` (`DELIVERY_OTP_EXPIRED`, `COLLECTION_OTP_EXPIRED`)
**Test:** `delivery/test_otp_expiry.py` (9), `cashcollections/tests.py::CollectionOtpExpiryTests` (5).

> The rest of the OTP flow audited **clean** and is unchanged: the code is minted
> at arrival (not at dispatch), 3 attempts then lockout, and `complete_delivery`
> genuinely refuses without `REACHED` + `otp_verified` + a proof photo.

### 9.2 A locked collection was a permanent dead end

**Problem:** Three wrong codes set `manual_verification_required` and locked the
OTP. `collect()` refuses without `otp_verified`, and — unlike delivery, which has
had `AdminManualVerifyView` since it was built — collections had **no override at
all**. An agent standing in front of a customer holding their cash had no way to
finish, and nothing anywhere could clear the flag.
**Fix:** `POST /admin/collections/<id>/manual-verify`, admin-only and audited as
a security event (it bypasses the customer's own confirmation of the amount). It
also unlocks the OTP row, or a later `request-otp` would start locked and
re-lock on the first mistyped code.
**Also fixed:** `manual_verification_required` was never cleared on a *later*
successful verify, in **either** flow — re-requesting an OTP unlocks the row but
left the task/collection permanently flagged in the board and every report.
**UI:** the admin Collections list now carries `manualVerificationRequired` and
shows a **Release lock** action on exactly the stuck rows — without it on the
list the override would be unreachable and nothing on any screen would say why
the agent was blocked.
**Test:** `cashcollections/tests.py::CollectionManualVerifyTests` (5), plus
lockout-recovery tests in both suites.

### 9.3 A hand-over could under-declare and hide the difference

**Module:** Cash book
**Problem:** `create_deposit` took the declared amount from the client and never
compared it to the collections it claimed. Claiming a collection is what removes
its cash from `cash_in_hand`, so an agent could attach ₹5,000 of collections
while declaring ₹500: all five left the exposure figure, the deposit booked ₹500,
and finance counting ₹500 marked it **VERIFIED** (counted >= declared). The
missing ₹4,500 was invisible at every step — exactly the "collected and banked
drift apart with no way to see it" the deposit record exists to prevent.
**Root cause:** The *online* hand-over path derives the amount from the rows and
says so in its own comment ("never from a client-supplied figure"). The physical
path trusted the client.
**Fix:** When collections are attached, the declared amount must equal their
total; the error names both figures. A deposit with no collections attached (a
loose top-up) keeps a free amount — there is nothing to reconcile against.
**Test:** `payments/test_cashbook.py::DeclaredAmountMustMatchCollectionsTests` (4).

> The rest of the cash chain audited **clean**: exclusive collection claiming
> under `select_for_update`, declared-vs-counted shortfall as its own status,
> rejection releasing collections back to "in hand", GL posting, and agent
> notifications on both outcomes.

### 9.4 Returns: the reviewer couldn't see the evidence, and the customer was never told

**Problem (evidence):** A return cannot be submitted without photos
(`RETURN_PHOTOS_REQUIRED`) — and `return_detail`, the payload **both** the admin
console and the store panel read, carried none. A reviewer approved or declined
without ever seeing the photos the customer was forced to upload.
`ReturnPhotoView` had always served them, permission-gated; nothing handed out
the URLs.
**Problem (notifications):** `set_return_status` transitioned the return
silently. Approved, declined and refunded were equally unannounced, so the
customer's only way to learn the outcome was to reopen the app and look. The
*pickup* phase notified properly all along (partner assigned, rescheduled,
settled at the door) — the **review decision**, the one the customer is waiting
on, did not. Store staff were likewise only notified when a pickup **failed** to
auto-assign; a return that assigned cleanly reached the store in silence.
**Fix:**
- `return_detail` now carries `evidence` (customer proof vs agent-at-the-door
  proof, labelled separately — they answer different questions) and the
  `accepted`/`settled` quantities the refund is actually computed on.
- Customer notified on approved / declined / refunded, with the reviewer's
  reason on a decline and the amount on a refund. Keyed with the §6 dedupe
  mechanism so a re-saved review can't buzz them twice. Fail-soft — a
  notification must never undo a refund that has already been processed.
- Store staff notified when a return is *raised*, once per return.
- **The admin console had no return detail view at all** — Approve/Reject were
  clickable straight from a table row showing only a reason word and an item
  count. Added a review dialog with the note, items, settled quantities and the
  photo gallery. The store panel's sheet gains the same gallery.
**Files:** `returns/admin_service.py`, `returns/pickup_services.py`,
`admin/components/return-detail-dialog.tsx`,
`admin/app/(console)/orders/returns/page.tsx`,
`store-admin/app/(console)/returns/page.tsx`
**Test:** `returns/test_review_visibility.py` (11), including that the emitted
URL actually serves bytes to a reviewer and still 403s for an unrelated customer.

---

## 10. Pre-deployment hardening pass

A separate audit gate. Full results in **`DEPLOYMENT_READINESS.md`**; the
defects it found and fixed are below. Backend 1343 → **1392** tests.

### 10.1 Historical order lines still carried the GST bug

`catalog.0010` fixed the *source* of the fraction-vs-percentage bug but not the
**24 existing `OrderItem` rows** it had already produced — real data in the dev
database recorded `0.18` where 18 % was charged. Added
`orders.0012_orderitem_gst_rate_as_percentage`, deliberately as a **separate**
migration so it can be skipped by anyone who would rather leave history
byte-identical. Same idempotent `0 < v < 1` guard; the money (`Order.gst`,
`Order.total`) is not touched, only the rate label.
Also added `scripts/verify_gst_migration.py` — read-only, safe on production,
run before and after and diff.
**Test:** `catalog/test_gst_migration.py` (16), covering no-double-conversion,
NULL/zero preservation, reversibility, row counts, untouched columns, and that
every migrated value lands on a legal slab.

### 10.2 A foreground push refreshed nothing

`onMessage` only drew a local banner. "Order Out For Delivery" appeared while
the order screen underneath still read "Confirmed", and stayed wrong until a
pull-to-refresh or a navigation — the tracking screen's own 12s poll masked it
there and nowhere else. Now a foreground push invalidates exactly the order it
concerns (plus the inbox badge), reading both `orderCode` and `order_code`;
reading only one spelling would have silently disabled the refresh for half the
pushes. No polling added.
**Files:** `user_app/lib/core/services/push_controller.dart`
**Test:** `user_app/test/core/push_invalidation_test.dart` (7).

### 10.3 Expired and invalid OTPs looked identical to the agent

The backend already distinguished them; the app did not. Both surfaced as the
same red toast, so a rider treated a stale code — costing no attempt and fixable
in one tap — as if they were being locked out. Delivery now shows a persistent
panel with a **"Send a new code"** action (re-confirms arrival, minting a fresh
code); collections shows the same panel pointing at its existing resend. A wrong
code keeps the attempts-left toast, and the lockout rules are unchanged.
**Test:** `delivery/test_otp_expiry.py::ExpiredVersusInvalidTests` (7),
asserting different codes, different messages, that expiry does **not** consume
an attempt, that three *wrong* codes still lock, and full recovery end to end.

### 10.4 The last unguarded `res.json()`

`doRefresh()` in both web clients still parsed directly. A refresh that came
back empty or non-JSON (a proxy 200, an HTML error page) threw inside its own
try and was reported as "refresh failed" — signing the operator out mid-task.
Now routed through `readBody` like every other response.

### 10.5 Authorization audit — no holes found

26 cross-tenant/IDOR tests added (`core/test_cross_tenant.py`), all passing:
agent-vs-agent tasks and cash, customer-vs-customer returns and ledgers, agent
self-verifying their own deposit, store-vs-store cash/returns/private products,
and 13 admin + 4 store surfaces called directly by a customer. **No
authorization defect was found** — the finding is the clean result itself.

Two of those tests initially passed for the wrong reason: an invalid
`reasonCode` produced a 400 *before* ownership was consulted, and that 400 would
have read as a denial. Fixed to send valid payloads so the request actually
reaches the authorization check — the same weak-assertion trap that hid the
proof-photo bug earlier.

---

## Verification

| Check | Result |
|---|---|
| `python manage.py check` | no issues |
| `python manage.py makemigrations --check` | no changes detected |
| `python manage.py test` | **1392 passed**, 4 skipped (was 1257) |
| `flutter analyze` (user_app) | No issues found |
| `flutter test` (user_app) | **171 passed** |
| `flutter analyze` (agent_app) | No issues found |
| `npx tsc --noEmit` (admin, store-admin) | clean |
| `npx next build` (admin, store-admin) | clean |

**Migrations added (4, all forward/backward safe):**
`catalog/0010_product_gst_rate_as_percentage`,
`catalog/0011_homefeature_and_more`,
`notifications/0003_notification_dedupe_key_and_more`,
`orders/0012_orderitem_gst_rate_as_percentage`.
Applied and verified against the dev database — see `DEPLOYMENT_READINESS.md`
for the production plan, the before/after diff and the rollback.

---

## Remaining known issues

Named honestly — these were **not** completed:

1. **No device testing.** Everything is verified by automated tests, analyzers
   and builds. The two Flutter apps have not been run on a handset, and the
   consoles have not been click-tested in a browser. The APKs also need
   rebuilding before the app-side fixes (minimum order, home rails, agent KYC)
   reach a device.
2. **Deployment.** Nothing has been deployed. The three migrations must run and
   both Next.js apps must be redeployed. `catalog/0010` rewrites
   `Product.gst_rate` values — take a database snapshot first.
3. **Customer-app state matrix** (§21: fresh install, token expiry, app killed/
   resumed, poor network) was not exercised — that needs a device.
4. **RBAC sweep** (§28) was verified only where I touched code (home curation is
   admin-only, store attendance needs no extra permission, store status
   transitions stay bounded, collection manual-verify is admin-only). A full
   role-by-role permission audit was not done.
5. **The agent app's OTP screens were not re-skinned** for the new expiry
   behaviour. The change is backward compatible — an expired code returns a new
   coded error rather than breaking the contract — but the agent sees the
   generic failure path rather than a tailored "confirm your arrival again to
   send a fresh code" prompt. Same for the collections screen.
6. `commonComingSoon` is an unused ARB string in the customer app — dead
   translation data, not a fake button. Harmless; left in place.
