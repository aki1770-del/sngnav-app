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
}
