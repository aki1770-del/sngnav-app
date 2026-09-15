/// A test visibility may add caution and never take any away, on the
/// advisor's own bands, for every pair of a measured state and a test value
/// the app's demo band offers (2026-09-16).
///
/// Read against the advisor itself: for each pair, the rung a driver with a
/// trusted position is given from the chosen visibility is never below the
/// rung from the measured one alone, and the test value is marked whenever it
/// is the one read.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/visibility_for_caution.dart';

DriveAdvice _advise(double? meters, double? age) => adviseInDrive(
  DriveSituation(
    positionTrust: PositionTrust.trusted,
    confidenceRadiusMeters: 0,
    secondsSinceTrustedFix: 0,
    hasPosition: true,
    visibilityMeters: meters,
    visibilityAgeSeconds: age,
    advisorySeverity: null,
    speedMetersPerSecond: null,
  ),
);

void main() {
  const measured = <(String, double?, double?)>[
    ('none', null, null),
    ('NaN', double.nan, 0),
    ('unknown age', 80, null),
    ('stale 80', 80, 301),
    ('stale 1500', 1500, 301),
    ('fresh 80', 80, 0),
    ('fresh 199', 199, 300),
    ('fresh 200', 200, 0),
    ('fresh 300', 300, 0),
    ('fresh 499', 499, 0),
    ('fresh 500', 500, 0),
    ('fresh 700', 700, 0),
    ('fresh 999', 999, 0),
    ('fresh 1000', 1000, 0),
    ('fresh 1500', 1500, 0),
  ];
  const tests = <double?>[
    null,
    double.nan,
    1500,
    1000,
    999,
    700,
    500,
    499,
    300,
    200,
    199,
    80,
  ];

  test('never lowers the rung, and marks a test value whenever it is '
      'read', () {
    for (final (name, m, age) in measured) {
      final base = _advise(m, age);
      for (final t in tests) {
        final v = visibilityForCaution(
          measuredMeters: m,
          measuredAgeSeconds: age,
          testMeters: t,
        );
        final got = _advise(v.meters, v.ageSeconds);
        final when = 'measured $name, test $t';
        expect(
          got.action.index,
          greaterThanOrEqualTo(base.action.index),
          reason: '$when: the rung fell',
        );
        if (!v.isTestValue) {
          expect(
            v.meters == m ||
                ((v.meters?.isNaN ?? false) && (m?.isNaN ?? false)),
            isTrue,
            reason: '$when: not marked, so the measured reading',
          );
          expect(v.ageSeconds, age, reason: '$when: the measured age');
        } else {
          expect(v.meters, t, reason: '$when: marked, so the test value');
          expect(got.action.index, greaterThanOrEqualTo(base.action.index));
          expect(
            visibilityConcern(t, 0),
            greaterThan(visibilityConcern(m, age)),
            reason: '$when: a test value read only where it adds',
          );
        }
      }
    }
  });

  test('a missing or stale reading is not cleared by a clear test value, and '
      'its own words stay', () {
    for (final (m, age) in const [(null, null), (80.0, 301.0)]) {
      final v = visibilityForCaution(
        measuredMeters: m,
        measuredAgeSeconds: age,
        testMeters: 1500,
      );
      expect(v.isTestValue, isFalse);
      expect(_advise(v.meters, v.ageSeconds).visibilityKnown, isFalse);
    }
  });

  test(
    'a lower test value adds: fresh 700 with a test 80 reads 80, marked',
    () {
      final v = visibilityForCaution(
        measuredMeters: 700,
        measuredAgeSeconds: 0,
        testMeters: 80,
      );
      expect(v, (meters: 80.0, ageSeconds: 0.0, isTestValue: true));
      expect(
        _advise(v.meters, v.ageSeconds).action,
        DriveAction.considerStopping,
      );
    },
  );

  test('the bands match the advisor at every edge', () {
    for (final m in const [0.0, 199.0, 200.0, 499.0, 500.0, 999.0, 1000.0]) {
      final rung = _advise(m, 0).action;
      final c = visibilityConcern(m, 0);
      expect(rung, switch (c) {
        0 => DriveAction.continueDriving,
        1 || 2 => DriveAction.heightenedCaution,
        _ => DriveAction.considerStopping,
      }, reason: '$m m');
    }
  });

  // AAA R52 mirror test, adopted. The edge test above compares with a trusted
  // position only, where concern 1 and 2 give the same rung, so a mirror that
  // ranks 500-999 m as low passed it (AAA's M2) and a demo 700 m replaced a
  // missing reading. The advisor's own concern is recovered from two
  // positions: trusted separates 0 / {1,2} / 3; degraded separates {0,1} /
  // {2,3} by compounding.
  test('the mirror equals the advisor concern across bands, edges and ages',
      () {
    DriveAction a(PositionTrust t, double? m, double? age) => adviseInDrive(
          DriveSituation(
            positionTrust: t,
            confidenceRadiusMeters: t == PositionTrust.trusted ? 0 : 50,
            secondsSinceTrustedFix: t == PositionTrust.trusted ? 0 : 10,
            hasPosition: true,
            visibilityMeters: m,
            visibilityAgeSeconds: age,
            advisorySeverity: null,
            speedMetersPerSecond: null,
          ),
        ).action;
    int advisorConcern(double? m, double? age) {
      final trusted = a(PositionTrust.trusted, m, age);
      if (trusted == DriveAction.continueDriving) return 0;
      if (trusted == DriveAction.considerStopping) return 3;
      return a(PositionTrust.degraded, m, age) == DriveAction.considerStopping
          ? 2
          : 1;
    }

    const ms = <double?>[null, double.nan, -1, 0, 80, 199, 200, 300, 499,
      500, 700, 999, 1000, 1500, double.infinity];
    const ages = <double?>[null, double.nan, -5, 0, 299, 300, 301,
      double.infinity];
    for (final m in ms) {
      for (final age in ages) {
        expect(visibilityConcern(m, age), advisorConcern(m, age),
            reason: 'meters $m age $age');
      }
    }
  });
}
