/// Which conditions count as measured, for a share with no trusted fix yet.
///
/// Why, written before the act (2026-09-14). Before a share's first trusted
/// fix, a position failure does not reach the caution rung by itself, and it
/// never takes away a caution a measured condition raises. So the app must
/// tell a measured condition from an absent one. A visibility the app could
/// not read, or read too long ago, is not a measurement; a measured reduced,
/// low or whiteout visibility, an area advisory above minor, or a firing
/// measured-weather watch is. A reading of 300 m is measured even though it
/// is not a whiteout: a failure fed only in a whiteout would drop the caution
/// that 300 m raises.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show AdvisoryLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/drive_safety_fusion.dart';
import 'package:sngnav_app/services/measured_hazard_floor.dart';

bool _raises({
  double? visibility,
  double? age = 0,
  AdvisoryLevel? advisory,
  MeasuredWeatherHazard hazard = MeasuredWeatherHazard.none,
}) =>
    measuredConditionRaisesCaution(
      visibilityMeters: visibility,
      visibilityAgeSeconds: visibility == null ? null : age,
      advisorySeverity: advisory,
      measuredHazard: hazard,
    );

void main() {
  group('not measured: raises nothing', () {
    test('no visibility reading, no advisory, no watch', () {
      expect(_raises(), isFalse);
    });
    test('a whiteout reading too old to trust (stale is not a measurement)', () {
      expect(_raises(visibility: 80, age: 3600), isFalse);
    });
    test('a whiteout reading of unknown age', () {
      expect(_raises(visibility: 80, age: null), isFalse);
    });
    test('a measured clear 1,500 m', () {
      expect(_raises(visibility: 1500), isFalse);
    });
    test('a minor advisory', () {
      expect(_raises(advisory: AdvisoryLevel.minor), isFalse);
    });
  });

  group('measured: raises caution', () {
    for (final (name, raised) in <(String, bool)>[
      ('a measured 80 m whiteout', _raises(visibility: 80)),
      ('a measured 300 m, not a whiteout', _raises(visibility: 300)),
      ('a measured 700 m, reduced', _raises(visibility: 700)),
      ('a moderate advisory', _raises(advisory: AdvisoryLevel.moderate)),
      ('a severe advisory', _raises(advisory: AdvisoryLevel.severe)),
      ('a firing black-ice watch',
          _raises(hazard: MeasuredWeatherHazard.blackIce)),
      ('a firing turmoil watch', _raises(hazard: MeasuredWeatherHazard.turmoil)),
      (
        'a firing watch with no visibility reading',
        _raises(hazard: MeasuredWeatherHazard.turmoil, visibility: null)
      ),
    ]) {
      test(name, () => expect(raised, isTrue));
    }
  });
}
