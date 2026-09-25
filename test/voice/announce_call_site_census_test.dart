/// Every call to `announce(` in lib/, counted by the function it sits in.
///
/// WHY (2026-09-19). The bundled mouth's coverage test
/// (runtime_voice_coverage_test.dart) is only as complete as
/// emittableSafetyStaticJa() in runtime_emissions.dart, and that enumeration is
/// written by hand, one call site at a time. The warning-channel check added an
/// announce() call and nobody added its line there, so the coverage test stayed
/// green while the check's Japanese line went to the phone's own voice.
///
/// This census reads the source and fails when a function gains, loses or
/// newly holds an announce() call that is not registered below. Registering a
/// call site means adding the lines it speaks to runtime_emissions.dart first,
/// then naming the step here. A count is all it checks. Which lines a call site
/// speaks is still the enumeration's to produce, by calling the real builders.
///
/// IT READS CODE, NOT TEXT (2026-09-25). An independent mutation corpus showed
/// this census passing six real defects, because it read names as text: a
/// release voice's only call removed with its name left in a trailing comment,
/// in a debug string, or in a dead arrow-bodied method nobody calls; the
/// whiteout caution replaced by a no-op carrying its name in a comment; and the
/// developer-page gate kept as text while governing a different element, or
/// weakened from `&&` to `||`. Every check here now reads the code-only view
/// of each file (test/support/dart_source.dart), in which comments and the
/// literal text of strings are blank and interpolations are still code. An
/// arrow-bodied method, a getter and a setter are functions. The release gate
/// is proven by what the `if` governs and by the shape of the condition, not
/// by where its text sits. The self-test at the end feeds the corpus's shapes
/// through the same functions, so this cannot quietly come undone.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

/// `file::function` -> (announce() calls in it, where runtime_emissions.dart
/// produces the lines it speaks).
const Map<String, (int, String)> _registered = {
  'lib/main.dart::_announceCurrentAlert': (
    1,
    'step (1), the road-surface alert',
  ),
  'lib/main.dart::_announceWatchTransitions': (
    6,
    'steps (3) and (3b), the invisible-ice and sub-zero lines; (4), turmoil; '
        '(5), conditions unknown, twice; (6), the forecast memory; and the '
        'slotted stale-ice line, which is recorded, not bundled',
  ),
  'lib/main.dart::_fireChannelCheck': (
    1,
    'step (7), the warning-channel check',
  ),
  'lib/services/drive_hud_controller.dart::_maybeAnnounce': (
    1,
    'step (2), the caution-rung line, and (5b), its test-value prefix',
  ),
  'lib/services/drive_hud_controller.dart::tellWithNoShare': (
    1,
    'step (2), the caution-rung line',
  ),
  'lib/services/drive_hud_controller.dart::narrateNextManeuver': (
    1,
    'emittableNavStaticJa(), the navigation remainder',
  ),
};

void main() {
  test('every announce() call site in lib/ is registered with the lines it '
      'speaks', () {
    final census = _Lib.fromDisk().announceCensus();
    final found = census.found;
    final problems = <String>[
      for (final u in census.unattributed)
        'an announce() call at $u is in no function this census can name',
      for (final e in found.entries)
        if (!_registered.containsKey(e.key))
          '${e.key} holds ${e.value} announce() call(s) and is not registered. '
              'Add the lines it speaks to emittableSafetyStaticJa() in '
              'test/voice/runtime_emissions.dart, then register it here.'
        else if (_registered[e.key]!.$1 != e.value)
          '${e.key} holds ${e.value} announce() call(s); ${_registered[e.key]!.$1} '
              'are registered (${_registered[e.key]!.$2}). A new call may speak '
              'a line the bundled mouth does not have.',
      for (final k in _registered.keys)
        if (!found.containsKey(k)) '$k is registered and holds no announce() call',
    ];
    // ignore: avoid_print
    print('AAE_CENSUS found=$found');
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  _reachability();
  _citationsByFunction();
  _selfTest();
}

/// The voice derivation says it cites call sites BY FUNCTION and that this
/// census pins those names. That promise is only true if a line number cannot
/// creep back: a line number in a moving file points somewhere whether or not
/// it is still true, so the reader who follows it is misled rather than
/// stopped. On 2026-09-25 the header of runtime_emissions.dart was repaired of
/// seven such citations; the same day nineteen more of the same family were
/// found still standing in the other three files below, and two in this file's
/// own first draft -- the rule is applied to the census that states it.
void _citationsByFunction() {
  test('the voice derivation cites call sites by function, never by a line '
      'number in a moving file', () {
    const files = [
      'lib/voice/offline_safety_voice.dart',
      'test/voice/runtime_emissions.dart',
      'test/voice/offline_safety_voice_test.dart',
      'test/voice/announce_call_site_census_test.dart',
    ];
    final cite = RegExp(r'(?:main|drive_hud_controller|route_fetch)\.dart:\d');
    final hits = <String>[];
    for (final f in files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (cite.hasMatch(lines[i])) hits.add('$f:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(hits, isEmpty,
        reason: 'cite the call site by the function that holds it (the census '
            'pins the names), not by a line that will move:\n'
            '${hits.join('\n')}');
  });
}

// ---------------------------------------------------------------------------
// SECOND COLUMN: can the SIGNED build she installs actually reach this voice?
//
// WHY (2026-09-25). The census above counts call sites and says so plainly:
// "A count is all it checks." A count cannot see the defect measured today --
// `_announceCurrentAlert` holds its one registered announce() call, the count
// matched, the suite stayed green, and the only widget that calls it sits
// inside `_developerSections()`, which `_developerPageOffered` hard-gates on
// `!kReleaseMode` (lib/main.dart). So 30 of the 41 bundled clips -- the
// road-surface alerts -- are speakable only in a build she will never hold.
// Counted 2026-09-25: 21 of those 30 name アイスバーン / 圧雪 / シャーベット /
// 凍結 (the other 9 are wet-road and loose-gravel lines), and every bundled
// clip that names 圧雪 or シャーベット is among them, so no release build SPEAKS
// either word (her diary chips still SHOW them). She does hear
// ブラックアイスバーン and 凍結 in release, from the two measured warnings
// (invisible ice, sub-zero). The bundled mouth was
// complete; the path to her mouth was not, and nothing said so.
//
// This column pins the fact rather than ruling on it. It does NOT assert that
// every voice must reach release: `_announceCurrentAlert` is driven by
// `_condition`, written at exactly one place (lib/main.dart, the onChanged of
// the dropdown whose own section title is `simulatedRoadConditionSectionTitle`)
// and never by a measurement. Un-gating it would speak SIMULATED road-surface advice to a
// driver in real snow. The gate is currently the only thing preventing that, so
// the honest loom records WHICH SIDE each voice is on and fails when a side
// changes silently -- in either direction. A voice that quietly stops reaching
// her is caught; so is a voice that quietly starts.
//
// HONEST BOUND OF THIS INSTRUMENT. It resolves one gate: the developer page. It
// walks the call graph by NAME over the code-only text, not by analysis of the
// real element model: two functions with one name are one node to it, and a
// voice reached through a tear-off stored in a field, a callback passed as
// data, or a dynamic dispatch is NOT traced. A reference that sits in no
// function it can name (a field initializer, a constructor) is UNDECIDED, and
// an undecided verdict fails rather than passing as "reaches release" -- until
// 2026-09-25 it passed. It asserts its own seed (below) so it cannot silently
// measure an ungated page and call it gated. What it does not see, it does not
// claim.

/// Per registered call site: does a RELEASE build have a path to it?
const Map<String, bool> _reachesRelease = {
  // The defect, pinned. See the note above for why it is not simply un-gated.
  'lib/main.dart::_announceCurrentAlert': false,
  'lib/main.dart::_announceWatchTransitions': true,
  'lib/main.dart::_fireChannelCheck': true,
  'lib/services/drive_hud_controller.dart::_maybeAnnounce': true,
  'lib/services/drive_hud_controller.dart::tellWithNoShare': true,
  'lib/services/drive_hud_controller.dart::narrateNextManeuver': true,
};

/// The developer page's own builders. Everything whose every reference lies
/// inside one of these is unreachable in a release build. Seeded by name rather
/// than inferred, and the seed is itself asserted below.
const Set<String> _developerPageRoots = {
  '_openDeveloperPage',
  '_developerSections',
};

void _reachability() {
  final lib = _Lib.fromDisk();

  test('the developer-page seed is really gated on !kReleaseMode', () {
    // Guard the guard. If the page ever stops being release-gated, every
    // verdict below silently inverts, so the seed is proven from the code:
    // the shape of both release conditions, the one entry, and the element
    // that entry's `if` governs. (Until 2026-09-25 the gate was proven by a
    // text prefix and by sitting within 8 lines of the entry.)
    final problems = lib.releaseGateProblems();
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every announce() call site is on the side of the release gate it is '
      'registered on', () {
    final measured = <String, _Reach>{};
    final paths = <String, String>{};
    final undecided = <String, Set<String>>{};
    for (final key in _registered.keys) {
      // A fresh walk per voice, so no verdict is memoised across voices.
      final walk = _Walk(lib);
      final name = key.split('::').last;
      measured[key] = walk.reach(name);
      paths[key] = walk.pathFrom(name);
      undecided[key] = walk.undecidedAt;
    }
    // ignore: avoid_print
    print('AAE_RELEASE_REACH measured='
        '${{for (final e in measured.entries) e.key: e.value.name}}');
    // ignore: avoid_print
    print('AAE_RELEASE_PATHS ${paths.values.join(' | ')}');
    final problems = <String>[
      for (final e in measured.entries)
        if (!_reachesRelease.containsKey(e.key))
          '${e.key} is registered in the census but its release-reachability '
              'is not declared'
        else if (e.value == _Reach.undecided)
          '${e.key}: this census cannot decide whether a release build reaches '
              'it. It is referenced from ${undecided[e.key]!.join(', ')}, '
              'which is in no function this census can name. Move the call '
              'into a function, or prove the path and say so here.'
        else if (_reachesRelease[e.key] != (e.value == _Reach.reaches))
          e.value == _Reach.reaches
              ? '${e.key} is registered as UNREACHABLE in a release build but a '
                  'release path now reaches it (${paths[e.key]}). If that is '
                  'intended, say so here -- and check what drives it: the '
                  'road-surface voice is keyed off a SIMULATED dropdown value, '
                  'and speaking it to a driver in real snow would be an '
                  'unmeasured alert.'
              : '${e.key} is registered as reaching a release build and no '
                  'longer does. HER build just went quiet on this voice. Other '
                  'suites may or may not fail too; this census is the check '
                  'that names which voice.',
      for (final k in _reachesRelease.keys)
        if (!_registered.containsKey(k))
          '$k declares a release-reachability but is not in the census',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

// ---------------------------------------------------------------------------
// The model: lib/ read as code, its functions, and a walk over their names.

/// One source file, with its code-only view (comments and string text blank).
class _Src {
  _Src(this.path, this.text)
      : code = dartCodeOnly(text),
        lineStarts = lineStartsOf(text);
  final String path;
  final String text;
  final String code;
  final List<int> lineStarts;

  /// 1-based line of [offset].
  int lineOf(int offset) => lineOfOffset(lineStarts, offset) + 1;
}

/// A function, method, getter or setter, and the span its head and body cover.
class _Fn {
  const _Fn(this.src, this.name, this.nameOffset, this.start, this.end);
  final _Src src;
  final String name;
  final int nameOffset;
  final int start; // offset of the line holding the head
  final int end; // offset just past the body's `}` or `;`
}

/// A reference to a name, and the innermost function holding it (null: none).
class _Ref {
  const _Ref(this.src, this.offset, this.fn);
  final _Src src;
  final int offset;
  final _Fn? fn;
  String get where => '${src.path}:${src.lineOf(offset)}';
}

enum _Reach { reaches, doesNot, undecided }

/// The head of a function or method: a return type, a name, and the `(` that
/// opens its parameters. Matched against CODE-ONLY text, so a comment or a
/// string never opens one; the body is then found by bracket matching. Until
/// 2026-09-25 the pattern refused any line holding `;`, so a one-line arrow
/// method (`void f() => g();`) was not a function to this census, and a
/// reference inside it was read as top-level code that always runs.
final _methodHead = RegExp(
  r'^[ \t]{0,4}(?:(?:static|external)[ \t]+)*'
  r'(?:Future<[^>\n]*>|void|bool|String\??|Widget|int|double|[A-Z][\w<>?, ]*)'
  r'[ \t]+(_?[a-zA-Z]\w*)(?=[ \t]*(?:<[^>()\n]*>)?[ \t]*\()',
  multiLine: true,
);

/// `Type get name` followed by `=>` or a block (checked when the body is read).
final _getterHead = RegExp(
  r'^[ \t]{0,4}(?:static[ \t]+)?(?:[A-Za-z_][\w<>?, ]*[ \t]+)?get[ \t]+'
  r'(_?[a-zA-Z]\w*)\b',
  multiLine: true,
);

/// `set name(` -- a setter's body is read like a method's.
final _setterHead = RegExp(
  r'^[ \t]{0,4}(?:static[ \t]+)?(?:void[ \t]+)?set[ \t]+(_?[a-zA-Z]\w*)'
  r'(?=[ \t]*\()',
  multiLine: true,
);

final _notAHead = RegExp(r'^(if|for|while|return|switch|else|case|await|throw)\b');

int _skipBlank(String code, int i) {
  while (i < code.length && ' \t\r\n'.contains(code[i])) {
    i++;
  }
  return i;
}

/// Offset just past the `;` that ends the expression starting at [from], at
/// bracket depth 0; null if the brackets close first.
int? _expressionEnd(String code, int from) {
  var depth = 0;
  for (var j = from; j < code.length; j++) {
    final ch = code[j];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
      if (depth < 0) return null;
    } else if (ch == ';' && depth == 0) {
      return j + 1;
    }
  }
  return null;
}

/// Where the body that follows a head ends: a block `{...}` or an arrow
/// `=> expression;`. Null for anything else (an abstract member, a field whose
/// type is a function type, a constructor's initializer list).
int? _bodyEnd(String code, int from, {required bool params}) {
  var i = from;
  if (params) {
    final open = code.indexOf('(', i);
    if (open < 0) return null;
    final close = closingBracketEnd(code, open);
    if (close == null) return null;
    i = close;
  }
  i = _skipBlank(code, i);
  for (final keyword in const ['async*', 'sync*', 'async']) {
    if (code.startsWith(keyword, i)) {
      i = _skipBlank(code, i + keyword.length);
      break;
    }
  }
  if (i < code.length && code[i] == '{') return closingBracketEnd(code, i);
  if (code.startsWith('=>', i)) return _expressionEnd(code, i + 2);
  return null;
}

List<_Fn> _functionsIn(_Src s) {
  final out = <_Fn>[];
  final code = s.code;
  void consider(RegExpMatch m, {required bool params}) {
    final name = m.group(1)!;
    if (_notAHead.hasMatch(code.substring(m.start, m.end).trimLeft())) return;
    final end = _bodyEnd(code, m.end, params: params);
    if (end == null) return;
    out.add(_Fn(s, name, m.end - name.length, m.start, end));
  }

  for (final m in _methodHead.allMatches(code)) {
    consider(m, params: true);
  }
  for (final m in _setterHead.allMatches(code)) {
    consider(m, params: true);
  }
  for (final m in _getterHead.allMatches(code)) {
    consider(m, params: false);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// The top-level `&&` operands of [expression], whitespace-normalised, or null
/// when anything but `&&` joins it at the top (`||`, `??`, a conditional).
/// An outer pair of parentheses around the whole expression is removed first.
List<String>? _topLevelConjuncts(String expression) {
  var e = expression.trim();
  while (e.startsWith('(') && closingBracketEnd(e, 0) == e.length) {
    e = e.substring(1, e.length - 1).trim();
  }
  final parts = <String>[];
  var depth = 0;
  var last = 0;
  for (var i = 0; i < e.length; i++) {
    final ch = e[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
    } else if (depth == 0) {
      if (e.startsWith('||', i) || e.startsWith('??', i)) return null;
      if (ch == '?' && !e.startsWith('?.', i) && !e.startsWith('?[', i)) {
        return null;
      }
      if (e.startsWith('&&', i)) {
        parts.add(e.substring(last, i));
        last = i + 2;
        i++;
      }
    }
  }
  parts.add(e.substring(last));
  return [for (final p in parts) p.replaceAll(RegExp(r'\s+'), ' ').trim()];
}

/// The span of the collection element that begins at [from] in [code]: up to
/// the `,` or closing bracket that ends it, or an `else`, at bracket depth 0.
(int, int)? _elementSpan(String code, int from) {
  final start = _skipBlank(code, from);
  var depth = 0;
  for (var i = start; i < code.length; i++) {
    final ch = code[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      if (depth == 0) return (start, i);
      depth--;
    } else if (depth == 0 && ch == ',') {
      return (start, i);
    } else if (depth == 0 &&
        code.startsWith('else', i) &&
        (i == 0 || !RegExp(r'\w').hasMatch(code[i - 1])) &&
        (i + 4 >= code.length || !RegExp(r'\w').hasMatch(code[i + 4]))) {
      return (start, i);
    }
  }
  return null;
}

class _Lib {
  _Lib(Map<String, String> sources) {
    for (final path in sources.keys.toList()..sort()) {
      final src = _Src(path, sources[path]!);
      files[path] = src;
      fnsByFile[path] = _functionsIn(src);
    }
  }

  factory _Lib.fromDisk() {
    final sources = <String, String>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      sources[f.path.replaceAll(r'\', '/')] = f.readAsStringSync();
    }
    return _Lib(sources);
  }

  final Map<String, _Src> files = {};
  final Map<String, List<_Fn>> fnsByFile = {};

  Iterable<_Fn> get fns => fnsByFile.values.expand((f) => f);

  _Fn? innermost(_Src s, int offset) {
    _Fn? inner;
    for (final f in fnsByFile[s.path]!) {
      if (offset < f.start || offset >= f.end) continue;
      if (inner == null || f.start > inner.start) inner = f;
    }
    return inner;
  }

  /// Every `.announce(` call in code (never in a comment or a string), by the
  /// innermost function holding it.
  ({Map<String, int> found, List<String> unattributed}) announceCensus() {
    final found = <String, int>{};
    final unattributed = <String>[];
    final call = RegExp(r'\.announce\(');
    for (final s in files.values) {
      for (final m in call.allMatches(s.code)) {
        final fn = innermost(s, m.start);
        if (fn == null) {
          unattributed.add('${s.path}:${s.lineOf(m.start)}');
          continue;
        }
        final key = '${s.path}::${fn.name}';
        found[key] = (found[key] ?? 0) + 1;
      }
    }
    return (found: found, unattributed: unattributed);
  }

  /// Every reference to [name] in code, other than its own declarations.
  List<_Ref> referrers(String name) {
    final word = RegExp(
        '(?<![A-Za-z0-9_\$])${RegExp.escape(name)}(?![A-Za-z0-9_\$])');
    final declared = {
      for (final f in fns)
        if (f.name == name) '${f.src.path}@${f.nameOffset}',
    };
    final hits = <_Ref>[];
    for (final s in files.values) {
      for (final m in word.allMatches(s.code)) {
        if (declared.contains('${s.path}@${m.start}')) continue;
        hits.add(_Ref(s, m.start, innermost(s, m.start)));
      }
    }
    return hits;
  }

  /// Called by the framework or the VM rather than by our own source: `main`,
  /// or a declaration carrying `@override` (build, initState, a lifecycle
  /// callback). Only these may have no caller and still run in a release build.
  bool isEntryPoint(String name) {
    if (name == 'main') return true;
    for (final f in fns.where((f) => f.name == name)) {
      final lines = f.src.code.split('\n');
      final head = f.src.lineOf(f.start) - 1;
      for (var k = head - 1; k >= 0 && k >= head - 3; k--) {
        final t = lines[k].trim();
        if (t == '@override') return true;
        if (t.isEmpty) continue;
        if (!t.startsWith('@')) break;
      }
    }
    return false;
  }

  /// What must hold for `_developerSections()` to be developer-only: both
  /// release conditions are conjunctions that include `!kReleaseMode`, the
  /// roots exist, the sections are built only from the page, and the page has
  /// one entry, which is the element `if (_developerPageOffered)` governs.
  List<String> releaseGateProblems() {
    final problems = <String>[];
    final main = files['lib/main.dart'];
    if (main == null) {
      return ['lib/main.dart is absent, so the release gate cannot be proven'];
    }
    final code = main.code;

    void conjunction(RegExp head, String what) {
      final m = head.firstMatch(code);
      if (m == null) {
        problems.add('$what was not found in lib/main.dart, so the release '
            'gate this census relies on cannot be read');
        return;
      }
      final end = _expressionEnd(code, m.end);
      final expression = end == null ? null : code.substring(m.end, end - 1);
      final conjuncts =
          expression == null ? null : _topLevelConjuncts(expression);
      if (conjuncts == null || !conjuncts.contains('!kReleaseMode')) {
        problems.add('$what is no longer `!kReleaseMode && ...` at the top '
            'level (it reads `${expression?.replaceAll(RegExp(r'\s+'), ' ').trim()}`), '
            'so a release build can open the developer page and every '
            'developer-only verdict in this file is void');
      }
    }

    conjunction(RegExp(r'\bbool\s+get\s+_developerPageOffered\s*=>'),
        '_developerPageOffered');
    conjunction(
        RegExp(r'\bconst\s+bool\s+kDeveloperPageFromEnvironment\s*='),
        'kDeveloperPageFromEnvironment');

    final names = fns.map((f) => f.name).toSet();
    for (final root in _developerPageRoots) {
      if (!names.contains(root)) {
        problems.add('$root no longer exists; the seed names a function that '
            'is gone and this census measures nothing');
      }
    }

    // The roots are developer-only BY MEASUREMENT, not by declaration. The
    // walk stops at a root and answers "unreachable" without looking further,
    // so if `_developerSections()` were built into her page, or a second
    // button opened the developer page, every verdict would stay
    // "unreachable" while the voice reached her.
    final sections = referrers('_developerSections')
        .map((r) => r.fn?.name ?? '<no function: ${r.where}>')
        .toSet();
    if (sections.length != 1 || sections.single != '_openDeveloperPage') {
      problems.add('_developerSections() is referenced from $sections, not '
          'only from _openDeveloperPage. A second path to the developer '
          'sections voids every developer-only verdict in this file.');
    }

    final opens = referrers('_openDeveloperPage')
        .where((r) => r.src.path == 'lib/main.dart')
        .toList();
    final elsewhere = referrers('_openDeveloperPage')
        .where((r) => r.src.path != 'lib/main.dart')
        .map((r) => r.where)
        .toList();
    if (opens.length != 1 || elsewhere.isNotEmpty) {
      problems.add('the developer page now has ${opens.length + elsewhere.length} '
          'entries (${[...opens.map((r) => r.where), ...elsewhere]}); this '
          'census proves exactly one, the element `if (_developerPageOffered)` '
          'governs. Prove any new entry is gated, then extend this check.');
      return problems;
    }
    final entry = opens.single.offset;
    final gates =
        RegExp(r'\bif\s*\(\s*_developerPageOffered\s*\)').allMatches(code);
    var governed = false;
    for (final g in gates) {
      final span = _elementSpan(code, g.end);
      if (span == null) continue;
      final (start, end) = span;
      final element = main.text.substring(start, end);
      if (entry >= start &&
          entry < end &&
          code.substring(start, end).trimLeft().startsWith('IconButton(') &&
          RegExp(r'''Key\(\s*['"]developer-page-entry['"]\s*\)''')
              .hasMatch(element)) {
        governed = true;
      }
    }
    if (!governed) {
      problems.add('the one entry to the developer page '
          '(${opens.single.where}) is no longer the element '
          '`if (_developerPageOffered)` governs -- the IconButton keyed '
          "'developer-page-entry' -- so it is no longer drawn only when the "
          'page is offered, a release build can open it, and every '
          'developer-only verdict in this file is void');
    }
    return problems;
  }
}

/// One walk over the call graph. Memoised within the walk only; a verdict
/// that rests on cutting a cycle is not memoised, because it could differ
/// when the same name is reached along another path.
class _Walk {
  _Walk(this.lib);
  final _Lib lib;
  final _memo = <String, _Reach>{};
  final _via = <String, String>{};

  /// References met in no function this census can name.
  final Set<String> undecidedAt = {};

  _Reach reach(String name) => _visit(name, <String>[]).$1;

  (_Reach, bool) _visit(String name, List<String> stack) {
    if (_developerPageRoots.contains(name)) return (_Reach.doesNot, false);
    final known = _memo[name];
    if (known != null) return (known, false);
    if (stack.contains(name)) return (_Reach.doesNot, true);
    stack.add(name);
    final refs = lib.referrers(name);
    var result = _Reach.doesNot;
    var cut = false;
    // Never referenced anywhere: an entry point ONLY if the framework calls it
    // (see [_Lib.isEntryPoint]). Until 2026-09-25 every unreferenced function
    // counted as one, so deleting a voice's last caller left it "reaching
    // release" -- a voice that went quiet read as a voice she still hears.
    if (refs.isEmpty && lib.isEntryPoint(name)) {
      result = _Reach.reaches;
      _via[name] = '<called by the framework>';
    }
    for (final r in refs) {
      if (result == _Reach.reaches) break;
      final fn = r.fn;
      if (fn == null) {
        result = _Reach.undecided;
        undecidedAt.add(r.where);
        continue;
      }
      final (verdict, cycle) = _visit(fn.name, stack);
      cut = cut || cycle;
      if (verdict == _Reach.reaches) {
        result = _Reach.reaches;
        _via[name] = '${fn.name} (${r.where})';
      } else if (verdict == _Reach.undecided) {
        result = _Reach.undecided;
      }
    }
    stack.removeLast();
    if (result == _Reach.reaches || !cut) _memo[name] = result;
    return (result, result != _Reach.reaches && cut);
  }

  /// The release path found for [name], callee first.
  String pathFrom(String name) {
    final hops = <String>[name];
    var current = name;
    for (var k = 0; k < 64; k++) {
      final via = _via[current];
      if (via == null) break;
      hops.add(via);
      if (via.startsWith('<')) break;
      current = via.split(' ').first;
    }
    return hops.join(' <- ');
  }
}

// ---------------------------------------------------------------------------
// SELF-TEST: the shapes that got past this census on 2026-09-25, fed through
// the same functions. Each is a fixture, not the real tree, so the proof does
// not depend on lib/ happening to hold any particular code.

const String _fixtureMain = r'''
const bool kDeveloperPageFromEnvironment =
    !kReleaseMode && bool.fromEnvironment('SNGNAV_DEVELOPER_PAGE');

class _HomeState extends State<Home> {
  bool get _developerPageOffered =>
      !kReleaseMode &&
      (widget.developerPageEntry ?? kDeveloperPageFromEnvironment);

  void _openDeveloperPage() {
    Navigator.of(context).push(_page(_developerSections()));
  }

  List<Widget> _developerSections() {
    return [TextButton(onPressed: _announceCurrentAlert, child: const Text('x'))];
  }

  void _announceCurrentAlert() {
    _announcer.announce('road');
  }

  @override
  void didChangeDependencies() {
    _refresh();
  }

  Future<void> _refresh() async {
    await _fetch();
    _announceWatchTransitions();
  }

  void _announceWatchTransitions() {
    _announcer.announce('ice');
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      actions: [
        // Drawn only in a build that asks for it.
        if (_developerPageOffered)
          IconButton(
            key: const Key('developer-page-entry'),
            onPressed: _openDeveloperPage,
          ),
      ],
    );
  }
}
''';

String _mutate(String from, String to) {
  expect(_fixtureMain.split(from).length, 2,
      reason: 'the self-test fixture must hold `$from` exactly once');
  return _fixtureMain.replaceFirst(from, to);
}

void _selfTest() {
  const liveCall = '    _announceWatchTransitions();\n';
  _Reach reachOf(String source) =>
      _Walk(_Lib({'lib/main.dart': source})).reach('_announceWatchTransitions');
  List<String> gateOf(String source) =>
      _Lib({'lib/main.dart': source}).releaseGateProblems();

  test('self-test: the healthy fixture passes, and the shapes that got past '
      'this census on 2026-09-25 now fail', () {
    // Healthy: the voice reaches release, the dev-only voice does not, the
    // gate is proven, and each function holds one call.
    expect(reachOf(_fixtureMain), _Reach.reaches);
    expect(_Walk(_Lib({'lib/main.dart': _fixtureMain}))
        .reach('_announceCurrentAlert'), _Reach.doesNot);
    expect(gateOf(_fixtureMain), isEmpty);
    expect(_Lib({'lib/main.dart': _fixtureMain}).announceCensus().found, {
      'lib/main.dart::_announceCurrentAlert': 1,
      'lib/main.dart::_announceWatchTransitions': 1,
    });

    // Control: the live call removed with nothing left behind.
    expect(reachOf(_mutate(liveCall, '')), _Reach.doesNot);
    // The name left in a trailing comment on a live line.
    expect(reachOf(_mutate(liveCall,
        '    setState(() {}); // _announceWatchTransitions() runs elsewhere\n')),
        _Reach.doesNot);
    // The name left in a block comment.
    expect(reachOf(_mutate(liveCall,
        '    /* _announceWatchTransitions(); */\n')), _Reach.doesNot);
    // The name left in a debug string.
    expect(reachOf(_mutate(liveCall,
        "    debugPrint('done; _announceWatchTransitions skipped');\n")),
        _Reach.doesNot);
    // An interpolation IS code: this still calls the voice.
    expect(reachOf(_mutate(liveCall,
        r"    debugPrint('${_announceWatchTransitions()}');" '\n')),
        _Reach.reaches);
    // Only a dead arrow-bodied method calls it.
    expect(reachOf(_mutate(liveCall,
        '  }\n\n  void _later() => _announceWatchTransitions();\n  void _x() {\n')),
        _Reach.doesNot);
    // Only a field initializer holds it: undecided, never "reaches".
    expect(reachOf(_mutate(liveCall,
        '  }\n\n  late final Object _later = _announceWatchTransitions;\n  void _x() {\n')),
        _Reach.undecided);

    // The gate kept as text but governing a different element.
    expect(gateOf(_mutate(
        '        if (_developerPageOffered)\n',
        '        if (_developerPageOffered)\n          const SizedBox.shrink(),\n')),
        isNotEmpty);
    // The entry moved to the else branch.
    expect(gateOf(_mutate(
        '        if (_developerPageOffered)\n',
        '        if (_developerPageOffered)\n          const SizedBox.shrink()\n        else\n')),
        isNotEmpty);
    // The gate weakened from && to ||.
    expect(gateOf(_mutate('      !kReleaseMode &&\n', '      !kReleaseMode ||\n')),
        isNotEmpty);
    // The environment constant loses its own release gate.
    expect(gateOf(_mutate('    !kReleaseMode && bool.fromEnvironment',
        '    bool.fromEnvironment')), isNotEmpty);
    // A second entry, even one that only names the page in a comment, is
    // not an entry; a second real one is.
    expect(gateOf(_mutate('  @override\n  Widget build',
        '  // _openDeveloperPage is opened from the app bar only.\n'
            '  @override\n  Widget build')), isEmpty);
    expect(gateOf(_mutate('  @override\n  Widget build',
        '  void _second() => _openDeveloperPage();\n\n'
            '  @override\n  Widget build')), isNotEmpty);

    // announce() in a comment or a string is not a call; one inside an arrow
    // method belongs to that method.
    expect(_Lib({'lib/main.dart': _mutate(
        "    _announcer.announce('ice');\n",
        "    _speak(); // was _announcer.announce('ice')\n")})
        .announceCensus().found.containsKey(
            'lib/main.dart::_announceWatchTransitions'), isFalse);
    expect(_Lib({'lib/main.dart': _mutate(
        '  @override\n  Widget build',
        "  void _say() => _announcer.announce('x');\n\n"
            '  @override\n  Widget build')})
        .announceCensus().found['lib/main.dart::_say'], 1);
  });
}
