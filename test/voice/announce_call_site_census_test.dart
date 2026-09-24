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
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

/// A line that opens a function or method body: a return type, a name, and a
/// parameter list that does not end the statement on the same line.
final _declaration = RegExp(
  r'^\s{0,4}(?:static\s+)?'
  r'(?:Future<[^>]*>|void|bool|String\??|Widget|int|double|[A-Z][\w<>?, ]*)'
  r'\s+(_?[a-zA-Z]\w*)\s*\([^;]*$',
);

void main() {
  test('every announce() call site in lib/ is registered with the lines it '
      'speaks', () {
    final found = <String, int>{};
    final unattributed = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        final code = l.trimLeft();
        if (code.startsWith('//') || !l.contains('.announce(')) continue;
        String? function;
        for (var j = i; j >= 0; j--) {
          final m = _declaration.firstMatch(lines[j]);
          final head = lines[j].trimLeft();
          if (m != null &&
              !RegExp(r'^(if|for|while|return|switch|else)\b').hasMatch(head)) {
            function = m.group(1);
            break;
          }
        }
        final path = file.path.replaceAll(r'\', '/');
        if (function == null) {
          unattributed.add('$path:${i + 1}');
          continue;
        }
        final key = '$path::$function';
        found[key] = (found[key] ?? 0) + 1;
      }
    }

    final problems = <String>[
      for (final u in unattributed)
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
// `!kReleaseMode` (lib/main.dart). So 30 of the bundled road-surface clips
// -- every line carrying アイスバーン / 圧雪 / シャーベット / 凍結 -- are
// speakable only in a build she will never hold. The bundled mouth was
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
// walks the call graph by source text, not by analysis of the real element
// model, so a voice reached through a tear-off stored in a field, a callback
// passed as data, or a dynamic dispatch is NOT traced. It asserts its own seed
// (below) so it cannot silently measure an ungated page and call it gated. What
// it does not see, it does not claim.

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

class _Fn {
  const _Fn(this.path, this.name, this.start, this.end);
  final String path;
  final String name;
  final int start; // 0-based line index of the declaration
  final int end; // 0-based line index of the closing brace
}

/// Every function body in lib/, with the line span it occupies.
List<_Fn> _functionsInLib() {
  final out = <_Fn>[];
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final lines = file.readAsLinesSync();
    final path = file.path.replaceAll(r'\', '/');
    for (var i = 0; i < lines.length; i++) {
      final m = _declaration.firstMatch(lines[i]);
      if (m == null) continue;
      final head = lines[i].trimLeft();
      if (RegExp(r'^(if|for|while|return|switch|else)\b').hasMatch(head)) {
        continue;
      }
      // Walk forward to the body's opening brace, then match it.
      var depth = 0;
      var opened = false;
      var end = -1;
      for (var j = i; j < lines.length; j++) {
        for (final ch in lines[j].split('')) {
          if (ch == '{') {
            depth++;
            opened = true;
          } else if (ch == '}') {
            depth--;
          }
        }
        if (opened && depth <= 0) {
          end = j;
          break;
        }
        // A declaration that reaches a `;` before any `{` is abstract/external.
        if (!opened && lines[j].contains(';')) break;
      }
      if (end > 0) out.add(_Fn(path, m.group(1)!, i, end));
    }
  }
  return out;
}

void _reachability() {
  final fns = _functionsInLib();
  final lines = <String, List<String>>{};
  for (final f in fns) {
    lines.putIfAbsent(f.path, () => File(f.path).readAsLinesSync());
  }

  /// Every reference to [name] in lib/ that is not its own declaration,
  /// returned as the function that contains it (null = top level).
  List<_Fn?> referrers(String name) {
    final hits = <_Fn?>[];
    final word = RegExp('(?<![A-Za-z0-9_])$name(?![A-Za-z0-9_])');
    for (final entry in lines.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final l = entry.value[i];
        if (l.trimLeft().startsWith('//') || l.trimLeft().startsWith('///')) {
          continue;
        }
        if (!word.hasMatch(l)) continue;
        // Skip the declaration line itself.
        final d = _declaration.firstMatch(l);
        if (d != null && d.group(1) == name) continue;
        _Fn? inner;
        for (final f in fns) {
          if (f.path != entry.key || i < f.start || i > f.end) continue;
          if (inner == null || f.start > inner.start) inner = f;
        }
        hits.add(inner);
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
      final source = lines[f.path]!;
      for (var k = f.start - 1; k >= 0 && k >= f.start - 3; k--) {
        final t = source[k].trim();
        if (t == '@override') return true;
        if (t.isEmpty || t.startsWith('//')) continue;
        if (!t.startsWith('@')) break;
      }
    }
    return false;
  }

  final memo = <String, bool>{};
  bool reachesRelease(String name, Set<String> seen) {
    if (_developerPageRoots.contains(name)) return false;
    if (memo.containsKey(name)) return memo[name]!;
    if (!seen.add(name)) return false; // cycle: no new path to release
    final refs = referrers(name);
    // Never referenced anywhere: an entry point ONLY if the framework calls it
    // (see [isEntryPoint]). Until 2026-09-25 every unreferenced function counted
    // as one, so deleting a voice's last caller left it "reaching release" --
    // a voice that went quiet read as a voice she still hears.
    var result = refs.isEmpty && isEntryPoint(name);
    for (final r in refs) {
      if (r == null) {
        result = true; // referenced at top level
        break;
      }
      if (reachesRelease(r.name, seen)) {
        result = true;
        break;
      }
    }
    seen.remove(name);
    memo[name] = result;
    return result;
  }

  test('the developer-page seed is really gated on !kReleaseMode', () {
    // Guard the guard. If the page ever stops being release-gated, every
    // verdict below silently inverts, so the seed is asserted, not assumed.
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main,
      contains(RegExp(r'bool get _developerPageOffered =>\s*!kReleaseMode')),
      reason: '_developerPageOffered no longer hard-gates on !kReleaseMode, so '
          '_developerSections() is not a developer-only region and every '
          'reachability verdict in this file is void',
    );
    for (final root in _developerPageRoots) {
      expect(_functionsInLib().map((f) => f.name), contains(root),
          reason: '$root no longer exists; the seed names a function that is '
              'gone and this census measures nothing');
    }

    // The roots are developer-only BY MEASUREMENT, not by declaration. The walk
    // stops at a root and answers "unreachable" without looking further, so if
    // `_developerSections()` were built into her page, or a second button
    // opened the developer page without asking `_developerPageOffered`, every
    // verdict below would stay "unreachable" while the voice reached her -- the
    // exact silent start this column exists to catch. (Added 2026-09-25, when
    // the seed was found to be declared rather than measured.)
    final sectionsCallers = referrers('_developerSections');
    expect(
      sectionsCallers.map((f) => f?.name ?? '<top level>').toSet(),
      {'_openDeveloperPage'},
      reason: '_developerSections() is referenced from '
          '${sectionsCallers.map((f) => f?.name ?? '<top level>').toList()}, '
          'not only from _openDeveloperPage. A second path to the developer '
          'sections voids every developer-only verdict in this file.',
    );

    final mainLines = File('lib/main.dart').readAsLinesSync();
    final openRef =
        RegExp(r'(?<![A-Za-z0-9_])_openDeveloperPage(?![A-Za-z0-9_])');
    final opens = <int>[
      for (var i = 0; i < mainLines.length; i++)
        if (openRef.hasMatch(mainLines[i]) &&
            !mainLines[i].trimLeft().startsWith('//') &&
            _declaration.firstMatch(mainLines[i])?.group(1) !=
                '_openDeveloperPage')
          i,
    ];
    expect(opens, hasLength(1),
        reason: 'the developer page now has ${opens.length} entries in '
            'lib/main.dart; this census proves exactly one, drawn under '
            '`if (_developerPageOffered)`. Prove any new entry is gated, then '
            'extend this check.');
    final gate = RegExp(r'^\s*if \(_developerPageOffered\)');
    final guarded = [
      for (var k = opens.single; k >= 0 && k >= opens.single - 8; k--)
        mainLines[k],
    ].any(gate.hasMatch);
    expect(guarded, isTrue,
        reason: 'the one entry to the developer page is no longer drawn under '
            '`if (_developerPageOffered)`, so a release build can open it and '
            'every developer-only verdict in this file is void');
  });

  test('every announce() call site is on the side of the release gate it is '
      'registered on', () {
    final measured = <String, bool>{
      for (final key in _registered.keys)
        key: reachesRelease(key.split('::').last, <String>{}),
    };
    // ignore: avoid_print
    print('AAE_RELEASE_REACH measured=$measured');
    final problems = <String>[
      for (final e in measured.entries)
        if (!_reachesRelease.containsKey(e.key))
          '${e.key} is registered in the census but its release-reachability '
              'is not declared'
        else if (_reachesRelease[e.key] != e.value)
          e.value
              ? '${e.key} is registered as UNREACHABLE in a release build but a '
                  'release path now reaches it. If that is intended, say so '
                  'here -- and check what drives it: the road-surface voice is '
                  'keyed off a SIMULATED dropdown value, and speaking it to a '
                  'driver in real snow would be an unmeasured alert.'
              : '${e.key} is registered as reaching a release build and no '
                  'longer does. HER build just went quiet on this voice and '
                  'every other suite stayed green.',
      for (final k in _reachesRelease.keys)
        if (!_registered.containsKey(k))
          '$k declares a release-reachability but is not in the census',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
