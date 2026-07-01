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
import 'package:sngnav_app/main.dart';

import '../support/fake_alert_actuators.dart';

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

      await tester.pumpWidget(SngnavApp(actuators: fake));
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
