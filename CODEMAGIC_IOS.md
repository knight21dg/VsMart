# VS Mart — iOS to TestFlight / App Store via Codemagic (no Mac needed)

App: **VS Mart** customer app · Bundle ID: **`com.vsmart.userApp`** · Repo: `knight21dg/VsMart` (the `codemagic.yaml` is at the repo root).

> Good news: the app's Firebase init is **fail-soft**, so the iOS build needs **no `GoogleService-Info.plist`** and **no push entitlement** to build/run on TestFlight. (Add those later only when you want iOS push/analytics.)

---

## Step 1 — Apple side (one-time)
1. **Apple Developer → Certificates, IDs & Profiles → Identifiers → +** → App IDs → App → Bundle ID **`com.vsmart.userApp`**. (Enable *Push Notifications* now if you want — optional.)
2. **App Store Connect → My Apps → +** → New App:
   - Platform **iOS**, name **VS Mart**, primary language **English (India)**, Bundle ID `com.vsmart.userApp`, SKU `vsmart-customer`.
   - Note the app's **Apple ID** (a number on the App Information page).
3. **App Store Connect → Users and Access → Integrations → App Store Connect API → Generate API Key**:
   - Access: **App Manager**. Download the **`.p8`** (one-time!) and note the **Issuer ID** and **Key ID**.

## Step 2 — Codemagic (one-time)
1. Sign up at **codemagic.io** with your GitHub → authorize → **Add application** → pick **`knight21dg/VsMart`** → it detects `codemagic.yaml`.
2. **Teams → Integrations → App Store Connect → Connect**:
   - Paste **Issuer ID**, **Key ID**, upload the **`.p8`**. Name the key exactly **`VSMart ASC`** (this matches `integrations.app_store_connect` in `codemagic.yaml` — or rename both to match).
3. (Optional, for iOS maps) **Environment variables** → group **`vsmart`** → add **`GMS_API_KEY_IOS`** = your iOS-restricted Google Maps key (restrict it to bundle `com.vsmart.userApp` in Google Cloud). Mark it secure.

## Step 3 — Build & ship to TestFlight
1. In Codemagic → the **`ios-testflight`** workflow → **Start new build**.
2. Codemagic spins up a Mac, **auto-creates the signing certificate + provisioning profile** (via your API key), builds the **signed IPA**, and **uploads it to TestFlight**.
3. In **App Store Connect → TestFlight**: the build appears (processing ~5–15 min). Add it to a tester group (Internal Testing → add your testers by email). They install **TestFlight** app → accept invite → run VS Mart.
   - First build asks export-compliance — already handled (`ITSAppUsesNonExemptEncryption=false`).

## Step 4 — App Store submission (when ready for public)
In App Store Connect, complete:
- **App Privacy** (data collection) — mirror the Play "Data safety" answers (in `PLAY_CONSOLE_VSMART.md`).
- **Age rating**, **category** (Shopping), **screenshots** (6.7" + 5.5" required), description, keywords.
- **Privacy Policy URL** `https://thevsmart.com/privacy`, **Support URL** `https://thevsmart.com`.
- ⚠️ **Financial/credit (BNPL):** Apple, like Google, scrutinises lending apps — be ready to show your **lending partner / regulated entity** details. Add `https://thevsmart.com/terms` + the lender disclosure.
- Attach the TestFlight build → **Submit for Review**.

---

### Notes
- Demo review login (App access / reviewer notes): phone **`9000000007`**, OTP **`123456`**.
- Versioning: each TestFlight/App Store upload needs a higher build number — bump `version:` in `pubspec.yaml` (now `1.0.0+2`) and push; Codemagic uses it.
- The same `codemagic.yaml` can later gain an Android workflow too, but Android is already covered by the GitHub Actions build + your signed AAB.
- If a build fails, open the Codemagic build log — the `xcodebuild_logs` artifact has the detail.
