plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.verspaetomat.verspaetomat"
    compileSdk = 37 // flutter_secure_storage 10 compiles against API 37; Flutter's default is lower
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.verspaetomat.verspaetomat"
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

flutter {
    source = "../.."
}

dependencies {
    // Station geofences and one-shot fixes for the nudge (docs/15).
    implementation("com.google.android.gms:play-services-location:21.3.0")
    // NotificationCompat / ContextCompat for the nudge notification.
    implementation("androidx.core:core:1.16.0")
    // The first tests this module has had (issue #40). Plain JVM, no Robolectric: `StationExtract`
    // takes a `File` and imports nothing from `android.*`, which is what keeps them that way.
    testImplementation("junit:junit:4.13.2")
}

// Deliberately NO `testOptions { unitTests.isReturnDefaultValues = true }`. The reader and the scan
// import nothing from `android.*`; leaving the framework stubs throwing is what keeps it that way,
// because an accidental `Log` or `Location.distanceBetween` then fails the test loudly instead of
// quietly returning 0.
tasks.withType<Test>().configureEach {
    // `rootProject.projectDir` is app/android, so its grandparent is the repository root. The
    // parity suite reads the shipped extract and the shared probe fixture from there.
    val repo = rootProject.projectDir.parentFile.parentFile
    systemProperty("verspaetomat.repo", repo.absolutePath)
    // An override for the probe fixture, so a freshly generated one can be tried before it lands.
    System.getProperty("verspaetomat.probes")?.let { systemProperty("verspaetomat.probes", it) }
    // Both are read by the parity suite and neither is on the compile classpath, so without this
    // a new extract or a regenerated fixture leaves the task UP-TO-DATE and the suite passes on
    // last week's answer.
    inputs.files(
        repo.resolve("app/assets/stations/stations.vst"),
        repo.resolve("testdata/stations/nearby-probes.tsv"),
    ).withPropertyName("stationParityFixtures").withPathSensitivity(PathSensitivity.NONE).optional(true)
    testLogging { events("passed", "skipped", "failed") }
}
