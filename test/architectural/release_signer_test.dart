// A release build is signed by the upload key, or it stops before anything is
// packaged (assertReleaseSigner in android/app/build.gradle.kts). Builds of
// this app reach phones by sideload, and an installed app takes an update only
// from the certificate that signed it, so a debug-signed release on her phone
// would block every later fix. A development build (SNGNAV_DEV_RELEASE=1) and
// every profile build are another app, dev.aki1770del.sngnav_app.dev, so
// none can replace hers. Gradle cannot run in a test, so this pins the pieces
// in the source: if the digest file goes, is malformed or changes value, or
// the wiring, the refusal or the suffix is removed, it fails here as well as
// in a release build.
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
    expect(
      RegExp(r'if \(!debugKey && c != null && pin\.getOrNull\(\) == c\.sha256\) \{'
              r'(?:\s*//[^\n]*)*\s*if \(allowed\) \{\s*throw GradleException\(')
          .hasMatch(gradle),
      isTrue,
      reason: 'the upload key under SNGNAV_DEV_RELEASE=1 must be refused',
    );
    expect(
      RegExp(r'if \(!source\.debugKeyByConstruction\) \{[\s\S]*?'
              r'if \(c == null \|\| p == null \|\| c\.sha256 == p\) \{[\s\S]*?'
              r'throw GradleException\(')
          .hasMatch(gradle),
      isTrue,
      reason: 'a profile build the upload key would sign must be refused',
    );
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
    // Both tasks that read a signer refuse it: release and profile.
    expect('source.problem?.let {'.allMatches(gradle).length, 2);
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

  test('the fallback is no longer described as unable to ship', () {
    // The comment this gate replaces said a debug-signed release "cannot
    // silently ship" because Play rejects it. It shipped by sideload.
    expect(gradle, isNot(contains('cannot silently ship')));
  });
}
