/// WS5 — widget test: tapping "Announce to driver" fires audio + haptic with
/// the correct JA whiteout guidance. This is the end-to-end in-env proof that
/// the app's button reaches BOTH channels; it does NOT prove on-device
/// HEAR/FEEL (DEFERRED, OPS-066 / AAE-1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';

import '../support/fake_alert_actuators.dart';

// A clear-conditions JMA observation so the W0 detection-survival lane stays
// SILENT (no ice, no turmoil, no feed loss) — isolating this WS5 announce-button
// test from the JMA announce path. Without an injected fetch the real AMeDAS
// call fails under the test binding and the no-cache absence-line would speak
// (correct app behavior, but noise for THIS test).
JmaObservation _clearObs() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 8.0,
      humidityPercent: 70,
      windMetersPerSecond: 2.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260115063000',
      fetchedAt: DateTime(2026, 1, 15, 6, 30),
    );

void main() {
  testWidgets(
    'tapping Announce (default ageingRural + ice) => speak(JA ice text, '
    'ja-JP) + critical haptic',
    (tester) async {
      final fake = FakeAlertActuators();
      // The guidance the default (ageingRural, ice) surface should speak.
      final expected = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.ageingRural,
      );

      await tester.pumpWidget(SngnavApp(
        actuators: fake,
        jmaFetch: () async => JmaSuccess(_clearObs()),
      ));
      await tester.pump();

      // initState holds the screen awake (foreground-only).
      expect(fake.keepAwakeCalls, contains(true));

      final button = find.byKey(const Key('announce-alert-button'));
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      // Flush the fire-and-forget announce() microtasks.
      await tester.pump();
      await tester.pump();

      // AUDIO: the JA ice guidance at the ja-JP voice tag.
      expect(fake.spoken, hasLength(1));
      expect(fake.spoken.single.text, expected.action);
      expect(fake.spoken.single.localeTag, 'ja-JP');

      // HAPTIC: critical cue (deaf/HoH parity).
      expect(fake.haptics, [HapticCuePattern.critical]);
    },
  );
}
