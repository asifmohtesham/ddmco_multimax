pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.1" apply false
    // Never applied (AGP 9 built-in Kotlin compiles Kotlin itself), but it pins the
    // Kotlin Gradle plugin version that built-in Kotlin uses in the app and every
    // plugin module. Without it the build silently falls back to an older KGP
    // (2.4.10 with Flutter 3.50; AGP 9.3.1 itself only requires 2.2.10).
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
    // Reads android/app/google-services.json (Firebase Cloud Messaging).
    id("com.google.gms.google-services") version "4.6.0" apply false
}

include(":app")
