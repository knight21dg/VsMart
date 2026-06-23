import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Maps API key — read from local.properties (dev, git-ignored) or the
// MAPS_API_KEY env var (CI secret). Kept OUT of source control so the public repo
// carries no key. Injected into AndroidManifest via the ${MAPS_API_KEY} placeholder.
val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val mapsApiKey: String = (localProperties.getProperty("MAPS_API_KEY")
    ?: System.getenv("MAPS_API_KEY") ?: "").ifBlank { "MISSING_MAPS_API_KEY" }

android {
    namespace = "com.vsmart.user_app"
    compileSdk = flutter.compileSdkVersion
    // Pinned: several plugins (secure_storage, geolocator, image_picker, etc.)
    // require this NDK; it is backward-compatible with the Flutter default.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vsmart.user_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase Auth 23.x requires minSdk 23, above Flutter's default of 21.
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
