import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release signing identity, read from `android/key.properties`.
//
// THAT FILE IS NEVER COMMITTED and neither is the keystore it points at — both
// are in `.gitignore` twice over, and `just constitution`'s `tracked_secrets`
// rule fails the build if either is ever staged. A signing key in the history
// is a key that has to be replaced, and replacing it means every install that
// already exists can no longer be upgraded.
//
// ABSENT, A RELEASE BUILD FAILS. It does not fall back to the debug key: the
// whole defect this replaces was an artefact that looked signed, installed
// fine, and carried `CN=Android Debug` — nobody re-reads a build file to
// discover that, and a fallback would reintroduce it silently the first time a
// checkout lacked the file. Debug builds and `flutter run` are untouched, so a
// clean checkout still develops without a keystore.
val keystoreFile = rootProject.file("key.properties")
val keystore = Properties().apply {
    if (keystoreFile.exists()) keystoreFile.inputStream().use(::load)
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

    signingConfigs {
        if (keystoreFile.exists()) {
            create("release") {
                storeFile = file(keystore.getProperty("storeFile"))
                storePassword = keystore.getProperty("storePassword")
                keyAlias = keystore.getProperty("keyAlias")
                keyPassword = keystore.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Null when there is no keystore, which leaves the artefact
            // UNSIGNED rather than debug-signed — an unsigned APK refuses to
            // install, so the failure is visible at the point of use even if
            // the guard below is somehow bypassed. The guard is what makes it
            // visible earlier and with an explanation.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// Refuse to assemble a release the keystore cannot sign.
//
// Checked on the task graph rather than at configuration time: throwing while
// the `signingConfigs` block is evaluated would fail EVERY gradle invocation,
// including the debug builds a keystore has nothing to do with.
if (!keystoreFile.exists()) {
    gradle.taskGraph.whenReady {
        val releasing = allTasks.any {
            it.name.contains("Release") &&
                (it.name.startsWith("assemble") || it.name.startsWith("bundle"))
        }
        if (releasing) {
            throw GradleException(
                "No android/key.properties — a release build would be " +
                    "unsigned. See docs/release-signing.md; debug builds and " +
                    "`flutter run` do not need it.",
            )
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
