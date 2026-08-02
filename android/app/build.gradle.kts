plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Firebase / Google services plugin (reads google-services.json).
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.arena.os"
    // compileSdk 36 required by flutter_secure_storage 10 / shared_preferences /
    // sqflite / url_launcher (newer plugins). Backward compatible with our
    // minSdk = 24 / targetSdk = 34.
    compileSdk = 36
    // NDK 28.2.13676358 is what jni 1.x ships with. Pre-installed via
    // `sdkmanager "ndk;28.2.13676358"` to avoid silent multi-hour downloads.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires Java 8+ APIs to work on
        // older Android versions — desugaring backports them.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Arena OS — locked package id per master prompt
        applicationId = "com.arena.os"
        // Android 7.0+ (per master prompt)
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    kotlinOptions {
        jvmTarget = "17"
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

dependencies {
    // Required by isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
