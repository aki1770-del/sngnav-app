/// Architectural guard — a doc comment that GUARANTEES a safety property is a
/// claim, and a false claim in a safety file is a defect, not prose.
///
/// `drive_hud_localizer.dart` asserted that 「特段の注意なし」
/// "never displays over an unmeasured or degraded read". That was measurably
/// FALSE on the advisory axis: `compound_failure_advisor` 0.1.2 has no unknown
/// channel for advisories, so an advisory-feed outage arrives as
/// `advisorySeverity: null` — indistinguishable from a quiet sky — and the
/// lowest rung fires. The guarantee held only for the axes the package
/// actually models as unknowns (position + visibility).
///
/// These greps keep the retired claim from returning and keep the honest
/// scope stated where a reader will meet it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final localizer = File('lib/services/drive_hud_localizer.dart');
  final axis = File('lib/services/advisory_axis.dart');

  test('the retired absolute guarantee does not come back', () {
    final text = localizer.readAsStringSync();
    for (final claim in [
      'never displays over an unmeasured or degraded read',
      'honest on every path that reaches it',
    ]) {
      expect(text, isNot(contains(claim)),
          reason: 'this guarantee is false on the advisory axis — scope it, '
              'do not restore it');
    }
  });

  test('the localizer states WHICH axes the firing basis actually covers', () {
    final text = localizer.readAsStringSync();
    expect(text, contains('advisory'),
        reason: 'the doc must name the axis its guarantee does NOT cover');
    expect(
      RegExp('position|visibility').hasMatch(text),
      isTrue,
      reason: 'and the axes it DOES cover',
    );
  });

  test('the axis reader carries the same caveat where the level is read', () {
    final text = axis.readAsStringSync();
    expect(text, contains('Unknown'),
        reason: 'the missing unknown channel is the root and must be named '
            'at the seam that works around it');
    expect(
      RegExp('cry.?wolf', caseSensitive: false).hasMatch(text),
      isTrue,
      reason: 'and the reason we withhold the reassurance instead of raising '
          'the rung must be stated where the next reader will change it',
    );
  });
}
