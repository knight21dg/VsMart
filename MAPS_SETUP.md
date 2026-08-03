# Google Maps — key wiring

VS Mart uses Google Maps in several places. **Client requirement: ONE key for
everything** (server + apps + admin). That is what is currently wired and deployed:

```
AIzaSyAVbIGw…Qtoc   ← the single VS Mart Google Maps key
```

Enable these APIs on the Google Cloud project, or the matching surface goes blank:

| API to enable | Needed by |
|---|---|
| **Maps SDK for Android** | Customer app pin picker + agent app route map |
| **Maps SDK for iOS** | Customer app (only if you ship iOS) |
| **Maps JavaScript API** | Admin console (zone polygon draw, store location, fleet map) |
| **Geocoding API** | Backend `/geo/reverse` (reverse-geocode the dropped pin) |
| **Places API (New)** | Backend `/geo/places/*` (search autocomplete + detail) |

## Where the one key goes

| Surface | Paste it into |
|---|---|
| **Backend** (`/geo` proxy) | Super-admin panel → Integration Settings → `google_maps_key` (overrides env, no redeploy) *or* `apps/backend/.env` → `GOOGLE_MAPS_API_KEY` |
| **Admin console** | Root `.env` → `ADMIN_MAPS_KEY` (compose passes it in as `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY`; inlined at **build** time → rebuild the admin image after changing it) |
| **Customer app** (Android, map tiles) | `apps/user_app/android/local.properties` → `MAPS_API_KEY=...` (gitignored; CI/release via the `MAPS_API_KEY` env var) |
| **Customer app** (iOS, map tiles) | `apps/user_app/ios/Runner/Info.plist` → `GMSApiKey` |
| **Customer app** (Dart — Places search) | `--dart-define=MAPS_API_KEY=...` at build time (see below) |

### The app needs the key TWICE

The native copy (manifest / Info.plist) only renders **map tiles**. The app also
calls **Places API (New) directly from the device** for location search, and Dart
can't read the native manifest — so the key must ALSO be passed as a dart-define:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.thevsmart.com/api/v1 \
  --dart-define=FLAVOR=prod \
  --dart-define=MAPS_API_KEY=<the one key>
```

Why direct instead of the backend `/geo` proxy: the key is unrestricted and already
ships inside the APK, so proxying protected nothing — while costing a hop and, worse,
requiring auth (`/geo/*` is login-only), which broke search on the pre-login
serviceability lock screen. Omitting the define is safe: the Places client falls
back to the `/geo` proxy automatically (login-only, as before).
| **Agent app** (Android) | `apps/agent_app/android/local.properties` → `MAPS_API_KEY=...` — **set 2026-07-21** to the same key as the customer app; verified present in the merged manifest via `flutter build apk --debug`. No Cloud Console change was needed because the key is unrestricted (see the restriction rule below). |

## The restriction rule (important)

Google allows only **ONE Application restriction per key**, but our surfaces each
need a *different* kind:

- server → IP restriction
- Android app → package + SHA-1
- browser (admin) → HTTP referrer

These are mutually exclusive, so a **single shared key MUST use
Application restriction = "None"**. Setting it to IP / referrer / Android would
break the other surfaces.

*Verified 2026-07-17:* the live key answers Geocoding, Places (New) and Maps JS
from the VPS **and** from unrelated IPs — i.e. it is already unrestricted, which is
why one key works everywhere (Android included).

**Because an unrestricted key is effectively public** — it ships inside the APK and
the admin's JS bundle and can be scraped — compensate with the two levers that
still apply when Application restrictions are "None":

1. **API restrictions** — on the key, restrict it to *only* the APIs listed above.
   This is allowed alongside "Application restrictions: None" and blocks abuse of
   every other Google API.
2. **Quotas + budget alerts** — Cloud Console → APIs & Services → Quotas: cap
   requests/day per API, and set a billing budget alert. This bounds the cost if
   the key leaks.

If the one-key rule is ever relaxed, split it (app key = Android/iOS restricted,
server key = IP restricted, browser key = referrer restricted). The code already
reads each surface's key from its own place, so that would be a config-only change.

## Notes

- Every surface is **already wired** — you only paste values. Android reads
  `MAPS_API_KEY` (build.gradle.kts → `${MAPS_API_KEY}` manifest placeholder; falls
  back to the literal `MISSING_MAPS_API_KEY`, which renders a blank map), iOS reads
  `GMSApiKey`.
- Missing key degrades gracefully: the admin shows a "Map key not configured"
  placeholder (coordinates still enterable) and the app's Places search /
  reverse-geocode fall back quietly.
- After changing the key: rebuild the app (`flutter build apk`), **rebuild** the
  admin image (the key is inlined at build time), and for the backend just save it
  in the super-admin panel (or restart if using env).
