// A build signed with the release key refuses a versionCode that is already
// spent, and the Play preflight refuses one too. Both read
// tool/version_code_floor. Gradle cannot run in a test, so this pins the
// pieces in the source: if the floor file goes, is lowered below its seed or
// below a code it names as spent, or the wiring is removed, it fails here as
// well as in a release build.
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

/// The highest code the file names as spent, from its comment lines of the
/// form `# 14: 0.0.2, release key ...`. A range line (`# 2-11: ...`) names
/// codes below the ones listed singly and is not read. Null when none.
int? highestNamedCode(String text) {
  final codes = RegExp(r'^#\s*(\d+):', multiLine: true)
      .allMatches(text)
      .map((m) => int.parse(m[1]!));
  return codes.isEmpty ? null : codes.reduce((a, b) => a > b ? a : b);
}

void main() {
  test('tool/version_code_floor holds the spent floor, and it is not lowered',
      () {
    final f = File('tool/version_code_floor');
    expect(f.existsSync(), isTrue, reason: 'the spent-code floor file is gone');
    final text = f.readAsStringSync();
    final n = floorNumber(text);
    expect(n, isNotNull,
        reason: 'it must hold exactly one number line, and that line a number');
    final named = highestNamedCode(text);
    expect(named, isNotNull,
        reason: 'the file names no spent code (lines of the form "# 14: ...")');
    expect(
      n,
      greaterThanOrEqualTo(named!),
      reason: 'the file names code $named as spent; '
          'the floor is raised, never lowered',
    );
    // The seed: 14 was spent on 2026-10-08, so lowering the number together
    // with the lines that name the codes above it still fails here.
    expect(
      n,
      greaterThanOrEqualTo(14),
      reason: 'code 14 is spent; the floor is raised, never lowered',
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
    // Which key signs a release is read by ONE rule, the signer gate's:
    // injected signing only when all four android.injected.signing.*
    // properties are set, as AGP requires. Until 2026-10-04 this line pinned
    // the floor's own rule, store.file alone, under which a debug-signed APK
    // wrote a ledger row as "injected signing".
    expect(g, contains('val releaseSignerSource = signerSourceFor("release")'));
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
