/// What an area advisory does to the rung a driver is given before her
/// share's first trusted fix, at the drive brain (decided 2026-09-15).
///
/// Why, written before the act. The app takes no advisory source a widget test
/// can give it, so nothing through the app can state these rows. Measured
/// before this test existed: a landing that left the advisory out of a failed
/// start's rung passed every test in the app, and at the drive brain it
/// lowered a severe or extreme advisory from the top rung to heightened
/// caution. So the rows are stated here, at the seam where the landing decides
/// where that rung comes from. A landing that puts the seam elsewhere keeps
/// the rows and moves the setup.
///
/// Each row is a state the app reaches: the advisory, or the visibility, is a
/// measured condition that raises caution, so a failure before the first
/// trusted fix is given to the brain. Expected rungs are worked from the
/// advisor's rules, not read back from it:
/// * An unlocated position (a failed start, or no event 60 s after the stream
///   subscribed) counts as a position that is uncertain but not lost. A
///   moderate advisory leaves it at heightened caution; a severe advisory
///   escalates it to the top rung; an extreme advisory stands at the top rung.
/// * The road's own rung (no event yet, inside 60 s) is what a driver with a
///   trusted position is given: a moderate or severe advisory gives
///   heightened caution, and an extreme advisory the top rung.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_safety_fusion.dart'
    show measuredConditionRaisesCaution;
import 'package:sngnav_app/services/measured_hazard_floor.dart';

import '../support/fake_alert_actuators.dart';

const _top = DriveAction.considerStopping;
const _heightened = DriveAction.heightenedCaution;

/// (visibility in metres or no reading, advisory, unlocated, road)
const _rows = <(double?, AdvisoryLevel?, DriveAction, DriveAction)>[
  (null, AdvisoryLevel.moderate, _heightened, _heightened),
  (null, AdvisoryLevel.severe, _top, _heightened),
  (null, AdvisoryLevel.extreme, _top, _top),
  (1500, AdvisoryLevel.moderate, _heightened, _heightened),
  (1500, AdvisoryLevel.severe, _top, _heightened),
  (1500, AdvisoryLevel.extreme, _top, _top),
  (700, null, _heightened, _heightened),
  (700, AdvisoryLevel.moderate, _heightened, _heightened),
  (700, AdvisoryLevel.severe, _top, _heightened),
  (700, AdvisoryLevel.extreme, _top, _top),
];

DriveAction? _rungGiven(
    StartRung from, double? visibility, AdvisoryLevel? advisory) {
  final brain = DriveHudController(actuators: FakeAlertActuators());
  brain.visibilityMeters = visibility;
  brain.visibilityAgeSeconds = visibility == null ? null : 0;
  brain.advisorySeverity = advisory;
  brain.speedMetersPerSecond = null;
  brain.measuredHazard = MeasuredWeatherHazard.none;
  brain.startRung = from;
  brain.onPositionFix(
    const PositionUnavailable('test: no position before the first fix'),
    now: DateTime.utc(2026, 1, 14, 21),
  );
  return brain.effectiveAction;
}

void main() {
  for (final (visibility, advisory, unlocated, road) in _rows) {
    final where = '${visibility == null ? 'no reading' : '$visibility m'}, '
        '${advisory?.name ?? 'no'} advisory';

    test('$where: a state the app reaches', () {
      expect(
        measuredConditionRaisesCaution(
          visibilityMeters: visibility,
          visibilityAgeSeconds: visibility == null ? null : 0,
          advisorySeverity: advisory,
          measuredHazard: MeasuredWeatherHazard.none,
        ),
        isTrue,
        reason: 'control: a failure here is given to the drive brain',
      );
    });

    test('$where: an unlocated position is given ${unlocated.name}', () {
      expect(_rungGiven(StartRung.unlocated, visibility, advisory), unlocated);
    });

    test('$where: the road\'s own rung is ${road.name}', () {
      expect(_rungGiven(StartRung.road, visibility, advisory), road);
    });
  }
}
