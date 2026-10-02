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
// cannot say whether that code was used before. Codes 2 to 12 were each built
// under the release key, some more than once: code 2 named at least seven
// release APKs, and a July bundle at code 2 sat beside the code-12 build and
// passed the Play preflight. Android refuses an update whose versionCode is not
// above the installed one, and Play refuses a code it has seen, so a second
// build at a spent code reaches no one as an update, and the code then names
// two different things.
//
// WHAT. Release signing is in force when android/key.properties exists, or
// when signing is injected (android.injected.signing.*: the IDE's "Generate
// Signed Bundle / APK", which needs no key.properties). Then a build that
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
// Builds signed with the debug key are not checked and write nothing.
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
val injectedReleaseSigning: Boolean = hasProperty("android.injected.signing.store.file")
val releaseKeySigning: Boolean = hasReleaseKeystore || injectedReleaseSigning
val releaseSigningSource: String = when {
    hasReleaseKeystore -> "android/key.properties"
    injectedReleaseSigning -> "injected signing (android.injected.signing.*)"
    else -> "the debug key"
}

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
                "VERSION CODE FLOOR: not checked: there is no android/key.properties and no " +
                    "injected signing, so this release build is signed with the debug key and " +
                    "writes no ledger row"
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
// and only when the release key signed them. A row already present for the
// same sha256 is not written twice.
fun appendMints(kind: String, artifacts: List<Pair<File, Int>>, commit: String) {
    val ledger = mintLedgerWriteFile
    val have = mintLedgerReadFiles.flatMap { readMintLedger(it) }.map { it.sha256 }.toSet()
    ledger.parentFile?.mkdirs()
    if (!ledger.exists()) {
        ledger.writeText(
            "# Release builds minted on this host, appended by android/app/build.gradle.kts.\n" +
                "# code\tkind\tsha256\tgit\tutc\n"
        )
    }
    for ((f, code) in artifacts) {
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
