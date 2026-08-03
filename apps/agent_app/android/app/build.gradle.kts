import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Maps API key — read from local.properties (dev, git-ignored) or the
// MAPS_API_KEY env var (CI secret). Kept OUT of source control. Injected into
// AndroidManifest via the ${MAPS_API_KEY} placeholder.
val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val mapsApiKey: String = (localProperties.getProperty("MAPS_API_KEY")
    ?: System.getenv("MAPS_API_KEY") ?: "").ifBlank { "MISSING_MAPS_API_KEY" }

android {
    namespace = "com.vsmart.agent.agent_app"
    compileSdk = flutter.compileSdkVersion
    // Pinned: several plugins (secure_storage, geolocator, image_picker, firebase)
    // require this NDK; it is backward-compatible with the Flutter default.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications (FCM branded channels) needs the Java 8+
        // desugared APIs (java.time etc.) on minSdk 23.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vsmart.agent.agent_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase (firebase-messaging 15.x) requires minSdk 23, above Flutter's
        // default of 21.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Inject the Google Maps key into AndroidManifest's ${MAPS_API_KEY} placeholder.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Firebase config binding. The google-services plugin fails the build if it can't
// find android/app/google-services.json, so apply it ONLY when that file is
// present. This keeps the app buildable today (Firebase config not yet dropped in
// → push is a clean no-op) and makes it wire up automatically the moment ops adds
// the JSON — no further Gradle edits needed.
if (rootProject.file("app/google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
