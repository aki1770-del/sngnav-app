// A build signed with the release key refuses a versionCode that is already
// spent, and the Play preflight refuses one too. Both read
// tool/version_code_floor. Gradle cannot run in a test, so this pins the
// pieces in the source: if the floor file goes, is lowered below its seed, or
// the wiring is removed, it fails here as well as in a release build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The first line that is neither blank nor a comment, as an integer.
int? floorNumber(String text) {
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    return int.tryParse(line);
  }
  return null;
}

void main() {
  test('tool/version_code_floor holds the spent floor, and it is not lowered',
      () {
    final f = File('tool/version_code_floor');
    expect(f.existsSync(), isTrue, reason: 'the spent-code floor file is gone');
    final n = floorNumber(f.readAsStringSync());
    expect(n, isNotNull, reason: 'its first non-comment line is not a number');
    expect(
      n,
      greaterThanOrEqualTo(12),
      reason: 'code 12 is installed on the maintainer\'s phone; '
          'the floor is raised, never lowered',
    );
  });

  test('a release build depends on assertVersionCodeUnspent and records its '
      'artifacts', () {
    final g = File('android/app/build.gradle.kts').readAsStringSync();
    expect(g, contains('tasks.register("assertVersionCodeUnspent")'));
    expect(
      RegExp(r'if \(name == "preReleaseBuild"\) \{\s*'
              r'dependsOn\(assertVersionCodeUnspent\)')
          .hasMatch(g),
      isTrue,
      reason: 'preReleaseBuild (assembleRelease, bundleRelease) must run it',
    );
    expect(g, contains('rootProject.file("../tool/version_code_floor")'));
    expect(g, contains('finalizedBy("recordMintedReleaseApk")'));
    expect(g, contains('finalizedBy("recordMintedReleaseBundle")'));
  });

  test('the Play preflight reads the same floor at gate 4', () {
    final s = File('tool/preflight_play_upload.sh').readAsStringSync();
    expect(s, contains(r'FLOOR_FILE="$REPO_ROOT/tool/version_code_floor"'));
    expect(s, contains(r'check_version_code_floor "$vc" "$floor"'));
  });
}
