import java.util.Properties
import java.io.FileInputStream
import java.security.MessageDigest; import java.security.KeyStore; import java.security.cert.X509Certificate; import java.util.jar.JarFile
import java.io.RandomAccessFile; import java.util.zip.ZipFile
import java.time.Instant

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (see BETA_PLAN.md): reads android/key.properties when present
// (keystore + key.properties are the maintainer's secrets, NEVER committed —
// key.properties is gitignored). Absent it, release is configured with the
// debug key, and assertReleaseSigner refuses it unless SNGNAV_DEV_RELEASE=1,
// which builds it as another app (dev.aki1770del.sngnav_app.dev).
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
fun gitIdentity(full: Boolean = false): String {
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
    val sha = (if (full) run("git", "rev-parse", "HEAD") else run("git", "rev-parse", "--short", "HEAD"))
        ?: return "UNKNOWN"
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

// ⚑ A DEVELOPMENT BUILD IS ANOTHER APP: dev.aki1770del.sngnav_app.dev.
//
// WHY. `flutter run` installs through the flutter tool, and when an install
// fails on an app that is already installed, the tool uninstalls that app,
// which deletes its data, and installs again, with no prompt (flutter_tools
// 3.47.5 android_device.dart installApp, "Uninstalling old version...").
// An install fails whenever the installed app was signed by another key. So
// the development command, `SNGNAV_DEV_RELEASE=1 flutter run --release`, with
// her phone attached, would remove her app and its data and put a build there
// that refuses every upload-signed fix after it. A warning printed during the
// build stops none of that; it relies on someone reading it in time (V9).
//
// WHAT. The release build under SNGNAV_DEV_RELEASE=1, and every profile
// build, get applicationIdSuffix ".dev". Android keys an installed app and its
// data by application ID, so such a build installs BESIDE hers and can never
// replace it. The flutter tool reads the ID from the APK it built
// (application_package.dart: "The gradle build script might alter the
// application Id"), so its uninstall-retry can reach only the .dev app.
// Without SNGNAV_DEV_RELEASE=1 a release build keeps her ID, and
// assertReleaseSigner (below) requires the upload key for it.
//
// THE UPLOAD KEY SIGNS ONLY HER APP. A .dev artifact signed by the upload key
// passed every Play preflight gate, which read the signer and never the
// package, and Play fixes an app's package at the first accepted upload (FBR
// R131 item 10, 2026-10-04). So under SNGNAV_DEV_RELEASE=1 the release build
// is signed with the debug key, never with android/key.properties, and
// assertReleaseSigner and reportProfileSigner refuse a .dev build that the
// upload key would sign (it can only arrive as injected signing). A row in the
// mint ledger also needs her package in the built bytes (appendMints).
//
// NOT CLOSED HERE, said so plainly: debug builds keep her ID, because changing
// it would change the app every emulator instrument drives by name. With her
// phone attached, a debug `flutter run` takes the same uninstall-retry. And
// `flutter install` runs no Gradle at all: it uninstalls the installed app
// first, whatever the signer, then installs whatever
// build/app/outputs/flutter-apk/app-release.apk holds; with no such file it
// falls back to her package, so it uninstalls her app and installs nothing
// (flutter_tools install.dart, application_package.dart; BIS round 2, 3).
// `flutter drive` uninstalls her package at teardown the same way. No build
// script can stop a command that does not run it. Never point any of them at
// a phone that holds an SNGNav release.
val devApplicationIdSuffix = ".dev"
val devReleaseValue: String? = System.getenv("SNGNAV_DEV_RELEASE")
val devReleaseAllowed: Boolean = devReleaseValue == "1"

android {
    namespace = "dev.aki1770del.sngnav_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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
            // The key named in android/key.properties when it exists; the
            // debug key otherwise. A debug-signed APK installs by sideload
            // like any other, so this fallback CAN ship: assertReleaseSigner
            // (below) refuses it, and every key but the upload key, before
            // packaging, unless SNGNAV_DEV_RELEASE=1 (a development build).
            // A development build is signed with the debug key even when
            // android/key.properties exists: the upload key signs only her
            // app (see THE UPLOAD KEY SIGNS ONLY HER APP above).
            signingConfig = if (hasReleaseKeystore && !devReleaseAllowed) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // A development release is another app (see above).
            if (devReleaseAllowed) applicationIdSuffix = devApplicationIdSuffix
        }
        // The Flutter plugin creates the profile build type (initWith debug).
        // Profile builds are for measuring on a development device, so every
        // one is another app, whichever key signs it (see above).
        getByName("profile") {
            applicationIdSuffix = devApplicationIdSuffix
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
        // QUIET, not lifecycle. The flutter tool runs gradle with -q unless
        // it is verbose (flutter_tools gradle.dart, `options.add('-q')`), and
        // -q drops every lifecycle line. At lifecycle level this pass never
        // appeared under `flutter build`, so a gate that passed looked the
        // same as a gate that never ran. Quiet is the level -q keeps.
        logger.quiet(
            "VERSION IDENTITY OK: ${stamped.first}+${stamped.second} == pubspec.yaml"
        )
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild" || name == "preProfileBuild") {
        dependsOn(assertVersionIdentity)
    }
}

// ⚑ VERSION CODE FLOOR: a build signed with the release key refuses a
// versionCode that is already spent.
//
// WHY. assertVersionIdentity makes the stamped code equal pubspec.yaml; it
// cannot say whether that code was used before. Codes 2 to 12 were each built
// under the release key, some more than once: code 2 named at least seven
// release APKs, and a July bundle at code 2 sat beside the code-12 build and
// passed the Play preflight. Android refuses an update whose versionCode is not
// above the installed one, and Play refuses a code it has seen, so a second
// build at a spent code reaches no one as an update, and the code then names
// two different things.
//
// WHAT. Release signing is in force when the release build is signed by a key
// other than the debug key, read by the one rule assertReleaseSigner uses
// (signerSourceFor, below: injected signing only when all four
// android.injected.signing.* properties are set, as AGP requires; else
// android/key.properties), and the build keeps her application ID (no
// SNGNAV_DEV_RELEASE=1). Then a build that
// packages a release artifact stops at preReleaseBuild, before anything is
// packaged, unless all of these hold:
//   - it has exactly one APK output, and its versionCode is
//     flutter.versionCode. split-per-abi gives each ABI's APK abi*1000+code,
//     so an arm64 APK at 2013 on a phone would refuse every later release
//     from 14 to 2012;
//   - it packages only through packageRelease and signReleaseBundle, which
//     write ledger rows (the bundletool APK tasks would write none);
//   - flutter.versionCode is above the number in tool/version_code_floor
//     (tracked: the highest code spent under the release key or reported back
//     by a device; 12 when this began), and above every code in this host's
//     mint ledger, $HOME/.sngnav/minted_release.tsv. packageRelease and
//     signReleaseBundle append one row per artifact: its own versionCode,
//     kind (apk|aab), sha256, full git commit, UTC time.
// One code may hold the APK AND the bundle of one release: a code already in
// the ledger is allowed again only for a kind it does not hold yet, from the
// same clean commit as every row at that code. Building the same kind again
// at that code is refused, because it would be a second set of bytes.
//
// BOUNDS. The ledger sees only builds on this host. A release key used on
// another machine or as a CI secret mints codes it never sees; raise
// tool/version_code_floor when that happens. SNGNAV_MINTED_LEDGER moves where
// rows are WRITTEN (a throwaway test key must not write into the real
// ledger), never what is read: the check reads that file and
// $HOME/.sngnav/minted_release.tsv together, and every run prints both.
// Builds signed with the debug key are not checked and write nothing. A
// development build (SNGNAV_DEV_RELEASE=1) is another app, so its versionCode
// spends none of hers: it is not checked and writes nothing. A row is written
// only when the certificate read from the built bytes is the upload key's
// (tool/upload_key_certificate_sha256), the one key her installed app accepts.
class MintRow(
    val code: Int,
    val kind: String,
    val sha256: String,
    val git: String,
    val utc: String,
)

val versionCodeFloorFile: File = rootProject.file("../tool/version_code_floor")
val realMintLedgerFile: File = File(
    System.getenv("HOME")?.takeIf { it.isNotBlank() } ?: System.getProperty("user.home"),
    ".sngnav/minted_release.tsv",
)
val mintLedgerWriteFile: File =
    System.getenv("SNGNAV_MINTED_LEDGER")?.takeIf { it.isNotBlank() }?.let { File(it) }
        ?: realMintLedgerFile
val mintLedgerReadFiles: List<File> =
    listOf(realMintLedgerFile, mintLedgerWriteFile).distinctBy { it.absoluteFile.normalize().path }
val gitCommitFull: String = gitIdentity(full = true)
// One rule for which key signs a release, the signer gate's. Until 2026-10-04
// this floor read android.injected.signing.store.file alone (hasProperty),
// while AGP and the gate need all four properties: with store.file alone AGP
// signed with the debug key, and this floor said "injected signing" and wrote
// a ledger row for that debug-signed APK (BIS ruling, board 36.17 row 7, 2.4).
val releaseSignerSource = signerSourceFor("release")
val releaseKeySigning: Boolean =
    !releaseSignerSource.debugKeyByConstruction && !devReleaseAllowed
val releaseSigningSource: String = releaseSignerSource.describe

// Every row, or a refusal naming the first line that is not one. A ledger
// line that cannot be read is not skipped: skipping it could hide a spent code.
fun readMintLedger(f: File): List<MintRow> {
    if (!f.exists()) return emptyList()
    return f.readLines().withIndex()
        .filter { (_, l) -> l.isNotBlank() && !l.startsWith("#") }
        .map { (i, l) ->
            val c = l.split('\t')
            val code = c.getOrNull(0)?.trim()?.toIntOrNull()
            if (code == null || c.size < 5) {
                throw GradleException(
                    "VERSION CODE FLOOR: ${f.path} line ${i + 1} is not " +
                        "`code<TAB>kind<TAB>sha256<TAB>git<TAB>utc`: \"$l\". Refusing " +
                        "rather than guessing which codes it spends."
                )
            }
            MintRow(code, c[1], c[2], c[3], c[4])
        }
}

fun describeLedgers(): String =
    "ledgers read: " + mintLedgerReadFiles.joinToString("; ") { f ->
        if (f.exists()) "${f.path} (${readMintLedger(f).size} rows)" else "${f.path} (absent)"
    } + "; rows are written to ${mintLedgerWriteFile.path}"

fun describeMint(r: MintRow): String =
    "versionCode ${r.code} ${r.kind} sha256=${r.sha256} git=${r.git} at ${r.utc}"

// Read once the task graph is known: which release artifacts this invocation
// packages, and whether it packages any through a task that writes no row.
val requestedReleaseKinds = mutableSetOf<String>()
val unrecordedReleasePackagers = mutableListOf<String>()
gradle.taskGraph.whenReady {
    if (hasTask(":app:packageRelease")) requestedReleaseKinds.add("apk")
    if (hasTask(":app:signReleaseBundle")) requestedReleaseKinds.add("aab")
    for (t in listOf("packageReleaseUniversalApk", "makeApkFromBundleForRelease")) {
        if (hasTask(":app:$t")) unrecordedReleasePackagers.add(t)
    }
}

// The release variant's outputs and the versionCode each will carry, read at
// execution time so that Flutter's split-per-abi override is already applied.
val releaseOutputCodes = mutableListOf<Pair<String, () -> Int?>>()

val assertVersionCodeUnspent = tasks.register("assertVersionCodeUnspent") {
    group = "verification"
    description = "Refuses a release-key build at a versionCode already spent."
    val active = releaseKeySigning
    val dev = devReleaseAllowed
    val source = releaseSigningSource
    val code = flutter.versionCode
    val floorFile = versionCodeFloorFile
    val commit = gitCommitFull
    val kinds = requestedReleaseKinds
    val unrecorded = unrecordedReleasePackagers
    val outputs = releaseOutputCodes
    mustRunAfter(assertVersionIdentity)
    doLast {
        if (!active) {
            logger.quiet(
                if (dev) {
                    "VERSION CODE FLOOR: not checked: SNGNAV_DEV_RELEASE=1 builds this release as " +
                        "dev.aki1770del.sngnav_app$devApplicationIdSuffix, another app, so its " +
                        "versionCode $code spends none of hers, and it writes no ledger row"
                } else {
                    "VERSION CODE FLOOR: not checked: this release build is signed with the debug " +
                        "key, from $source, and writes no ledger row"
                }
            )
            return@doLast
        }
        if (unrecorded.isNotEmpty()) {
            throw GradleException(
                "VERSION CODE FLOOR: this build packages release-signed APKs through " +
                    "${unrecorded.joinToString(", ")}, which write no row in the mint " +
                    "ledger, so the codes they spend would be invisible to every later " +
                    "check. Build the APK with assembleRelease and the bundle with " +
                    "bundleRelease."
            )
        }
        val codes = outputs.map { (name, read) -> name to read() }
        if (codes.size != 1 || codes.any { it.second != code }) {
            throw GradleException(
                "VERSION CODE FLOOR: under $source this build would package " +
                    "${codes.size} APK output(s): " +
                    codes.joinToString(", ") { "${it.first} at versionCode ${it.second}" } +
                    "; the release code is $code. split-per-abi gives each ABI's APK " +
                    "abi*1000+code, so an arm64 APK at ${2000 + code} on a phone would refuse " +
                    "every later release from ${code + 1} to ${2000 + code - 1}. Build one APK " +
                    "(without --split-per-abi) when signing with the release key."
            )
        }
        val floorLines = if (floorFile.exists()) floorFile.readLines() else emptyList()
        val numberLines = floorLines.map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }
        val floor = numberLines.singleOrNull()?.toIntOrNull()
            ?: throw GradleException(
                "VERSION CODE FLOOR: tool/version_code_floor must hold exactly one number " +
                    "line and holds ${numberLines.size} (${numberLines.joinToString(", ")}), " +
                    "so nothing says which versionCodes are spent. Refusing to sign versionCode " +
                    "$code under $source."
            )
        val rows = mintLedgerReadFiles.flatMap { readMintLedger(it) }
        val highest = (rows.map { it.code } + floor).maxOrNull() ?: floor
        val move = "Move `version:` in pubspec.yaml to +${highest + 1} or higher; " +
            "a versionCode names one build."
        if (code <= floor) {
            val named = floorLines.filter { Regex("^#\\s*[0-9][0-9, -]*:").containsMatchIn(it) }
            throw GradleException(
                "VERSION CODE FLOOR: versionCode $code is spent. tool/version_code_floor " +
                    "says every code up to $floor is already used" +
                    (if (named.isEmpty()) "." else ":\n  " + named.joinToString("\n  ")) +
                    "\n$move"
            )
        }
        val newer = rows.filter { it.code > code }
        if (newer.isNotEmpty()) {
            throw GradleException(
                "VERSION CODE FLOOR: versionCode $code is below what this host has " +
                    "already minted (${describeLedgers()}):\n  " +
                    newer.sortedByDescending { it.code }.joinToString("\n  ") { describeMint(it) } +
                    "\n$move"
            )
        }
        val same = rows.filter { it.code == code }
        if (same.isNotEmpty()) {
            val clean = !commit.endsWith("-dirty") && commit != "UNKNOWN"
            val held = same.map { it.kind }.toSet()
            val oneRelease = clean && kinds.isNotEmpty() &&
                same.all { it.git == commit } && kinds.none { it in held }
            if (!oneRelease) {
                throw GradleException(
                    "VERSION CODE FLOOR: versionCode $code already names these bytes " +
                        "(${describeLedgers()}):\n  " +
                        same.joinToString("\n  ") { describeMint(it) } +
                        "\nThis build (${kinds.sorted().joinToString("+").ifEmpty { "no artifact" }} " +
                        "from git $commit) would be another set of bytes at the same code. " +
                        "Only the other kind of the same release, from the same clean " +
                        "commit, may share it.\n$move"
                )
            }
            logger.quiet(
                "VERSION CODE FLOOR OK: $code under $source is above the floor $floor " +
                    "(tool/version_code_floor); it already holds " +
                    held.sorted().joinToString("+") + " from git $commit, and this build " +
                    "adds the " + kinds.sorted().joinToString("+") + " of the same release " +
                    "(${describeLedgers()})"
            )
            return@doLast
        }
        logger.quiet(
            "VERSION CODE FLOOR OK: $code under $source is above the floor $floor " +
                "(tool/version_code_floor) and above every code in the mint ledgers " +
                "(${describeLedgers()})"
        )
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild") {
        dependsOn(assertVersionCodeUnspent)
    }
}

// The ledger rows: written by the packaging tasks themselves (packageRelease
// for APKs, whichever lifecycle or install task asked for it; signReleaseBundle
// for the bundle), from the bytes they produced, each with its own versionCode,
// and only when the certificate read FROM THOSE BYTES is the upload key's. A
// row already present for the same sha256 is not written twice.
//
// WHY THE BYTES. Until 2026-10-04 a row was written whenever key.properties
// existed or store.file was injected, so a test key under SNGNAV_DEV_RELEASE=1
// and a debug-signed APK under partial injection each wrote a row that names a
// version and does not tell the truth about it (V14). The build script's own
// reading of the keystore is what the gate checks; the row is about the bytes.
//
// HER PACKAGE, IN THE BYTES. Her installed app takes an update only from her
// package AND her key. Until 2026-10-04 the writer read no package: .dev stayed
// out of the ledger only because one flag, devReleaseAllowed, both added the
// suffix and turned the writer off. With the suffix applied and the flag
// unset, a pin-signed .dev APK wrote a row (FBR R131, mutation M9). Now an
// artifact whose package is not hers is refused on the writer's own terms, and
// the build fails: no path that writes rows is meant to make another app.
val herApplicationId: String = checkNotNull(android.defaultConfig.applicationId) {
    "android.defaultConfig.applicationId is not set"
}

fun sha256Hex(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

// The package an artifact installs as, read from its own bytes: an APK's
// binary manifest through AGP's apksig, a bundle's base manifest (aapt2's
// protobuf XmlNode) through the aapt2-proto classes AGP ships. Throws when it
// cannot be read.
fun builtPackage(kind: String, f: File): String {
    if (kind == "apk") {
        return RandomAccessFile(f, "r").use { raf ->
            com.android.apksig.apk.ApkUtils.getPackageNameFromBinaryAndroidManifest(
                com.android.apksig.apk.ApkUtils.getAndroidManifest(
                    com.android.apksig.util.DataSources.asDataSource(raf)
                )
            )
        }
    }
    ZipFile(f).use { z ->
        val e = z.getEntry("base/manifest/AndroidManifest.xml")
            ?: throw GradleException("it has no base/manifest/AndroidManifest.xml")
        val root = z.getInputStream(e).use { com.android.aapt.Resources.XmlNode.parseFrom(it) }.element
        if (root.name != "manifest") throw GradleException("its manifest's root element is <${root.name}>")
        return root.attributeList.singleOrNull { it.name == "package" && it.namespaceUri.isEmpty() }?.value
            ?: throw GradleException("its manifest names no package")
    }
}

// The SHA-256 of each signer's certificate, read from the artifact's own bytes:
// an APK through AGP's own apksig (every APK signature scheme), a bundle
// through its JAR signature, every entry read and verified. Throws when the
// bytes do not verify.
fun builtSignerDigests(kind: String, f: File): List<String> {
    if (kind == "apk") {
        val r = com.android.apksig.ApkVerifier.Builder(f).build().verify()
        if (!r.isVerified) throw GradleException("it does not verify: ${r.errors.joinToString("; ")}")
        return r.signerCertificates.map { sha256Hex(it.encoded) }
    }
    val digests = linkedSetOf<String>()
    JarFile(f, true).use { jar ->
        val buf = ByteArray(1 shl 16)
        for (e in jar.entries()) {
            if (e.isDirectory || e.name.startsWith("META-INF/")) continue
            jar.getInputStream(e).use { ins -> while (ins.read(buf) > 0) { } }
            val signers = e.codeSigners ?: throw GradleException("its entry ${e.name} is not signed")
            for (s in signers) digests.add(sha256Hex(s.signerCertPath.certificates[0].encoded))
        }
    }
    return digests.toList()
}

fun appendMints(kind: String, artifacts: List<Pair<File, Int>>, commit: String) {
    val ledger = mintLedgerWriteFile
    val have = mintLedgerReadFiles.flatMap { readMintLedger(it) }.map { it.sha256 }.toSet()
    val pin = readUploadKeyPin(uploadKeyPinFile)
    for ((f, code) in artifacts) {
        if (!f.isFile) {
            logger.quiet("MINT LEDGER: no $kind at ${f.path}; nothing written for it")
            continue
        }
        // Her package first (HER PACKAGE, IN THE BYTES, above). Unreadable is a
        // refusal too, as for the signer below.
        val pkg = try {
            builtPackage(kind, f)
        } catch (e: Exception) {
            throw GradleException(
                "MINT LEDGER: the package of the $kind at ${f.path} could not be read from its bytes " +
                    "(${e.message}), so this host cannot say whether versionCode $code is her app's. " +
                    "Nothing was written."
            )
        }
        if (pkg != herApplicationId) {
            throw GradleException(
                "MINT LEDGER: refused: the $kind at ${f.path} is $pkg, not her app $herApplicationId, " +
                    "though nothing said this was a development build. A row records only a build her " +
                    "installed app accepts as an update, and an app with another package never is one. " +
                    "Nothing was written."
            )
        }
        // A signer that cannot be read is a refusal, never a guess either way:
        // writing would record a code on a guess, skipping could hide one.
        val signers = try {
            builtSignerDigests(kind, f)
        } catch (e: Exception) {
            throw GradleException(
                "MINT LEDGER: the signer of the $kind at ${f.path} could not be read from its " +
                    "bytes (${e.message}), so this host cannot say whether versionCode $code is " +
                    "spent. Nothing was written."
            )
        }
        if (signers.singleOrNull() != pin) {
            logger.quiet(
                "MINT LEDGER: not written: the $kind at ${f.path} is signed by " +
                    "${signers.size} signer(s) with certificate SHA-256 " +
                    "${signers.joinToString(", ").ifEmpty { "(none)" }}, not by the upload key " +
                    "alone ($pin, tool/upload_key_certificate_sha256). A row records only a " +
                    "build her installed app accepts as an update."
            )
            continue
        }
        ledger.parentFile?.mkdirs()
        if (!ledger.exists()) {
            ledger.writeText(
                "# Release builds minted on this host, appended by android/app/build.gradle.kts.\n" +
                    "# code\tkind\tsha256\tgit\tutc\n"
            )
        }
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { ins ->
            val buf = ByteArray(1 shl 16)
            while (true) {
                val n = ins.read(buf)
                if (n <= 0) break
                md.update(buf, 0, n)
            }
        }
        val sha = md.digest().joinToString("") { "%02x".format(it) }
        if (sha in have) {
            logger.quiet("MINT LEDGER: $kind sha256=$sha is already recorded")
            continue
        }
        val row = "$code\t$kind\t$sha\t$commit\t${Instant.now()}"
        ledger.appendText(row + "\n")
        logger.quiet("MINT LEDGER: appended to ${ledger.path}: ${row.replace('\t', ' ')}")
    }
}

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        for (o in variant.outputs) {
            val name = o.filters.joinToString(",") { "${it.filterType}=${it.identifier}" }
                .ifEmpty { "main" }
            releaseOutputCodes.add(name to { o.versionCode.orNull })
        }
        val apkDir = variant.artifacts.get(com.android.build.api.artifact.SingleArtifact.APK)
        val apkLoader = variant.artifacts.getBuiltArtifactsLoader()
        val bundle = variant.artifacts.get(com.android.build.api.artifact.SingleArtifact.BUNDLE)
        val active = releaseKeySigning
        val commit = gitCommitFull
        val code = flutter.versionCode
        val bundleCode = variant.outputs.singleOrNull()?.versionCode
        tasks.register("recordMintedReleaseApk") {
            inputs.files(apkDir)
            doLast {
                if (!active) return@doLast
                val built = apkLoader.load(apkDir.get())
                val artifacts = built?.elements?.map { e ->
                    if (e.versionCode == null) {
                        logger.quiet("MINT LEDGER: ${e.outputFile} lists no versionCode; recording $code")
                    }
                    File(e.outputFile) to (e.versionCode ?: code)
                }.orEmpty()
                if (artifacts.isEmpty()) {
                    logger.quiet("MINT LEDGER: no APK listed in ${apkDir.get().asFile}; nothing written")
                }
                appendMints("apk", artifacts, commit)
            }
        }
        tasks.register("recordMintedReleaseBundle") {
            inputs.file(bundle)
            doLast {
                if (!active) return@doLast
                appendMints("aab", listOf(bundle.get().asFile to (bundleCode?.orNull ?: code)), commit)
            }
        }
    }
}
tasks.configureEach {
    if (name == "packageRelease") finalizedBy("recordMintedReleaseApk")
    if (name == "signReleaseBundle") finalizedBy("recordMintedReleaseBundle")
}

// ⚑ RELEASE SIGNER: a release build is signed by the upload key, or it stops
// before anything is packaged.
//
// WHY. Builds of this app reach phones by sideload: `adb install`, or a tap on
// the file in Download/. Play has received none (tool/
// play_uploaded_version_codes.txt holds no code). Android installs a
// debug-signed APK as readily as any other, and an installed app takes an
// update only from the certificate that signed it. So a release APK signed by
// the debug key or a test key either cannot update the build on her phone or,
// installed first, blocks every upload-signed fix after it until the app is
// uninstalled, which deletes its data. The one check that refused a debug
// signature, check_signer in tool/preflight_play_upload.sh, runs only in CI's
// release-apk job, which runs only on manual dispatch. Read 2026-10-04: the
// repository holds 0 Actions secrets, and 0 of its 133 workflow runs were
// dispatched. Every build for a phone is made on a laptop, and there a
// debug-signed release build printed one quiet line and succeeded.
//
// WHAT. A task on preReleaseBuild, the seam the version-code floor uses, so it
// runs for `flutter build apk` / `appbundle`, `flutter run --release`,
// assembleRelease, bundleRelease and installRelease, and for Android Studio's
// "Generate Signed Bundle / APK". It reads the certificate AGP will sign with,
// in AGP's own order (injected signing when all four android.injected.signing.*
// properties are set, else the release signingConfig, i.e. android/
// key.properties or the debug key), and compares its SHA-256 with tool/
// upload_key_certificate_sha256. Anything else is refused, and the refusal
// says why and what to do instead.
//
// THE DEVELOPMENT LINE. Gradle cannot tell `flutter run --release` from
// `flutter build apk --release`: the flutter tool runs the same assembleRelease
// for both (flutter_tools gradle.dart; only -Ptarget-platform differs), and
// both leave the same app-release.apk behind. So the line is the developer's
// own word: SNGNAV_DEV_RELEASE=1 in the environment allows a release build
// signed by another key, builds it as dev.aki1770del.sngnav_app.dev, another
// app that installs beside hers (see the top of this file), and says so at the
// level `flutter build` prints. That key is the debug key, never
// android/key.properties; injected signing may name another, but never the
// upload key, which signs only her app (refused below). Debug builds are
// untouched. A profile build is signed with the debug key by the Flutter
// plugin (initWith debug); it is not refused, it is always the .dev app, and it
// says so on every run, unless injected signing would sign it with the upload
// key, or with a key that cannot be confirmed not to be it.
//
// AN EMPTY INJECTED VALUE IS REFUSED. AGP 9.1.0 treats a signing property that
// is present as set, even when its value is empty, and an empty value cannot
// sign. This gate refuses it rather than read a key AGP will not use (V16).
//
// WHY THE DIGEST AND NOT THE NAME. check_signer accepts any certificate whose
// owner contains "CN=SNGNav Upload", and any throwaway key can carry that name.
// A certificate's SHA-256 names one key.
//
// BOUNDS. This reads the keystore the build is configured with, not the bytes
// it produces (the ledger rows are written from the bytes), and AGP's order is
// read from AGP 9.1.0. It cannot see an APK built before this gate existed or
// on another machine; whoever stages a file for a phone still reads its signer
// from the file (apksigner verify --print-certs).
val uploadKeyPinFile: File = rootProject.file("../tool/upload_key_certificate_sha256")

class SignerSource(
    val describe: String,
    val debugKeyByConstruction: Boolean,
    val store: File?,
    val storePassword: String?,
    val keyAlias: String?,
    val storeType: String?,
    // Set when an injected signing property is present but empty: then which
    // key AGP would sign with is not what this script reads, and both tasks
    // that read a signer refuse.
    val problem: String? = null,
)

class SignerCert(val subject: String, val sha256: String)

fun injectedSigning(name: String): String? =
    (findProperty("android.injected.signing.$name") as String?)?.takeIf { it.isNotBlank() }

// The injected signing properties that are present with an empty value.
fun emptyInjectedSigning(): List<String> =
    listOf("store.file", "store.password", "key.alias", "key.password", "store.type").filter {
        hasProperty("android.injected.signing.$it") &&
            (findProperty("android.injected.signing.$it") as String?).isNullOrBlank()
    }

// The key a build type will be signed with, in AGP's order: the injected
// config overrides the build type's own when all four properties are present
// (AGP ignores an incomplete set, and so does this).
fun signerSourceFor(buildType: String): SignerSource {
    val empty = emptyInjectedSigning()
    if (empty.isNotEmpty()) {
        val names = empty.joinToString(", ") { "android.injected.signing.$it" }
        return SignerSource(
            "injected signing with an empty value", false, null, null, null, null,
            problem = "$names ${if (empty.size == 1) "is" else "are"} set with an empty value. AGP " +
                "reads a property that is present as set, so it would try to sign with injected " +
                "signing, while an empty value names no key; which key signs this build is not " +
                "known. Set all four android.injected.signing.* properties, or none",
        )
    }
    val storeFile = injectedSigning("store.file")
    val storePassword = injectedSigning("store.password")
    val keyAlias = injectedSigning("key.alias")
    val keyPassword = injectedSigning("key.password")
    if (storeFile != null && storePassword != null && keyAlias != null && keyPassword != null) {
        return SignerSource(
            "injected signing (android.injected.signing.*)", false,
            file(storeFile), storePassword, keyAlias, injectedSigning("store.type"),
        )
    }
    val partial = if (storeFile != null) {
        " (android.injected.signing.store.file is set without all four " +
            "android.injected.signing.* properties, so AGP ignores injected signing)"
    } else {
        ""
    }
    val debugConfig = android.signingConfigs.getByName("debug")
    val config = android.buildTypes.getByName(buildType).signingConfig
    if (config == null || config === debugConfig) {
        val store = debugConfig.storeFile
            ?: File(System.getProperty("user.home"), ".android/debug.keystore")
        val reason = when {
            buildType != "release" ->
                "the $buildType build type's own signing config, with no injected signing"
            devReleaseAllowed && hasReleaseKeystore ->
                "SNGNAV_DEV_RELEASE=1 signs a development release with the debug key, never with " +
                    "android/key.properties, and there is no injected signing"
            else -> "there is no android/key.properties and no injected signing"
        }
        return SignerSource(
            "the debug keystore ($reason)$partial",
            true, store, debugConfig.storePassword ?: "android",
            debugConfig.keyAlias ?: "androiddebugkey", debugConfig.storeType,
        )
    }
    return SignerSource(
        "android/key.properties$partial", false,
        config.storeFile, config.storePassword, config.keyAlias, config.storeType,
    )
}

fun readSignerCert(s: SignerSource): SignerCert {
    val store = s.store ?: throw GradleException("no keystore file is configured")
    if (!store.isFile) throw GradleException("${store.path} is not a file")
    val password = (s.storePassword ?: "").toCharArray()
    val keyStore = if (s.storeType.isNullOrBlank()) {
        KeyStore.getInstance(store, password)
    } else {
        KeyStore.getInstance(s.storeType).apply {
            store.inputStream().use { load(it, password) }
        }
    }
    val alias = s.keyAlias ?: throw GradleException("no key alias is configured")
    val cert = keyStore.getCertificate(alias) as? X509Certificate
        ?: throw GradleException("${store.path} holds no certificate under the alias \"$alias\"")
    val sha = MessageDigest.getInstance("SHA-256").digest(cert.encoded)
        .joinToString("") { "%02x".format(it) }
    return SignerCert(cert.subjectX500Principal.toString(), sha)
}

// The pinned digest: the file's only line that is neither blank nor a comment.
fun readUploadKeyPin(f: File): String {
    if (!f.isFile) throw GradleException("${f.path} is missing")
    val lines = f.readLines().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }
    val line = lines.singleOrNull()
        ?: throw GradleException("${f.path} must hold exactly one digest line and holds ${lines.size}")
    val digest = line.replace(":", "").lowercase()
    if (!Regex("^[0-9a-f]{64}$").matches(digest)) {
        throw GradleException("${f.path}: \"$line\" is not a SHA-256 digest")
    }
    return digest
}

fun describeSigner(source: SignerSource, cert: Result<SignerCert>): String =
    cert.fold(
        { "${it.subject} (certificate SHA-256 ${it.sha256}), from ${source.describe}" },
        { "a key whose certificate could not be read (${it.message}), from ${source.describe}" },
    )

val assertReleaseSigner = tasks.register("assertReleaseSigner") {
    group = "verification"
    description = "Refuses a release build that is not signed by the upload key " +
        "(SNGNAV_DEV_RELEASE=1 allows one for development, and says so)."
    val source = releaseSignerSource
    val pinFile = uploadKeyPinFile
    val allowed = devReleaseAllowed
    val envValue = devReleaseValue
    val devId = "dev.aki1770del.sngnav_app$devApplicationIdSuffix"
    val herId = herApplicationId
    mustRunAfter(assertVersionIdentity)
    doLast {
        source.problem?.let {
            throw GradleException("RELEASE SIGNER: refused before packaging. $it.")
        }
        val pin = runCatching { readUploadKeyPin(pinFile) }
        val cert = runCatching { readSignerCert(source) }
        val c = cert.getOrNull()
        val debugKey = source.debugKeyByConstruction || c?.subject?.contains("CN=Android Debug") == true
        if (!debugKey && c != null && pin.getOrNull() == c.sha256) {
            // THE UPLOAD KEY SIGNS ONLY HER APP (top of this file). Under the
            // allowance the release signing config is the debug key, so this
            // is reached only through injected signing.
            if (allowed) {
                throw GradleException(
                    "RELEASE SIGNER: refused before packaging. SNGNAV_DEV_RELEASE=1 builds this release " +
                        "as $devId, another app, and it would be signed by the upload key: " +
                        "${describeSigner(source, cert)}.\n" +
                        "The upload key signs only her app, $herId. Play fixes an app's package " +
                        "at the first accepted upload, and an upload-key bundle of another app passes every " +
                        "check that reads only the signer.\n" +
                        "For a development build, leave android.injected.signing.* unset: it is then signed " +
                        "with the debug key. To build her release, unset SNGNAV_DEV_RELEASE."
                )
            }
            logger.quiet(
                "RELEASE SIGNER OK: signed by ${c.subject}, the upload key (certificate SHA-256 " +
                    "${c.sha256} matches tool/upload_key_certificate_sha256), from ${source.describe}"
            )
            return@doLast
        }
        val why = when {
            debugKey -> "would be signed with the debug key: ${describeSigner(source, cert)}"
            c == null -> "would be signed by ${describeSigner(source, cert)}, so its signer cannot be confirmed"
            pin.isFailure -> "would be signed by ${describeSigner(source, cert)}, and the upload key's " +
                "digest cannot be read (${pin.exceptionOrNull()?.message}), so it cannot be confirmed as the upload key"
            else -> "would be signed by ${describeSigner(source, cert)}, which is not the upload key " +
                "(tool/upload_key_certificate_sha256: ${pin.getOrNull()})"
        }
        if (allowed) {
            logger.quiet(
                "RELEASE SIGNER: NOT THE UPLOAD KEY, allowed because SNGNAV_DEV_RELEASE=1 says this is a " +
                    "development build. This release build $why. It is built as $devId, another app: " +
                    "it installs beside an SNGNav release and cannot replace it or its data, and it " +
                    "writes no ledger row. Do not hand it on as SNGNav."
            )
            return@doLast
        }
        val refusal = "RELEASE SIGNER: refused before packaging. This release build $why.\n" +
            "An installed app takes an update only from the certificate that signed it, and builds of " +
            "this app reach phones by sideload. A release signed by any other key cannot update the app " +
            "on her phone, or, installed first, blocks every upload-signed fix until the app is " +
            "uninstalled, which deletes its data.\n" +
            "To build for a phone: sign with the upload key, through android/key.properties or Android " +
            "Studio's \"Generate Signed Bundle / APK\".\n" +
            "To build release mode for development on your own device or an emulator, say so. The " +
            "build is then another app, $devId, which installs beside hers:\n" +
            "    SNGNAV_DEV_RELEASE=1 flutter run --release" +
            (if (envValue != null) "\n(SNGNAV_DEV_RELEASE is set to \"$envValue\"; only 1 allows a development build.)" else "")
        throw GradleException(refusal)
    }
}
assertVersionCodeUnspent.configure { mustRunAfter(assertReleaseSigner) }

val reportProfileSigner = tasks.register("reportProfileSigner") {
    group = "verification"
    description = "Says which key signs a profile build. A profile build is not refused."
    val source = signerSourceFor("profile")
    val pinFile = uploadKeyPinFile
    val devId = "dev.aki1770del.sngnav_app$devApplicationIdSuffix"
    val herId = herApplicationId
    doLast {
        source.problem?.let {
            throw GradleException("RELEASE SIGNER: refused before packaging. $it.")
        }
        val cert = runCatching { readSignerCert(source) }
        // THE UPLOAD KEY SIGNS ONLY HER APP (top of this file). The profile
        // build type is signed with the debug key; another key arrives only as
        // injected signing, and then it must be known NOT to be the upload key.
        if (!source.debugKeyByConstruction) {
            val pin = runCatching { readUploadKeyPin(pinFile) }
            val c = cert.getOrNull()
            val p = pin.getOrNull()
            if (c == null || p == null || c.sha256 == p) {
                val why = when {
                    c == null -> "and its signer cannot be confirmed not to be the upload key"
                    p == null -> "and the upload key's digest cannot be read " +
                        "(${pin.exceptionOrNull()?.message}), so its signer cannot be confirmed not to be it"
                    else -> "and it would be signed by the upload key"
                }
                throw GradleException(
                    "RELEASE SIGNER: refused before packaging. A profile build is $devId, another app, " +
                        "$why: ${describeSigner(source, cert)}.\n" +
                        "The upload key signs only her app, $herId. Play fixes an app's package " +
                        "at the first accepted upload. Build profile with the debug key: leave " +
                        "android.injected.signing.* unset."
                )
            }
        }
        logger.quiet(
            "RELEASE SIGNER: a profile build is not refused. It is built as $devId, another app, " +
                "so it installs beside an SNGNav release and cannot replace it. It is signed by " +
                "${describeSigner(source, cert)}."
        )
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild") {
        dependsOn(assertReleaseSigner)
    }
    if (name == "preProfileBuild") {
        dependsOn(reportProfileSigner)
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
