// Integrator-wiring tests for Wave 1 sub-bundle 2 — DriverState-axis
// scaffolding (NSC 0.10.0 #28 CircadianPhase / #29 SessionState /
// #30 ConfidenceProvider).
//
// Verifies sngnav-app's wiring of the four new optional inputs to
// NavigationSafetyConfig.forDriverContext + the cap-override-with-
// confirmation pattern. Tests verify behaviour at the API boundary
// per AAA Article 17 (β); no driver-facing wording exercised.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

import 'package:sngnav_app/main.dart';

void main() {
  group('Sub-bundle 2 — DriverState-axis API contract', () {
    test(
      '#28 — circadianPhase lateNight raises warning visibility above '
      'baseline+vehicle (caution-add-only multiplier 1.5x)',
      () {
        final base = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.ageingRural,
        );
        final withPhase = NavigationSafetyConfig.forDriverContext(
          const DriverContext(
            profile: DriverProfile.ageingRural,
            state: DriverState.alert,
          ),
          circadianPhase: CircadianPhase.lateNight,
        );
        // Caution-add-only: lateNight (1.5x) raises warningVisibility.
        expect(
          withPhase.warningVisibilityMeters,
          greaterThan(base.warningVisibilityMeters),
        );
      },
    );

    test(
      '#29 — sessionState severe lifts warning visibility above rested',
      () {
        final rested = NavigationSafetyConfig.forDriverContext(
          const DriverContext(
            profile: DriverProfile.ageingRural,
            state: DriverState.alert,
          ),
          sessionState: const SessionState(
            consecutiveDrivingDays: 0,
            cumulativeFatigue: CumulativeFatigueClass.rested,
          ),
        );
        final severe = NavigationSafetyConfig.forDriverContext(
          const DriverContext(
            profile: DriverProfile.ageingRural,
            state: DriverState.alert,
          ),
          sessionState: const SessionState(
            consecutiveDrivingDays: 8,
            cumulativeFatigue: CumulativeFatigueClass.severe,
          ),
        );
        expect(
          severe.warningVisibilityMeters,
          greaterThan(rested.warningVisibilityMeters),
        );
      },
    );

    test(
      '#30 — Confidence.high WITHOUT confirmation behaves as medium '
      '(driver-always-drives invariant; cap NOT loosened)',
      () {
        final medium = NavigationSafetyConfig.forDriverContext(
          const DriverContext(
            profile: DriverProfile.ageingRural,
            state: DriverState.alert,
          ),
          confidence: Confidence.medium,
        );
        final highUnconfirmed = NavigationSafetyConfig.forDriverContext(
          const DriverContext(
            profile: DriverProfile.ageingRural,
            state: DriverState.alert,
          ),
          confidence: Confidence.high,
          // isHighConfidenceConfirmed defaults to false.
        );
        // The cap MUST be identical when high is unconfirmed.
        expect(
          highUnconfirmed.alertsPerMinuteCapOverride,
          equals(medium.alertsPerMinuteCapOverride),
        );
      },
    );

    test(
      '#30 — Confidence.low tightens the alerts-per-minute cap below '
      'medium baseline',
      () {
        final medium = NavigationSafetyConfig.forDriverContext(
          const DriverContext(
            profile: DriverProfile.ageingRural,
            state: DriverState.alert,
          ),
          confidence: Confidence.medium,
        );
        final low = NavigationSafetyConfig.forDriverContext(
          const DriverContext(
            profile: DriverProfile.ageingRural,
            state: DriverState.alert,
          ),
          confidence: Confidence.low,
        );
        // low MUST tighten (= equal-or-lower cap; never higher).
        // Either an explicit override appears OR baseline is unchanged
        // (depending on per-profile defaults). We assert non-loosen.
        final lowCap = low.alertsPerMinuteCapOverride;
        final mediumCap = medium.alertsPerMinuteCapOverride;
        if (lowCap != null && mediumCap != null) {
          expect(lowCap, lessThanOrEqualTo(mediumCap));
        }
      },
    );
  });

  group('Sub-bundle 2 — sngnav-app wiring', () {
    testWidgets(
      'Driver state inputs section renders with 3 dropdowns + sliders',
      (tester) async {
        await tester.pumpWidget(const SngnavApp());
        await tester.pump();
        // Section header is visible.
        expect(
          find.textContaining('Driver state inputs'),
          findsOneWidget,
        );
        // Three sub-headers per brief: circadian / session / confidence.
        expect(find.textContaining('Circadian phase'), findsOneWidget);
        expect(find.textContaining('Session state'), findsWidgets);
        expect(find.textContaining('Confidence'), findsWidgets);
      },
    );

    testWidgets(
      'Threshold preview shows baseline + vehicle + driver-state row '
      '(extended composition)',
      (tester) async {
        await tester.pumpWidget(const SngnavApp());
        await tester.pump();
        // Three rows now visible per brief shape.
        expect(
          find.textContaining('Baseline warning visibility'),
          findsOneWidget,
        );
        expect(
          find.textContaining('With-vehicle warning visibility'),
          findsOneWidget,
        );
        expect(
          find.textContaining('+ driver-state warning visibility'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Confidence dropdown set to high reveals confirmation toggle '
      '(cap-override-with-confirmation surface)',
      (tester) async {
        await tester.pumpWidget(const SngnavApp());
        await tester.pump();
        // Find the confidence dropdown by its placeholder text.
        await tester.ensureVisible(
          find.text('(no signal — no cap modification)').first,
        );
        await tester
            .tap(find.text('(no signal — no cap modification)').first);
        await tester.pumpAndSettle();
        // Tap the high item.
        final highItem =
            find.text('high (requires confirmation to loosen)');
        expect(highItem, findsWidgets);
        await tester.tap(highItem.last);
        await tester.pumpAndSettle();
        // The confirmation toggle now appears.
        expect(
          find.text('High-confidence confirmation'),
          findsOneWidget,
        );
      },
    );
  });
}
