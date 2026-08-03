# 02 · Data Model (source of truth)

PostgreSQL. All tables get `id` (BigAuto/UUID), `created_at`, `updated_at` unless noted.
Money columns are **integer paise** (`amount_paise`) or `Decimal(12,2)` — pick one
project-wide; this doc uses `money` to mean that type. Enums are Postgres enums or
`varchar` + `CHECK`.

Legend: **PK** primary key · **FK** foreign key · `?` nullable · `↺` append-only (no UPDATE/DELETE).

---

## Identity & Access — `accounts`

### user
| col | type | notes |
|---|---|---|
| id | PK | |
| phone | varchar(15) unique | E.164, +91… (login identity) |
| email | varchar ? unique | optional |
| name | varchar | |
| role | enum(`superadmin`,`admin`,`agent`,`customer`) | default `customer` |
| avatar_url | varchar ? | |
| is_active | bool | soft-disable |
| kyc_status | enum(`not_started`,`pending`,`verified`,`rejected`) | mirrors KYC app state |
| credit_enabled | bool | true once approved |
| last_login_at | timestamptz ? | |

> Use a single `user` table with a `role` column (simpler than per-type tables). Django
> `Group`/`Permission` back the admin console; `role` drives API permission classes.

### agent_profile  (1–1 with user where role=agent)
| col | type | notes |
|---|---|---|
| user_id | FK→user unique | |
| code | varchar unique | agent ID |
| assigned_pincodes | text[] | service area |
| is_available | bool | |

### otp_challenge  *(or store in Redis with TTL — preferred)*
| col | type | notes |
|---|---|---|
| phone | varchar | |
| code_hash | varchar | never store raw OTP |
| purpose | enum(`login`,`payment`) | |
| expires_at | timestamptz | TTL ~5 min |
| attempts | int | lock after N |
| verification_id | uuid | returned to client |

### device_token
| user_id FK · token varchar · platform enum(`android`,`ios`) · is_active bool |

### refresh_token  *(if not using stateless rotation only)*
| user_id FK · jti uuid · expires_at · revoked_at? · user_agent · ip |

### audit_log  ↺
| col | type | notes |
|---|---|---|
| actor_id | FK→user | who did it |
| action | varchar | e.g. `credit.limit.update` |
| target_type | varchar | `user`,`order`,`credit_account`… |
| target_id | varchar | |
| before | jsonb ? | |
| after | jsonb ? | |
| ip | inet ? | |
| created_at | timestamptz | |

---

## KYC — `kyc`

### kyc_application
| user_id FK · status enum(`not_started`,`pending`,`verified`,`rejected`) · submitted_at? · reviewed_by FK→user(agent/admin)? · reviewed_at? · rejection_reason? |

### kyc_document
| application_id FK · type enum(`aadhaar`,`pan`,`selfie`,`residence`) · number_masked varchar? · file_key varchar (MinIO object) · status enum(`pending`,`approved`,`rejected`) · reviewed_by FK? |

### verification_step
| application_id FK · step enum(`aadhaar`,`pan`,`selfie`,`residence`,`credit`) · status enum(`pending`,`in_review`,`approved`,`rejected`) · agent_id FK? · note? |

---

## Catalog — `catalog`

### category
| col | type | notes |
|---|---|---|
| id | PK | |
| name | varchar | |
| slug | varchar unique | |
| parent_id | FK→category ? | null = department (top level) |
| icon_name | varchar ? | maps to app icon |
| image_url | varchar ? | |
| product_count | int | denormalized, refreshed by job |
| sort_order | int | |
| is_active | bool | |

### product
| col | type | notes |
|---|---|---|
| id | PK | |
| name | varchar | |
| brand | varchar | |
| unit | varchar | e.g. "250 g", "1 L", "Each" |
| price | money | selling price |
| mrp | money | strike-through |
| credit_price | money ? | price when paid on credit |
| category_id | FK→category | |
| rating | numeric(2,1) | denormalized avg |
| review_count | int | denormalized |
| in_stock | bool | |
| stock_count | int ? | drives low/out-of-stock |
| description | text ? | |
| is_active | bool | |
| search_vector | tsvector | GIN-indexed full-text search |

### product_image
| product_id FK · url varchar · sort int |

### product_variant
| product_id FK · label varchar · price_delta money · in_stock bool |

### product_specification
| product_id FK · key varchar · value varchar |  *(or a single `specifications jsonb` on product)*

### review  *(optional v1)*
| product_id FK · user_id FK · rating int(1–5) · comment text? · created_at · unique(product,user) |

---

## Cart & Wishlist — `cart`

### cart
| user_id FK unique · updated_at |  *(one live cart per user)*

### cart_item
| cart_id FK · product_id FK · variant_id FK? · quantity int · price_snapshot money · unique(cart,product,variant) |

### wishlist_item
| user_id FK · product_id FK · created_at · unique(user,product) |

---

## Addresses — `addresses`

### address
| col | type | notes |
|---|---|---|
| user_id | FK | |
| label | varchar | Home/Work/… |
| name | varchar | recipient |
| phone | varchar | |
| line1 | varchar | |
| area | varchar | |
| city / district | varchar | |
| state | varchar | |
| pincode | varchar(6) | |
| latitude / longitude | numeric ? | from device GPS |
| is_default | bool | one true per user (enforced in service) |

---

## Orders — `orders`

### order
| col | type | notes |
|---|---|---|
| id | PK | display code e.g. VSORD… |
| user_id | FK | |
| status | enum(`pending`,`confirmed`,`packed`,`out_for_delivery`,`delivered`,`cancelled`) | |
| placed_at | timestamptz | |
| delivery_slot | varchar ? | |
| estimated_delivery | timestamptz ? | |
| address_snapshot | jsonb | frozen address at order time |
| payment_method | enum(`cod`,`upi`,`card`,`netbanking`,`credit`) | |
| payment_status | enum(`pending`,`paid`,`failed`,`refunded`) | |
| subtotal / delivery_fee / gst / discount / total | money | |
| credit_used | money | amount put on VS Credit |
| coupon_code | varchar ? | |

### order_item
| order_id FK · product_id FK? · name · brand · unit · price money · mrp money · quantity int |  *(name/price frozen at purchase)*

### order_status_event  ↺
| order_id FK · status enum · note? · at timestamptz · by FK? |

### delivery_assignment
| order_id FK · agent_id FK→user · status enum(`assigned`,`picked`,`delivered`,`failed`) · assigned_at · delivered_at? |

### order_tracking
| order_id FK unique · agent_name? · latitude? · longitude? · eta? · updated_at |

---

## Credit (fintech core) — `credit`

### credit_account
| col | type | notes |
|---|---|---|
| user_id | FK unique | |
| credit_limit | money | approved limit |
| outstanding | money | derived from ledger (cached) |
| available | money | = limit − outstanding (derived) |
| vs_score | int | 0–900 |
| status | enum(`active`,`frozen`,`closed`) | frozen on overdue |
| opened_at | timestamptz | |

### credit_ledger_entry  ↺  **(append-only — the heart of the system)**
| col | type | notes |
|---|---|---|
| account_id | FK→credit_account | |
| type | enum(`purchase`,`repayment`,`fee`,`adjustment`,`refund`) | |
| amount | money | signed by `type` (purchase +, repayment −) |
| balance_after | money | running outstanding snapshot |
| order_id | FK? | for purchases |
| payment_id | FK? | for repayments |
| statement_id | FK? | |
| note | varchar ? | |
| created_by | FK? | staff for adjustments |
| created_at | timestamptz | |

> Never UPDATE or DELETE a ledger row. Corrections are new `adjustment` rows.
> `credit_account.outstanding` is rebuilt from `SUM(amount)` and reconciled by a job.

### statement
| col | type | notes |
|---|---|---|
| account_id | FK | |
| period | enum(`weekly`,`monthly`) | |
| period_start / period_end | date | |
| opening_balance / purchases / payments / fees / closing_balance | money | |
| due_date | date | |
| status | enum(`open`,`paid`,`overdue`,`partially_paid`) | |
| generated_at | timestamptz | by Celery beat |

### statement_line  ↺
| statement_id FK · ledger_entry_id FK · order_id FK? |

### family_group
| primary_user_id FK→user · shared_limit money · created_at |

### family_member
| group_id FK · user_id FK · relationship varchar · status enum(`active`,`pending`,`removed`) · shared_usage money(derived) · unique(group,user) |

---

## Payments — `payments`

### payment
| col | type | notes |
|---|---|---|
| id | PK | |
| user_id | FK | |
| purpose | enum(`order`,`repayment`) | |
| order_id | FK? | when paying for an order |
| statement_id | FK? | when repaying credit |
| amount | money | |
| method | enum(`upi`,`card`,`netbanking`,`cash`) | |
| gateway | enum(`razorpay`,`cashfree`,`manual`) | |
| gateway_order_id / gateway_payment_id | varchar ? | |
| status | enum(`created`,`pending`,`success`,`failed`,`refunded`) | finalized by webhook |
| idempotency_key | varchar unique ? | |
| created_at | timestamptz | |

### payment_webhook_event  ↺
| gateway · event_id varchar unique · signature_ok bool · payload jsonb · processed bool · received_at |

### cash_collection
| col | type | notes |
|---|---|---|
| user_id | FK→user(customer) | |
| agent_id | FK→user(agent) ? | assigned |
| amount | money | |
| status | enum(`requested`,`assigned`,`collected`,`cancelled`) | |
| statement_id | FK? | what it repays |
| requested_at / assigned_at / collected_at | timestamptz ? | |
| payment_id | FK? | the `cash` payment it produces on collection |

---

## Offers — `offers`

### offer
| id PK · type enum(`banner`,`deal`,`coupon`) · title · subtitle? · code? · image_url? · badge? · discount_percent int? · deal_price money? · original_price money? · product_id FK? · valid_from? · valid_to? · is_active bool · sort_order int |

### coupon
| code varchar unique · discount_type enum(`flat`,`percent`) · value money/int · min_order money? · max_discount money? · usage_limit int? · per_user_limit int? · valid_to? · is_active |

### coupon_redemption  ↺
| coupon_id FK · user_id FK · order_id FK · amount money · redeemed_at · unique(coupon,order) |

---

## Notifications — `notifications`

### notification
| user_id FK · type varchar · title · body · data jsonb? · read_at timestamptz? · created_at |

### notification_preference
| user_id FK unique · push bool · sms bool · whatsapp bool · email bool · reminder_time time? |

*(device_token lives in `accounts`.)*

---

## Support — `support`

### support_ticket
| id PK(code) · user_id FK · category varchar · priority enum(`low`,`medium`,`high`) · subject · status enum(`open`,`in_progress`,`resolved`,`closed`) · assigned_to FK?(agent/admin) · order_id FK? · created_at |

### ticket_message
| ticket_id FK · sender_id FK · body text · attachments jsonb? · created_at |

### faq
| category varchar · question · answer text · sort_order int · is_active |

---

## Referrals — `referrals`

### referral
| referrer_id FK · referee_id FK? · code varchar unique · reward money · status enum(`pending`,`completed`,`expired`) · created_at · unique(referrer,referee) |

---

## Cross-cutting

### idempotency_key
| key varchar PK · user_id FK · endpoint varchar · response_hash · created_at |  *(blocks duplicate POSTs)*

## Relationship summary

- `user 1—1 credit_account 1—* credit_ledger_entry`
- `user 1—* order 1—* order_item`; `order 1—1 order_tracking`; `order *—1 agent (delivery)`
- `order → credit_ledger_entry(purchase)`; `payment → credit_ledger_entry(repayment)`
- `statement 1—* statement_line → ledger_entry`
- `user 1—1 kyc_application 1—* kyc_document` ; reviewed by agent/admin
- `family_group 1—* family_member → user` (shared credit limit)
- `cash_collection → payment(cash) → credit_ledger_entry(repayment)`

## Indexing notes

- `user.phone` unique btree · `product.search_vector` GIN · `order(user_id, placed_at)` ·
  `credit_ledger_entry(account_id, created_at)` · `payment(gateway_payment_id)` ·
  `notification(user_id, read_at)` · `coupon.code` · `address(user_id, is_default)`.
