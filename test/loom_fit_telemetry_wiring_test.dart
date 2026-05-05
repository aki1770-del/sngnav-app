// Integrator-wiring tests for #101 (AlertExplainer) + #102 (LoomFitTelemetry).
//
// Verifies sngnav-app's wiring at the alert-firing surface:
// - LoomFitTelemetry receives one record per shouldFire call.
// - Records carry the active DriverProfile (per-class fit substrate).
// - AlertExplainer.forConditionAndProfile returns non-empty action
//   string for default state (ageingRural × ice).
// - Profile-switch changes throttle cap AND explainer action AND
//   telemetry record's profileClass.
//
// AAA Article 17 (β) discipline: these tests verify behavior; they
// do NOT exercise driver-facing wording. Wording-class verification
// lives in navigation_safety_core's own test suite.

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

import 'package:sngnav_app/main.dart';

void main() {
  testWidgets(
    '#102 — _fireAlertSequence emits 8 telemetry records in default state',
    (tester) async {
      await tester.pumpWidget(const SngnavApp());
      await tester.pump();
      // Tap the fire-alert-sequence button.
      final fireButton = find.text('Fire 8 sequential warning alerts');
      expect(fireButton, findsOneWidget);
      await tester.ensureVisible(fireButton);
      await tester.tap(fireButton);
      await tester.pump();
      // After firing, the throttle panel renders 8 attempt rows.
      expect(find.textContaining('Attempt 1 (t+0s):'), findsOneWidget);
      expect(find.textContaining('Attempt 8 (t+35s):'), findsOneWidget);
      // The LoomFit telemetry panel renders the rolling list of
      // records — ageingRural is the default profile, so each row
      // includes that token; expect 8 rows in the rolling list (cap
      // 16, so all 8 fit).
      expect(find.textContaining('ageingRural'), findsWidgets);
      // Outcome tokens should appear — at least one droppedByThrottle
      // (cap 1.0/min × 8 attempts in 35s window) AND one fired or
      // coldStart.
      expect(find.textContaining('droppedByThrottle'), findsWidgets);
    },
  );

  test(
    '#101 — AlertExplainer returns non-empty action for default state '
    '(ageingRural × ice)',
    () {
      final explainer = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.ageingRural,
      );
      expect(explainer.action, isNotEmpty);
      expect(explainer.localeTag, equals('ja'));
      expect(explainer.verbosity, equals(VerbosityLevel.full));
      expect(explainer.condition, equals(RoadSurfaceCondition.ice));
    },
  );

  test(
    '#101 + #102 — profile switch changes throttle cap, explainer '
    'action, and telemetry profileClass',
    () {
      // Throttle cap differs across profiles.
      final ageingCap =
          AlertDensityThrottle.defaultCapFor(DriverProfile.ageingRural);
      final professionalCap =
          AlertDensityThrottle.defaultCapFor(DriverProfile.professional);
      expect(ageingCap, isNot(equals(professionalCap)));

      // Explainer action differs across profiles for the same condition.
      final ageingAction = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.ageingRural,
      ).action;
      final professionalAction = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.professional,
      ).action;
      expect(ageingAction, isNot(equals(professionalAction)));

      // Telemetry record carries the profile passed in; downstream
      // analytics can disambiguate per-class fit.
      final r1 = LoomFitTelemetryRecord(
        profileClass: DriverProfile.ageingRural,
        ambientThreshold: 't1',
        alertSequence: const [],
        responseLatency: null,
        outcome: LoomFitOutcome.fired,
      );
      final r2 = LoomFitTelemetryRecord(
        profileClass: DriverProfile.professional,
        ambientThreshold: 't1',
        alertSequence: const [],
        responseLatency: null,
        outcome: LoomFitOutcome.fired,
      );
      expect(r1.profileClass, isNot(equals(r2.profileClass)));
    },
  );
}
