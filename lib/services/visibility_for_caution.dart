/// Which visibility her caution reads, when a test value may be set beside the
/// station's reading (ruled 2026-09-15; invariant 2026-09-16).
///
/// A value that is not a measurement may ADD caution and may never take any
/// away. Each candidate is ranked on the advisor's own bands, where a missing
/// or stale reading is the middle concern and never clear. The test value is
/// read only when it ranks strictly above the measured one; on a tie the
/// measured reading stays, so a missing reading's own words stay on her card.
///
/// On any build: nothing here reads whether the build is a release build, so
/// a control that writes a test value in a debug build or a later one reaches
/// the same rule.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show kVisClearM, kVisLowM, kVisReducedM, kVisStaleSeconds;

/// The concern the advisor gives a visibility of [meters] aged [ageSeconds]:
/// 0 clear, 1 reduced or not measured (missing, NaN, unknown age or stale),
/// 2 low, 3 whiteout. Mirrors `compound_failure_advisor` 0.1.2's bands.
int visibilityConcern(double? meters, double? ageSeconds) {
  final exists = meters != null && !meters.isNaN;
  final fresh =
      exists &&
      ageSeconds != null &&
      !ageSeconds.isNaN &&
      ageSeconds <= kVisStaleSeconds;
  if (!fresh) return 1;
  if (meters >= kVisClearM) return 0;
  if (meters >= kVisReducedM) return 1;
  if (meters >= kVisLowM) return 2;
  return 3;
}

/// The visibility her caution reads, and whether it is a test value.
typedef VisibilityForCaution = ({
  double? meters,
  double? ageSeconds,
  bool isTestValue,
});

/// The measured reading, unless [testMeters] ranks strictly higher on
/// [visibilityConcern]; then the test value, fresh, marked as a test value.
VisibilityForCaution visibilityForCaution({
  required double? measuredMeters,
  required double? measuredAgeSeconds,
  required double? testMeters,
}) {
  final measured = (
    meters: measuredMeters,
    ageSeconds: measuredAgeSeconds,
    isTestValue: false,
  );
  if (testMeters == null || testMeters.isNaN) return measured;
  if (visibilityConcern(testMeters, 0) >
      visibilityConcern(measuredMeters, measuredAgeSeconds)) {
    return (meters: testMeters, ageSeconds: 0.0, isTestValue: true);
  }
  return measured;
}
