plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.android.libraries.mapsplatform.secrets-gradle-plugin")
    // DRIVER-PUSH-R1: procesa android/app/google-services.json (archivo
    // real fuera de git, ver README / android/app/google-services.json.example).
    id("com.google.gms.google-services")
}

// Google Maps API key injection.
//
// Real key: android/secrets.properties (gitignored, developer-local, never committed).
// Fallback used by CI/other developers when secrets.properties is absent:
// android/local.defaults.properties (versioned, contains only a placeholder).
secrets {
    propertiesFileName = "secrets.properties"
    defaultPropertiesFileName = "local.defaults.properties"
}

android {
    namespace = "pe.tukituki.driver"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // DRIVER-PUSH-R1 (Etapa 2): flutter_local_notifications usa
        // APIs de java.time; el desugaring las hace disponibles en
        // minSdk < 26.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pe.tukituki.driver"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // DRIVER-PUSH-R1 (Etapa 2): requerido por flutter_local_notifications
    // junto con isCoreLibraryDesugaringEnabled. Si el build de AGP pide
    // otra versión, ajustar a la que indique el error.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
