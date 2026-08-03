# 10 · API Contract (Flutter-authoritative)

This document is the **exact** backend contract extracted from the VS Mart Flutter
app (`apps/user_app/lib`). The Flutter code is authoritative: every JSON key,
HTTP method, and shape below is taken verbatim from the app's `ApiConstants`,
remote data sources, and `*_model.dart` (de)serializers. **No renames** —
the Django serializers must emit/accept these exact keys (note the mixed
casing called out below).

> Scope note: only the **auth** module currently makes live calls to the VS Mart
> backend (`auth_remote_datasource.dart`). Catalog/offers run against DummyJSON,
> and cart/orders/credit/billing/verification use local fixtures + Hive. The
> `ApiConstants` paths and the `*_model.dart` JSON shapes are therefore the
> authoritative intent for the endpoints not yet wired — they define what the
> backend must return when each data source is swapped to Dio.

---

## Conventions

- **Base URL:** `/api/v1` (from `AppConfig` — e.g. `https://api.vsmart.app/api/v1`).
- **Content type:** `application/json`. `validateStatus` accepts anything `< 500`.
- **Response envelope** — the app unwraps a top-level `data` key
  (`_data()` in the datasources; `ApiResponse.fromJson`):
  ```json
  { "success": true, "message": null, "data": { ... }, "meta": { ... } }
  ```
  - Single object: `data` is an object.
  - List: `data` is an array + a `meta` pagination block.
  - The app reads `data`; `success` defaults to `true` and `message` is optional.
- **Pagination meta** (`PageMeta.fromJson`) — the app accepts snake_case **or**
  camelCase (snake_case preferred). Keys and defaults:
  | key (preferred) | alt | default | type |
  |---|---|---|---|
  | `current_page` | `currentPage` | 1 | int |
  | `last_page` | `lastPage` | 1 | int |
  | `per_page` | `perPage` | 20 | int |
  | `total` | `total` | 0 | int |
- **List request params** (`PageRequest.toQuery`): `page` (int, default 1),
  `per_page` (int, default 20), `q` (string, optional).
- **Auth header:** `Authorization: Bearer <access_token>`, attached by
  `AuthInterceptor` to every request **except** those built with
  `ApiClient.noAuth()` (sends header flag `x-skip-auth`). On any `401` the app
  clears tokens and triggers re-login.
- **Public (noAuth) endpoints:** `POST /auth/otp/send`, `POST /auth/otp/verify`.
  All other endpoints send the bearer token (catalog reads are intended public on
  the backend even though the client sends the header when a token exists).

> ⚠️ **Casing inconsistency (must honor exactly).** The **auth** models use
> **snake_case** JSON keys (`access_token`, `refresh_token`, `expires_at`,
> `avatar_url`, `kyc_status`, `credit_enabled`, `created_at`, `is_new_user`,
> `verification_id`). All **other** models (Product, Category, Offer, Address,
> CartItem, Order, etc.) use **camelCase** keys (`imageUrl`, `creditPrice`,
> `inStock`, `productId`, `isDefault`, …). Serializers must match per-module.

---

## Auth — `/auth`, `/users`

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| POST | `/auth/otp/send` | public | `{ phone }` | `{ verification_id }` |
| POST | `/auth/otp/verify` | public | `{ phone, otp, verification_id? }` | AuthToken fields (`access_token`, `refresh_token?`, `expires_at?`) **+** `is_new_user: bool` |
| POST | `/auth/register` | bearer | `{ name, email? }` | User object |
| POST | `/auth/refresh` | (bearer*) | `{ refresh_token }` (see note) | AuthToken |
| POST | `/auth/logout` | bearer | _empty_ | — (ignored) |
| GET | `/users/me` | bearer | — | User object |
| PATCH | `/users/me` | bearer | partial User map, e.g. `{ name?, email?, avatar_url? }` | User object |

Notes:
- `sendOtp` reads `data.verification_id` (string).
- `verifyOtp` parses the **whole** `data` block as the AuthToken (so the token
  fields sit at the top level of `data`, alongside `is_new_user`).
- `/auth/refresh` and `/auth/logout` paths exist in `ApiConstants`; the live
  refresh call is wired through the auth layer (`onUnauthorized`) — body uses the
  AuthToken key names (`refresh_token`).
- KYC status drives routing; see User model `kyc_status` accepted values below.

---

## KYC — `/kyc`

Paths from `ApiConstants` (`kycSubmit`, `kycStatus`); data source is a fixture
returning a `VerificationApplication`. The submitted payload is the
`VerificationDraft`.

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| POST | `/kyc/submit` | bearer | VerificationDraft (multipart for the doc/image paths) | VerificationApplication |
| GET | `/kyc/status` | bearer | — | VerificationApplication |

VerificationDraft request fields (camelCase, from `VerificationDraftModel.toJson`):
`aadhaarNumber`, `panNumber`, `aadhaarFrontPath`, `aadhaarBackPath`, `panPath`,
`selfiePath`, `occupation`, `monthlyIncome`, `familyMembers`, `houseType`
(`independent|apartment|shared`), `ownership` (`owned|rented|family`),
`requestedLimit`, `status`.

VerificationApplication response fields (entity shape — no model yet, names are
the entity fields): `applicationId`, `status`
(`notStarted|draft|pending|underReview|approved|rejected`), `submittedAt`,
`expectedReviewDays` (int, default 2), `approvedLimit?`, `rejectionReason?`.

---

## Addresses — `/addresses`

`AddressModel` JSON (camelCase). CRUD over the collection + by id.

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| GET | `/addresses` | bearer | — | `[Address]` |
| POST | `/addresses` | bearer | Address (no `id`) | Address |
| GET | `/addresses/{id}` | bearer | — | Address |
| PATCH/PUT | `/addresses/{id}` | bearer | partial Address | Address |
| DELETE | `/addresses/{id}` | bearer | — | — |

---

## Catalog — `/categories`, `/products`

Public reads. The live client maps DummyJSON today, but the intended VS Mart
shapes are `CategoryModel` / `ProductModel` (camelCase).

| Method | Path | Auth | Query | Response (`data`) |
|---|---|---|---|---|
| GET | `/categories` | public | — | `[Category]` (departments / top-level) |
| GET | `/categories/{categoryId}/sub-categories` | public | — | `[Category]` (children; empty ⇒ UI browses all products) |
| GET | `/products` | public | `category`, `sort`, `brand`, `q`, `page`, `per_page`, `min_price`, `max_price`, `inStockOnly` | `[Product]` + `meta` |
| GET | `/products/{id}` | public | — | Product (with images, variants, specifications) |
| GET | `/products/search` | public | `q` (required), `page`, `per_page` | `[Product]` + `meta` |

Filters available (`ProductFilter`): `minPrice`, `maxPrice`, `inStockOnly`,
`brands[]`, `categories[]`, `subCategories[]`, `minimumDiscount`.
Sort values (`ProductSort`): `popularity`, `newest`, `priceLowToHigh`,
`priceHighToLow`, `discount`.

---

## Offers — `/offers`

`OfferModel` (camelCase). Banners / deals / coupons distinguished by `type`.

| Method | Path | Auth | Query | Response (`data`) |
|---|---|---|---|---|
| GET | `/offers` | public | `type` = `banner` \| `deal` \| `coupon` (optional) | `[Offer]` |

---

## Wishlist — `/wishlist`

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| GET | `/wishlist` | bearer | — | `[Product]` |
| POST | `/wishlist/{productId}` | bearer | — | — (toggle on) |
| DELETE | `/wishlist/{productId}` | bearer | — | — (toggle off) |

---

## Cart — `/cart`

`CartItemModel` (camelCase). Server is intended source of truth for the bill.

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| GET | `/cart` | bearer | — | `{ items: [CartItem], …totals }` |
| POST | `/cart/items` | bearer | `{ productId, quantity, … }` (upsert) | Cart / CartItem |
| PATCH | `/cart/items/{id}` | bearer | `{ quantity }` (0 ⇒ remove) | Cart / CartItem |
| DELETE | `/cart/items/{id}` | bearer | — | — |

CartItem fields: `productId`, `name`, `brand`, `unit`, `price`, `mrp`,
`quantity`, `imageUrl?`.

---

## Checkout & Orders — `/checkout`, `/orders`

`OrderModel` + nested parts (camelCase). The fixture seeds orders; the
checkout body assembles address + payment + summary + items.

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| POST | `/checkout` | bearer | `{ address_id/address, payment_method, …coupon? }` | Order |
| GET | `/orders` | bearer | `status` (filter), `page`, `per_page` | `[Order]` + `meta` |
| GET | `/orders/{id}` | bearer | — | Order (items, timeline, payment, summary) |
| GET | `/orders/{id}/tracking` | bearer | — | OrderTracking |

Order status filter values (`OrderStatus`): `pending`, `confirmed`, `packed`,
`outForDelivery`, `delivered`, `cancelled`, `returned`.

---

## Credit — `/credit`

Fixtures today; shapes from `CreditAccount` / `CreditPaymentResult` /
`CreditTransaction` entities. Note these are entity field names (no JSON model
yet) — the backend should emit these keys.

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| GET | `/credit/dashboard` | bearer | — | CreditAccount |
| GET | `/credit/score` | bearer | — | score + factors (`vsScore`) |
| GET | `/credit/bills/weekly` | bearer | — | current weekly bill / Statement |
| GET | `/credit/bills/monthly` | bearer | — | current monthly bill / Statement |

CreditAccount fields: `creditLimit`, `outstanding`, `vsScore` (int),
`billingCycle` (`weekly|monthly`), `dueDate?`, `purchasesThisMonth`,
`paymentsThisMonth` (`available` = limit − outstanding is computed client-side).

---

## Payments — `/payments`

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| POST | `/payments` | bearer | `{ amount, method, … }` | CreditPaymentResult / payment |
| GET | `/payments/history` | bearer | `page`, `per_page` | `[Repayment]` + `meta` |

CreditPaymentResult fields: `transactionId`, `amountPaid`, `method`, `account`
(CreditAccount), `scorePointsEarned` (int).

---

## Notifications — `/notifications`

UI-only feature (no Dio data source / model yet). Shape from the
`AppNotification` entity.

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| GET | `/notifications` | bearer | `page`, `per_page` | `[Notification]` + `meta` |
| POST | `/notifications/{id}/read` | bearer | — | — |
| POST | `/notifications/device-token` | bearer | `{ token, platform }` | — |

Notification fields: `id`, `title`, `body`, `type`
(`order|delivery|credit|payment|offer|account`), `time`, `read` (bool),
`important` (bool), `actionLabel?`, `route?`.

---

## Support — `/support`

UI-only feature (no model yet). Ticket shape inferred from the support screens.

| Method | Path | Auth | Request | Response (`data`) |
|---|---|---|---|---|
| GET | `/support/tickets` | bearer | `status` (filter), `page` | `[SupportTicket]` + `meta` |
| POST | `/support/tickets` | bearer | `{ subject, category, … }` | SupportTicket |
| GET | `/support/faqs` | public | — | `[Faq]` |

SupportTicket fields (from UI): `id`, `subject`, `category`, `status`
(`open|inProgress|resolved|closed`), `updated`, `highPriority` (bool).

---

# Appendix · Data models (exact JSON fields)

Field names are taken verbatim from the Dart `fromJson`/`toJson`. **Auth models
are snake_case; all others are camelCase.** `num` = numeric (int or decimal).

### User  (`user_model.dart`, snake_case)
| field | type | notes |
|---|---|---|
| `id` | string | required |
| `phone` | string | default `""` |
| `name` | string | default `""` |
| `email` | string? | |
| `avatar_url` | string? | |
| `kyc_status` | string? | accepted: `verified`/`approved`, `pending`/`in_review`, `rejected`/`failed`, else `notStarted` |
| `credit_enabled` | bool | default `false` |
| `created_at` | datetime? | ISO 8601 |

### AuthToken  (`auth_token_model.dart`, snake_case)
| field | type | notes |
|---|---|---|
| `access_token` | string | required |
| `refresh_token` | string? | |
| `expires_at` | datetime? | ISO 8601 |

(`/auth/otp/verify` `data` also carries `is_new_user: bool` and `verification_id` is the key returned by `/auth/otp/send`.)

### Address  (`address_model.dart`, camelCase)
| field | type |
|---|---|
| `id` | string |
| `name` | string |
| `phone` | string |
| `line1` | string |
| `village` | string |
| `area` | string |
| `district` | string |
| `state` | string |
| `pincode` | string |
| `landmark` | string |
| `latitude` | double? |
| `longitude` | double? |
| `isDefault` | bool |

### Category  (`category_model.dart`, camelCase)
| field | type |
|---|---|
| `id` | string |
| `name` | string |
| `productCount` | int |
| `imageUrl` | string? |
| `iconName` | string? |
| `parentId` | string? |

### Product  (`product_model.dart`, camelCase)
| field | type | notes |
|---|---|---|
| `id` | string | |
| `name` | string | |
| `brand` | string | |
| `unit` | string | e.g. `250 g`, `Each` |
| `price` | num | |
| `mrp` | num | |
| `creditPrice` | num? | |
| `categoryId` | string | |
| `rating` | double | |
| `reviews` | int | |
| `imageUrl` | string? | |
| `images` | [string] | gallery |
| `inStock` | bool | default `true` |
| `stockCount` | int? | |
| `description` | string? | |
| `variants` | [ProductVariant] | |
| `specifications` | map<string,string> | |

### ProductVariant  (`product_model.dart`, camelCase)
| field | type |
|---|---|
| `id` | string |
| `label` | string |
| `priceDelta` | num |
| `inStock` | bool |

### Offer  (`offer_model.dart`, camelCase)
| field | type | notes |
|---|---|---|
| `id` | string | |
| `title` | string | |
| `type` | string | `banner` \| `deal` \| `coupon` |
| `subtitle` | string | |
| `code` | string? | coupon code |
| `imageUrl` | string? | |
| `badge` | string? | |
| `discountPercent` | int? | |
| `dealPrice` | num? | |
| `originalPrice` | num? | |
| `productId` | string? | deal target |

### CartItem  (`cart_item_model.dart`, camelCase)
| field | type |
|---|---|
| `productId` | string |
| `name` | string |
| `brand` | string |
| `unit` | string |
| `price` | num |
| `mrp` | num |
| `quantity` | int |
| `imageUrl` | string? |

### Order  (`order_model.dart`, camelCase)
| field | type | notes |
|---|---|---|
| `id` | string | |
| `items` | [OrderItem] | |
| `address` | OrderAddress | |
| `payment` | OrderPayment | |
| `summary` | OrderSummary | |
| `status` | string | OrderStatus name |
| `placedAt` | int (epoch ms) | |
| `estimatedDelivery` | int (epoch ms)? | |
| `timeline` | [OrderTimelineEntry] | |

### OrderItem
| field | type |
|---|---|
| `productId` | string |
| `name` | string |
| `brand` | string |
| `unit` | string |
| `price` | num |
| `quantity` | int |
| `mrp` | num? |
| `imageUrl` | string? |

### OrderAddress
| field | type |
|---|---|
| `name` | string |
| `phone` | string |
| `formatted` | string |
| `pincode` | string |
| `latitude` | double? |
| `longitude` | double? |

### OrderPayment
| field | type | notes |
|---|---|---|
| `method` | string | `credit` \| `cashOnDelivery` \| `upi` \| `card` |
| `status` | string | `pending` \| `paid` \| `failed` \| `refunded` |
| `amount` | num | |
| `creditUsed` | num | |

### OrderSummary
| field | type |
|---|---|
| `itemTotal` | num |
| `deliveryFee` | num |
| `grandTotal` | num |
| `discount` | num |
| `creditUsed` | num |

### OrderTimelineEntry
| field | type | notes |
|---|---|---|
| `status` | string | OrderStatus name |
| `label` | string | |
| `at` | int (epoch ms)? | |
| `done` | bool | |

### OrderTracking  (entity)
| field | type |
|---|---|
| `orderId` | string |
| `currentStatus` | string (OrderStatus) |
| `timeline` | [OrderTimelineEntry] |
| `agentName` | string? |
| `agentPhone` | string? |
| `etaLabel` | string? |

### CreditAccount  (entity)
| field | type | notes |
|---|---|---|
| `creditLimit` | num | |
| `outstanding` | num | |
| `vsScore` | int | |
| `billingCycle` | string | `weekly` \| `monthly` |
| `dueDate` | datetime? | |
| `purchasesThisMonth` | num | |
| `paymentsThisMonth` | num | |

### CreditTransaction  (entity)
| field | type | notes |
|---|---|---|
| `id` | string | |
| `type` | string | `purchase` \| `payment` |
| `amount` | num | |
| `date` | datetime | |
| `description` | string | |

### CreditPaymentResult  (entity)
| field | type |
|---|---|
| `transactionId` | string |
| `amountPaid` | num |
| `method` | string |
| `account` | CreditAccount |
| `scorePointsEarned` | int |

### CreditLedgerEntry  (`billing_models.dart`, camelCase)
| field | type | notes |
|---|---|---|
| `id` | string | |
| `type` | string | `purchase` \| `repayment` \| `penalty` \| `adjustment` \| `refund` |
| `status` | string | `pending` \| `completed` \| `failed` \| `reversed` |
| `amount` | num | |
| `date` | int (epoch ms) | |
| `description` | string | |
| `balanceAfter` | num? | |
| `orderId` | string? | |
| `cycleId` | string? | |

### Statement  (entity)
| field | type |
|---|---|
| `statementId` | string |
| `cycleId` | string |
| `generatedDate` | datetime |
| `transactions` | [CreditLedgerEntry] |
| `amountDue` | num |
| `minimumDue` | num |
| `dueDate` | datetime |
| `paid` | bool |

### Repayment  (`billing_models.dart`, camelCase)
| field | type | notes |
|---|---|---|
| `id` | string | |
| `amount` | num | |
| `method` | string | `upi` \| `card` \| `bankTransfer` \| `cashCollection` |
| `status` | string | `pending` \| `completed` \| `failed` \| `reversed` |
| `date` | int (epoch ms) | |
| `reference` | string? | |
| `statementId` | string? | |

### CollectionRecord  (`billing_models.dart`, camelCase)
| field | type | notes |
|---|---|---|
| `id` | string | |
| `amount` | num | |
| `status` | string | `pending` \| `assigned` \| `collected` \| `failed` |
| `createdAt` | int (epoch ms) | |
| `agentId` | string? | |
| `agentName` | string? | |
| `collectedAt` | int (epoch ms)? | |
| `method` | string | RepaymentMethod name |
| `address` | string? | |

### BillingCycle  (entity)
`cycleId`, `startDate`, `endDate`, `dueDate`, `openingBalance`, `newPurchases`,
`paymentsReceived`, `penalties`, `closingBalance`.

### Invoice  (entity)
`invoiceId`, `orderId`, `amount`, `generatedDate`, `status`
(`pending|paid|overdue|cancelled`).

### VerificationDraft  (`verification_draft_model.dart`, camelCase)
| field | type | notes |
|---|---|---|
| `aadhaarNumber` | string | |
| `panNumber` | string | |
| `aadhaarFrontPath` | string? | |
| `aadhaarBackPath` | string? | |
| `panPath` | string? | |
| `selfiePath` | string? | |
| `occupation` | string | |
| `monthlyIncome` | num? | |
| `familyMembers` | int? | |
| `houseType` | string? | `independent` \| `apartment` \| `shared` |
| `ownership` | string? | `owned` \| `rented` \| `family` |
| `requestedLimit` | num? | |
| `status` | string | VerificationStatus name |

### VerificationApplication  (entity)
| field | type | notes |
|---|---|---|
| `applicationId` | string | |
| `status` | string | `notStarted` \| `draft` \| `pending` \| `underReview` \| `approved` \| `rejected` |
| `submittedAt` | datetime | |
| `expectedReviewDays` | int | default 2 |
| `approvedLimit` | num? | |
| `rejectionReason` | string? | |

### Notification  (`app_notification.dart` entity)
| field | type | notes |
|---|---|---|
| `id` | string | |
| `title` | string | |
| `body` | string | |
| `type` | string | `order` \| `delivery` \| `credit` \| `payment` \| `offer` \| `account` |
| `time` | datetime | |
| `read` | bool | |
| `important` | bool | |
| `actionLabel` | string? | |
| `route` | string? | |

### SupportTicket  (from support UI)
| field | type | notes |
|---|---|---|
| `id` | string | e.g. `#VS-TKT-102548` |
| `subject` | string | |
| `category` | string | |
| `status` | string | `open` \| `inProgress` \| `resolved` \| `closed` |
| `updated` | string/datetime | |
| `highPriority` | bool | |

---

## Enum value reference (string names sent over the wire)

| Enum | Values |
|---|---|
| KycStatus (User `kyc_status`) | `verified`/`approved`, `pending`/`in_review`, `rejected`/`failed`, `notStarted` |
| OrderStatus | `pending`, `confirmed`, `packed`, `outForDelivery`, `delivered`, `cancelled`, `returned` |
| PaymentMethod | `credit`, `cashOnDelivery`, `upi`, `card` |
| PaymentStatus | `pending`, `paid`, `failed`, `refunded` |
| OfferType | `banner`, `deal`, `coupon` |
| ProductSort | `popularity`, `newest`, `priceLowToHigh`, `priceHighToLow`, `discount` |
| BillingCycle | `weekly`, `monthly` |
| CreditTransactionType | `purchase`, `payment` |
| TransactionType (ledger) | `purchase`, `repayment`, `penalty`, `adjustment`, `refund` |
| TransactionStatus | `pending`, `completed`, `failed`, `reversed` |
| RepaymentMethod | `upi`, `card`, `bankTransfer`, `cashCollection` |
| CollectionStatus | `pending`, `assigned`, `collected`, `failed` |
| InvoiceStatus | `pending`, `paid`, `overdue`, `cancelled` |
| VerificationStatus | `notStarted`, `draft`, `pending`, `underReview`, `approved`, `rejected` |
| HouseType | `independent`, `apartment`, `shared` |
| Ownership | `owned`, `rented`, `family` |
| NotificationType | `order`, `delivery`, `credit`, `payment`, `offer`, `account` |
