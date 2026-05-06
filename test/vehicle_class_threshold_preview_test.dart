// Integrator-wiring tests for NSC #3 vehicle-class threshold-preview
// surface (spawn -82b).
//
// Verifies sngnav-app's wiring of the NSC 0.9.0 vehicle-class API:
// - NavigationSafetyConfig.forProfileWithContext baseline call returns
//   the per-profile baseline thresholds (anchor: ageingRural).
// - DrivingContext(vehicleClassToken: 'kei-car') + withKeiCarDefault()
//   raises warningVisibilityMeters by exactly +50m and
//   warningTemperatureCelsius by exactly +1°C vs baseline (verbatim
//   delta from NSC 0.9.0 CHANGELOG).
// - DrivingContext(vehicleClassToken: 'compact-sedan') +
//   withKeiCarDefault() returns identical config to baseline (no-op
//   fallback per applyOverrideForToken semantics).
// - Widget test: vehicle-class dropdown change to 'kei-car' triggers
//   state update + threshold preview displays the +50 / +1 delta.
//
// AAA Article 17 (β) discipline: tests verify integrator-side
// caution-add-only behaviour at the NSC API boundary; do NOT exercise
// driver-facing wording. Wording-class verification lives in
// navigation_safety_core's own test suite.

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

import 'package:sngnav_app/main.dart';

void main() {
  group('NSC #3 vehicle-class threshold-config wiring', () {
    test(
      'baseline forProfileWithContext(ageingRural) returns the per-profile '
      'baseline (warningVisibility=300, warningTemperature=2)',
      () {
        final baseline = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.ageingRural,
        );
        // Anchor against navigation_safety_core/lib/src/navigation_safety_config.dart
        // forProfile(ageingRural) baseline (lines 64-74 at 0.9.0).
        expect(baseline.warningVisibilityMeters, 300);
        expect(baseline.warningTemperatureCelsius, 2);
      },
    );

    test(
      'kei-car token + withKeiCarDefault() override raises '
      'warningVisibility by exactly +50m and warningTemperature by '
      'exactly +1°C vs baseline (caution-add-only)',
      () {
        final overrides = VehicleThresholdOverrides.withKeiCarDefault();
        final baseline = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.ageingRural,
        );
        final withKeiCar = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.ageingRural,
          context: const DrivingContext(vehicleClassToken: 'kei-car'),
          vehicleOverrides: overrides,
        );
        expect(
          withKeiCar.warningVisibilityMeters -
              baseline.warningVisibilityMeters,
          50,
          reason: 'kei-car override must add exactly +50m to warning '
              'visibility per NSC 0.9.0 CHANGELOG',
        );
        expect(
          withKeiCar.warningTemperatureCelsius -
              baseline.warningTemperatureCelsius,
          1,
          reason: 'kei-car override must add exactly +1°C to warning '
              'temperature per NSC 0.9.0 CHANGELOG',
        );
        // Score floors preserved (severity-not-profile invariant).
        expect(withKeiCar.safeScoreFloor, baseline.safeScoreFloor);
        expect(withKeiCar.infoScoreFloor, baseline.infoScoreFloor);
        expect(withKeiCar.warningScoreFloor, baseline.warningScoreFloor);
      },
    );

    test(
      'compact-sedan token + withKeiCarDefault() returns identical '
      'config to baseline (no-op fallback for unregistered token)',
      () {
        final overrides = VehicleThresholdOverrides.withKeiCarDefault();
        final baseline = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.ageingRural,
        );
        final withCompactSedan = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.ageingRural,
          context: const DrivingContext(vehicleClassToken: 'compact-sedan'),
          vehicleOverrides: overrides,
        );
        expect(
          withCompactSedan.warningVisibilityMeters,
          baseline.warningVisibilityMeters,
        );
        expect(
          withCompactSedan.warningTemperatureCelsius,
          baseline.warningTemperatureCelsius,
        );
        // Equatable equality should hold for an unregistered token.
        expect(withCompactSedan, equals(baseline));
      },
    );
  });

  testWidgets(
    'NSC #3 — vehicle-class dropdown selection of kei-car renders '
    '+50 / +1 delta in the threshold preview section',
    (tester) async {
      await tester.pumpWidget(const SngnavApp());
      await tester.pump();

      // Baseline render: with vehicleClassToken = null, the
      // with-vehicle visibility row should equal the baseline (no
      // delta annotation parenthesis).
      expect(
        find.text(
          'Vehicle class (HER cohort: kei-car-at-65 default)',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Threshold preview (profile × vehicle × driver-state)',
        ),
        findsOneWidget,
      );

      // Open the vehicle-class dropdown. There are two String? dropdowns
      // possible on screen; we scope to the one inside the section we
      // just verified is present by tapping the first matching label.
      final keiCarItemFinder = find.text(
        'kei-car (HER cohort default — overrides registered)',
      );
      // Find the dropdown by its current value text and tap to open.
      await tester.ensureVisible(
        find.text('unknown / no signal (baseline)').first,
      );
      await tester.tap(find.text('unknown / no signal (baseline)').first);
      await tester.pumpAndSettle();

      // The dropdown menu surface displays the kei-car item; tap it.
      expect(keiCarItemFinder, findsWidgets);
      await tester.tap(keiCarItemFinder.last);
      await tester.pumpAndSettle();

      // The threshold preview now shows the delta on warning visibility
      // (+50) and warning temperature (+1). For ageingRural baseline:
      // visibility 300 -> 350 (+50); temperature 2 -> 3 (+1).
      expect(find.text('350 m (+50)'), findsOneWidget);
      expect(find.text('3 °C (+1)'), findsOneWidget);
    },
  );
}
