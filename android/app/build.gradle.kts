import java.util.Properties
import java.io.FileInputStream
import java.security.MessageDigest
import java.time.Instant

plugins {
    id("com.android.application")
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
// cannot say whether that code was used before. Codes 2 to 12 were each built,
// some many times: one code named seven release APKs, and a July bundle at code
// 2 sat beside the code-12 build and passed the Play preflight. Android refuses
// an update whose versionCode is not above the installed one, and Play refuses
// a code it has seen, so a second build at a spent code reaches no one as an
// update, and the code then names two different things.
//
// WHAT. When release signing resolves from android/key.properties, a release
// build (assembleRelease, bundleRelease: both run preReleaseBuild) stops,
// before anything is packaged, unless flutter.versionCode is above
//   (a) the number in tool/version_code_floor (tracked; 12 when this began),
//   (b) every code in this host's mint ledger, which the release packaging
//       appends to after each build: $HOME/.sngnav/minted_release.tsv, one
//       row per artifact: code, kind (apk|aab), sha256, git commit, UTC time.
// One code may hold the APK AND the bundle of one release: a code already in
// the ledger is allowed again only for a kind it does not hold yet, from the
// same clean commit as every row at that code. Building the same kind again at
// that code is refused, because it would be a second set of bytes.
//
// BOUNDS. The ledger sees only builds on this host. A release key used on
// another machine or as a CI secret mints codes it never sees; raise
// tool/version_code_floor when that happens. SNGNAV_MINTED_LEDGER points the
// ledger elsewhere (for a throwaway test key, so test rows never mix with real
// ones), and every run prints the path it read. Debug builds, and release
// builds without key.properties (which are debug-signed), are not checked and
// write nothing.
class MintRow(
    val code: Int,
    val kind: String,
    val sha256: String,
    val git: String,
    val utc: String,
)

val versionCodeFloorFile: File = rootProject.file("../tool/version_code_floor")
val mintLedgerFile: File =
    System.getenv("SNGNAV_MINTED_LEDGER")?.takeIf { it.isNotBlank() }?.let { File(it) }
        ?: File(System.getProperty("user.home"), ".sngnav/minted_release.tsv")

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

fun describeMint(r: MintRow): String =
    "versionCode ${r.code} ${r.kind} sha256=${r.sha256} git=${r.git} at ${r.utc}"

// Which kinds of artifact this invocation will package, read once the task
// graph is known: `flutter build apk` runs assembleRelease and
// `flutter build appbundle` runs bundleRelease.
val requestedReleaseKinds = mutableSetOf<String>()
gradle.taskGraph.whenReady {
    if (hasTask(":app:assembleRelease")) requestedReleaseKinds.add("apk")
    if (hasTask(":app:bundleRelease")) requestedReleaseKinds.add("aab")
}

val assertVersionCodeUnspent = tasks.register("assertVersionCodeUnspent") {
    group = "verification"
    description = "Refuses a release-key build at a versionCode already spent."
    val active = hasReleaseKeystore
    val code = flutter.versionCode
    val floorFile = versionCodeFloorFile
    val ledger = mintLedgerFile
    val commit = gitSha
    val kinds = requestedReleaseKinds
    mustRunAfter(assertVersionIdentity)
    doLast {
        if (!active) {
            logger.quiet(
                "VERSION CODE FLOOR: not checked: there is no android/key.properties, " +
                    "so this release build is debug-signed and writes no ledger row"
            )
            return@doLast
        }
        val floorLines = if (floorFile.exists()) floorFile.readLines() else emptyList()
        val floor = floorLines.map { it.trim() }
            .firstOrNull { it.isNotEmpty() && !it.startsWith("#") }
            ?.toIntOrNull()
            ?: throw GradleException(
                "VERSION CODE FLOOR: tool/version_code_floor is missing or holds no " +
                    "number, so nothing says which versionCodes are spent. Refusing to " +
                    "sign versionCode $code with the release key."
            )
        val rows = readMintLedger(ledger)
        val highest = (rows.map { it.code } + floor).maxOrNull() ?: floor
        val move = "Move `version:` in pubspec.yaml to +${highest + 1} or higher; " +
            "a versionCode names one build."
        if (code <= floor) {
            val named = floorLines.filter { Regex("^#\\s*[0-9][0-9-]*:").containsMatchIn(it) }
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
                    "already minted (${ledger.path}):\n  " +
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
                        "(${ledger.path}):\n  " +
                        same.joinToString("\n  ") { describeMint(it) } +
                        "\nThis build (${kinds.sorted().joinToString("+").ifEmpty { "no artifact" }} " +
                        "from git $commit) would be another set of bytes at the same code. " +
                        "Only the other kind of the same release, from the same clean " +
                        "commit, may share it.\n$move"
                )
            }
            logger.quiet(
                "VERSION CODE FLOOR OK: $code is above the floor $floor " +
                    "(tool/version_code_floor); it already holds " +
                    held.sorted().joinToString("+") + " from git $commit, and this build " +
                    "adds the " + kinds.sorted().joinToString("+") + " of the same release " +
                    "(ledger ${ledger.path})"
            )
            return@doLast
        }
        logger.quiet(
            "VERSION CODE FLOOR OK: $code is above the floor $floor " +
                "(tool/version_code_floor) and above every code in ${ledger.path} " +
                "(${rows.size} rows" +
                (rows.maxOfOrNull { it.code }?.let { ", highest $it" } ?: "") + ")"
        )
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild") {
        dependsOn(assertVersionCodeUnspent)
    }
}

// The ledger rows: written after packaging, from the bytes packaging produced
// (the APKs listed in output-metadata.json, and the signed bundle), only when
// the release key signed them. A row already present for the same sha256 is
// not written twice.
fun appendMints(ledger: File, kind: String, files: List<File>, code: Int, commit: String) {
    val have = readMintLedger(ledger).map { it.sha256 }.toSet()
    ledger.parentFile?.mkdirs()
    if (!ledger.exists()) {
        ledger.writeText(
            "# Release builds minted on this host, appended by android/app/build.gradle.kts.\n" +
                "# code\tkind\tsha256\tgit\tutc\n"
        )
    }
    for (f in files) {
        if (!f.isFile) {
            logger.quiet("MINT LEDGER: no $kind at ${f.path}; nothing written for it")
            continue
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
            logger.quiet("MINT LEDGER: $kind sha256=$sha is already in ${ledger.path}")
            continue
        }
        val row = "$code\t$kind\t$sha\t$commit\t${Instant.now()}"
        ledger.appendText(row + "\n")
        logger.quiet("MINT LEDGER: appended to ${ledger.path}: ${row.replace('\t', ' ')}")
    }
}

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        val apkDir = variant.artifacts.get(com.android.build.api.artifact.SingleArtifact.APK)
        val apkLoader = variant.artifacts.getBuiltArtifactsLoader()
        val bundle = variant.artifacts.get(com.android.build.api.artifact.SingleArtifact.BUNDLE)
        val active = hasReleaseKeystore
        val ledger = mintLedgerFile
        val commit = gitSha
        val code = flutter.versionCode
        tasks.register("recordMintedReleaseApk") {
            inputs.files(apkDir)
            doLast {
                if (!active) return@doLast
                val built = apkLoader.load(apkDir.get())
                val files = built?.elements?.map { File(it.outputFile) }.orEmpty()
                if (files.isEmpty()) {
                    logger.quiet("MINT LEDGER: no APK listed in ${apkDir.get().asFile}; nothing written")
                }
                appendMints(ledger, "apk", files, code, commit)
            }
        }
        tasks.register("recordMintedReleaseBundle") {
            inputs.file(bundle)
            doLast {
                if (!active) return@doLast
                appendMints(ledger, "aab", listOf(bundle.get().asFile), code, commit)
            }
        }
    }
}
tasks.configureEach {
    if (name == "assembleRelease") finalizedBy("recordMintedReleaseApk")
    if (name == "bundleRelease") finalizedBy("recordMintedReleaseBundle")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
