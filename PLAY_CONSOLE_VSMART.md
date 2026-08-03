# VS Mart — Customer App: Play Console field values (Internal Testing)

App: **VS Mart** (customer/shopper app) · Package: **`com.vsmart.user_app`**

---

## 0. Before you upload — Play App Signing
When you upload the first AAB, Google offers **Play App Signing** (accept it).
- **Upload key** = the keystore I generated (`android/app/upload-keystore.jks`).
- Upload-key fingerprints (Play Console → Setup → App integrity → *Upload key certificate*):
  - **SHA-1:** `0A:AA:A8:1B:DB:D5:67:3F:AD:1D:41:DB:5D:59:C9:33:E8:90:37:5D`
  - **SHA-256:** `DA:5A:BA:2D:94:46:11:EA:C9:66:AF:65:64:DB:A0:19:DD:AA:B8:2A:E1:55:40:A8:AF:8B:87:9B:62:A1:4F:BA`
- ⚠️ Keep `upload-keystore.jks` + its password safe (password: `VsMart#Upload2026`, alias `upload`). It is **git-ignored** (never pushed).

---

## 1. Create app
| Field | Value |
|---|---|
| App name | **VS Mart** |
| Default language | **English (India) – en-IN** |
| App or game | **App** |
| Free or paid | **Free** |
| Declarations | Tick the Developer Program Policies + US export laws boxes |

## 2. Internal testing track
- **Testing → Internal testing → Create new release**.
- Upload the **AAB** (`app-release.aab`).
- **Release name:** `1.0.0 (1) – internal` (auto-fills from the bundle).
- **Release notes:** `Initial internal test build of VS Mart customer app.`
- **Testers:** create an email list (your testers' Gmail addresses) → save → **copy the opt-in URL** and share with testers.

## 3. App access (IMPORTANT — app needs login)
The app requires OTP login, so give Google a way in:
- Choose **"All or some functionality is restricted"** → add an instruction:
  - **Name:** Demo login
  - **Username/phone:** `9000000007`
  - **OTP / password:** `123456`
  - **Instructions:** "Enter phone `9000000007`, tap Continue, then enter OTP `123456` to sign in. Browse products, add to cart, view VS Credit."

## 4. Store listing (Main store listing)
| Field | Value |
|---|---|
| App name | VS Mart |
| Short description (≤80) | `Order groceries & essentials now, pay later — weekly or monthly with VS Credit.` |
| Full description | see block below |
| App icon | **512×512 PNG** (use `apps/vsmartlanding/public/assets/vsmart-appicon.png`, resized to 512²) |
| Feature graphic | **1024×500 PNG** (banner) — required |
| Phone screenshots | **2–8**, PNG/JPG, 16:9 or 9:16, min 320 px side (capture from the app) |
| App category | **Shopping** |
| Tags | grocery, shopping, buy now pay later, credit |
| Contact email | `knight21digihub@gmail.com` |
| Website | `https://thevsmart.com` |
| **Privacy policy URL** | `https://thevsmart.com/privacy` |

**Full description (paste):**
> VS Mart is your neighbourhood grocery and essentials store with the freedom to pay later. Shop fresh groceries, household items and daily needs, and settle your bill at the end of the week or month with VS Credit — no need to pay upfront for every order.
>
> • Shop thousands of products with fast local delivery
> • VS Credit — buy now, pay later; clear your balance weekly or monthly
> • Live order tracking to your doorstep
> • Secure payments and simple KYC
> • Reorder favourites in a tap
>
> VS Credit is offered in partnership with a regulated lending partner. Download VS Mart and shop smarter.

## 5. Content rating (questionnaire)
- **Category:** *Shopping / e-commerce* (it's not a game).
- Violence / sexual / language / controlled substances → **No** to all.
- Does the app share user location? **Yes** (delivery). Digital purchases? **Yes** (groceries).
- Result will be **Everyone / PEGI 3** (rated after you submit answers).
- Email for the certificate: `knight21digihub@gmail.com`.

## 6. Target audience & content
- **Target age:** **18+** (financial/credit product — keep it adults-only).
- Appeals to children? **No**.

## 7. Ads
- **Does your app contain ads?** **No**.

## 8. Data safety (Data safety form)
Encryption in transit: **Yes (HTTPS)**. Users can request deletion: **Yes → `https://thevsmart.com/delete-account`**.

| Data type | Collected | Shared | Purpose | Required |
|---|---|---|---|---|
| Name | Yes | No | Account management | Yes |
| Email | Yes | No | Account management | Optional |
| Phone number | Yes | No | Account, OTP login | Yes |
| Address | Yes | Yes (delivery agent) | Order delivery | Yes |
| Approx + precise location | Yes | No | Delivery / serviceability / maps | Optional |
| Purchase history | Yes | No | App functionality | Yes |
| Credit info (BNPL) | Yes | Yes (lending partner) | Provide credit | Optional |
| Payment info | Yes | Yes (payment processor – Razorpay) | Process payments | Optional |
| Photos (KYC docs, delivery proof) | Yes | No | Identity verification | Optional |
| App activity / interactions | Yes | No | Analytics, app functionality | No |
| Device / FCM ID | Yes | No | Push notifications | No |

(Card numbers are handled by the payment processor — the app does **not** store them.)

## 9. ⚠️ Financial features declaration (READ THIS)
VS Mart offers **BNPL / credit**, so in **Policy → App content → Financial features** you must declare it:
- Tick **"My app provides … credit / loans"** (Buy-Now-Pay-Later).
- India **Personal Loan App** rules apply for production: you'll need to provide your **lending partner's** name + their RBI registration / NBFC details (VS Mart uses a regulated lending-partner model, not its own books).
- For **internal testing** you can usually proceed, but plan to complete this with your lending-partner docs **before production**. Have those ready.

## 10. Other "App content" declarations
- Government app? **No.** · COVID-19 contact tracing? **No.** · News app? **No.**
- Privacy policy: `https://thevsmart.com/privacy` (also link Terms `https://thevsmart.com/terms`).
- Account deletion URL (Play requires it for apps with accounts): `https://thevsmart.com/delete-account`.

---

### Quick checklist to publish internal test
1. Accept Play App Signing → upload AAB.
2. Fill App access (demo login above).
3. Complete Content rating + Data safety + Target audience + Ads + Financial features.
4. Main store listing (icon, feature graphic, 2+ screenshots, descriptions).
5. Internal testing → add testers → roll out → share opt-in link.
