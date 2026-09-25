/// The update manifest's read set is CLOSED, and a new key goes back to the
/// reviewer who ruled on it.
///
/// WHY, written before this file. WDA, the reviewer who rules on what this
/// update channel may carry, ruled on 2026-09-25 that it carries version
/// facts, where the build is, and exactly one control fact (`manifest_url`),
/// and that any further key is a new decision that returns to WDA. The older
/// test in update_check_test.dart proves that stuffed prose fields do not
/// survive a parse, by checking the fields it knows. When the address reader
/// added `manifest_url`, nothing turned red: a test that checks known fields
/// cannot see a key nobody told it about. This one reads the parser and
/// requires the keys it reads to EQUAL WDA's list, in both directions, and
/// it fails on any read it cannot attribute. The machine catches the new
/// key; a reviewer does not have to notice it.
///
/// WDA's ruling, condition W-1, is recorded in the unit's masterplan at
/// `outputs/weaver-dignity-auditor/r122_4a_reader_nsc_snow_d4_2026_09_25/VERDICT.md`.
///
/// HOW. It reads `UpdateManifest.tryParse`, the one place the fetched JSON
/// is decoded, and follows the document through the four locals that hold
/// it: `decoded` (the top level), `latest`, `hist` (the history list) and
/// `r` (one history row). Every subscript on those must be a plain string
/// literal. Anything the scan cannot attribute FAILS rather than passing
/// unseen: a key that is not a literal, a subscript on an expression, a read
/// through another local, or one of the four used whole (copied, passed on,
/// iterated, interpolated), because each of those can read keys no literal
/// names.
///
/// HONEST BOUND. It reads source text through dart_views.dart, not a call
/// graph. A read made in another file, or by reflection, is outside it; the
/// last test holds the one other file that fetches a manifest to "decodes
/// nothing itself".
library;

import 'package:flutter_test/flutter_test.dart';

import 'dart_views.dart';

const _parserPath = 'lib/services/update_manifest.dart';
const _checkerPath = 'lib/services/update_check.dart';

/// WDA's list, as ruled: "`schema`; `latest.{versionCode, versionName,
/// artifact_url, package, sha256, size_bytes, signer_sha256}`;
/// `history[].{versionCode, sha256}`; `manifest_url`". The two containers,
/// `latest` and `history`, are read to reach the dotted keys, so they are
/// listed too.
const _wdaAllowlist = <String>{
  'schema',
  'latest',
  'latest.versionCode',
  'latest.versionName',
  'latest.artifact_url',
  'latest.package',
  'latest.sha256',
  'latest.size_bytes',
  'latest.signer_sha256',
  'history',
  'history[].versionCode',
  'history[].sha256',
  'manifest_url',
};

/// The local that holds each part of the document, and the path its keys
/// sit under. `hist` is the history LIST: it may be type-tested and walked
/// with `for (final r in hist)`, and nothing else.
const _mapLocals = {'decoded': '', 'latest': 'latest.', 'r': 'history[].'};
const _listLocal = 'hist';

const _wda = 'WDA ruled (2026-09-25, condition W-1) that the update channel '
    'carries version facts, the artifact URL and exactly ONE control fact, '
    'manifest_url, and that any further key is a new decision that returns '
    'to WDA before it merges. Do not widen the list in this file to make it '
    'pass.';

/// What [parserSource]'s tryParse reads: the key paths it names, and every
/// read it could not attribute.
({Set<String> keys, List<String> unattributed}) readSetOf(String parserSource) {
  final v = DartViews(parserSource);
  final head = RegExp(
    r'static\s+UpdateManifest\?\s+tryParse\s*\(\s*String\s+\w+\s*\)\s*\{',
  ).firstMatch(v.shape);
  if (head == null) {
    return (keys: <String>{}, unattributed: ['tryParse(String) was not found']);
  }
  final open = head.end - 1;
  final close = v.closingBrace(open);
  final keys = <String>{};
  final bad = <String>[];
  String where(int at) => 'line ${v.lineOf(at)}';
  const keywords = {'const', 'return', 'in', 'yield', 'await', 'case', 'else'};

  // 1. Every subscript in the body.
  for (final b in RegExp(r'\[').allMatches(v.shape.substring(0, close), open)) {
    final at = b.start;
    final before = v.shape.substring(open, at).trimRight();
    final prev = before.isEmpty ? '' : before[before.length - 1];
    if (!RegExp(r'[A-Za-z0-9_$)\]?!]').hasMatch(prev)) continue; // a list
    final recv =
        RegExp(r'([A-Za-z_$][A-Za-z0-9_$]*)\s*[?!]?$').firstMatch(before);
    if (recv != null && keywords.contains(recv.group(1))) continue;
    if (recv == null) {
      bad.add('${where(at)}: a subscript on an expression, whose key cannot '
          'be attributed');
      continue;
    }
    final name = recv.group(1)!;
    if (name == _listLocal) {
      bad.add('${where(at)}: `$_listLocal[...]` indexes the history list; '
          'rows are read only through `for (final r in $_listLocal)`');
      continue;
    }
    final prefix = _mapLocals[name];
    if (prefix == null) {
      bad.add('${where(at)}: a read through `$name`, which is not one of the '
          'locals this test follows (${_mapLocals.keys.join(', ')})');
      continue;
    }
    final end = v.shape.indexOf(']', at);
    final inside = v.code.substring(at + 1, end).trim();
    final lit =
        RegExp(r'''^(?:'([^'\\$]*)'|"([^"\\$]*)")$''').firstMatch(inside);
    if (lit == null) {
      bad.add('${where(at)}: `$name[$inside]` is not a plain string literal');
      continue;
    }
    keys.add('$prefix${lit.group(1) ?? lit.group(2)}');
  }

  // 2. Every other use of the four locals.
  final body = v.shape.substring(open, close);
  for (final local in [..._mapLocals.keys, _listLocal]) {
    final use = RegExp('(?<![A-Za-z0-9_\$.])$local(?![A-Za-z0-9_\$])');
    for (final m in use.allMatches(body)) {
      final before = body.substring(0, m.start);
      final after = body.substring(m.end);
      final ok =
          // a subscript, handled above
          RegExp(r'^\s*[?!]?\s*\[').hasMatch(after) ||
              // its declaration
              RegExp(r'final\s+$').hasMatch(before) ||
              // a type test
              RegExp(r'^\s+is[!\s]').hasMatch(after) ||
              // a named-argument label: `latest: UpdateManifestEntry(`
              (RegExp(r'^\s*:(?!:)').hasMatch(after) &&
                  RegExp(r'[(,]\s*$').hasMatch(before)) ||
              // walking the history list
              (local == _listLocal && RegExp(r'\bin\s+$').hasMatch(before));
      if (!ok) {
        final at = open + m.start;
        final line = v.text.split('\n')[v.lineOf(at) - 1].trim();
        bad.add('${where(at)}: `$local` is used whole ($line); a map that is '
            'copied, passed on, iterated or interpolated can read any key');
      }
    }
  }
  return (keys: keys, unattributed: bad);
}

String _explain(Set<String> keys, List<String> bad, Set<String> allow) {
  final extra = keys.difference(allow).toList()..sort();
  final missing = allow.difference(keys).toList()..sort();
  return [
    _wda,
    if (extra.isNotEmpty) 'READ BUT NOT ALLOWED: ${extra.join(', ')}',
    if (missing.isNotEmpty)
      'ALLOWED BUT NO LONGER READ: ${missing.join(', ')} (the list is WDA\'s '
          'ruling; change it only with WDA)',
    for (final b in bad) 'CANNOT ATTRIBUTE: $b',
  ].join('\n');
}

bool _closed(({Set<String> keys, List<String> unattributed}) got) =>
    got.unattributed.isEmpty &&
    got.keys.containsAll(_wdaAllowlist) &&
    _wdaAllowlist.containsAll(got.keys);

void main() {
  final parser = DartViews.read(_parserPath).text;

  test('the parser reads exactly the keys WDA allowed, and nothing it cannot '
      'attribute', () {
    final got = readSetOf(parser);
    final why = _explain(got.keys, got.unattributed, _wdaAllowlist);
    expect(got.unattributed, isEmpty, reason: why);
    expect(got.keys, _wdaAllowlist, reason: why);
  });

  // STANDING NEGATIVE CONTROLS, run every time on the REAL parser text with
  // one edit made in memory. The ruling required this test to be proven to
  // fail when a key is added; these keep proving it.
  group('it can fail: the same parser with one edit', () {
    const anchor = "      final declared = decoded['manifest_url'];\n";

    String edited(String insert, {String? replace}) {
      expect(parser.split(anchor).length, 2,
          reason: 'the controls anchor on the manifest_url read; if it moved, '
              'move the anchor with it, never delete a control');
      return parser.replaceFirst(anchor, replace ?? '$insert$anchor');
    }

    // (what the edited parser does, a line to insert before the anchor, or
    // null and a replacement for the anchor itself)
    final cases = <(String, String?, String?)>[
      ('reads a new latest key', "      final notes = latest['notes'];\n", null),
      ('reads a new top-level key',
          "      final msg = decoded['message'];\n", null),
      ('reads a key that is not a literal',
          "      const k = 'notes';\n      final n = latest[k];\n", null),
      ('builds a key by interpolation',
          "      final n = latest['no\${1}tes'];\n", null),
      ('reads through an alias', '      final all = latest;\n', null),
      ('interpolates the whole map', r"      final s = '$latest';" '\n', null),
      ('iterates the whole map',
          '      for (final k in decoded.keys) {}\n', null),
      ('chains a subscript',
          "      final x = decoded['latest']['notes'];\n", null),
      ('indexes the history list',
          '      final first = hist is List ? hist[0] : null;\n', null),
      ('no longer reads the one control fact', null,
          '      final Object? declared = null;\n'),
    ];
    for (final (why, insert, replace) in cases) {
      test('a parser that $why is caught', () {
        final src = edited(insert ?? '', replace: replace);
        expect(src, isNot(parser), reason: 'the edit did not apply');
        final got = readSetOf(src);
        expect(_closed(got), isFalse,
            reason: 'passed a parser that $why:\n'
                '${_explain(got.keys, got.unattributed, _wdaAllowlist)}');
      });
    }

    test('REPLAY: the list as it stood on 2026-09-24, before the reader, goes '
        'red on this parser and names manifest_url', () {
      final before = {..._wdaAllowlist}..remove('manifest_url');
      expect(readSetOf(parser).keys.difference(before), {'manifest_url'},
          reason: 'this is the red the reader should have met the day it '
              'added the key');
    });
  });

  test('the checker decodes nothing itself: every manifest it fetches goes '
      'through UpdateManifest.tryParse', () {
    final checker = DartViews.read(_checkerPath).shape;
    expect(RegExp(r'\bjsonDecode\b|\bjson\s*\.\s*decode\b').hasMatch(checker),
        isFalse,
        reason: '$_wda\nA second decode site is a second read set this test '
            'cannot see.');
    expect(
        RegExp(r'\bjsonDecode\s*\(').allMatches(DartViews(parser).shape).length,
        1,
        reason: '$_wda\nThe parser must decode in exactly one place, '
            'tryParse.');
  });
}
