// The commit in the identity triple must read back exactly, for any hex value,
// and a commit the app could not read must say so.
//
// Two halves, because the value crosses two layers:
//
//  1. The stamp. Gradle writes the short sha into a manifest <meta-data>
//     value, and aapt2 stores a value it can parse as a number AS a number:
//     measured with AGP 9.1.0's aapt2 (2.20), `4370561` became the integer
//     4370561, `0123456` became 123456, `0e12345` became the float 0.0 and
//     `1234e05` the float 123400000. `Bundle.getString` returns null for a
//     number, so the app fell back to UNKNOWN, and for `0123456` or
//     `0e12345` the digits were gone from the APK anyway. A value that
//     starts with `git:` is always stored as a string. The group below pins
//     that prefix on both sides, because a test cannot run aapt2; the device
//     check is in the change's description.
//
//  2. The display. The triple used to drop UNKNOWN without a word, so a
//     build whose commit could not be read showed two parts and looked
//     complete. Every non-sha state now has a word in the third slot.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/build_identity.dart';

const _self =
    '561b56fac98b6c1898d4dee6de988faca5eb1d35f31cf49b1a099c18c5994bc1';

BuildIdentity _withCommit(String? gitSha) => BuildIdentity(
      versionName: '0.0.2',
      versionCode: 12,
      packageName: 'dev.aki1770del.sngnav_app',
      selfSha256: _self,
      gitSha: gitSha,
      artifactCount: 1,
    );

void main() {
  group('the commit slot of the identity triple', () {
    // Every shape aapt2 was measured to mangle, plus ordinary ones.
    for (final sha in const [
      '1e84909',
      '4370561',
      '0123456',
      '0e12345',
      '1234e05',
      'f8c19ce',
      '4370561-dirty',
    ]) {
      test('$sha is shown exactly', () {
        expect(_withCommit(sha).display, '0.0.2 (12) · 561b56fac98b · $sha');
      });
    }

    test('a build made where git could not run says UNKNOWN', () {
      expect(
        _withCommit('UNKNOWN').display,
        '0.0.2 (12) · 561b56fac98b · UNKNOWN',
      );
    });

    test('a commit the app could not read says UNREADABLE', () {
      expect(
        _withCommit('UNREADABLE').display,
        '0.0.2 (12) · 561b56fac98b · UNREADABLE',
      );
      // No commit at all from the platform is the same abstention, never a
      // shorter triple that looks complete.
      expect(
        _withCommit(null).display,
        '0.0.2 (12) · 561b56fac98b · UNREADABLE',
      );
    });

    test('an unread identity is still the single word unknown', () {
      expect(const BuildIdentity.unknown().display, 'unknown');
    });
  });

  group('the stamp is a string for any hex value', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/dev/aki1770del/sngnav_app/MainActivity.kt',
    ).readAsStringSync();

    test('the manifest stamps git:<sha>, never the bare sha', () {
      expect(manifest, contains(r'android:value="git:${gitSha}"'));
      expect(manifest, isNot(contains(r'android:value="${gitSha}"')));
    });

    test('the app strips that prefix and never falls back to UNKNOWN', () {
      expect(activity, contains('GIT_SHA_PREFIX = "git:"'));
      expect(activity, isNot(contains('?: "UNKNOWN"')));
      expect(activity, contains('"UNREADABLE"'));
    });
  });
}
