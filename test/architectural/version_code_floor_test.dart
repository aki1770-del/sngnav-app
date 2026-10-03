// A build signed with the release key refuses a versionCode that is already
// spent, and the Play preflight refuses one too. Both read
// tool/version_code_floor. Gradle cannot run in a test, so this pins the
// pieces in the source: if the floor file goes, is lowered below its seed, or
// the wiring is removed, it fails here as well as in a release build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The file's number: the ONLY line that is neither blank nor a comment.
/// Null when there is none, when there are several, or when it is not an
/// integer (the gate and the preflight refuse all three).
int? floorNumber(String text) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  return lines.length == 1 ? int.tryParse(lines.single) : null;
}

void main() {
  test('tool/version_code_floor holds the spent floor, and it is not lowered',
      () {
    final f = File('tool/version_code_floor');
    expect(f.existsSync(), isTrue, reason: 'the spent-code floor file is gone');
    final n = floorNumber(f.readAsStringSync());
    expect(n, isNotNull,
        reason: 'it must hold exactly one number line, and that line a number');
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
    // The rows are written by the packaging tasks themselves, so every path
    // that packages a release artifact (install, package, assemble, bundle)
    // records it.
    expect(g,
        contains('if (name == "packageRelease") finalizedBy("recordMintedReleaseApk")'));
    expect(g,
        contains('if (name == "signReleaseBundle") finalizedBy("recordMintedReleaseBundle")'));
    // Injected signing (the IDE path, no key.properties) is release signing.
    expect(g, contains('hasProperty("android.injected.signing.store.file")'));
    // One APK output at the release code: split-per-abi codes are refused.
    expect(g, contains('codes.size != 1 || codes.any { it.second != code }'));
  });

  test('the Play preflight reads the same floor at gate 4', () {
    final s = File('tool/preflight_play_upload.sh').readAsStringSync();
    expect(s, contains(r'FLOOR_FILE="$REPO_ROOT/tool/version_code_floor"'));
    expect(s, contains(r'check_version_code_floor "$vc" "$floor"'));
    // A redirect of the ledger is read IN ADDITION to the real one.
    expect(s, contains(r'MINT_LEDGER_REAL="$HOME/.sngnav/minted_release.tsv"'));
  });
}
