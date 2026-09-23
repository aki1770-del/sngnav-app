/// Every platform location call lives in ONE library, and now something checks it.
///
/// WHY THIS FILE EXISTS, and it is not the invariant — it is the CLAIM about
/// the invariant. `lib/her_position.dart` told its readers: "every
/// `Geolocator.*` call in this app is inside this library, and that containment
/// is checked." Measured 2026-09-23 by VDE: NOTHING checked it. No test, no
/// lint rule, no CI step. The property held by discipline alone while the
/// comment said a machine was watching.
///
/// That is worse than silence. A reader who is told the machine has it covered
/// stops being the last line of defence and does not know they have stopped —
/// Sakichi Vision 9: "The operator must not be the last line of defense against
/// defects — the machine itself must catch them." A false claim that the
/// machine is watching removes the operator without adding the machine.
///
/// I wrote that sentence in the same change that added
/// `openPlatformLocationSettings` to that library, reasoning that putting one
/// call in main.dart to save an import would break the property that makes the
/// position surface auditable. The reasoning was right. The claim that it was
/// enforced was not, and I made it in the act of relying on it.
///
/// WHAT THE CONTAINMENT BUYS. Every route to her GPS — the permission check,
/// the permission request, the stream, the service-enabled probe, the settings
/// page — is reachable only through one file. That is what lets a reviewer
/// answer "can this app reach her position without asking?" by reading one
/// library instead of the whole tree, and it is what makes the consent gate
/// auditable at all.
///
/// HONEST BOUND. This is a grep over source text, not a call graph. It cannot
/// see the package reached through an aliased import in a file it does not
/// read, and it says nothing about what the plugin does. It catches the shape
/// that would actually occur: a second file importing geolocator for
/// convenience.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one library allowed to touch the platform location API.
const String _home = 'lib/her_position.dart';

/// Source with comments stripped, so prose about `Geolocator` — including the
/// sentences in this app that explain the containment — cannot break it.
String _code(String text) => text
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      if (t.startsWith('///') || t.startsWith('//')) return '';
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

Iterable<File> _libDart() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('no library but her_position.dart names Geolocator in code', () {
    final offenders = <String>[];
    for (final f in _libDart()) {
      if (f.path == _home) continue;
      final code = _code(f.readAsStringSync());
      final hits = RegExp(r'\bGeolocator\b').allMatches(code).length;
      if (hits > 0) offenders.add('${f.path} ($hits)');
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Every route to her GPS must stay reachable through one library, '
          'so a reviewer can answer "can this app reach her position without '
          'asking?" by reading $_home instead of the whole tree. Found: '
          '$offenders. If you need the platform API elsewhere, add a wrapper '
          'to $_home and call that — which is what '
          'openPlatformLocationSettings is.',
    );
  });

  test('no library but her_position.dart IMPORTS the geolocator package', () {
    final offenders = <String>[];
    for (final f in _libDart()) {
      if (f.path == _home) continue;
      final code = _code(f.readAsStringSync());
      if (code.contains("package:geolocator/")) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'the import is the step before the call, and catching it here '
            'names the mistake earlier: $offenders');
  });

  test('and the home library really is the home — this guard fails closed if '
      'the calls ever move out of it', () {
    // A guard that would pass on an empty tree proves nothing. Measured: the
    // home library must actually contain the calls it is the home for.
    final code = _code(File(_home).readAsStringSync());
    final hits = RegExp(r'\bGeolocator\.').allMatches(code).length;
    expect(hits, greaterThanOrEqualTo(4),
        reason: 'if these moved out, the two tests above would pass by '
            'vacuity while the property they name had been abandoned');
  });
}
