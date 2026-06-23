# VS Mart — Phase 3 Order Architecture Report (Sign-off)

Handoff document for Phase 4 (Credit Billing & Collections). The order pipeline
below is built, integrated, offline-first, and `flutter analyze lib` clean. It
is the shared transaction layer for User App, Agent App, and Admin Panel.

---

## 1. Order Domain (`features/orders/domain/`)

| Type | Notes |
|---|---|
| `OrderStatus` | pending → confirmed → packed → outForDelivery → delivered (+ cancelled, returned); `isActive`/`isCompleted`/`isCancelled`/`progress` |
| `PaymentMethod` | credit / cashOnDelivery / upi / card |
| `PaymentStatus` | pending / paid / failed / refunded |
| `OrderItem` | line snapshot (productId, name, brand, unit, price, qty, mrp, imageUrl) |
| `OrderAddress` | delivery snapshot |
| `OrderPayment` | method, status, amount, creditUsed |
| `OrderSummary` | itemTotal, deliveryFee, grandTotal, discount, creditUsed |
| `OrderTimelineEntry` | status, label, at, done |
| `Order` | aggregate (items, address, payment, summary, status, placedAt, estimatedDelivery, timeline) |
| `OrderTracking` | orderId, currentStatus, timeline, agentName/phone, etaLabel |

## 2. Repositories & Data

- **`OrderRepository`** — `placeOrder`, `getOrders`, `getOrderById`, `getTracking`, `cancelOrder`.
- **`OrderRepositoryImpl`** — **offline-first**: persists to Hive `orderBox`, builds the 5-step timeline, seeds history from `OrderFixtureDataSource` on first run. The fixture is the single backend seam.
- **`OrderModel`** — full nested JSON (items/address/payment/summary/timeline).
- **`CartValidationService`** — validates cart lines vs live catalog (stock / quantity / price).
- **`CreditCheckoutValidator`** — `canPurchase` / `availableCredit` / `creditShortfall`.

## 3. Hive Storage

`orderBox` (history + placed orders), `orderDraftBox`, `trackingBox`, `checkoutDraftBox` (resumable checkout), `addressBox`. All opened at bootstrap.

## 4. Providers

- **Orders:** `orderRepositoryProvider`, `ordersProvider`, `orderByIdProvider.family`, `orderTrackingProvider.family`, `recentlyOrderedProductsProvider`, `orderRecommendationProvider`.
- **Cart:** `cartControllerProvider`, `cartSummaryProvider`, `cartValidationServiceProvider`, `cartValidationProvider`.
- **Address:** `addressSelectionProvider`, `selectedAddressProvider`.
- **Checkout:** `checkoutControllerProvider` (engine), `lastPlacedOrderProvider`, `creditCheckoutValidatorProvider`.

## 5. Checkout Engine

`CheckoutController` is **pure orchestration** over cart / address / credit:
`selectAddress`, `selectPaymentMethod`, `setDeliverySlot`, `toggleTerms`,
`applyCoupon` / `removeCoupon`, `placeOrder`. The draft persists to
`checkoutDraftBox` so an interrupted checkout resumes. `placeOrder` validates
(cart valid · address selected · terms accepted · credit sufficient), builds the
`Order` from the cart, persists via `OrderRepository`, clears cart + draft, and
records `lastPlacedOrderProvider`.

## 6. Credit Purchase Logic

When paying on credit, `VSCreditEligibilityBanner` + `VSCreditCheckoutCard` show
limit / used / available / purchase / remaining. Place Order is disabled when
`available < total`; the shortfall is surfaced. Settled orders mark
`creditUsed` on both the payment and summary.

## 7. Widgets

`VSCartItem`, `VSCartSummaryCard`, `VSCartFooter`, `VSEmptyCart`,
`VSAddressSelector`, `VSNoAddressState`, `VSCreditCheckoutCard`,
`VSCreditEligibilityBanner`, `VSOrderStatusChip`, `VSOrderTimeline`,
`VSOrderSummary` (+ reused core `VSOrderCard`, `VSAddressCard`, `VSOfflineBanner`).

## 8. Analytics Events

`cart_viewed`, `cart_item_added`, `cart_item_removed`, `checkout_started`,
`address_selected`, `payment_method_selected`, `credit_payment_selected`,
`order_placed`, `order_cancelled`, `order_viewed`, `tracking_viewed`.

## 9. Offline Strategy

Orders, checkout draft, addresses, and cart all persist to Hive and work fully
offline (place order → stored locally → history/tracking available). Cart and
order screens show `VSOfflineBanner`. Seed order history loads on first run.

## 10. Screen Inventory

| Screen | State |
|---|---|
| Cart | Validated items, summary, blocking banner, offline, pull-to-refresh |
| Address Selection / Add Address | Modular, multi-address, default, edit/delete |
| Checkout | Address/slot/coupon/payment/credit/terms; engine-driven |
| Order Success | Id, amount, payment, credit, ETA + Track/Orders/Continue |
| Orders List | Active / Completed / Cancelled tabs, reorder, track |
| Order Details | Timeline, items, address, payment, billing, cancel/support |
| Order Tracking | Status banner, ETA, agent, progress timeline |

## Home integration

Home surfaces an **active-order status card** (tap → tracking) and a **Recently
Ordered** rail (`recentlyOrderedProductsProvider`).

---

## Phase 4 readiness

The order + credit layers feed Phase 4 directly: `creditUsed` per order, payment
status, and the `CreditAccount` are the inputs for **Credit Billing,
Repayment, Collections, Statements, Invoices, Payment History, Agent Collection,
and Admin Credit Management**. `orderRepository` + `creditRepository` are the
shared sources those modules build on.
