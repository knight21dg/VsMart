# VS Mart — Customer App

Grocery Commerce + Credit Ecosystem. Flutter (Material 3) customer application
built with **Clean Architecture** + **Feature-First** structure.

> Status: **Architecture foundation complete.** UI screens are built
> screen-by-screen from Figma. Routes not yet designed render a `PendingScreen`
> placeholder so the full navigation graph stays runnable.

## Build (Android & iOS)

```bash
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://api.thevsmart.com/api/v1
flutter build ios --release --dart-define=API_BASE_URL=https://api.thevsmart.com/api/v1   # macOS + Xcode
```

**Google Maps key** is NOT committed. For local Android builds add it to the
git-ignored `android/local.properties`: `MAPS_API_KEY=your_key`. CI reads it from
the `MAPS_API_KEY` GitHub Actions **secret**.

**CI / server build:** `.github/workflows/build.yml` builds the Android APK and an
unsigned iOS app on every push to `main`; artifacts attach to the run. Set the repo
secret `MAPS_API_KEY`. For signed iOS/TestFlight, add Apple signing secrets and use
`flutter build ipa`.

## Tech stack

| Concern         | Package |
|-----------------|---------|
| State           | `flutter_riverpod` (+ `riverpod_generator`) |
| Routing         | `go_router` (StatefulShellRoute for tabs) |
| Networking      | `dio` (+ `pretty_dio_logger`, `connectivity_plus`) |
| Models          | `freezed`, `json_serializable` |
| Local storage   | `hive`, `flutter_secure_storage`, `shared_preferences` |
| Backend         | `firebase_core/auth/messaging`, `cloud_firestore` |
| Media           | `cached_network_image`, `google_fonts`, `shimmer`, `lottie`, `flutter_svg` |
| Device          | `geolocator`, `image_picker`, `permission_handler` |
| FP / utils      | `dartz`, `equatable`, `intl`, `logger` |

## Project structure

```
lib/
├── app/                 # App-level concerns
│   ├── config/          # AppConfig (flavors, base URLs via --dart-define)
│   ├── constants/       # App / API / asset / storage-key constants
│   ├── routes/          # GoRouter, route paths+names, AppShell
│   ├── theme/           # Design system (colors, type, spacing, theme, ext.)
│   └── app.dart         # MaterialApp.router root
├── core/                # Cross-cutting infrastructure
│   ├── network/         # ApiClient, interceptors, ApiResponse, pagination
│   ├── storage/         # Hive, secure, token, user, cart, cache
│   ├── services/        # Firebase, notifications (FCM), location
│   ├── widgets/         # VS* reusable component library
│   ├── errors/          # Failures, exceptions, ErrorHandler
│   ├── extensions/      # context / string / num / datetime
│   └── utils/           # UseCase base, validators, formatters, logger
├── features/<feature>/  # 18 features, each:
│   ├── data/            # models · datasources · repositories (impl)
│   ├── domain/          # entities · repositories (abstract) · usecases
│   └── presentation/    # screens · widgets · providers
├── shared/              # Cross-feature widgets, models, providers
└── main.dart            # Bootstrap (config → Hive → Firebase → runApp)
```

Features: `auth, onboarding, home, categories, products, search, offers,
wishlist, cart, checkout, orders, credit, payments, profile, addresses,
notifications, support, settings`.

## Architecture rules

- **Dependency direction:** `presentation → domain ← data`. The domain layer is
  pure Dart (entities, abstract repositories, use cases) and depends on nothing
  Flutter-specific.
- **Errors:** data sources throw; repositories wrap calls in `BaseRepository.guard`
  and return `Either<Failure, T>` (dartz). UI handles `Failure` without try/catch.
- **DI:** Riverpod providers compose the graph (see `shared/providers/core_providers.dart`
  and each feature's `*_provider.dart`).
- **Design system:** never hard-code colors/sizes — use `AppColors`, `AppSpacing`,
  `AppRadius`, `AppTypography`, `AppShadows`, or `context.vsColors` (theme extension).

## Getting started

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generate *.freezed/.g.dart
flutter run --dart-define=API_BASE_URL=https://dev-api.vsmart.app/api/v1
```

### Firebase setup (required before release)

Bootstrap is **fail-soft** — the app runs without Firebase configured. To enable
Auth/Messaging/Firestore:

```bash
dart pub global activate flutterfire_cli
flutterfire configure        # generates lib/firebase_options.dart
```

Then pass the options in `main.dart`:

```dart
await FirebaseService.init(options: DefaultFirebaseOptions.currentPlatform);
```

## Code generation

Run after editing any `@freezed` / `@JsonSerializable` model:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

## Component library (`core/widgets`)

Buttons (`VSButton`, `VSOutlinedButton`, `VSIconButton`), inputs (`VSTextField`,
`VSPhoneField`, `VSOTPField`, `VSSearchField`), cards (`VSProductCard`,
`VSCategoryCard`, `VSOfferCard`, `VSOrderCard`, `VSCreditCard`, `VSAddressCard`),
and shell/state widgets (`VSAppBar`, `VSBottomNavigation`, `VSStatusChip`,
`VSLoadingView`, `VSErrorView`, `VSEmptyState`, `VSNetworkImage`, `VSShimmer`).
Import via `package:user_app/core/widgets/widgets.dart`.
