# Deep links (Android App Links / iOS Universal Links)

A shared product link — `https://thevsmart.com/products/<shareToken>` — opens the
product **in the app** when it's installed, and falls back to the landing site's
product page when it isn't.

## How a link travels

```
share sheet  →  https://thevsmart.com/products/<shareToken>
                        │
      ┌─────────────────┴─────────────────┐
   app installed                    app not installed
      │                                   │
   OS verifies domain              Next.js /products/[id]
   (assetlinks.json / AASA)        renders the product page
      │                            + Play Store button
   app_links → DeepLinkController
      │
   resolveDeepLink() allowlist  →  parked in PendingDeepLink
      │
   go_router redirect consumes it once every gate has passed
      │
   ProductDetailScreen  (backend resolves the share token)
```

The token, not the sequential id, is what travels — see
`catalog.models.Product.share_token`. A store-private product is therefore
shareable by link while its numeric id stays unguessable.

## Why the link is parked instead of navigated to

Handing an incoming link straight to the router loses it. Three gates in
`app_router.dart` would each discard it:

1. **Splash hold** — for `AppConstants.splashDuration` every location is rewritten
   to `/splash`, then replaced by a lifecycle landing route.
2. **Auth gate** — an unauthenticated non-guest is sent to `/login` from anywhere.
3. **Serviceability gate** — on a fresh install, while the first GPS verdict
   resolves, non-exempt routes are forced to `/not-serviceable`.

So `DeepLinkController` parks the path in `PendingDeepLink`, and the redirect
takes it at the single point where all gates have already allowed the current
location. A link therefore survives a cold start, onboarding and a sign-in.

`PendingDeepLink.take()` clears on the first attempt, deliberately: a link whose
target a gate still rejects shows the gate screen rather than ping-ponging until
go_router's redirect limit trips.

## Security

`resolveDeepLink` (`lib/core/services/deep_link.dart`) is an **allowlist**, not a
URL translator. A deep link is untrusted input — anyone can send one.

- Host must be `thevsmart.com` / `www.thevsmart.com`, scheme `https` (or the
  unverified `vsmart://` custom scheme, same allowlist).
- Only `/products/<id>` and its legacy `/product/<id>` alias are accepted.
- Exactly one path segment; encoded separators and `..` are rejected, and the
  identifier is re-encoded so it can't split into a second segment.

Anything else returns null and the app opens normally. This mirrors the `://`
rejection in `resolveNotificationPath`, which guards the push channel — do not
relax either.

Covered by `test/core/deep_link_test.dart` (lookalike hosts, unpublished
sections, smuggled separators, duplicate delivery).

## Activation checklist

The code is complete on both platforms. Two values are required to switch
verification on, and neither exists in the repo.

### Android

1. Get the **app-signing** SHA-256 from
   Play Console → Test and release → Setup → App integrity →
   *App signing key certificate*.

   ⚠️ Not the upload key. `PLAY_CONSOLE_VSMART.md` documents the **upload**
   fingerprint (`DA:5A:BA:…`); with Play App Signing, Google re-signs the
   artifact, so using that value makes verification fail on every installed build.
   List both if you also want locally-installed release builds to verify.

2. Set it on the landing service and restart:

   ```bash
   # /opt/vsmart/.env
   ANDROID_SHA256_CERT_FINGERPRINTS="<play app-signing SHA-256>,<upload SHA-256>"
   docker compose up -d landing
   ```

3. Verify:

   ```bash
   curl -sS https://thevsmart.com/.well-known/assetlinks.json
   adb shell pm get-app-links com.vsmart.user_app     # expect: verified
   adb shell am start -a android.intent.action.VIEW \
     -d "https://thevsmart.com/products/<shareToken>"
   ```

   Domain verification runs at **install** time. After changing the file,
   reinstall the app (or `adb shell pm verify-app-links --re-verify <pkg>`).

### iOS — blocked on an Apple Team ID

`DEVELOPMENT_TEAM` is set nowhere in the project (Codemagic signs via an App
Store Connect API key, which never writes it in). Get the Team ID from
developer.apple.com → Membership, then:

1. `APPLE_APP_ID="<TeamID>.com.vsmart.userApp"` on the landing service.
2. In Xcode: Runner target → Signing & Capabilities → select the Team →
   **+ Capability → Associated Domains**. That links
   `ios/Runner/Runner.entitlements` (already written, with
   `applinks:thevsmart.com`) and sets `CODE_SIGN_ENTITLEMENTS` for every build
   configuration. This step is manual on purpose — hand-editing
   `project.pbxproj` can't be built or verified from a non-Mac machine.
3. Commit the resulting `project.pbxproj` change.
4. Verify: `curl -sSI https://thevsmart.com/.well-known/apple-app-site-association`
   must return `Content-Type: application/json`.

Both endpoints return **404 with an explanatory message** until configured, so an
unset value is obvious rather than silently serving a file that never verifies.

## Gotchas

- **Bundle ids differ by platform**: Android `com.vsmart.user_app`, iOS
  `com.vsmart.userApp`. Not a bug, but the AASA `appIDs` uses the iOS one.
- **The landing image has no volume mount.** Its `public/` is baked in at build
  time — but these are Route Handlers reading env per request, so a fingerprint
  change needs only `docker compose up -d landing`, not a rebuild.
- **`.well-known` must be Route Handlers, not `public/`.** The AASA file has no
  extension; static serving would return `application/octet-stream` and Apple
  rejects it.
- **Adding a new link shape means changing three places**: the allowlist in
  `deep_link.dart`, the Android `pathPrefix` filters, and the AASA `components`.
- Android `pathPrefix` is scoped to `/products/` and `/product/` so marketing
  pages, `/privacy` and `/terms` keep opening in the browser.
