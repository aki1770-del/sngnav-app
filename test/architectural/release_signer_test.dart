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

  test('an injected signing property with an empty value is refused', () {
    expect(gradle, contains('fun emptyInjectedSigning(): List<String>'));
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

  test('the fallback is no longer described as unable to ship', () {
    // The comment this gate replaces said a debug-signed release "cannot
    // silently ship" because Play rejects it. It shipped by sideload.
    expect(gradle, isNot(contains('cannot silently ship')));
  });
}
