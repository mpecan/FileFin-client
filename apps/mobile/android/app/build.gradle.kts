plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.filefin.filefin_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.filefin.filefin_mobile"
        // SPEC.md C5: Android 8. Written as a literal rather than
        // `flutter.minSdkVersion`, which is 24 on this SDK — a floor that moves
        // when Flutter moves is not a constraint, and C5 is a decision (D7).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug keys. C6 makes distribution a direct APK rather than a
            // store upload, so there is no release keystore yet and inventing
            // one before there is a release to sign is a §1 violation. The
            // milestone that ships an artefact owns this line.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
