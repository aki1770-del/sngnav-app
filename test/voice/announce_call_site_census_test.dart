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
///
/// IT READS WHAT HER RELEASE BUILD RUNS (2026-09-25, round 5a). The same
/// corpus's next round found five ways to silence a voice ONLY in her release
/// build that this census still passed, and that nothing else we run can see,
/// because `flutter test` runs in debug mode. Reachability is now decided per
/// announce() call and per reference, by what a release build runs, and a
/// build-mode spelling this census cannot read fails instead of passing. See
/// the second column.
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
// WHAT HER BUILD RUNS (2026-09-25, round 5a). `flutter test` runs every test in
// debug mode, where kReleaseMode is false and kDebugMode is true. So a voice
// silenced only in her release build passes every test we run and compiles
// clean, and this column is the only instrument built to see it. An
// independent mutation corpus (round 4b) measured five such shapes passing it:
//  - F1, the watch voice returning first thing in release;
//  - F2, the whiteout caution's one announce() wrapped in `if (kDebugMode)`
//    inside its function: the column asked whether release reaches the
//    FUNCTION, never whether it reaches the CALL;
//  - F3, the watch call under `kDebugMode || _developerPageOffered`: it gave up
//    on any `||`;
//  - F4, the same call under `_developerPageOffered` alone, a condition this
//    file itself proves false in release;
//  - F5, the caller returning early in release, before the call.
// Each is now decided per call and per reference, by what a release build runs:
//  - a condition is read as a release build reads it, through `!`, `&&`, `||`
//    and parentheses: kReleaseMode is true; kDebugMode, kProfileMode and the
//    two gates this file proves (_developerPageOffered,
//    kDeveloperPageFromEnvironment) are false;
//  - what a false condition governs does not run, nor does the `else` of a
//    true one; a `return`, `throw`, `break` or `continue` that a release build
//    takes, unconditionally or under a condition true in release, ends the
//    rest of its block; `assert(...)` does not run;
//  - a name whose value comes from build mode cannot be decided, and neither
//    can a condition that reads it. That covers a getter, a field or a
//    method's result computed from kReleaseMode or its kin, directly or
//    through another such name, and a field set under such a condition;
//  - FAIL CLOSED: a build-mode value anywhere in a reference's or a call's own
//    function, before it or inside its own expression, that is not a
//    condition read above, leaves it UNDECIDED, and undecided fails. So a
//    spelling this census does not know stops it instead of passing.
//
// HONEST BOUND OF THIS INSTRUMENT. It resolves one gate by proof: the developer
// page. It walks the call graph by NAME over the code-only text, not by
// analysis of the real element model: two functions with one name are one node
// to it, and a voice reached through a tear-off stored in a field, a callback
// passed as data, or a dynamic dispatch is NOT traced. A reference that sits in
// no function it can name (a field initializer, a constructor) is UNDECIDED.
// It reads each function's own body: a callee that throws, or never returns,
// only in release is not traced into its caller, a local value set under a
// build-mode condition and read later is caught only by the fail-closed scan,
// and a condition on runtime state is taken to run. Widget-typed values are
// not treated as build-mode values, because a widget never gates a call. It
// does not read `dart:io` Platform checks, which also differ between the test
// host and her phone. It asserts its own seed (below) so it cannot silently
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
    final quiet = <String, Set<String>>{};
    final calls = <String, List<({String where, _Live live, String why})>>{};
    for (final key in _registered.keys) {
      // A fresh walk per voice, so no verdict is memoised across voices.
      final walk = _Walk(lib);
      final name = key.split('::').last;
      measured[key] = walk.reach(name);
      paths[key] = walk.pathFrom(name);
      undecided[key] = walk.undecidedAt;
      quiet[key] = walk.quietAt;
      calls[key] = lib.announceCallsIn(key);
    }
    // ignore: avoid_print
    print('AAE_RELEASE_REACH measured='
        '${{for (final e in measured.entries) e.key: e.value.name}}');
    // ignore: avoid_print
    print('AAE_RELEASE_PATHS ${paths.values.join(' | ')}');
    // ignore: avoid_print
    print('AAE_RELEASE_CALLS ${{
      for (final e in calls.entries) e.key: [for (final c in e.value) c.live.name],
    }}');
    // A voice registered as reaching her build speaks only the lines whose
    // announce() call a release build runs. Until round 5a this column asked
    // whether release reaches the FUNCTION, and a call wrapped inside it in
    // `if (kDebugMode)` passed.
    String callProblem(String key) {
      final list = calls[key]!;
      final dead = list.where((c) => c.live == _Live.doesNot).toList();
      final open = list.where((c) => c.live == _Live.undecided).toList();
      return [
        if (dead.isNotEmpty)
          '$key: ${dead.length} of ${list.length} announce() call(s) do not run '
              'in a release build, so HER build is silent on the line(s) they '
              'speak although the voice is reached: '
              '${dead.map((c) => '${c.where}, ${c.why}').join('; ')}',
        if (open.isNotEmpty)
          '$key: this census cannot decide whether a release build runs '
              '${open.length} of ${list.length} announce() call(s): '
              '${open.map((c) => '${c.where}, ${c.why}').join('; ')}. Say it so '
              'this census can read it, or prove it and say so here.',
      ].join('\n');
    }

    final problems = <String>[
      for (final e in measured.entries)
        if (!_reachesRelease.containsKey(e.key))
          '${e.key} is registered in the census but its release-reachability '
              'is not declared'
        else if (e.value == _Reach.undecided)
          '${e.key}: this census cannot decide whether a release build reaches '
              'it: ${undecided[e.key]!.join('; ')}. Move the call into a '
              'function and out from under what this census cannot read, or '
              'prove the path and say so here.'
        else if (_reachesRelease[e.key]! &&
            e.value == _Reach.reaches &&
            callProblem(e.key).isNotEmpty)
          callProblem(e.key)
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
                  'that names which voice. What a release build does not run: '
                  '${quiet[e.key]!.isEmpty ? 'no reference is left' : quiet[e.key]!.join('; ')}.',
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
  const _Fn(this.src, this.name, this.nameOffset, this.start, this.end,
      {required this.returnsValue});
  final _Src src;
  final String name;
  final int nameOffset;
  final int start; // offset of the line holding the head
  final int end; // offset just past the body's `}` or `;`

  /// A getter, or a method whose result could gate a call: not `void`, not
  /// `Future<void>`, not a widget.
  final bool returnsValue;
}

/// A reference to a name, and the innermost function holding it (null: none).
class _Ref {
  const _Ref(this.src, this.offset, this.fn, this.length);
  final _Src src;
  final int offset;
  final _Fn? fn;
  final int length;
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
  r'(Future<[^>\n]*>|void|bool|String\??|Widget|int|double|[A-Z][\w<>?, ]*)'
  r'[ \t]+(_?[a-zA-Z]\w*)(?=[ \t]*(?:<[^>()\n]*>)?[ \t]*\()',
  multiLine: true,
);

/// `Type get name` followed by `=>` or a block (checked when the body is read).
final _getterHead = RegExp(
  r'^[ \t]{0,4}(?:static[ \t]+)?(?:([A-Za-z_][\w<>?, ]*)[ \t]+)?get[ \t]+'
  r'(_?[a-zA-Z]\w*)\b',
  multiLine: true,
);

/// A result that cannot gate a call: nothing, or a widget.
final _noGatingValue = RegExp(
    r'^(?:void|Future<void>|FutureOr<void>|\w*Widget|(?:List|Iterable)<\w*Widget>)\??$');

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

/// Where the expression holding [at] ends: the `,`, `;` or closing bracket
/// after it at its own depth. A call's arguments are part of it.
int _ownExpressionEnd(String code, int at) {
  var depth = 0;
  for (var i = at; i < code.length; i++) {
    final ch = code[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      if (depth == 0) return i;
      depth--;
    } else if (depth == 0 && (ch == ',' || ch == ';')) {
      return i;
    }
  }
  return code.length;
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
  void consider(RegExpMatch m,
      {required bool params, required int nameGroup, int? typeGroup,
      bool setter = false}) {
    final name = m.group(nameGroup)!;
    if (_notAHead.hasMatch(code.substring(m.start, m.end).trimLeft())) return;
    final end = _bodyEnd(code, m.end, params: params);
    if (end == null) return;
    final type = typeGroup == null ? null : m.group(typeGroup)?.trim();
    out.add(_Fn(s, name, m.end - name.length, m.start, end,
        returnsValue: !setter && (type == null || !_noGatingValue.hasMatch(type))));
  }

  for (final m in _methodHead.allMatches(code)) {
    consider(m, params: true, nameGroup: 2, typeGroup: 1);
  }
  for (final m in _setterHead.allMatches(code)) {
    consider(m, params: true, nameGroup: 1, setter: true);
  }
  for (final m in _getterHead.allMatches(code)) {
    consider(m, params: false, nameGroup: 2, typeGroup: 1);
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

bool _isIdent(String ch) => RegExp(r'[A-Za-z0-9_$]').hasMatch(ch);

/// Whether [word] stands at [at] in [code] as a whole word.
bool _wordAt(String code, int at, String word) =>
    code.startsWith(word, at) &&
    (at == 0 || !_isIdent(code[at - 1])) &&
    (at + word.length >= code.length || !_isIdent(code[at + word.length]));

/// The span of what an `if` governs, beginning at [from] in [code]: a block;
/// an `if` with its whole `else` chain, a loop with its body, a `switch`, a
/// `try` with its clauses; or else the collection element or statement up to
/// the `,` or closing bracket that ends it (not included), the `;` that ends
/// it (included), or an `else`, at bracket depth 0. Until round 5a a compound
/// statement ran on to the next `;`, past its own body.
(int, int)? _elementSpan(String code, int from) {
  final start = _skipBlank(code, from);
  if (start >= code.length) return null;
  if (code[start] == '{') {
    final end = closingBracketEnd(code, start);
    return end == null ? null : (start, end);
  }
  (int, int)? head(String keyword) {
    final open = _skipBlank(code, start + keyword.length);
    if (open >= code.length || code[open] != '(') return null;
    final close = closingBracketEnd(code, open);
    return close == null ? null : (open, close);
  }

  if (_wordAt(code, start, 'if')) return _ifAt(code, start)?.span;
  for (final loop in const ['for', 'while']) {
    if (!_wordAt(code, start, loop)) continue;
    final h = head(loop);
    final body = h == null ? null : _elementSpan(code, h.$2);
    return body == null ? null : (start, body.$2);
  }
  if (_wordAt(code, start, 'switch')) {
    final h = head('switch');
    final open = h == null ? -1 : _skipBlank(code, h.$2);
    if (open < 0 || open >= code.length || code[open] != '{') return null;
    final end = closingBracketEnd(code, open);
    return end == null ? null : (start, end);
  }
  if (_wordAt(code, start, 'try')) {
    var i = _skipBlank(code, start + 3);
    if (i >= code.length || code[i] != '{') return null;
    var end = closingBracketEnd(code, i);
    while (end != null) {
      final k = _skipBlank(code, end);
      if (!_wordAt(code, k, 'on') &&
          !_wordAt(code, k, 'catch') &&
          !_wordAt(code, k, 'finally')) {
        break;
      }
      i = code.indexOf('{', k);
      if (i < 0) return null;
      end = closingBracketEnd(code, i);
    }
    return end == null ? null : (start, end);
  }
  if (_wordAt(code, start, 'do')) {
    final body = _elementSpan(code, start + 2);
    if (body == null) return null;
    final w = _skipBlank(code, body.$2);
    if (!_wordAt(code, w, 'while')) return null;
    final end = _expressionEnd(code, w);
    return end == null ? null : (start, end);
  }
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
    } else if (depth == 0 && ch == ';') {
      return (start, i + 1);
    } else if (depth == 0 && _wordAt(code, i, 'else')) {
      return (start, i);
    }
  }
  return null;
}

/// An `if` statement or collection-if: its condition, what it governs, and its
/// `else`.
typedef _If = ({
  int start,
  int condOpen,
  int condEnd,
  (int, int) then,
  (int, int)? orElse,
  (int, int) span,
});

_If? _ifAt(String code, int start) {
  final open = _skipBlank(code, start + 2);
  if (open >= code.length || code[open] != '(') return null;
  final condEnd = closingBracketEnd(code, open);
  if (condEnd == null) return null;
  final then = _elementSpan(code, condEnd);
  if (then == null) return null;
  final k = _skipBlank(code, then.$2);
  final orElse = _wordAt(code, k, 'else') ? _elementSpan(code, k + 4) : null;
  return (
    start: start,
    condOpen: open,
    condEnd: condEnd,
    then: then,
    orElse: orElse,
    span: (start, orElse?.$2 ?? then.$2),
  );
}

// ---------------------------------------------------------------------------
// What a release build runs (round 5a). See "WHAT HER BUILD RUNS" above.

/// kReleaseMode and its kin: fixed when a build is compiled, and fixed
/// differently for `flutter test` (debug) than for her build (release).
const Set<String> _buildModeWords = {
  'kReleaseMode',
  'kDebugMode',
  'kProfileMode',
};

/// A boolean --dart-define (`bool.fromEnvironment`, `bool.hasEnvironment`) is
/// a switch her build may set differently from a test run, so it is build
/// mode too. A String or int define is data, not a switch: counting it (as
/// the first draft did) spread "undecided" through the update check's
/// manifest address to every function that reads it.
const String _boolDefine = r'bool\s*\.\s*(?:fromEnvironment|hasEnvironment)';

/// The gates [_Lib.releaseGateProblems] proves are `!kReleaseMode && ...` at
/// the top level: false in every release build, once that proof passes, and
/// undecided while it does not.
const Set<String> _provenReleaseFalse = {
  '_developerPageOffered',
  'kDeveloperPageFromEnvironment',
};

/// Build mode, spelled by [_buildModeWords], [_boolDefine] or any of [names].
RegExp _modePattern(Iterable<String> names) => RegExp(
    '(?<![A-Za-z0-9_\$])(?:$_boolDefine|'
    '${{..._buildModeWords, ...names}.map(RegExp.escape).join('|')})'
    '(?![A-Za-z0-9_\$])');

/// A condition's value in a release build: always true, always false,
/// decided at run time by something other than build mode, or not decidable
/// here.
enum _InRelease { isTrue, isFalse, runtime, undecided }

_InRelease _not(_InRelease v) => switch (v) {
      _InRelease.isTrue => _InRelease.isFalse,
      _InRelease.isFalse => _InRelease.isTrue,
      _ => v,
    };

_InRelease _and(_InRelease a, _InRelease b) {
  if (a == _InRelease.isFalse || b == _InRelease.isFalse) return _InRelease.isFalse;
  if (a == _InRelease.undecided || b == _InRelease.undecided) {
    return _InRelease.undecided;
  }
  if (a == _InRelease.runtime || b == _InRelease.runtime) return _InRelease.runtime;
  return _InRelease.isTrue;
}

_InRelease _or(_InRelease a, _InRelease b) {
  if (a == _InRelease.isTrue || b == _InRelease.isTrue) return _InRelease.isTrue;
  if (a == _InRelease.undecided || b == _InRelease.undecided) {
    return _InRelease.undecided;
  }
  if (a == _InRelease.runtime || b == _InRelease.runtime) return _InRelease.runtime;
  return _InRelease.isFalse;
}

/// [e] split at [op] (`||` or `&&`) outside brackets; null when a conditional
/// (`? :`) or an if-null (`??`) joins it at the top, because both bind looser
/// than `||` and a split would misread it.
List<String>? _splitTopLevel(String e, String op) {
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
      if (e.startsWith('??', i)) return null;
      if (ch == '?' &&
          !e.startsWith('?.', i) &&
          !e.startsWith('?[', i) &&
          e.indexOf(':', i) > i) {
        return null;
      }
      if (e.startsWith(op, i)) {
        parts.add(e.substring(last, i));
        last = i + op.length;
        i += op.length - 1;
      }
    }
  }
  parts.add(e.substring(last));
  return parts;
}

/// Whether a release build runs a piece of code.
enum _Live { runs, doesNot, undecided }

/// Code a release build does not run, or that this census cannot decide, and
/// why, in words fit for the failure message.
class _Span {
  const _Span(this.start, this.end, this.live, this.why);
  final int start;
  final int end;
  final _Live live;
  final String why;
  bool holds(int offset) => offset >= start && offset < end;
}

/// How an element leaves its block: never, perhaps, or always.
enum _Jump { none, maybe, always }

final _jumpWord = RegExp(
    r'(?<![A-Za-z0-9_$.])(return|throw|rethrow|break|continue)(?![A-Za-z0-9_$])');

/// `return`, `throw`, `rethrow`, `break` and `continue` that BEGIN a
/// statement: after `{`, `;` or `}`, or after a case label's `:` (not
/// `throw`, which can also end a conditional expression, `c ? a : throw e`).
/// Offset and word.
List<(int, String)> _statementJumps(String code) => [
      for (final m in _jumpWord.allMatches(code))
        if (_beginsStatement(code, m.start, m.group(1)!)) (m.start, m.group(1)!),
    ];

bool _beginsStatement(String code, int at, String word) {
  var k = at - 1;
  while (k >= 0 && ' \t\r\n'.contains(code[k])) {
    k--;
  }
  if (k < 0) return true;
  final prev = code[k];
  return prev == '{' || prev == ';' || prev == '}' || (prev == ':' && word != 'throw');
}

/// A labelled `break outer;` or `continue outer;` leaves more than its own
/// block, so what it ends cannot be read from the block alone.
bool _labelled(String code, int at) =>
    RegExp(r'(?:break|continue)\s+[A-Za-z_$]').matchAsPrefix(code, at) != null;

/// Net bracket depth from [from] to [to].
int _depthBetween(String code, int from, int to) {
  var depth = 0;
  for (var i = from; i < to; i++) {
    final ch = code[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
    }
  }
  return depth;
}

/// Whether [span], an element an `if` governs, leaves its block.
_Jump _jumpOf(String code, (int, int) span) {
  final text = code.substring(span.$1, span.$2);
  final lead = span.$1 + text.length - text.trimLeft().length;
  final head = _jumpWord.matchAsPrefix(code, lead);
  if (head != null) return _labelled(code, lead) ? _Jump.maybe : _Jump.always;
  if (lead < code.length && code[lead] == '{') {
    for (final m in _jumpWord.allMatches(code.substring(0, span.$2), lead)) {
      if (_beginsStatement(code, m.start, m.group(1)!) &&
          _depthBetween(code, lead + 1, m.start) == 0) {
        return _labelled(code, m.start) ? _Jump.maybe : _Jump.always;
      }
    }
  }
  return RegExp(r'(?<![A-Za-z0-9_$])(?:return|throw|rethrow|break|continue|exit)'
              r'(?![A-Za-z0-9_$])')
          .hasMatch(text)
      ? _Jump.maybe
      : _Jump.none;
}

/// Every `{...}` pair in [code], by the offset of its `{`.
List<(int, int)> _bracePairs(String code) {
  final pairs = <(int, int)>[];
  final stack = <int>[];
  for (var i = 0; i < code.length; i++) {
    final ch = code[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      stack.add(i);
    } else if ((ch == ')' || ch == ']' || ch == '}') && stack.isNotEmpty) {
      final open = stack.removeLast();
      if (code[open] == '{') pairs.add((open, i));
    }
  }
  return pairs;
}

/// Where the rest of the block holding [at] ends: its `}`, or the next case
/// label at the block's own level, whichever is first. Null outside a block.
int? _restOfBlockEnd(String code, List<(int, int)> braces, int at) {
  (int, int)? inner;
  for (final p in braces) {
    if (p.$1 < at && at < p.$2 && (inner == null || p.$1 > inner.$1)) inner = p;
  }
  if (inner == null) return null;
  var depth = 0;
  for (var i = at; i < inner.$2; i++) {
    final ch = code[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
    } else if (depth == 0 && (_wordAt(code, i, 'case') || _wordAt(code, i, 'default'))) {
      return i;
    }
  }
  return inner.$2;
}

List<(int, int)> _assertSpans(String code) => [
      for (final m in RegExp(r'(?<![A-Za-z0-9_$.])assert\s*\(').allMatches(code))
        if (closingBracketEnd(code, m.end - 1) case final close?) (m.start, close),
    ];

/// Where the statement holding [at] begins: just after the `;`, `{` or `}`
/// before it at its own depth, or just inside the bracket that holds it.
int _statementStart(String code, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final ch = code[i];
    if (ch == ')' || ch == ']') {
      depth++;
    } else if (ch == '}') {
      if (depth == 0) return i + 1;
      depth++;
    } else if (ch == '(' || ch == '[' || ch == '{') {
      if (depth == 0) return i + 1;
      depth--;
    } else if (ch == ';' && depth == 0) {
      return i + 1;
    }
  }
  return 0;
}

bool _isAssignment(String code, int i) {
  if (code[i] != '=') return false;
  final next = i + 1 < code.length ? code[i + 1] : '';
  final prev = i > 0 ? code[i - 1] : '';
  if (next == '=' || next == '>' || prev == '=' || prev == '!') return false;
  if (prev == '<' || prev == '>') return i > 1 && code[i - 2] == prev; // <<= >>=
  return true;
}

/// The name the statement from [from] assigns, when [at] lies on the right of
/// its `=`, and whether the statement DECLARES it (a type or a keyword before
/// the name). Null for none, and for a member of another object (`a.b = `).
(String, bool)? _assignedAt(String code, int from, int at) {
  var depth = 0;
  int? eq;
  for (var i = from; i < at; i++) {
    final ch = code[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
    } else if (depth == 0 && _isAssignment(code, i)) {
      eq = i;
    }
  }
  if (eq == null) return null;
  var k = eq - 1;
  while (k >= from && '?|&+-*/~%^<> \t\r\n'.contains(code[k])) {
    k--;
  }
  final nameEnd = k + 1;
  while (k >= from && _isIdent(code[k])) {
    k--;
  }
  final name = code.substring(k + 1, nameEnd);
  if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name)) return null;
  final before = code.substring(from, k + 1).trimRight();
  if (before.endsWith('.')) return before.endsWith('this.') ? (name, false) : null;
  // A control head before the name (`if (c) x = ...`, `else x = ...`, a case
  // label) governs the statement; it does not declare the name.
  var prefix = before.trim();
  while (true) {
    final word = RegExp(r'^(else|do)(?![A-Za-z0-9_$])').firstMatch(prefix) ??
        RegExp(r'^(?:case|default)\b[^:]*:').firstMatch(prefix);
    if (word != null) {
      prefix = prefix.substring(word.end).trim();
      continue;
    }
    final head = RegExp(r'^(?:if|for|while)\s*\(').firstMatch(prefix);
    final close = head == null ? null : closingBracketEnd(prefix, head.end - 1);
    if (close == null) break;
    prefix = prefix.substring(close).trim();
  }
  return (name, prefix.isNotEmpty);
}

/// What one file's release build runs: the dead and undecided spans, and the
/// conditions the model read (a build-mode value inside one is accounted for).
class _ReleaseFacts {
  final spans = <_Span>[];
  final conditions = <(int, int)>[];
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

  /// The two developer-page gates are false in release only once proven.
  late final bool gateProven = releaseGateProblems().isEmpty;

  /// Names whose value a release build computes from build mode (see
  /// [_releaseDerivedNames]).
  late final Set<String> derived = _releaseDerivedNames();

  /// Every build-mode word, derived name and proven gate, for the fail-closed
  /// scan.
  late final RegExp _modeRefs = _modePattern({..._provenReleaseFalse, ...derived});

  final Map<String, List<_If>> _ifsByFile = {};
  final Map<String, List<(int, int)>> _bracesByFile = {};
  final Map<String, _ReleaseFacts> _factsByFile = {};

  List<_If> _ifsOf(_Src s) => _ifsByFile[s.path] ??= [
        for (final m in RegExp(r'(?<![A-Za-z0-9_$.])if\s*\(').allMatches(s.code))
          ?_ifAt(s.code, m.start),
      ];

  List<(int, int)> _bracesOf(_Src s) =>
      _bracesByFile[s.path] ??= _bracePairs(s.code);

  /// What [expression] is worth in a release build.
  _InRelease releaseValue(String expression) {
    var e = expression.trim();
    while (e.startsWith('(') && closingBracketEnd(e, 0) == e.length) {
      e = e.substring(1, e.length - 1).trim();
    }
    final ors = _splitTopLevel(e, '||');
    if (ors == null) return _opaque(e);
    if (ors.length > 1) return ors.map(releaseValue).reduce(_or);
    final ands = _splitTopLevel(e, '&&')!;
    if (ands.length > 1) return ands.map(releaseValue).reduce(_and);
    if (e.startsWith('!') && !e.startsWith('!=')) {
      return _not(releaseValue(e.substring(1)));
    }
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(e)) return _opaque(e);
    switch (e) {
      case 'true' || 'kReleaseMode':
        return _InRelease.isTrue;
      case 'false' || 'kDebugMode' || 'kProfileMode':
        return _InRelease.isFalse;
    }
    if (_provenReleaseFalse.contains(e)) {
      return gateProven ? _InRelease.isFalse : _InRelease.undecided;
    }
    if (derived.contains(e) || _buildModeWords.contains(e)) {
      return _InRelease.undecided;
    }
    return _InRelease.runtime;
  }

  /// An expression the evaluator does not take apart: undecided when it
  /// mentions build mode, else a run-time value.
  _InRelease _opaque(String e) =>
      _modeRefs.hasMatch(e) ? _InRelease.undecided : _InRelease.runtime;

  /// Names whose value a release build computes differently from a test run:
  /// assigned (outside a function, or to a field from inside one) from an
  /// expression that mentions build mode; a getter or a method whose result
  /// could gate a call and whose body mentions it; and a field assigned under
  /// a condition that mentions it. Through each other, to a fixed point. The
  /// two proven gates are excluded: their value is known.
  Set<String> _releaseDerivedNames() {
    final derived = <String>{};
    // A name assigned inside a function is that function's own when the
    // statement declares it, or when the function declared it earlier (a
    // local, or a parameter); otherwise it is a field or a top-level name.
    bool ownLocal(String code, _Fn fn, int at, (String, bool) assigned) {
      if (assigned.$2) return true;
      // `Type name;`, `late Type name`, `var name =`, a parameter `Type name)`:
      // a type or a declaring keyword before the name -- never `return name;`.
      final declared = RegExp(r'(?<![A-Za-z0-9_$.])(?:var|final|late|const|'
          r'(?!(?:return|await|yield|throw|case|else|in|is|as|new)\b)'
          r'[A-Za-z_$][A-Za-z0-9_$]*(?:<[^;(){}]*>)?\??)'
          '\\s+${RegExp.escape(assigned.$1)}\\s*[;=,)}]');
      return declared.hasMatch(code.substring(fn.start, at));
    }
    while (true) {
      final before = derived.length;
      final pattern = _modePattern(derived);
      for (final s in files.values) {
        final code = s.code;
        final asserts = _assertSpans(code);
        final ifs = _ifsOf(s);
        for (final m in pattern.allMatches(code)) {
          if (asserts.any((a) => m.start >= a.$1 && m.start < a.$2)) continue;
          final fn = innermost(s, m.start);
          final assigned = _assignedAt(code, _statementStart(code, m.start), m.start);
          if (assigned != null && (fn == null || !ownLocal(code, fn, m.start, assigned))) {
            derived.add(assigned.$1);
          }
          if (fn != null && fn.returnsValue) derived.add(fn.name);
          for (final i in ifs) {
            if (m.start < i.condOpen || m.start >= i.condEnd) continue;
            for (final branch in [i.then, i.orElse].whereType<(int, int)>()) {
              for (var k = branch.$1; k < branch.$2; k++) {
                if (!_isAssignment(code, k)) continue;
                final t = _assignedAt(code, _statementStart(code, k), k + 1);
                if (t != null && (fn == null || !ownLocal(code, fn, k, t))) {
                  derived.add(t.$1);
                }
              }
            }
          }
        }
      }
      derived.removeAll(_provenReleaseFalse);
      derived.removeAll(_buildModeWords);
      if (derived.length == before) return derived;
    }
  }

  _ReleaseFacts factsOf(_Src s) => _factsByFile[s.path] ??= _releaseFacts(s);

  _ReleaseFacts _releaseFacts(_Src s) {
    final facts = _ReleaseFacts();
    final code = s.code;
    final braces = _bracesOf(s);
    String at(int offset) => '${s.path}:${s.lineOf(offset)}';
    for (final a in _assertSpans(code)) {
      facts.spans.add(_Span(a.$1, a.$2, _Live.doesNot,
          'inside assert() at ${at(a.$1)}, which a release build drops'));
    }
    void after(_If i, (int, int)? taken, String label) {
      if (taken == null) return;
      final jump = _jumpOf(code, taken);
      if (jump == _Jump.none) return;
      final stop = _restOfBlockEnd(code, braces, i.start);
      if (stop == null || i.span.$2 >= stop) return;
      facts.spans.add(jump == _Jump.always
          ? _Span(i.span.$2, stop, _Live.doesNot,
              'after $label, whose branch a release build always takes and '
              'which leaves the block')
          : _Span(i.span.$2, stop, _Live.undecided,
              'after $label, whose branch a release build takes and which '
              'may leave the block'));
    }

    for (final i in _ifsOf(s)) {
      facts.conditions.add((i.condOpen, i.condEnd));
      final text = code.substring(i.condOpen + 1, i.condEnd - 1);
      final label =
          '`if (${text.replaceAll(RegExp(r'\s+'), ' ').trim()})` at ${at(i.start)}';
      switch (releaseValue(text)) {
        case _InRelease.isFalse:
          facts.spans.add(_Span(i.then.$1, i.then.$2, _Live.doesNot,
              'inside $label, false in every release build'));
          after(i, i.orElse, label);
        case _InRelease.isTrue:
          if (i.orElse case final e?) {
            facts.spans.add(_Span(e.$1, e.$2, _Live.doesNot,
                'in the else of $label, true in every release build'));
          }
          after(i, i.then, label);
        case _InRelease.undecided:
          for (final branch in [i.then, i.orElse].whereType<(int, int)>()) {
            facts.spans.add(_Span(branch.$1, branch.$2, _Live.undecided,
                'under $label, whose value in a release build this census '
                'cannot decide'));
          }
          final jumps = [i.then, i.orElse]
              .whereType<(int, int)>()
              .any((b) => _jumpOf(code, b) != _Jump.none);
          final stop = _restOfBlockEnd(code, braces, i.start);
          if (jumps && stop != null && i.span.$2 < stop) {
            facts.spans.add(_Span(i.span.$2, stop, _Live.undecided,
                'after $label, whose value in a release build this census '
                'cannot decide, and whose branch may leave the block'));
          }
        case _InRelease.runtime:
          break;
      }
    }
    for (final (j, word) in _statementJumps(code)) {
      final end = _expressionEnd(code, j);
      final stop = _restOfBlockEnd(code, braces, j);
      if (end == null || stop == null || end >= stop) continue;
      facts.spans.add(_Span(end, stop, _Live.doesNot,
          'after the `$word` at ${at(j)}, which always leaves the block'));
    }
    return facts;
  }

  /// Whether a release build runs the code at [offset] in [s], inside [fn],
  /// and why not. [self] is the reference's own name, which the fail-closed
  /// scan does not count against it.
  (_Live, String) liveness(_Src s, int offset, _Fn? fn, {int self = 0}) {
    final facts = factsOf(s);
    for (final live in const [_Live.doesNot, _Live.undecided]) {
      for (final sp in facts.spans) {
        if (sp.live == live && sp.holds(offset)) return (live, sp.why);
      }
    }
    if (fn == null) return (_Live.runs, '');
    final code = s.code;
    final to = _ownExpressionEnd(code, offset);
    for (final m in _modeRefs.allMatches(code, fn.start)) {
      if (m.start >= to) break;
      if (m.start >= offset && m.start < offset + self) continue;
      if (facts.conditions.any((c) => m.start >= c.$1 && m.start < c.$2)) continue;
      if (facts.spans.any((sp) => sp.live == _Live.doesNot && sp.holds(m.start))) {
        continue;
      }
      return (
        _Live.undecided,
        '`${m.group(0)}` at ${s.path}:${s.lineOf(m.start)}, a build-mode value '
            'in ${fn.name}, before it or in its own expression, is in a form '
            'this census cannot read as a release build does'
      );
    }
    return (_Live.runs, '');
  }

  /// Every announce() call in the function [key] names, with whether a
  /// release build runs it.
  List<({String where, _Live live, String why})> announceCallsIn(String key) {
    final out = <({String where, _Live live, String why})>[];
    final call = RegExp(r'\.announce\(');
    for (final s in files.values) {
      for (final m in call.allMatches(s.code)) {
        final fn = innermost(s, m.start);
        if (fn == null || '${s.path}::${fn.name}' != key) continue;
        final (live, why) = liveness(s, m.start, fn);
        out.add((where: '${s.path}:${s.lineOf(m.start)}', live: live, why: why));
      }
    }
    return out;
  }

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
        hits.add(_Ref(s, m.start, innermost(s, m.start), name.length));
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
        final source = end == null ? '' : main.text.substring(m.end, end - 1);
        problems.add('$what is no longer `!kReleaseMode && ...` at the top '
            'level (it reads `${source.replaceAll(RegExp(r'\s+'), ' ').trim()}`), '
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

  /// References whose release run this census cannot decide, and why.
  final Set<String> undecidedAt = {};

  /// References a release build does not run, and why.
  final Set<String> quietAt = {};

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
      final (live, why) = lib.liveness(r.src, r.offset, r.fn, self: r.length);
      if (live == _Live.doesNot) {
        quietAt.add('$name at ${r.where}: $why');
        continue; // a release build does not run it
      }
      final fn = r.fn;
      if (fn == null) {
        result = _Reach.undecided;
        undecidedAt.add('${r.where}, which is in no function this census can '
            'name');
        continue;
      }
      if (live == _Live.undecided) {
        result = _Reach.undecided;
        undecidedAt.add('$name at ${r.where}: $why');
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
    // Wrapped in a condition that is false in release, or in an assert.
    for (final wrapped in [
      '    if (kDebugMode) _announceWatchTransitions();\n',
      '    if (kDebugMode && _ready) {\n      _announceWatchTransitions();\n    }\n',
      '    if (!kReleaseMode) _announceWatchTransitions();\n',
      '    assert(() {\n      _announceWatchTransitions();\n      return true;\n    }());\n',
    ]) {
      expect(reachOf(_mutate(liveCall, wrapped)), _Reach.doesNot,
          reason: 'a release build does not run: $wrapped');
    }
    // A condition that holds in release, and an else branch, still reach.
    expect(reachOf(_mutate(liveCall,
        '    if (!kDebugMode) _announceWatchTransitions();\n')), _Reach.reaches);
    expect(reachOf(_mutate(liveCall,
        '    if (kDebugMode) _log(); else _announceWatchTransitions();\n')),
        _Reach.reaches);
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

  _selfTestReleaseOnly();
}

/// The fixture with each (from, to) applied in turn, each `from` held once.
String _mutateAll(List<(String, String)> edits) {
  var s = _fixtureMain;
  for (final (from, to) in edits) {
    expect(s.split(from).length, 2,
        reason: 'the self-test fixture must hold `$from` exactly once');
    s = s.replaceFirst(from, to);
  }
  return s;
}

/// Round 5a: a voice silenced ONLY in her release build. Each shape is judged
/// on the watch voice of the fixture, for the verdict AND for the reason the
/// census gives, so a shape caught by accident does not count as caught.
void _selfTestReleaseOnly() {
  const liveCall = '    _announceWatchTransitions();\n';
  const voiceHead = '  void _announceWatchTransitions() {\n';
  const voiceCall = "    _announcer.announce('ice');\n";
  const beforeBuild = '  @override\n  Widget build';
  ({_Reach reach, List<_Live> calls, String why}) judge(
      List<(String, String)> edits) {
    final lib = _Lib({'lib/main.dart': _mutateAll(edits)});
    final walk = _Walk(lib);
    final reach = walk.reach('_announceWatchTransitions');
    final calls = lib.announceCallsIn('lib/main.dart::_announceWatchTransitions');
    return (
      reach: reach,
      calls: [for (final c in calls) c.live],
      why: [...walk.quietAt, ...walk.undecidedAt, for (final c in calls) c.why]
          .join(' | '),
    );
  }

  void quietCall(String shape, List<(String, String)> edits, String because) {
    final v = judge(edits);
    expect(v.reach, _Reach.reaches, reason: '$shape: the voice is still reached');
    expect(v.calls, [_Live.doesNot], reason: '$shape: its one call is silent in release');
    expect(v.why, contains(because), reason: '$shape: caught for its own reason');
  }

  void quietVoice(String shape, List<(String, String)> edits, String because) {
    final v = judge(edits);
    expect(v.reach, _Reach.doesNot, reason: '$shape: no release path reaches it');
    expect(v.why, contains(because), reason: '$shape: caught for its own reason');
  }

  void undecided(String shape, List<(String, String)> edits, String because,
      {bool atTheCall = false}) {
    final v = judge(edits);
    if (atTheCall) {
      expect(v.calls, [_Live.undecided], reason: '$shape: fails closed at the call');
    } else {
      expect(v.reach, _Reach.undecided, reason: '$shape: fails closed');
    }
    expect(v.why, contains(because), reason: '$shape: names what it cannot read');
  }

  void heard(String shape, List<(String, String)> edits) {
    final v = judge(edits);
    expect(v.reach, _Reach.reaches, reason: '$shape: a release build reaches it');
    expect(v.calls, [_Live.runs], reason: '$shape: and runs its call');
  }

  test('self-test (round 5a): each shape that silences a voice only in her '
      'release build is caught, for its own reason', () {
    heard('healthy', const []);

    // The independent corpus, round 4b.
    quietCall('F1', [(voiceHead, '$voiceHead    if (kReleaseMode) return;\n')],
        'after `if (kReleaseMode)`');
    quietCall('F2', [
      (voiceCall, "    if (kDebugMode) {\n      _announcer.announce('ice');\n    }\n"),
    ], 'inside `if (kDebugMode)`');
    quietVoice('F3', [
      (liveCall,
          '    if (kDebugMode || _developerPageOffered) _announceWatchTransitions();\n'),
    ], 'inside `if (kDebugMode || _developerPageOffered)`');
    quietVoice('F4', [
      (liveCall, '    if (_developerPageOffered) _announceWatchTransitions();\n'),
    ], 'inside `if (_developerPageOffered)`');
    quietVoice('F5', [
      (liveCall, '    if (kReleaseMode) return;\n    _announceWatchTransitions();\n'),
    ], 'after `if (kReleaseMode)`');
    quietVoice('F6a', [
      (liveCall, '    return;\n    // ignore: dead_code\n    _announceWatchTransitions();\n'),
    ], 'after the `return`');
    quietVoice('F6b', [
      (liveCall, '    return;\n    _announceWatchTransitions();\n'),
    ], 'after the `return`');
    // F4 reads `_developerPageOffered` as false only because the gate is
    // proven. Unproven, the same shape is undecided: it still fails.
    undecided('F4, gate unproven', [
      (liveCall, '    if (_developerPageOffered) _announceWatchTransitions();\n'),
      ('      !kReleaseMode &&\n', '      !kReleaseMode ||\n'),
    ], 'cannot decide');

    // The same silences, spelled other ways the model reads.
    quietVoice('a block that returns in release', [
      (liveCall,
          '    if (kReleaseMode) {\n      return;\n    }\n    _announceWatchTransitions();\n'),
    ], 'after `if (kReleaseMode)`');
    quietVoice('the else of a false condition returns', [
      (liveCall,
          '    if (!kReleaseMode) {\n      _log();\n    } else {\n      return;\n    }\n'
              '    _announceWatchTransitions();\n'),
    ], 'after `if (!kReleaseMode)`');
    quietVoice('two conditions false in release', [
      (liveCall, '    if (kProfileMode || kDebugMode) _announceWatchTransitions();\n'),
    ], 'inside `if (kProfileMode || kDebugMode)`');
    quietCall('the call in the else of a true condition', [
      (voiceCall,
          "    if (kReleaseMode) {\n      _log();\n    } else {\n      _announcer.announce('ice');\n    }\n"),
    ], 'in the else of `if (kReleaseMode)`');
    quietCall('a throw in release', [
      (voiceHead, "$voiceHead    if (kReleaseMode) throw StateError('quiet');\n"),
    ], 'after `if (kReleaseMode)`');

    // Spellings the model does NOT read: each fails closed.
    undecided('a conditional expression', [
      (liveCall, '    kReleaseMode ? null : _announceWatchTransitions();\n'),
    ], '`kReleaseMode`');
    undecided('a local set from build mode', [
      (liveCall,
          '    final quiet = kReleaseMode;\n    if (quiet) return;\n    _announceWatchTransitions();\n'),
    ], '`kReleaseMode`');
    undecided('a getter set from build mode', [
      (beforeBuild, '  bool get _quiet => kReleaseMode;\n\n$beforeBuild'),
      (liveCall, '    if (_quiet) return;\n    _announceWatchTransitions();\n'),
    ], '`if (_quiet)`');
    undecided('a field set under a build-mode condition', [
      (liveCall,
          '    if (kReleaseMode) _muted = true;\n    if (_muted) return;\n'
              '    _announceWatchTransitions();\n'),
    ], '`if (_muted)`');
    undecided('a loop that runs only outside release', [
      (liveCall,
          '    while (!kReleaseMode) {\n      _announceWatchTransitions();\n      break;\n    }\n'),
    ], '`kReleaseMode`');
    undecided('a boolean define', [
      (liveCall,
          "    if (const bool.fromEnvironment('QUIET')) return;\n    _announceWatchTransitions();\n"),
    ], 'cannot decide');
    undecided('an import prefix', [
      (liveCall, '    if (foundation.kReleaseMode) return;\n    _announceWatchTransitions();\n'),
    ], 'cannot decide');
    undecided('build mode inside the call itself', [
      (voiceCall, "    _announcer.announce(kReleaseMode ? '' : 'ice');\n"),
    ], '`kReleaseMode`', atTheCall: true);
    // Over-reach, stated: a closure's `return` cannot be told from the
    // function's, so a taken branch holding one fails closed.
    undecided('a return inside a closure in a taken branch', [
      (liveCall,
          '    if (kReleaseMode) _items.forEach((i) { return; });\n'
              '    _announceWatchTransitions();\n'),
    ], 'may leave the block');

    // Controls: build mode that does not silence her stays heard.
    heard('a return only a debug build takes', [
      (liveCall, '    if (kDebugMode) return;\n    _announceWatchTransitions();\n'),
    ]);
    heard('a release-only line that does not leave', [
      (liveCall, "    if (kReleaseMode) debugPrint('r');\n    _announceWatchTransitions();\n"),
    ]);
    heard('debug-only logging before the call', [
      (liveCall, "    if (kDebugMode) debugPrint('x');\n    _announceWatchTransitions();\n"),
    ]);
    heard('build mode that leaves a run-time condition', [
      (liveCall, '    if (kReleaseMode && _paused) return;\n    _announceWatchTransitions();\n'),
    ]);
    heard('a run-time early return', [
      (liveCall, '    if (!mounted) return;\n    _announceWatchTransitions();\n'),
    ]);
    heard('a run-time early return before the call', [
      (voiceCall, "    if (_line.isEmpty) return;\n    _announcer.announce('ice');\n"),
    ]);
  });
}
