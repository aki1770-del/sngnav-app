// A release build is signed by the upload key, or it stops before anything is
// packaged (assertReleaseSigner in android/app/build.gradle.kts). Builds of
// this app reach phones by sideload, and an installed app takes an update only
// from the certificate that signed it, so a debug-signed release on her phone
// would block every later fix. A development build (SNGNAV_DEV_RELEASE=1) and
// every profile build are another app, dev.aki1770del.sngnav_app.dev, so
// none can replace hers. Gradle cannot run in a test, so this pins the pieces
// in the source: if the digest file goes, is malformed or changes value, or
// the wiring, the refusal or the suffix is removed, it fails here as well as
// in a release build. A debug build keeps her ID, so the upload key never
// signs one either (assertDebugSigner).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The file's digest: the ONLY line that is neither blank nor a comment,
/// with colons removed and lower-cased. Null when there is none, when there
/// are several, or when it is not 64 hex digits (the gate refuses all three).
String? pinnedDigest(String text) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  if (lines.length != 1) return null;
  final d = lines.single.replaceAll(':', '').toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(d) ? d : null;
}

void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('tool/upload_key_certificate_sha256 holds exactly one SHA-256 digest',
      () {
    final f = File('tool/upload_key_certificate_sha256');
    expect(f.existsSync(), isTrue, reason: 'the upload key pin is gone');
    expect(pinnedDigest(f.readAsStringSync()), isNotNull,
        reason: 'it must hold exactly one 64-hex-digit line');
  });

  test('the pin parser refuses what the gate refuses', () {
    const d = '6a4906edb4ebdc5f54ad24ab1818054618adba480df98b4f4f1dac45600d0f14';
    expect(pinnedDigest('# note\n$d\n'), d);
    expect(pinnedDigest('# colons and case are accepted\n'
        '6A:49:06:ED:B4:EB:DC:5F:54:AD:24:AB:18:18:05:46:'
        '18:AD:BA:48:0D:F9:8B:4F:4F:1D:AC:45:60:0D:0F:14\n'), d);
    expect(pinnedDigest('# none\n'), isNull);
    expect(pinnedDigest('$d\n$d\n'), isNull, reason: 'two lines are refused');
    expect(pinnedDigest('${d.substring(1)}\n'), isNull,
        reason: '63 digits are refused');
  });

  test('a release build depends on assertReleaseSigner, which reads the pin',
      () {
    expect(gradle, contains('tasks.register("assertReleaseSigner")'));
    expect(
      RegExp(r'if \(name == "preReleaseBuild"\) \{\s*'
              r'dependsOn\(assertReleaseSigner\)')
          .hasMatch(gradle),
      isTrue,
      reason: 'preReleaseBuild (assemble, bundle, install, flutter run '
          '--release) must run it',
    );
    expect(gradle,
        contains('rootProject.file("../tool/upload_key_certificate_sha256")'));
    // The refusal is a thrown exception, not a log line.
    expect(gradle, contains('throw GradleException(refusal)'));
    // Only the exact value 1 allows a development build.
    expect(gradle, contains('System.getenv("SNGNAV_DEV_RELEASE")'));
    expect(gradle, contains('devReleaseAllowed: Boolean = devReleaseValue == "1"'));
    // Injected signing (Android Studio's signed build) is read first, as AGP
    // reads it.
    expect(gradle, contains('injectedSigning("store.file")'));
    // The signer gate runs before the version-code floor.
    expect(gradle,
        contains('assertVersionCodeUnspent.configure { mustRunAfter(assertReleaseSigner) }'));
  });

  test('the pin is the upload key\'s certificate, by VALUE', () {
    // Pinned here as well as in the file, so changing the key takes two
    // deliberate edits. The value is the certificate that signed code 12, the
    // build on her phone, as tool/version_code_floor records it.
    final pin =
        pinnedDigest(File('tool/upload_key_certificate_sha256').readAsStringSync());
    expect(pin,
        '6a4906edb4ebdc5f54ad24ab1818054618adba480df98b4f4f1dac45600d0f14');
    // The floor file names the certificate of the highest code it records.
    final named = File('tool/version_code_floor')
        .readAsLinesSync()
        .map((l) => RegExp(r'^#\s*(\d+):.*cert ([0-9a-f]{8})\.\.\.([0-9a-f]{4})')
            .firstMatch(l))
        .whereType<RegExpMatch>()
        .toList()
      ..sort((a, b) => int.parse(b[1]!).compareTo(int.parse(a[1]!)));
    expect(named, isNotEmpty,
        reason: 'tool/version_code_floor names no certificate for any code');
    expect(pin, startsWith(named.first[2]!),
        reason: 'the pin is not the certificate of code ${named.first[1]}');
    expect(pin, endsWith(named.first[3]!),
        reason: 'the pin is not the certificate of code ${named.first[1]}');
  });

  test('a development release and every profile build are another app; '
      'debug keeps her ID', () {
    expect(gradle, contains('applicationId = "dev.aki1770del.sngnav_app"'));
    expect(gradle, contains('val devApplicationIdSuffix = ".dev"'));
    expect(gradle,
        contains('if (devReleaseAllowed) applicationIdSuffix = devApplicationIdSuffix'));
    expect(
      RegExp(r'getByName\("profile"\)\s*\{\s*'
              r'applicationIdSuffix = devApplicationIdSuffix')
          .hasMatch(gradle),
      isTrue,
      reason: 'every profile build must be the .dev app',
    );
    // Exactly those two: debug builds keep her ID.
    expect('applicationIdSuffix ='.allMatches(gradle).length, 2);
    // The allowance is read before android {} configures the build types.
    expect(gradle.indexOf('val devReleaseAllowed'),
        lessThan(gradle.indexOf('\nandroid {')));
  });

  test('the floor and the ledger read the signer gate\'s own rule', () {
    expect(gradle, contains('val releaseSignerSource = signerSourceFor("release")'));
    expect(gradle,
        contains('!releaseSignerSource.debugKeyByConstruction && !devReleaseAllowed'));
    expect(gradle, contains('val source = releaseSignerSource'));
    // The one-property rule is gone.
    expect(gradle,
        isNot(contains('hasProperty("android.injected.signing.store.file")')));
  });

  test('a ledger row is written only for bytes signed by the upload key alone',
      () {
    expect(gradle, contains('com.android.apksig.ApkVerifier.Builder(f)'));
    expect(gradle, contains('builtSignerDigests(kind, f)'));
    expect(gradle, contains('if (signers.singleOrNull() != pin) {'));
  });

  test('a ledger row needs her package, read from the built bytes, on the '
      "writer's own terms", () {
    // Until 2026-10-04 the writer read no package: with the suffix applied
    // and the allowance unset, a pin-signed .dev APK wrote a row (FBR R131,
    // mutation M9). The writer's own check does not lean on devReleaseAllowed.
    expect(
        gradle,
        contains('val herApplicationId: String = '
            'checkNotNull(android.defaultConfig.applicationId)'));
    expect(gradle,
        contains('com.android.apksig.apk.ApkUtils.getPackageNameFromBinaryAndroidManifest('));
    expect(gradle, contains('com.android.aapt.Resources.XmlNode.parseFrom(it)'));
    final check = RegExp(r'val pkg = try \{\s*builtPackage\(kind, f\)\s*\}'
        r'[\s\S]*?if \(pkg != herApplicationId\) \{\s*throw GradleException\(');
    expect(check.hasMatch(gradle), isTrue,
        reason: 'another package must be refused by a thrown exception');
    // Before the signer: a pin-signed .dev must never get as far as a row.
    expect(gradle.indexOf('if (pkg != herApplicationId) {'),
        lessThan(gradle.indexOf('if (signers.singleOrNull() != pin) {')));
  });

  test('the upload key signs only her app: never a development release or a '
      'profile build', () {
    // A .dev bundle signed by the pinned key passed every Play preflight gate
    // (FBR R131 item 10). Under the allowance the release config is the debug
    // key, and the injected upload key is refused for release and profile.
    expect(gradle,
        contains('signingConfig = if (hasReleaseKeystore && !devReleaseAllowed) {'));
    // ONE rule for every build that is not her release. Until 2026-10-04 it was
    // written twice, and the development-release copy allowed a signer or a
    // pin it could not read (BIS round 3, F1).
    final rule = RegExp(
        r'fun notHerReleaseSignerRefusal\([\s\S]*?\): String\? \{\s*'
        r'val c = cert\.getOrNull\(\)\s*'
        r'val p = pin\.getOrNull\(\)\s*'
        r'return when \{\s*'
        r'c != null && p != null && c\.sha256 == p -> "[^"]+"\s*'
        r'source\.debugKeyByConstruction -> null\s*'
        r'c == null -> "[^"]+" \+\s*"[^"]+"\s*'
        r'p == null -> "[^"]+" \+\s*"[^"]+"\s*'
        r'else -> null\s*\}');
    expect(rule.hasMatch(gradle), isTrue,
        reason: 'the rule must refuse the upload key from any source, and an '
            'unreadable signer or pin unless the source is the debug key by '
            'construction');
    // Every task that reads a signer calls it (release, profile and, since
    // 2026-10-05, debug), and each call throws.
    final call = RegExp(r'notHerReleaseSignerRefusal\(source, cert, pin\)\?\.let \{ why ->\s*'
        r'throw GradleException\(');
    expect(call.allMatches(gradle).length, 3);
    // Renamed 2026-10-05 (BIS ruling D-3, F-D2): a debug build IS her app, so
    // "not her app" was untrue of a caller. Outside comments, the old name is
    // gone.
    expect(
        gradle
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .where((l) => l.contains('notHerAppSignerRefusal')),
        isEmpty);
    // Under SNGNAV_DEV_RELEASE=1 the call comes first, before anything is
    // logged or allowed.
    expect(
      RegExp(r'if \(allowed\) \{(?:\s*//[^\n]*)*\s*'
              r'notHerReleaseSignerRefusal\(source, cert, pin\)\?\.let \{ why ->\s*'
              r'throw GradleException\(')
          .hasMatch(gradle),
      isTrue,
      reason: 'a development release must take the rule before it is allowed',
    );
    final allowedAt = gradle.indexOf('        if (allowed) {');
    expect(allowedAt, greaterThan(0));
    expect(allowedAt, lessThan(gradle.indexOf('RELEASE SIGNER OK:')),
        reason: 'the allowance must be decided before her release can pass');
    // Inside reportProfileSigner too.
    final profile = gradle.substring(
        gradle.indexOf('tasks.register("reportProfileSigner")'));
    expect(call.hasMatch(profile), isTrue,
        reason: 'a profile build must take the same rule');
  });

  test('"NOT THE UPLOAD KEY" is said only of a signer read and compared', () {
    // At f0c3fc5 the allowed development release logged "NOT THE UPLOAD
    // KEY" about a signer whose certificate, or whose pin, was never read: a
    // sentence shaped like a check that did not happen. Now the words exist
    // once in code (comments aside), in the branch where both were read.
    final saying = gradle
        .split('\n')
        .where((l) =>
            !l.trimLeft().startsWith('//') && l.contains('NOT THE UPLOAD KEY'))
        .toList();
    expect(saying, hasLength(1), reason: saying.join('\n'));
    expect(
      RegExp(r'fun devReleaseSignerStatement\([\s\S]*?return when \{\s*'
              r'c != null && p != null ->\s*"NOT THE UPLOAD KEY\.')
          .hasMatch(gradle),
      isTrue,
      reason: 'the words must sit in the branch where cert and pin were read',
    );
    expect(gradle,
        contains(r'"RELEASE SIGNER: ${devReleaseSignerStatement(source, cert, pin)}. Allowed because "'));
  });

  test('the .dev build types carry another launcher label', () {
    // Two "SNGNav" icons on one phone are one glance from the wrong app
    // (BIS round 2, N2).
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains(r'android:label="${appLabel}"'));
    expect(gradle, contains('val herAppLabel = "SNGNav"'));
    expect(gradle, contains('val devAppLabel = "@string/dev_app_label"'));
    expect(gradle, contains('manifestPlaceholders["appLabel"] = herAppLabel'));
    expect(gradle,
        contains('if (devReleaseAllowed) manifestPlaceholders["appLabel"] = devAppLabel'));
    expect(
      RegExp(r'getByName\("profile"\)\s*\{\s*'
              r'applicationIdSuffix = devApplicationIdSuffix\s*'
              r'manifestPlaceholders\["appLabel"\] = devAppLabel')
          .hasMatch(gradle),
      isTrue,
    );
    expect('manifestPlaceholders["appLabel"] ='.allMatches(gradle).length, 3);
    for (final dir in ['values', 'values-ja']) {
      final xml = File('android/app/src/main/res/$dir/dev_app_label.xml')
          .readAsStringSync();
      final label = RegExp(r'<string name="dev_app_label"[^>]*>([^<]+)</string>')
          .firstMatch(xml)?[1];
      expect(label, isNotNull, reason: '$dir has no dev_app_label');
      // Her label is "SNGNav"; the .dev label must differ in its FIRST word,
      // so a launcher that truncates the end still shows the difference.
      expect(label!.startsWith('SNGNav'), isFalse, reason: '$dir: $label');
    }
  });

  test('an injected signing property with an empty value is refused', () {
    expect(gradle, contains('fun emptyInjectedSigning(): List<String>'));
    // The predicate itself, over every property AGP reads: present AND empty.
    // A mutation that disables it keeps the function's name, so the name
    // alone passed it (M4, 2026-10-04).
    expect(
        gradle,
        contains('listOf("store.file", "store.password", "key.alias", '
            '"key.password", "store.type").filter {'));
    expect(
      RegExp(r'\.filter \{\s*hasProperty\("android\.injected\.signing\.\$it"\) &&\s*'
              r'\(findProperty\("android\.injected\.signing\.\$it"\) as String\?\)'
              r'\.isNullOrBlank\(\)\s*\}')
          .hasMatch(gradle),
      isTrue,
      reason: 'an injected property must be refused when present and empty',
    );
    // Every task that reads a signer refuses it: release, profile and debug.
    expect('source.problem?.let {'.allMatches(gradle).length, 3);
  });

  test('the Play preflight reads the same pin, every signer, and refuses a '
      'development build', () {
    final s = File('tool/preflight_play_upload.sh').readAsStringSync();
    expect(s, contains(r'PIN_FILE="$REPO_ROOT/tool/upload_key_certificate_sha256"'));
    expect(s, contains(r'check_signer "$upload_pin" "$signer_out"'));
    expect(s, isNot(contains('EXPECTED_SIGNER_CN')));
    expect(s, contains(r'check_not_dev_release "$dev_release_state"'));
  });

  test("the preflight's live run FAILS on gate 1's verdict and on the "
      'package, at their call sites', () {
    // --self-test drives the predicates, never their call sites. With gate
    // 1's `if` made to ignore its verdict (`check_signer ... || true`), the
    // self-test stayed 80/80 and this file stayed green, and a bundle signed
    // by another key got PREFLIGHT PASS (FBR R131 mutation M2c, 2026-10-04).
    // So each call site is pinned whole: the bare predicate is the condition,
    // and its else-branch counts the failed gate.
    final s = File('tool/preflight_play_upload.sh').readAsStringSync();
    final live = s.substring(s.indexOf('# ---------------------------------'
        '------------------------------- live run'));
    void site(String call, {String indent = ''}) {
      final i = RegExp.escape(indent);
      final block = RegExp(
          '^${i}if ${RegExp.escape(call)}; then\n'
          '(?:$i  [^\n]*\n)+'
          '${i}else\n'
          '$i  fails=\\\$\\(\\(fails\\+1\\)\\)\n'
          '${i}fi\$',
          multiLine: true);
      expect(block.allMatches(live).length, 1,
          reason: 'the call site `if $call; then … else fails=… fi` is '
              'missing or altered');
    }

    site(r'check_signer "$upload_pin" "$signer_out"');
    site(r'check_app_id "$APP_ID" "$aab_pkg" bundle');
    site(r'check_app_id "$APP_ID" "$apk_pkg" APK', indent: '  ');
    // Those are the only calls in the live run: no second call can carry
    // the verdict past the pinned one.
    expect('check_signer '.allMatches(live).length, 1);
    expect('check_app_id '.allMatches(live).length, 2);
  });

  test("the preflight's live run never forgets a failed gate, and passes "
      'only at its verdict', () {
    // The call-site pins read the shape of each `if`, not what its OK branch
    // does. With `fails=0` added to gate 1's OK branch, the self-test stayed
    // 92/92 and this file stayed green, and a .dev bundle printed WRONG
    // PACKAGE twice and then PREFLIGHT PASS, rc 0 (FBR mutation M2f,
    // 2026-10-04). So the counter is pinned whole: set to 0 once, before any
    // gate; after that only ever incremented; read only by the verdict.
    final s = File('tool/preflight_play_upload.sh').readAsStringSync();
    final live = s.substring(s.indexOf('# ---------------------------------'
        '------------------------------- live run'));
    const inc = r'fails=$((fails+1))';
    const init = 'fails=0';
    const verdict = r'if [ "$fails" -eq 0 ]; then';
    const report =
        r'echo "PREFLIGHT FAIL — $fails gate(s) failed. Do not upload."';
    final other = <String>[];
    var inits = 0, verdicts = 0, reports = 0, incs = 0;
    for (final raw in live.split('\n')) {
      final l = raw.trim();
      if (l.startsWith('#') || !l.contains('fails')) continue;
      if (l == init) {
        inits++;
      } else if (l == verdict) {
        verdicts++;
      } else if (l == report) {
        reports++;
      } else {
        incs += inc.allMatches(l).length;
        if (l.replaceAll(inc, '').contains('fails')) other.add(l);
      }
    }
    expect(other, isEmpty,
        reason: 'after it is set, only `$inc` may touch the counter');
    expect(inits, 1, reason: 'the counter is set to 0 exactly once');
    expect(verdicts, 1);
    expect(reports, 1);
    // Every failed gate counts. With one increment deleted, the self-test
    // stayed 92/92 and this file stayed green (AAE round 4, MF5). Each FAIL
    // note in the live run carries an increment on its own line or the next,
    // and the number of increments is pinned, so adding or removing a gate
    // takes two deliberate edits, as changing the upload key does.
    final lines = live.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('note "FAIL')) continue;
      final counted = lines[i].contains(inc) ||
          (i + 1 < lines.length && lines[i + 1].trim() == inc);
      expect(counted, isTrue,
          reason: 'a FAIL that is not counted: ${lines[i].trim()}');
    }
    expect(incs, 16,
        reason: 'the live run had 16 increments on 2026-10-04; a gate was '
            'added or one stopped counting');
    final setAt = live.indexOf('\n$init\n');
    expect(setAt, greaterThan(0));
    expect(setAt, lessThan(live.indexOf('if check_bundle_matches_apk ')),
        reason: 'the counter must be set before the first gate');
    // The one way to PASS is the verdict: after the counter is set, `exit 0`
    // appears once, inside it, and PREFLIGHT PASS is printed nowhere else.
    final after = live.substring(setAt);
    expect('exit 0'.allMatches(after).length, 1);
    expect(
      RegExp(r'\nif \[ "\$fails" -eq 0 \]; then\n'
              r'  echo "PREFLIGHT PASS[^\n]*\n'
              r'(?:  [^\n]*\n)*'
              r'  exit 0\n'
              r'fi\n')
          .hasMatch(after),
      isTrue,
      reason: 'PASS and exit 0 must sit inside the verdict',
    );
    final printed = s
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#') && l.contains('PREFLIGHT PASS'))
        .toList();
    expect(printed, hasLength(1), reason: printed.join('\n'));
  });

  test("the preflight's APP_ID is the build's applicationId, and a bundle "
      'named alone reads no APK', () {
    final s = File('tool/preflight_play_upload.sh').readAsStringSync();
    final appId = RegExp(r'^APP_ID="([^"]+)"$', multiLine: true)
        .allMatches(s)
        .map((m) => m[1])
        .toList();
    expect(appId, hasLength(1));
    expect(gradle, contains('applicationId = "${appId.single}"'));
    // The default APK path is replaced, before any gate, by what apk_to_read
    // says (nothing, when a bundle was named alone): FBR R131 run I10a2.
    final live = s.substring(s.indexOf('# ---------------------------------'
        '------------------------------- live run'));
    expect(live, contains(r'APK="$(apk_to_read "$GIVEN_AAB" "$GIVEN_APK" "$APK")"'));
    expect(live.indexOf(r'APK="$(apk_to_read'),
        lessThan(live.indexOf('-- artifacts under test')));
  });

  test('the development command the refusal prints builds before it runs', () {
    // `flutter run --release` picks the app it stops on quit before it
    // builds; on a tree with no .dev APK left, that is her ID. The printed
    // command builds the .dev APK first (FBR R133 D4b; AAE round 4 D4r/D4g).
    const twoStep = 'SNGNAV_DEV_RELEASE=1 flutter build apk --release && '
        'SNGNAV_DEV_RELEASE=1 flutter run --release';
    expect(gradle, contains('"    $twoStep\\n" +'));
    // No line of the refusal suggests the run alone.
    expect(gradle, isNot(contains('"    SNGNAV_DEV_RELEASE=1 flutter run --release"')));
    expect(gradle, isNot(contains('"    SNGNAV_DEV_RELEASE=1 flutter run --release\\n"')));
  });

  test('the upload key never signs a debug build, which keeps her ID', () {
    // AGP 9.1.0 applies injected signing to the debug variant too. On 989ec9d
    // a debug build with the four properties naming the pinned key built her
    // ID, signed by that key, at pubspec's versionCode, with no check and no
    // ledger row (BIS round 3, O1; board 36.17 D-3; AAE run R1). Gradle cannot
    // run here, so this pins the wiring, the source, the rule and the throw.
    expect(
      RegExp(r'if \(name == "preDebugBuild"\) \{\s*'
              r'dependsOn\(assertDebugSigner\)')
          .hasMatch(gradle),
      isTrue,
      reason: 'preDebugBuild (flutter run, build apk --debug, assembleDebug, '
          'installDebug, a signed debug build from the IDE) must run it',
    );
    final at = gradle.indexOf('val assertDebugSigner = tasks.register("assertDebugSigner") {');
    expect(at, greaterThan(0), reason: 'the task is gone');
    final task = gradle.substring(at, gradle.indexOf('\ntasks.configureEach {', at));
    // The debug build type's signer, read in AGP's order (injected first).
    expect(task, contains('val source = signerSourceFor("debug")'));
    // An empty injected value names no key: refused, as for release and profile.
    expect(
      RegExp(r'doLast \{\s*source\.problem\?\.let \{\s*'
              r'throw GradleException\("DEBUG SIGNER: refused before packaging\. \$it\."\)')
          .hasMatch(task),
      isTrue,
    );
    // The one rule, thrown, before anything is said or allowed.
    final call = RegExp(r'notHerReleaseSignerRefusal\(source, cert, pin\)\?\.let \{ why ->\s*'
        r'throw GradleException\(\s*"DEBUG SIGNER: refused before packaging\.');
    expect(call.hasMatch(task), isTrue,
        reason: 'a debug build the upload key would sign must be refused by '
            'a thrown exception');
    expect(task.indexOf('notHerReleaseSignerRefusal('),
        lessThan(task.indexOf('logger.')),
        reason: 'the rule must run before the build is allowed');
  });

  test('a debug build says what it did not read, and logs quietly only what '
      'it read', () {
    // "ANOTHER KEY" only where the certificate and the pin were both read
    // (the V14 shape of BIS round 3 F1, not repeated here).
    expect(
      RegExp(r'fun debugSignerStatement\([\s\S]*?return when \{\s*'
              r'c != null && p != null ->\s*"ANOTHER KEY\.')
          .hasMatch(gradle),
      isTrue,
    );
    final words = gradle
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//') && l.contains('ANOTHER KEY'))
        .toList();
    expect(words, hasLength(1), reason: words.join('\n'));
    // Out of sight (info) only when the debug key by construction was read
    // and compared; otherwise at the level `flutter run` shows.
    expect(
      RegExp(r'if \(source\.debugKeyByConstruction && cert\.isSuccess && pin\.isSuccess\) \{\s*'
              r'logger\.info\(said\)\s*\} else \{\s*logger\.quiet\(said\)\s*\}')
          .hasMatch(gradle),
      isTrue,
    );
  });

  test('the fallback is no longer described as unable to ship', () {
    // The comment this gate replaces said a debug-signed release "cannot
    // silently ship" because Play rejects it. It shipped by sideload.
    expect(gradle, isNot(contains('cannot silently ship')));
  });
}
