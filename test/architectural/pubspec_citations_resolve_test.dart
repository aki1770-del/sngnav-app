/// Architectural guard — a pubspec comment that JUSTIFIES a dependency by
/// naming the file that uses it is a claim, and the claim must be true on the
/// line that ships.
///
/// WHY (2026-09-25). `pubspec.yaml` declares `japanese_snow_vocabulary` DIRECT
/// "because lib/services/drive_diary.dart now imports it", and says "a drift
/// guard pins our labels to its terms (test/services/drive_diary_vocabulary_test.dart)".
/// The declaration reached the shipping line on 2026-08-23. The import and the
/// drift guard did not: they sat uncommitted in a working tree and survived
/// only in preservation snapshots. For a month the line carried a dependency
/// whose written reason was false, and nothing failed. Dart's tooling warns
/// about an import with no declaration (`depend_on_referenced_packages`); it
/// never warns about a declaration whose cited importer imports nothing.
///
/// This guard reads the comment block directly above each pubspec entry.
/// Every repo-relative path the block names must exist AND be committed.
/// Where the block says the cited Dart file imports the dependency, that file
/// must carry a real `import`/`export` directive for it — one in a `//` line,
/// a `/* */` block or a string is not one.
///
/// HARDENED (2026-09-25). An independent mutation corpus showed the first
/// version passing three real defects:
///
/// - a blank line between the comment and its entry detached the claim, the
///   import was removed, and the guard's own count fell from `imports=6` to
///   `imports=4` while it still reported `problems=0` — a silent drop;
/// - an import wrapped in a `/* */` block still counted as an import;
/// - the cited drift guard present on disk but not committed passed, because
///   the guard read only the working tree — the founding defect's own shape.
///
/// It also neither checked nor counted a citation under `docs/`. Now: a block
/// attaches to its entry across blank lines, and a block that claims an
/// import but sits above no entry fails; the Dart file is read with comments
/// stripped (test/support/dart_source.dart); every cited path must be tracked
/// by git; a path under ANY directory of this package is checked; and the
/// exact set of import checks is pinned, so one that stops being checked fails
/// by name instead of lowering a number nobody reads.
///
/// HONEST BOUND. It checks what the comments CITE, not whether every dependency
/// has a comment, and it cannot tell a path cited as an importer from one cited
/// for another reason except by the block's own word "import". Elided shorthand
/// (`android/.../MainActivity.kt`) is not a path; it is counted as skipped, and
/// the count is printed, never passed silently. A path-shaped token that names
/// something outside this package (an API route) is not checked; the set of
/// them is pinned below, so a new one is looked at rather than passed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

/// A path-shaped token: segments joined by `/`, ending in an extension. Not
/// preceded by `/`, `.`, `:`, `@`, `-` or a word character, so the path inside
/// a URL (`https://host/a/b.json`) is not read as one. A sentence-final period
/// is not part of it: the backtracking `\.\w+` tail ends the match at the last
/// extension.
final RegExp _pathToken = RegExp(r'(?<![\w/.:@-])((?:[\w.-]+/)+[\w.-]*\.\w+)');

/// A dependency entry: exactly two spaces of indent, then the package name.
final RegExp _entry = RegExp(r'^  ([a-z_][a-z0-9_]*):');

/// The block's own word for an import claim. A word, so "important" is not one.
final RegExp _importWord =
    RegExp(r'\bimport(?:s|ed|ing)?\b', caseSensitive: false);

class CitationAudit {
  final List<String> problems = [];
  final List<String> checkedPaths = [];
  final List<String> checkedImports = [];
  final List<String> skipped = [];

  /// Path-shaped tokens whose first segment is no directory of this package.
  final List<String> notInThisPackage = [];
}

/// Whether [dartSource] carries a real `import`/`export` directive for
/// `package:[dependency]/` — not in a comment, not inside a string.
bool importsPackage(String dartSource, String dependency) {
  final uncommented = dartCodeOnly(dartSource, keepStrings: true);
  final codeOnly = dartCodeOnly(dartSource);
  final directive = RegExp(
    '^[ \\t]*(import|export)[ \\t]+[\'"]package:${RegExp.escape(dependency)}/',
    multiLine: true,
  );
  for (final m in directive.allMatches(uncommented)) {
    final keyword = m.start + m.group(0)!.indexOf(m.group(1)!);
    // In the code-only view a keyword inside a string is blank.
    if (codeOnly.startsWith(m.group(1)!, keyword)) return true;
  }
  return false;
}

/// Pure over its inputs so the self-test below can feed it the real defects.
CitationAudit auditPubspecCitations(
  String pubspec, {
  required bool Function(String path) exists,
  required bool Function(String path) tracked,
  required bool Function(String directory) isPackageDirectory,
  required String Function(String path) read,
}) {
  final audit = CitationAudit();

  void check(List<String> block, {String? dependency, required String below}) {
    final text = block.join(' ');
    final claimsImport = _importWord.hasMatch(text);
    for (final m in _pathToken.allMatches(text)) {
      final path = m.group(1)!;
      if (path.contains('...')) {
        audit.skipped.add(path);
        continue;
      }
      if (!isPackageDirectory(path.split('/').first)) {
        audit.notInThisPackage.add(path);
        continue;
      }
      audit.checkedPaths.add(path);
      final where = dependency == null ? '' : ' (above `$dependency`)';
      if (!exists(path)) {
        audit.problems.add(
            'pubspec.yaml cites $path$where and it does not exist on this tree');
        continue;
      }
      if (!tracked(path)) {
        audit.problems.add('pubspec.yaml cites $path$where and it exists on '
            'disk but is not committed, so the line that ships does not have '
            'it (the 2026-08-23 landing had exactly this shape)');
      }
      if (!claimsImport || !path.endsWith('.dart')) continue;
      if (dependency == null) {
        audit.problems.add('pubspec.yaml says $path imports a dependency, but '
            'the comment sits above no dependency entry (it is followed by '
            '`${below.trim()}`), so nothing can check which package it means');
        continue;
      }
      audit.checkedImports.add('$path -> $dependency');
      if (!importsPackage(read(path), dependency)) {
        audit.problems.add(
          'pubspec.yaml justifies `$dependency` by saying $path imports '
          'it, and $path has no import of package:$dependency',
        );
      }
    }
  }

  final block = <String>[];
  var blankSinceBlock = false;
  for (final line in pubspec.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#')) {
      if (block.isNotEmpty && blankSinceBlock) {
        // A new comment after a blank line: the earlier block is on its own.
        check(block, below: '<a blank line, then another comment>');
        block.clear();
      }
      blankSinceBlock = false;
      block.add(trimmed);
      continue;
    }
    if (block.isEmpty) continue;
    if (trimmed.isEmpty) {
      // A blank line does not detach a comment from the entry it describes.
      blankSinceBlock = true;
      continue;
    }
    check(block, dependency: _entry.firstMatch(line)?.group(1), below: line);
    block.clear();
    blankSinceBlock = false;
  }
  if (block.isNotEmpty) check(block, below: '<end of file>');
  return audit;
}

/// Every import justification pubspec.yaml makes today, as `path -> package`.
/// Pinned so a claim that stops being checked fails by name. On 2026-09-25 a
/// blank line made two of these six stop being checked, and the only trace
/// was `imports=4` in a line nobody reads. Adding a justification means adding
/// it here; removing one means removing it here.
const Set<String> _expectedImportChecks = {
  'lib/actuators/hardened_tts_engine.dart -> flutter_tts',
  'lib/services/voice_lane_readiness.dart -> flutter_tts',
  'lib/services/drive_diary.dart -> japanese_snow_vocabulary',
  'test/services/drive_diary_vocabulary_test.dart -> japanese_snow_vocabulary',
  'lib/services/radiative_frost_decline.dart -> navigation_safety_calibration',
  'test/services/ice_watch_scope_envelope_test.dart -> '
      'navigation_safety_calibration',
};

/// Path-shaped tokens in pubspec.yaml that name something outside this
/// package, and why each is not a path here.
const Map<String, String> _notInThisPackage = {
  'bosai/warning/data/warning/050000.json': 'a JMA API route, measured by GET',
  'bosai/warning/data/r8/050000.json': 'a JMA API route, measured by GET',
};

/// The files git tracks under the current directory, or null with the reason.
(Set<String>?, String) _trackedFiles() {
  try {
    final r = Process.runSync('git', ['ls-files', '-z']);
    if (r.exitCode != 0) return (null, 'exit ${r.exitCode}: ${r.stderr}');
    return (
      (r.stdout as String).split('\u0000').where((s) => s.isNotEmpty).toSet(),
      '',
    );
  } on ProcessException catch (e) {
    return (null, e.message);
  }
}

void main() {
  const pubspec = '''
dependencies:
  # Declared DIRECT because lib/services/diary.dart now imports it. A drift
  # guard pins our labels to its terms (test/services/diary_vocab_test.dart).
  vocab_pkg: ^0.2.3
''';
  const imported = "import 'package:vocab_pkg/vocab_pkg.dart' show X;\n";
  bool packageDirs(String d) => const {'lib', 'test', 'docs'}.contains(d);

  CitationAudit audit(
    String spec, {
    bool Function(String)? exists,
    bool Function(String)? tracked,
    String Function(String)? read,
  }) =>
      auditPubspecCitations(
        spec,
        exists: exists ?? (_) => true,
        tracked: tracked ?? (_) => true,
        isPackageDirectory: packageDirs,
        read: read ?? (_) => imported,
      );

  test('the guard sees the defect it exists for (self-test on a fixture shaped '
      'like the 2026-08-23 landing)', () {
    // The shipped shape: the importer exists but imports only something else
    // (a commented-out import does not count), and the drift guard is absent.
    final broken = audit(
      pubspec,
      exists: (p) => p == 'lib/services/diary.dart',
      read: (_) => "// import 'package:vocab_pkg/vocab_pkg.dart';\n"
          "import 'package:path_provider/path_provider.dart';\n",
    );
    expect(broken.problems, hasLength(2), reason: broken.problems.join('\n'));
    expect(broken.problems.join('\n'), contains('diary_vocab_test.dart'));
    expect(broken.problems.join('\n'), contains('no import of package:vocab_pkg'));

    // Control: the same comment over a tree where both are true passes.
    final whole = audit(pubspec);
    expect(whole.problems, isEmpty);
    // Both cited Dart files are held to the block's word "imports": the drift
    // guard reads the package's terms, so it must import the package too.
    expect(whole.checkedImports, [
      'lib/services/diary.dart -> vocab_pkg',
      'test/services/diary_vocab_test.dart -> vocab_pkg',
    ]);
  });

  test('self-test: the shapes that got past this guard on 2026-09-25 now fail',
      () {
    final detachedByBlank =
        pubspec.replaceFirst('  vocab_pkg:', '\n  vocab_pkg:');
    // A blank line alone is not a defect: the claim still attaches and holds.
    final blankOnly = audit(detachedByBlank);
    expect(blankOnly.problems, isEmpty, reason: blankOnly.problems.join('\n'));
    expect(blankOnly.checkedImports, hasLength(2));
    // A blank line plus the import removed: caught, not skipped.
    final blankAndGone = audit(detachedByBlank,
        read: (_) => "// import 'package:vocab_pkg/vocab_pkg.dart';\n");
    expect(blankAndGone.problems.join('\n'),
        contains('no import of package:vocab_pkg'));

    // A claim that sits above no entry at all fails instead of vanishing.
    final orphan = audit(pubspec.replaceFirst(
        '  vocab_pkg: ^0.2.3', 'dev_dependencies:\n  vocab_pkg: ^0.2.3'));
    expect(orphan.problems.join('\n'), contains('sits above no dependency entry'));

    // The import inside a block comment, a nested block comment, or a string.
    for (final hidden in [
      "/*\n$imported*/\n",
      "/* outer /* inner */\n$imported*/\n",
      "const s = '''\n$imported''';\n",
    ]) {
      final r = audit(pubspec, read: (_) => hidden);
      expect(r.problems.join('\n'), contains('no import of package:vocab_pkg'),
          reason: 'an import inside ${hidden.split('\n').first} is not one');
    }
    // A URL with // inside a string does not start a comment.
    expect(importsPackage(
        "const u = 'https://x.y';\nimport 'package:vocab_pkg/a.dart';\n",
        'vocab_pkg'), isTrue);

    // The cited file present on disk but not committed.
    final uncommitted = audit(pubspec,
        tracked: (p) => p != 'test/services/diary_vocab_test.dart');
    expect(uncommitted.problems.join('\n'), contains('is not committed'));

    // A citation under docs/ is checked; one outside the package is counted.
    final docs = audit('''
dependencies:
  # Verification owed (docs/checklist.md); route bosai/x/050000.json.
  other_pkg: ^1.0.0
''', exists: (p) => p != 'docs/checklist.md');
    expect(docs.problems.join('\n'), contains('docs/checklist.md'));
    expect(docs.notInThisPackage, ['bosai/x/050000.json']);

    // "important" is not a claim that something imports anything.
    final important = audit('''
dependencies:
  # Important: lib/a.dart reads it.
  other_pkg: ^1.0.0
''', read: (_) => '');
    expect(important.checkedImports, isEmpty);
    expect(important.problems, isEmpty);
  });

  test('every path pubspec.yaml cites exists and is committed, and every '
      'cited importer imports the dependency it justifies', () {
    final (files, why) = _trackedFiles();
    expect(files, isNotNull,
        reason: 'cannot tell whether the cited paths are committed: '
            '`git ls-files` failed ($why). This guard exists because a cited '
            'file sat uncommitted for a month; run it in a git checkout.');
    final trackedFiles = files!;
    final result = auditPubspecCitations(
      File('pubspec.yaml').readAsStringSync(),
      exists: (p) => File(p).existsSync() || Directory(p).existsSync(),
      tracked: (p) =>
          trackedFiles.contains(p) ||
          trackedFiles.any((f) => f.startsWith('$p/')),
      isPackageDirectory: (d) => Directory(d).existsSync(),
      read: (p) => File(p).readAsStringSync(),
    );
    // ignore: avoid_print
    print('PUBSPEC_CITATIONS paths=${result.checkedPaths.length} '
        'imports=${result.checkedImports.length} '
        'skipped=${result.skipped} '
        'notInThisPackage=${result.notInThisPackage} '
        'problems=${result.problems.length}');
    // Guard the guard: a parser that finds nothing would pass vacuously.
    expect(result.checkedPaths, isNotEmpty,
        reason: 'no cited path was found in pubspec.yaml; this guard would '
            'protect nothing');
    expect(result.problems, isEmpty, reason: result.problems.join('\n'));

    final measured = result.checkedImports.toSet();
    final missing = _expectedImportChecks.difference(measured);
    final added = measured.difference(_expectedImportChecks);
    expect(missing.isEmpty && added.isEmpty, isTrue,
        reason: [
          if (missing.isNotEmpty)
            'these import justifications are no longer checked: $missing. A '
                'comment may have been detached from its entry or edited. If '
                'the claim was removed on purpose, remove it from '
                '_expectedImportChecks.',
          if (added.isNotEmpty)
            'these import justifications are new: $added. Pin them in '
                '_expectedImportChecks.',
        ].join('\n'));

    final unknown = result.notInThisPackage.toSet()
      ..removeAll(_notInThisPackage.keys);
    expect(unknown, isEmpty,
        reason: 'pubspec.yaml cites $unknown, which is under no directory of '
            'this package, so nothing checks it. If it is a file here, write '
            'it from the package root (lib/..., docs/...). If it names '
            'something outside the package, add it to _notInThisPackage with '
            'why.');
  });
}
