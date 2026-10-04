// A release build is signed by the upload key, or it stops before anything is
// packaged (assertReleaseSigner in android/app/build.gradle.kts). Builds of
// this app reach phones by sideload, and an installed app takes an update only
// from the certificate that signed it, so a debug-signed release on her phone
// would block every later fix. Gradle cannot run in a test, so this pins the
// pieces in the source: if the digest file goes or is malformed, or the
// wiring or the refusal is removed, it fails here as well as in a release
// build.
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

  test('the fallback is no longer described as unable to ship', () {
    // The comment this gate replaces said a debug-signed release "cannot
    // silently ship" because Play rejects it. It shipped by sideload.
    expect(gradle, isNot(contains('cannot silently ship')));
  });
}
