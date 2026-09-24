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
/// Every repo-relative path the block names must exist. Where the block says
/// the cited Dart file imports the dependency, that file must carry a real
/// `import`/`export` directive for it — a commented-out import is not one.
///
/// HONEST BOUND. It checks what the comments CITE, not whether every dependency
/// has a comment, and it cannot tell a path cited as an importer from one cited
/// for another reason except by the block's own word "import". Elided shorthand
/// (`android/.../MainActivity.kt`) is not a path; it is counted as skipped, and
/// the count is printed, never passed silently.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A repo-relative path with an extension. A sentence-final period is not part
/// of it: the backtracking `\.\w+` tail ends the match at the last extension.
final RegExp _citedPath =
    RegExp(r'(?<![\w/.])((?:lib|test|tool|assets|android)/[\w./-]+\.\w+)');

/// A dependency entry: exactly two spaces of indent, then the package name.
final RegExp _entry = RegExp(r'^  ([a-z_][a-z0-9_]*):');

class CitationAudit {
  final List<String> problems = [];
  final List<String> checkedPaths = [];
  final List<String> checkedImports = [];
  final List<String> skipped = [];
}

/// Pure over its inputs so the self-test below can feed it the real defect.
CitationAudit auditPubspecCitations(
  String pubspec, {
  required bool Function(String path) exists,
  required String Function(String path) read,
}) {
  final audit = CitationAudit();
  final block = <String>[];
  for (final line in pubspec.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#')) {
      block.add(trimmed);
      continue;
    }
    if (block.isNotEmpty) {
      final text = block.join(' ');
      final dependency = _entry.firstMatch(line)?.group(1);
      final claimsImport = text.toLowerCase().contains('import');
      for (final m in _citedPath.allMatches(text)) {
        final path = m.group(1)!;
        if (path.contains('...')) {
          audit.skipped.add(path);
          continue;
        }
        audit.checkedPaths.add(path);
        if (!exists(path)) {
          audit.problems.add(
            'pubspec.yaml cites $path'
            '${dependency == null ? '' : ' (above `$dependency`)'}'
            ' and it does not exist on this tree',
          );
          continue;
        }
        if (dependency != null && claimsImport && path.endsWith('.dart')) {
          audit.checkedImports.add('$path -> $dependency');
          final directive = RegExp(
            '^\\s*(?:import|export)\\s+[\'"]package:$dependency/',
            multiLine: true,
          );
          if (!directive.hasMatch(read(path))) {
            audit.problems.add(
              'pubspec.yaml justifies `$dependency` by saying $path imports '
              'it, and $path has no import of package:$dependency',
            );
          }
        }
      }
      block.clear();
    }
  }
  return audit;
}

void main() {
  test('the guard sees the defect it exists for (self-test on a fixture shaped '
      'like the 2026-08-23 landing)', () {
    const pubspec = '''
dependencies:
  # Declared DIRECT because lib/services/diary.dart now imports it. A drift
  # guard pins our labels to its terms (test/services/diary_vocab_test.dart).
  vocab_pkg: ^0.2.3
''';
    // The shipped shape: the importer exists but imports only something else
    // (a commented-out import does not count), and the drift guard is absent.
    final broken = auditPubspecCitations(
      pubspec,
      exists: (p) => p == 'lib/services/diary.dart',
      read: (_) => "// import 'package:vocab_pkg/vocab_pkg.dart';\n"
          "import 'package:path_provider/path_provider.dart';\n",
    );
    expect(broken.problems, hasLength(2), reason: broken.problems.join('\n'));
    expect(broken.problems.join('\n'), contains('diary_vocab_test.dart'));
    expect(broken.problems.join('\n'), contains('no import of package:vocab_pkg'));

    // Control: the same comment over a tree where both are true passes.
    final whole = auditPubspecCitations(
      pubspec,
      exists: (_) => true,
      read: (_) => "import 'package:vocab_pkg/vocab_pkg.dart' show X;\n",
    );
    expect(whole.problems, isEmpty);
    // Both cited Dart files are held to the block's word "imports": the drift
    // guard reads the package's terms, so it must import the package too.
    expect(whole.checkedImports, [
      'lib/services/diary.dart -> vocab_pkg',
      'test/services/diary_vocab_test.dart -> vocab_pkg',
    ]);
  });

  test('every path pubspec.yaml cites exists, and every cited importer imports '
      'the dependency it justifies', () {
    final audit = auditPubspecCitations(
      File('pubspec.yaml').readAsStringSync(),
      exists: (p) => File(p).existsSync() || Directory(p).existsSync(),
      read: (p) => File(p).readAsStringSync(),
    );
    // ignore: avoid_print
    print('PUBSPEC_CITATIONS paths=${audit.checkedPaths.length} '
        'imports=${audit.checkedImports.length} '
        'skipped=${audit.skipped} problems=${audit.problems.length}');
    // Guard the guard: a parser that finds nothing would pass vacuously.
    expect(audit.checkedPaths, isNotEmpty,
        reason: 'no cited path was found in pubspec.yaml; this guard would '
            'protect nothing');
    expect(audit.checkedImports, isNotEmpty,
        reason: 'no import justification was found; the half of this guard '
            'that caught the 2026-08-23 landing would protect nothing');
    expect(audit.problems, isEmpty, reason: audit.problems.join('\n'));
  });
}
