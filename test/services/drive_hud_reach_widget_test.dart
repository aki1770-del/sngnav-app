/// WS6 — end-to-end reach: the live drive-caution panel renders in the REAL app
/// tree (render-SEE, OPS-066) AND a real compound-failure hazard AUTO-announces
/// on the app's single injected actuator — no manual button.
///
/// HER-trace: this is the in-env proof that the WS6 brain is WIRED into
/// SngnavApp — sharing a (mock) position then losing GPS drives the honest dot
/// to `lost`, the on-screen JA caution banner rises to 停車の検討, and the same
/// rung auto-fires audio + haptic through the injected actuator. It does NOT
/// prove she HEARS / FEELS it on a phone (DEFERRED — docs/DEVICE_VERIFICATION.md,
/// OPS-066 / AAE-1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';

import '../support/fake_alert_actuators.dart';

// A clear-conditions JMA observation: no ice, no turmoil, no feed loss — so the
// W0 detection-survival lane stays deterministically SILENT and this WS6
// drive-HUD reach test is isolated from the JMA announce path. (Without an
// injected fetch the real AMeDAS call fails under the test binding and the
// no-cache feed-loss absence-line would speak, which is correct app behavior
// but noise for THIS test.)
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
    'share mock position → GPS blackout → JA caution banner rises to '
    '停車の検討 AND auto-announces (audio + haptic) on the injected actuator',
    (tester) async {
      final fake = FakeAlertActuators();
      await tester.pumpWidget(
        SngnavApp(
          actuators: fake,
          locale: const Locale('ja'),
          jmaFetch: () async => JmaSuccess(_clearObs()),
        ),
      );
      await tester.pump();

      // Feed a trusted position via the Akita mock. There is no visibility
      // reading (AMeDAS returns null; no demo override) → the live brain holds
      // the honest UNKNOWN floor: heightened caution, but SILENT (an
      // unknown-visibility-only rise is shown, never announced — no cry-wolf).
      final mockBtn = find.byKey(const Key('use-mock-button'));
      expect(mockBtn, findsOneWidget);
      await tester.ensureVisible(mockBtn);
      await tester.pump();
      await tester.tap(mockBtn);
      await tester.pump();
      await tester.pump();

      final banner = find.byKey(const Key('drive-hud-caution-banner'));
      await tester.ensureVisible(banner);
      await tester.pump();
      // render-SEE: the caution banner is on screen in the real app, in JA,
      // reading the honest held UNKNOWN floor (未計測 ≠ clear) — never a false
      // "continue" when we have taken no visibility reading.
      expect(banner, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.text('注意して走行')),
        findsOneWidget,
      );
      // An unknown-visibility-only heightened rise is SILENT: nothing spoken or
      // buzzed yet (the alarm is reserved for a measured hazard).
      expect(fake.spoken, isEmpty);
      expect(fake.haptics, isEmpty);

      // Simulate GPS blackout: 3 × +60 s → past the 120 s honesty horizon →
      // the dot degrades to `lost`. A lost position alone reaches the ceiling.
      final blackoutBtn = find.byKey(const Key('drive-hud-blackout-button'));
      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(blackoutBtn);
        await tester.pump();
        await tester.tap(blackoutBtn);
        await tester.pump();
        await tester.pump();
      }

      // render-SEE: the banner has RISEN to 停車の検討 with the calm JA guidance.
      await tester.ensureVisible(banner);
      await tester.pump();
      expect(
        find.descendant(of: banner, matching: find.text('停車の検討')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('安全な場所での停車'),
        ),
        findsOneWidget,
      );

      // REACH: the same rung auto-fired audio + haptic on the app's single
      // injected actuator — the caution reached HER eyes-off, no manual button.
      expect(fake.spoken, isNotEmpty);
      expect(fake.spoken.last.localeTag, 'ja-JP');
      expect(fake.spoken.last.text, contains('停車'));
      expect(fake.haptics.last, HapticCuePattern.critical);
    },
  );
}
