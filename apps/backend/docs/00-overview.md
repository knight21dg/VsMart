# 00 · Product Overview & Scope

## What VS Mart is

A grocery commerce app with an embedded **credit line (buy-now-pay-later)**. Customers
shop on credit, get billed on a cycle (weekly/monthly), and repay via UPI/card or
**cash collected by field agents**. KYC gates the credit facility. Staff (admins) run
operations; agents do field work (KYC verification, cash collection, deliveries).

This makes it a **fintech app**, not a plain store — money, ledgers, KYC, and audit
trails are first-class.

## Actors / roles

| Role | Surface | What they do |
|---|---|---|
| **Customer** | Flutter app | Shop, manage cart/orders, use & repay credit, KYC, support. |
| **Agent** | Flutter app (role-gated) or agent web | Verify KYC, collect cash, fulfil/deliver orders assigned to them. |
| **Admin** | Web console | Catalog, orders, customers, credit approvals/limits, offers, support, refunds. |
| **Superadmin** | Web console | Everything admin can, **plus** manage admins/agents, roles, and global config. |

Full permission matrix: [`04-rbac.md`](04-rbac.md).

## Modules (derived from the existing app)

1. **Identity & Auth** — phone OTP login, JWT, registration, roles, sessions, audit log.
2. **KYC & Verification** — Aadhaar, PAN, selfie, residence; agent/admin review workflow.
3. **Catalog** — departments, categories, products, variants, search, reviews.
4. **Cart & Wishlist** — server-synced cart, wishlist.
5. **Addresses** — multiple addresses, default, geo-coordinates.
6. **Checkout & Orders** — order placement, delivery slots, status timeline, tracking, reorder.
7. **Credit (core)** — credit account, **append-only ledger**, limits, VS score, statements
   (weekly/monthly), outstanding dues, **family/household shared limit**.
8. **Payments** — UPI/card/netbanking via gateway + webhooks; **cash collection** by agents; repayments.
9. **Offers** — banners, deals, coupons/wallet, redemptions.
10. **Notifications** — in-app inbox, push (device tokens), payment reminders, preferences.
11. **Support** — tickets, ticket chat, FAQs.
12. **Engagement** — referrals.
13. **Admin/Ops** — staff management, dashboards, manual overrides, refunds, reporting.

## Out of scope (v1)

- Real-time agent GPS tracking on a map (start with status + ETA only).
- Multi-warehouse inventory / supplier portal.
- Marketplace (third-party sellers). Single-tenant store only.
- Web customer storefront (mobile app is the customer surface).

## Key product rules (confirm with client)

- **Credit cycle:** purchases bill on the 1st, due by the 5th, no interest if paid on time;
  late fee + credit freeze after due date. (App copy in FAQ implies this — verify.)
- **GST:** 18% applied at checkout (matches app). Confirm per-category GST if needed.
- **Delivery fee:** flat fee below a free-delivery threshold (app uses ₹45 below ₹499).
- **Currency:** INR (₹). Phone: +91, OTP length 6.
- **Family shared limit:** a primary account holder shares their credit limit with members.

## Glossary

- **VS Credit** — the BNPL credit line attached to a customer.
- **VS Score** — internal creditworthiness score (0–900-ish) shown to the customer.
- **Ledger** — append-only record of every credit movement (purchase, repayment, fee, adjustment).
- **Statement** — a billing-cycle summary with an amount due and due date.
- **Cash collection** — an agent physically collecting a repayment, recorded against the ledger.
- **KYC application** — a customer's set of identity documents + verification steps.
