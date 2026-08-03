# VS Mart — API Response Code Catalog

_184 machine-readable codes. Single source of truth: `core/response_codes.py`. Served live at `GET /api/v1/response-codes` (optionally `?module=credit`)._

Every coded response carries: `success, code, title, message, action, retryable, severity, nextStep` (camelCase on the wire) plus a back-compat `error:{code,message,fields}`. Failures also write an `AuditLog` row.

**Action types:** `navigate`(+target) · `retry` · `retry_verification` · `logout` · `reauth` · `contact_support` · `refresh`.


## System / Generic

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `VALIDATION_ERROR`  | 400 | warning | Check Your Details | Some of the information entered isn't valid. | — | yes |
| `NOT_FOUND`  | 404 | warning | Not Found | We couldn't find what you're looking for. | — | — |
| `CONFLICT`  | 409 | info | Already Done | This action has already been completed. | — | — |
| `RATE_LIMITED`  | 429 | warning | Slow Down | You're doing that a bit too fast. | — | yes |
| `SYSTEM_ERROR`  | 500 | error | Something Needs Attention | We hit a temporary problem on our end. | `retry` | yes |
| `SERVICE_UNAVAILABLE`  | 503 | error | Service Busy | The service is temporarily unavailable. | `retry` | yes |
| `MAINTENANCE`  | 503 | warning | Under Maintenance | VS Mart is briefly down for maintenance. | — | — |
| `FEATURE_DISABLED`  | 403 | info | Not Available | This feature isn't available right now. | — | — |
| `DEPENDENCY_FAILED`  | 502 | error | Temporary Glitch | A connected service didn't respond in time. | `retry` | yes |

## Auth / Registration

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `AUTH_REQUIRED`  | 401 | warning | Sign In Required | Please sign in to continue. | `navigate` → `/login` | — |
| `PHONE_ALREADY_EXISTS`  | 409 | warning | Account Exists | An account already exists with this mobile number. | `navigate` → `/login` | — |
| `OTP_LIMIT_REACHED`  | 429 | warning | Too Many Attempts | You've requested too many OTPs. | — | — |
| `OTP_EXPIRED`  | 400 | warning | Code Expired | The verification code has expired. | `retry` | yes |
| `OTP_INVALID`  | 400 | warning | Incorrect Code | The code entered doesn't match. | — | yes |
| `BLOCKED_MOBILE`  | 403 | error | Number Restricted | This mobile number is restricted from creating accounts. | `contact_support` | — |
| `ACCOUNT_SUSPENDED`  | 403 | error | Account Suspended | Your account has been temporarily suspended. | `contact_support` | — |
| `PROFILE_INCOMPLETE`  | 400 | info | Complete Your Profile | Add your name to finish setting up your account. | `navigate` → `/profile/edit` | — |
| `OTP_SENT` ✅ | 200 | success | Code Sent | We've sent a verification code to your mobile. | — | — |
| `LOGIN_SUCCESS` ✅ | 200 | success | Welcome Back | You're signed in. | — | — |

## Security

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `SESSION_EXPIRED`  | 401 | warning | Session Expired | Your login session has expired. | `logout` | — |
| `INVALID_SESSION`  | 401 | warning | Session Invalid | Your session is no longer valid. | `logout` | — |
| `TOKEN_REVOKED`  | 401 | warning | Signed Out | This session was signed out. | `logout` | — |
| `MULTIPLE_DEVICE_LOGIN`  | 401 | warning | New Device Login | Your account was logged in on another device. | `reauth` | — |
| `DEVICE_NOT_TRUSTED`  | 403 | warning | Verify This Device | This device needs to be verified. | `reauth` | — |
| `TOO_MANY_REQUESTS`  | 429 | warning | Too Many Requests | You've exceeded the allowed request limit. | — | yes |
| `IP_RESTRICTED`  | 403 | error | Access Restricted | Access from this location is restricted. | `contact_support` | — |
| `ACCOUNT_LOCKED`  | 423 | error | Account Locked | Account access has been temporarily locked. | `contact_support` | — |
| `INSUFFICIENT_PERMISSIONS`  | 403 | warning | Not Allowed | You don't have permission to perform this action. | — | — |

## Zone / Serviceability

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `OUTSIDE_SERVICE_AREA`  | 422 | warning | Service Unavailable | VS Mart currently doesn't deliver to your location. | `navigate` → `/serviceability` | — |
| `LOCATION_PERMISSION_REQUIRED`  | 400 | warning | Location Required | Enable location access to check delivery availability. | `navigate` → `/location` | yes |
| `GPS_ACCURACY_LOW`  | 400 | warning | Can't Detect Location | We're unable to accurately detect your location. | `retry` | yes |
| `ZONE_DISABLED`  | 200 | warning | Service Paused | Deliveries are temporarily unavailable in your area. | — | — |
| `NO_STORE_ASSIGNED`  | 200 | warning | No Store Nearby | No active store serves this location yet. | `navigate` → `/serviceability` | — |
| `STORE_CLOSED`  | 409 | warning | Store Closed | The nearest store is currently closed. | — | — |
| `SERVICEABLE` ✅ | 200 | success | We Deliver Here | Great news — we deliver to your location. | — | — |

## KYC / Verification

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `KYC_NOT_STARTED`  | 403 | warning | Verification Required | Complete verification before applying for credit. | `navigate` → `/verification` | — |
| `KYC_REQUIRED`  | 403 | warning | Verification Required | Complete your identity verification before applying for credit. | `navigate` → `/verification` | — |
| `VERIFICATION_PENDING`  | 200 | info | Under Review | Your verification is currently under review. | — | — |
| `VERIFICATION_REJECTED`  | 200 | warning | Verification Not Approved | Verification couldn't be approved. | `retry_verification` | — |
| `DOCUMENT_BLURRY`  | 400 | warning | Document Unclear | The uploaded document is unclear. | `retry_verification` | yes |
| `FACE_MISMATCH`  | 400 | warning | Selfie Mismatch | Your selfie doesn't match the submitted identity documents. | `retry_verification` | — |
| `PAN_INVALID`  | 400 | warning | PAN Not Verified | The PAN entered couldn't be verified. | — | yes |
| `PAN_NAME_MISMATCH`  | 400 | warning | Details Don't Match | PAN details do not match your Aadhaar records. | `retry_verification` | — |
| `AADHAAR_INVALID`  | 400 | warning | Aadhaar Not Validated | The Aadhaar details couldn't be validated. | — | yes |
| `AADHAAR_ALREADY_USED`  | 409 | error | Already Linked | This Aadhaar is already linked to another account. | `contact_support` | — |
| `DUPLICATE_KYC`  | 409 | error | Already Verified Elsewhere | Identity verification already exists on another account. | `contact_support` | — |
| `KYC_AGE_RESTRICTED`  | 403 | warning | Not Eligible For Credit | You must be at least 18 years old to apply for credit. | — | — |
| `GPS_VERIFICATION_FAILED`  | 400 | warning | Location Check Failed | Location verification was unsuccessful. | `retry` | yes |
| `HOUSE_VERIFICATION_PENDING`  | 200 | info | Field Verification Pending | Field verification of your address is still pending. | — | — |
| `KYC_SUBMITTED` ✅ | 200 | success | Submitted For Review | Your verification has been submitted. | — | — |
| `KYC_VERIFIED` ✅ | 200 | success | Verified | Your identity has been verified. | — | — |

## Credit

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `CREDIT_DISABLED`  | 403 | warning | Credit Unavailable | Credit purchasing is currently unavailable on your account. | `navigate` → `/credit` | — |
| `AGE_NOT_ELIGIBLE`  | 403 | warning | Credit Not Available | You must be at least 18 years old to apply for credit. | — | — |
| `LIMIT_EXCEEDED`  | 409 | warning | Credit Limit Reached | Your outstanding balance exceeds your available credit. | `navigate` → `/credit/repay` | — |
| `OVERDUE_PAYMENT`  | 402 | warning | Payment Required | Clear your overdue dues before placing a new credit order. | `navigate` → `/credit/repay` | — |
| `HIGH_RISK_CUSTOMER`  | 403 | error | Account Under Review | Your account is currently classified as high risk. | `contact_support` | — |
| `CREDIT_FROZEN`  | 403 | error | Credit Temporarily Disabled | Your credit usage has been temporarily frozen. | `contact_support` | — |
| `CREDIT_SUSPENDED`  | 403 | error | Credit Suspended | Your credit privileges have been suspended. | `contact_support` | — |
| `CREDIT_UNDER_REVIEW`  | 403 | info | Credit Under Review | Your account is under credit review. | — | — |
| `CREDIT_NOT_ELIGIBLE`  | 403 | warning | Not Eligible Yet | Your account isn't eligible for credit yet. | `navigate` → `/verification` | — |
| `LIMIT_INCREASE_PENDING`  | 200 | info | Review In Progress | Your credit limit review request is still being processed. | — | — |
| `LIMIT_INCREASE_APPROVED` ✅ | 200 | success | Limit Increased | Your credit limit has been increased. | — | — |
| `LIMIT_INCREASE_REJECTED`  | 200 | warning | Request Not Approved | Your credit limit review request wasn't approved. | — | — |
| `REPAYMENT_SUCCESS` ✅ | 200 | success | Payment Received | Your repayment was successful. | — | — |

## Ordering

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `CART_EMPTY`  | 400 | info | Cart Is Empty | Add items before placing an order. | `navigate` → `/home` | — |
| `MIN_ORDER_NOT_MET`  | 400 | warning | Add A Little More | Your cart hasn't reached the minimum order value. | `navigate` → `/cart` | — |
| `OUT_OF_STOCK`  | 409 | warning | Item Unavailable | One or more items in your cart are currently out of stock. | `navigate` → `/cart` | — |
| `INSUFFICIENT_QUANTITY`  | 409 | warning | Not Enough Stock | The requested quantity exceeds what's available. | `navigate` → `/cart` | — |
| `STOCK_UPDATED`  | 409 | warning | Cart Updated | Product quantities changed while you were checking out. | `navigate` → `/cart` | — |
| `STORE_INVENTORY_CHANGED`  | 409 | warning | Availability Changed | Some items in your cart have changed in availability. | `navigate` → `/cart` | — |
| `PRICE_UPDATED`  | 409 | info | Prices Updated | Prices changed since the items were added to your cart. | `navigate` → `/cart` | — |
| `PRODUCT_DISABLED`  | 410 | warning | Product Unavailable | This product is no longer available. | `navigate` → `/cart` | — |
| `ORDER_ALREADY_PLACED`  | 409 | info | Already Placed | This order has already been processed. | `navigate` → `/orders` | — |
| `DUPLICATE_ORDER`  | 409 | warning | Looks Familiar | A similar order was placed just moments ago. | `navigate` → `/orders` | — |
| `ORDER_NOT_CANCELLABLE`  | 409 | warning | Can't Cancel | This order can no longer be cancelled. | — | — |
| `ORDER_ACCEPTED` ✅ | 201 | success | Order Placed | Your order has been successfully placed. | — | — |
| `ORDER_CANCELLED` ✅ | 200 | info | Order Cancelled | The order has been cancelled. | — | — |
| `ORDER_CANCELLED_STORE` ✅ | 200 | warning | Order Cancelled | The store cancelled this order due to inventory issues. | — | — |
| `ORDER_DELIVERED` ✅ | 200 | success | Delivered | Your order has been successfully delivered. | — | — |
| `REORDER_SUCCESS` ✅ | 200 | success | Added To Cart | Items from your previous order were added to the cart. | `navigate` → `/cart` | — |

## Payments

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `COD_NOT_AVAILABLE`  | 400 | warning | Cash On Delivery Unavailable | Cash on Delivery isn't available for this order. | — | — |
| `PAYMENT_FAILED`  | 402 | error | Payment Failed | The transaction couldn't be completed. | `retry` | yes |
| `PAYMENT_PENDING`  | 202 | info | Awaiting Confirmation | We're waiting for your bank to confirm the payment. | — | — |
| `PAYMENT_CANCELLED`  | 200 | info | Payment Cancelled | You cancelled the payment. | `retry` | yes |
| `PAYMENT_GATEWAY_ERROR`  | 502 | error | Gateway Unavailable | The payment gateway didn't respond. | `retry` | yes |
| `PAYMENT_SUCCESS` ✅ | 200 | success | Payment Successful | Your payment was successful. | — | — |

## Finance

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `REFUND_INITIATED` ✅ | 200 | success | Refund Started | Your refund has been initiated. | — | — |
| `REFUND_COMPLETED` ✅ | 200 | success | Refund Completed | Your refund has been completed. | — | — |
| `REFUND_REJECTED`  | 200 | warning | Refund Not Approved | The refund request wasn't approved. | `contact_support` | — |
| `LEDGER_LOCKED`  | 409 | error | Period Closed | This accounting period has already been closed. | — | — |
| `JOURNAL_POSTED` ✅ | 201 | success | Entry Posted | The financial entry has been posted successfully. | — | — |
| `NO_DUES_FOUND`  | 200 | info | Nothing Due | You have no outstanding payments. | — | — |

## Delivery

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `AGENT_UNAVAILABLE`  | 200 | warning | Assignment Delayed | Delivery assignment is delayed due to agent availability. | — | — |
| `AGENT_NOT_ASSIGNED`  | 200 | info | No Agent Yet | No delivery agent has been assigned to this order. | — | — |
| `AGENT_ASSIGNED` ✅ | 200 | success | Agent Assigned | A delivery agent has been assigned. | — | — |
| `PICKUP_FAILED`  | 409 | warning | Pickup Failed | The pickup couldn't be completed. | `retry` | yes |
| `CUSTOMER_UNREACHABLE`  | 200 | warning | Customer Unreachable | The customer couldn't be contacted. | — | — |
| `ADDRESS_NOT_FOUND`  | 404 | warning | Address Not Found | The delivery location couldn't be located. | `navigate` → `/addresses` | — |
| `INVALID_DELIVERY_OTP`  | 400 | warning | Wrong OTP | The delivery OTP entered is incorrect. | — | yes |
| `DELIVERY_FAILED`  | 200 | warning | Delivery Failed | The delivery attempt was unsuccessful. | — | — |
| `DELIVERY_RESCHEDULED` ✅ | 200 | info | Rescheduled | The delivery has been rescheduled. | — | — |
| `DELIVERY_COMPLETED` ✅ | 200 | success | Delivered | The order was delivered successfully. | — | — |
| `DELIVERY_ASSIGNED` ✅ | 200 | success | Delivery Assigned | An agent has been assigned to this order. | — | — |
| `PICKED_UP` ✅ | 200 | success | Picked Up | The order has been picked up from the store. | — | — |
| `OUT_FOR_DELIVERY` ✅ | 200 | success | Out For Delivery | The order is on its way. | — | — |
| `REACHED_LOCATION` ✅ | 200 | success | Reached | The agent has reached the delivery location. | — | — |
| `DELIVERY_OTP_SENT` ✅ | 200 | success | OTP Sent | A delivery code has been sent to the customer. | — | — |
| `DELIVERY_OTP_VERIFIED` ✅ | 200 | success | OTP Verified | The delivery code was verified. | — | — |
| `DELIVERY_LOCATION_MISMATCH`  | 409 | warning | Not At Location | You must be within 50 metres of the delivery address to complete it. | — | yes |
| `MANUAL_VERIFICATION_REQUIRED`  | 423 | error | Manual Verification Needed | Too many incorrect OTP attempts — store approval is required. | `contact_support` | — |
| `DELIVERY_OTP_REQUIRED`  | 409 | warning | Verify OTP First | Verify the customer's delivery OTP before completing. | — | — |
| `DELIVERY_PHOTO_REQUIRED`  | 409 | warning | Photo Required | Capture proof-of-delivery before completing. | — | — |
| `INVALID_DELIVERY_TRANSITION`  | 409 | warning | Action Not Allowed | That delivery step can't be done from the current status. | — | — |
| `FAILED_CUSTOMER_UNREACHABLE`  | 200 | warning | Customer Unreachable | The customer could not be contacted at delivery. | — | — |
| `FAILED_ADDRESS_NOT_FOUND`  | 200 | warning | Address Not Found | The delivery address could not be located. | — | — |
| `FAILED_CUSTOMER_REJECTED`  | 200 | warning | Customer Refused | The customer refused the delivery. | — | — |
| `FAILED_SECURITY_CONCERN`  | 200 | error | Safety Issue | The delivery was stopped due to a safety concern. | `contact_support` | — |
| `REATTEMPT_SCHEDULED` ✅ | 200 | info | Re-attempt Scheduled | A new delivery attempt has been scheduled. | — | — |
| `RETURN_TO_STORE` ✅ | 200 | info | Returned To Store | The undelivered order has been returned to the store. | — | — |

## Collections

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `COLLECTION_CREATED` ✅ | 201 | success | Collection Created | The collection task has been created. | — | — |
| `COLLECTION_ASSIGNED`  | 409 | warning | Already Assigned | This recovery task is already assigned to another agent. | — | — |
| `COLLECTION_COMPLETED` ✅ | 200 | success | Payment Collected | The payment was collected successfully. | — | — |
| `COLLECTION_FAILED`  | 200 | warning | Collection Failed | The collection attempt was unsuccessful. | — | — |
| `CUSTOMER_NOT_AVAILABLE`  | 200 | warning | Customer Unavailable | The customer was unavailable for collection. | — | — |
| `PAYMENT_DISPUTE`  | 200 | warning | Dispute Raised | The customer has raised a payment dispute. | `contact_support` | — |
| `PARTIAL_PAYMENT` ✅ | 200 | info | Partial Payment | Only part of the amount was collected. | — | — |
| `RECOVERY_CLOSED` ✅ | 200 | success | Fully Recovered | The outstanding amount has been fully recovered. | — | — |
| `COLLECTION_ACCEPTED` ✅ | 200 | success | Collection Accepted | You've accepted this collection task. | — | — |
| `COLLECTION_EN_ROUTE` ✅ | 200 | success | On The Way | You're on the way to the customer. | — | — |
| `COLLECTION_REACHED` ✅ | 200 | success | Reached Customer | You've reached the customer location. | — | — |
| `COLLECTION_OTP_SENT` ✅ | 200 | success | OTP Sent | A collection code has been sent to the customer. | — | — |
| `COLLECTION_OTP_VERIFIED` ✅ | 200 | success | OTP Verified | The collection code was verified. | — | — |
| `INVALID_COLLECTION_OTP`  | 400 | warning | Wrong OTP | The collection OTP entered is incorrect. | — | yes |
| `COLLECTION_OTP_REQUIRED`  | 409 | warning | Verify OTP First | Verify the customer's OTP before recording cash. | — | — |
| `COLLECTION_OTP_LOCKED`  | 423 | error | Verification Locked | Too many incorrect OTP attempts — supervisor approval needed. | `contact_support` | — |
| `INVALID_COLLECTION_TRANSITION`  | 409 | warning | Action Not Allowed | That collection step can't be done from the current status. | — | — |
| `COLLECTION_AMOUNT_INVALID`  | 400 | warning | Invalid Amount | The amount must be greater than zero and within the due balance. | — | — |
| `COLLECTION_CANCELLED` ✅ | 200 | info | Collection Cancelled | This collection task was cancelled. | — | — |

## Inventory

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `LOW_STOCK_ALERT` ✅ | 200 | warning | Low Stock | Inventory levels are running low. | — | — |
| `CRITICAL_STOCK` ✅ | 200 | error | Critical Stock | Immediate replenishment is recommended. | — | — |
| `EXPIRY_WARNING` ✅ | 200 | warning | Expiry Approaching | This product's expiry is approaching. | — | — |
| `NEAR_EXPIRY_PRODUCT` ✅ | 200 | warning | Near Expiry | This product is approaching its expiry date. | — | — |
| `PRODUCT_EXPIRED`  | 409 | error | Expired Product | Expired products cannot be sold. | — | — |
| `BATCH_EXPIRED`  | 409 | error | Batch Expired | This batch can't be added because it's already expired. | — | — |
| `DUPLICATE_BATCH`  | 409 | warning | Batch Exists | This batch already exists. | — | — |
| `NEGATIVE_STOCK_PREVENTION`  | 409 | error | Stock Can't Go Negative | Stock cannot become negative. | — | — |
| `INVENTORY_INVOICE_MISSING`  | 400 | warning | Invoice Required | This inventory entry requires a supplier invoice. | `navigate` → `/procurement` | — |
| `STOCK_ADJUSTMENT_SUCCESS` ✅ | 200 | success | Inventory Updated | Inventory has been updated successfully. | — | — |

## Procurement

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `PURCHASE_ORDER_CREATED` ✅ | 201 | success | PO Created | Purchase order created successfully. | — | — |
| `INVOICE_UPLOADED` ✅ | 200 | success | Invoice Saved | The supplier invoice has been stored. | — | — |
| `INVOICE_REQUIRED`  | 400 | warning | Invoice Required | A supplier invoice must be uploaded. | — | — |
| `SUPPLIER_INACTIVE`  | 409 | warning | Supplier Inactive | Orders can't be created for inactive suppliers. | — | — |
| `RECEIVING_QTY_MISMATCH`  | 409 | warning | Quantity Mismatch | The received quantity differs from the purchase order. | — | — |
| `PURCHASE_CLOSED`  | 409 | info | Already Completed | This purchase order has already been completed. | — | — |

## Store Admin

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `STORE_DISABLED`  | 403 | warning | Store Inactive | This store is currently inactive. | — | — |
| `STORE_OUT_OF_STOCK`  | 409 | warning | Not In This Store | The requested quantity is unavailable in this store. | — | — |
| `MANAGER_APPROVAL_REQUIRED`  | 403 | warning | Approval Needed | This action requires store manager approval. | — | — |
| `DAILY_LIMIT_EXCEEDED`  | 429 | warning | Daily Limit Reached | The permitted daily threshold has been exceeded. | — | — |
| `STORE_INVENTORY_LOCKED`  | 423 | warning | Inventory Locked | Inventory changes are temporarily locked. | — | — |

## Employee

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `EMPLOYEE_INACTIVE`  | 403 | warning | Account Inactive | This employee account is inactive. | `contact_support` | — |
| `EMPLOYEE_NOT_AUTHORIZED`  | 403 | warning | Not Authorized | You don't have permission for this action. | — | — |
| `SHIFT_NOT_STARTED`  | 403 | warning | Start Your Shift | Start your shift before performing this action. | `navigate` → `/shift` | — |
| `SHIFT_CLOSED`  | 409 | info | Shift Closed | Your shift has already been closed. | — | — |
| `ATTENDANCE_MISSING`  | 403 | warning | Mark Attendance | Attendance must be recorded first. | `navigate` → `/attendance` | — |
| `LOCATION_OUTSIDE_STORE`  | 403 | warning | Wrong Location | You must be at your assigned store location. | — | — |

## Support / CRM

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `TICKET_CREATED` ✅ | 201 | success | Ticket Raised | Your support ticket has been created. | — | — |
| `TICKET_CLOSED`  | 409 | info | Ticket Closed | This ticket is closed. | — | — |
| `FEEDBACK_RECEIVED` ✅ | 200 | success | Thanks For Your Feedback | Your feedback has been recorded. | — | — |

## Offers / Coupons

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `COUPON_INVALID`  | 200 | warning | Invalid Coupon | This coupon code isn't valid. | — | — |
| `COUPON_EXPIRED`  | 200 | warning | Coupon Expired | This coupon has expired. | — | — |
| `COUPON_MIN_NOT_MET`  | 200 | info | Add More To Apply | Your cart doesn't meet this coupon's minimum value. | `navigate` → `/cart` | — |
| `COUPON_APPLIED` ✅ | 200 | success | Coupon Applied | Your discount has been applied. | — | — |

## Loyalty

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `INSUFFICIENT_POINTS`  | 400 | warning | Not Enough Points | You don't have enough points to redeem that amount. | — | — |
| `POINTS_REDEEMED` ✅ | 200 | success | Points Redeemed | Your points have been redeemed to your wallet. | — | — |

## Referrals

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `REFERRAL_ALREADY_APPLIED`  | 409 | info | Already Applied | You've already applied a referral code. | — | — |
| `REFERRAL_INVALID`  | 400 | warning | Invalid Code | This referral code isn't valid. | — | — |
| `REFERRAL_APPLIED` ✅ | 200 | success | Referral Applied | Your referral reward is on the way. | — | — |

## Returns

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `RETURN_WINDOW_CLOSED`  | 409 | warning | Return Window Closed | The return window for this order has closed. | — | — |
| `RETURN_NOT_ELIGIBLE`  | 409 | warning | Not Returnable | This order isn't eligible for return. | — | — |
| `RETURN_CREATED` ✅ | 201 | success | Return Requested | Your return request has been created. | — | — |

## Subscriptions

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `SUBSCRIPTION_CREATED` ✅ | 201 | success | Subscription Active | Your subscription is active. | — | — |
| `SUBSCRIPTION_UPDATED` ✅ | 200 | success | Subscription Updated | Your subscription has been updated. | — | — |

## Reporting

| Code | HTTP | Severity | Title | Message | Action | Retry |
|------|------|----------|-------|---------|--------|-------|
| `REPORT_GENERATING` ✅ | 202 | info | Preparing Report | Your report is being generated. | — | — |
| `REPORT_EMPTY` ✅ | 200 | info | No Data | There's no data for the selected filters. | — | — |
