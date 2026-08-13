plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release signing identity, from the ENVIRONMENT rather than from a file.
//
// The passwords live in 1Password and are injected for the length of one
// command by `op run` (`just release-apk`), so there is no
// `android/key.properties` and never was one holding a real password. A
// plaintext file is a file that gets backed up, synced, and grepped; an
// environment variable dies with the process.
//
// The KEYSTORE itself is unavoidably a file — Android's signing config takes a
// path — so `just release-apk` writes it to a 0700 temp directory, builds, and
// removes it on exit. `FILEFIN_STORE_FILE` is that path. Nothing here is
// tracked by git and `just constitution`'s `tracked_secrets` rule fails on a
// staged keystore.
//
// ABSENT, A RELEASE BUILD FAILS. It does not fall back to the debug key: the
// defect this replaces was an artefact that looked signed, installed fine, and
// carried `CN=Android Debug` — nobody re-reads a build file to discover that,
// and a fallback would reintroduce it silently the first time the environment
// was not set. Debug builds and `flutter run` are untouched, so a clean
// checkout still develops with no key at all.
val signingEnv = listOf(
    "FILEFIN_STORE_FILE",
    "FILEFIN_STORE_PASSWORD",
    "FILEFIN_KEY_ALIAS",
    "FILEFIN_KEY_PASSWORD",
).associateWith(System::getenv)
val canSign = signingEnv.values.all { !it.isNullOrEmpty() }

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
        if (canSign) {
            create("release") {
                storeFile = file(signingEnv["FILEFIN_STORE_FILE"]!!)
                storePassword = signingEnv["FILEFIN_STORE_PASSWORD"]
                keyAlias = signingEnv["FILEFIN_KEY_ALIAS"]
                keyPassword = signingEnv["FILEFIN_KEY_PASSWORD"]
            }
        }
    }

    buildTypes {
        release {
            // Null when the environment is unset, which leaves the artefact
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
if (!canSign) {
    val missing = signingEnv.filterValues { it.isNullOrEmpty() }.keys
    gradle.taskGraph.whenReady {
        val releasing = allTasks.any {
            it.name.contains("Release") &&
                (it.name.startsWith("assemble") || it.name.startsWith("bundle"))
        }
        if (releasing) {
            throw GradleException(
                "Release signing is not configured: ${missing.joinToString(", ")} " +
                    "unset. Build with `just release-apk`, which fetches the key " +
                    "from 1Password for one command. See docs/release-signing.md; " +
                    "debug builds and `flutter run` need none of this.",
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
