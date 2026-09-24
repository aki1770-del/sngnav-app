import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (see BETA_PLAN.md): reads android/key.properties when present
// (keystore + key.properties are the maintainer's secrets, NEVER committed —
// key.properties is gitignored). Absent the file, release falls back to
// debug keys so `flutter run --release` keeps working for development.
// BIS A-2 (ruling 2026-09-24) -- the git SHA is DERIVED BY GRADLE ON EVERY
// BUILD, never typed and never checked in. `--dart-define` was REJECTED by
// that ruling: `String.fromEnvironment` silently defaults to '' and
// `flutter build apk` typed without the define is the ordinary way anyone
// builds, which makes the human typing the command the last line of defence
// -- V9, "the operator must not be the last line of defense against defects".
// Gradle runs on every build with no operator step.
//
// The dirty marker is NOT optional: BIS measured 15 modified paths in the tree
// that produced the build on the emulator, so an unqualified SHA would already
// have been a lie. git absent or failing yields the literal UNKNOWN -- never a
// blank, never a guess.
fun gitIdentity(): String {
    fun run(vararg args: String): String? = try {
        val p = ProcessBuilder(*args)
            .directory(rootProject.projectDir.parentFile)
            .redirectErrorStream(true)
            .start()
        val out = p.inputStream.bufferedReader().readText().trim()
        if (p.waitFor() == 0) out else null
    } catch (_: Exception) {
        null
    }
    val sha = run("git", "rev-parse", "--short", "HEAD") ?: return "UNKNOWN"
    if (sha.isEmpty()) return "UNKNOWN"
    val dirty = run("git", "status", "--porcelain")
    return if (dirty.isNullOrEmpty()) sha else "$sha-dirty"
}
val gitSha = gitIdentity()

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "dev.aki1770del.sngnav_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.aki1770del.sngnav_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Trusts gitignored android/local.properties; a release/profile build
        // refuses to stamp it unless it equals pubspec.yaml -- see
        // assertVersionIdentity below.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Read back at runtime through PackageManager (never a Dart
        // constant), so versionCode, versionName and gitSha all reach the
        // app from one source of truth: the installed package record.
        manifestPlaceholders["gitSha"] = gitSha
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real release signing when android/key.properties exists
            // (Play-track builds); debug keys otherwise so
            // `flutter run --release` works in development. A Play upload
            // with debug keys is rejected by the store, so the fallback
            // cannot silently ship.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// ⚑ VERSION IDENTITY, TIER 1: a release or profile build FAILS rather than
// stamp a versionCode pubspec.yaml does not record. Drafted by BIS (ruling
// 2026-09-24, outputs/build-identity-steward/r121_pre_arrival_ruling_2026_09_24/
// RULING.md §2), argued with and landed by AAE 2026-09-25.
//
// WHY. `versionCode = flutter.versionCode` in defaultConfig trusts
// android/local.properties, which is gitignored. The Flutter Gradle plugin
// takes the code SOLELY from that file and defaults an absent key to "1"
// (flutter_tools FlutterPlugin.kt, rootProjectLocalProperties.getProperty(
// "flutter.versionCode", "1")); the flutter tool rewrites the file from
// pubspec.yaml only on its own build path (gradle_utils.dart
// updateLocalProperties, inside `if (buildInfo != null)`). So `flutter build`
// stamps the committed number and a direct `gradlew assembleRelease` stamps
// whatever sits in the file, or 1. BIS measured 88 trees on this host with the
// file: 75 disagree with their own pubspec and 73 would stamp 1. The worktree
// this was written in was one of them. A versionCode names one build; 1 is on
// no ledger row and below every code a phone has received, so it installs
// nowhere on hers.
//
// WHAT. Every release or profile build, however invoked, must stamp exactly
// the `version:` in pubspec.yaml, or it stops here. Debug builds and IDE sync
// are NOT blocked: the ledger records release-signed identities only, and a
// fresh clone must still sync before anyone has run `flutter build`.
//
// WHY A TASK, NOT A doFirst ON preReleaseBuild. AGP's pre-build task can be
// UP-TO-DATE, and an up-to-date task runs no actions, so the check would vanish
// on exactly the incremental build where the file went stale. A task that
// declares no outputs is never up-to-date.
//
// WHY FAIL, NOT OVERRIDE (i.e. why not `versionCode = <pubspec +N>`). An
// override would silently discard an explicit `flutter build --build-number`
// and ship a number its operator did not ask for: a success-shaped value over a
// failed intent (V14). Nothing in this repo passes --build-number today; if
// something ever does, it fails loudly here and the version moves in
// pubspec.yaml, where the ledger reads it.
val pubspecVersion: Pair<String, String>? = run {
    val pubspec = rootProject.file("../pubspec.yaml")
    if (!pubspec.exists()) return@run null
    val line = pubspec.readLines().firstOrNull { it.startsWith("version:") }
        ?: return@run null
    val raw = line.removePrefix("version:").substringBefore('#').trim().trim('"', '\'')
    val plus = raw.indexOf('+')
    if (plus <= 0 || plus == raw.length - 1) return@run null
    Pair(raw.substring(0, plus), raw.substring(plus + 1))
}
val versionStampedByGradle = Pair(flutter.versionName, flutter.versionCode.toString())
val versionCodeKeyInLocalProperties: Boolean = run {
    val f = rootProject.file("local.properties")
    f.exists() && Properties().apply { f.reader().use { load(it) } }
        .containsKey("flutter.versionCode")
}

val assertVersionIdentity = tasks.register("assertVersionIdentity") {
    group = "verification"
    description = "Refuses a release/profile build whose version differs from pubspec.yaml."
    val expected = pubspecVersion
    val stamped = versionStampedByGradle
    val keyPresent = versionCodeKeyInLocalProperties
    doLast {
        if (expected == null) {
            throw GradleException(
                "VERSION IDENTITY: pubspec.yaml has no `version: <name>+<code>` line " +
                    "this build can read, so nothing records the versionCode it would stamp."
            )
        }
        if (expected != stamped) {
            val why = if (keyPresent) {
                "android/local.properties holds a stale flutter.versionCode/versionName"
            } else {
                "android/local.properties has no flutter.versionCode, so the Flutter " +
                    "Gradle plugin defaulted it to 1"
            }
            throw GradleException(
                "VERSION IDENTITY: this build would stamp ${stamped.first}+${stamped.second} " +
                    "but pubspec.yaml says ${expected.first}+${expected.second}: $why. " +
                    "Build with `flutter build apk` / `flutter build appbundle` (it rewrites " +
                    "that file from pubspec.yaml), or move the version in pubspec.yaml. " +
                    "A versionCode names one build; this one would name the wrong one."
            )
        }
        logger.lifecycle(
            "VERSION IDENTITY OK: ${stamped.first}+${stamped.second} == pubspec.yaml"
        )
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild" || name == "preProfileBuild") {
        dependsOn(assertVersionIdentity)
    }
}

flutter {
    source = "../.."
}
