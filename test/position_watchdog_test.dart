/// N8 — the real-GPS-blackout watchdog decision table.
///
/// The degradation machine's poll() was production-wired ONLY to the demo
/// blackout button: in a REAL blackout no fix events arrive, nothing polls,
/// and the honest dot stays "trusted" forever — a confidently-wrong dot in
/// exactly the compound-failure scenario the app exists for. The app now
/// polls on a periodic tick through [positionWatchdogPollTime]; this table
/// pins when it polls, when it stays quiet, and which clock it uses.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart'
    show SngnavApp, positionWatchdogPollTime;

import 'support/fake_alert_actuators.dart';

// A clear, warm observation: no invisible-ice window, no turmoil — the JMA
// lane stays silent so any spoken line in these tests can only come from the
// drive brain's degradation path.
JmaObservation _clearObs() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 15.0,
      humidityPercent: 30,
      windMetersPerSecond: 1.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260715063000',
      fetchedAt: DateTime(2026, 7, 15, 6, 30),
    );

void main() {
  final now = DateTime.utc(2026, 1, 15, 6, 30);
  const cadence = Duration(seconds: 30);

  group('positionWatchdogPollTime', () {
    test('nothing ever fed → no poll (no baseline to degrade; the permission '
        'dialog may still be up)', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: null,
          demoClock: null,
        ),
        isNull,
      );
    });

    test('a fresh event within the cadence → no poll (the pipeline is alive; '
        'degrading it would cry wolf at a healthy feed)', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(const Duration(seconds: 29)),
          demoClock: null,
        ),
        isNull,
      );
    });

    test('a drought at exactly the cadence → POLL (the boundary counts as '
        'stale — absence must not get a free extra tick of calm)', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(cadence),
          demoClock: null,
        ),
        now,
      );
    });

    test('a real drought → poll with the real clock', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(const Duration(minutes: 3)),
          demoClock: null,
        ),
        now,
      );
    });

    test('demo blackout clock AHEAD of real now → poll with the demo clock '
        '(the localizer clock must never run backwards mid-degradation)', () {
      final demoClock = now.add(const Duration(seconds: 120));
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(const Duration(minutes: 3)),
          demoClock: demoClock,
        ),
        demoClock,
      );
    });

    test('demo clock BEHIND real now (stale baseline, no demo pressed lately) '
        '→ the real clock wins', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(const Duration(minutes: 3)),
          demoClock: now.subtract(const Duration(minutes: 3)),
        ),
        now,
      );
    });
  });

  // ---- stop-sharing lifecycle (widget-level) ------------------------------
  //
  // The watchdog exists to degrade a feed that CLAIMS to be live. When she
  // taps 停止 she ends that claim — the watchdog must die with it, or ~30 s
  // later the app speaks escalating "blackout" warnings about a feed she
  // deliberately turned off (phantom degradation). The control test proves
  // this harness DOES detect the failure mode when sharing continues.

  group('stop-sharing cancels the blackout watchdog (widget)', () {
    Future<(FakeAlertActuators, StreamController<PositionFix>)> pumpSharing(
      WidgetTester tester,
      DateTime Function() clock,
    ) async {
      final fake = FakeAlertActuators();
      // broadcast: the re-share test subscribes a second time.
      final positions = StreamController<PositionFix>.broadcast();
      await tester.pumpWidget(SngnavApp(
        actuators: fake,
        locale: const Locale('ja'),
        clock: clock,
        jmaFetch: () async => JmaSuccess(_clearObs()),
        positionSource: () => positions.stream,
      ));
      await tester.pump();
      await tester.pump();

      // Start the real drive: share location, deliver one trusted fix.
      // (ensureVisible: the button sits below the fold of the scroll page.)
      await tester.ensureVisible(find.text('現在地を共有'));
      await tester.pump();
      await tester.tap(find.text('現在地を共有'));
      await tester.pump();
      positions.add(PositionAvailable(
        latitude: 39.7167,
        longitude: 140.0983,
        accuracyMeters: 20,
        timestamp: clock(),
      ));
      await tester.pump();
      return (fake, positions);
    }

    testWidgets(
        'CONTROL — sharing continues, fixes stop arriving: the watchdog '
        'degrades the dot and the drive brain announces (the harness can '
        'see the failure mode)', (tester) async {
      var now = DateTime.utc(2026, 1, 15, 6, 30);
      final (fake, positions) = await pumpSharing(tester, () => now);
      expect(fake.spoken, isEmpty,
          reason: 'clear skies + a fresh trusted fix announce nothing');

      // A REAL blackout: no fixes for 3 minutes while sharing stays on.
      now = now.add(const Duration(minutes: 3));
      await tester.pump(const Duration(minutes: 3));

      expect(fake.spoken, isNotEmpty,
          reason: 'a genuine 3-min GPS drought with sharing ON must degrade '
              'and announce — if this stops holding, the stop-test below '
              'proves nothing');
      await positions.close();
    });

    testWidgets(
        '停止 (stop) then 3 silent minutes: NO phantom degradation announce '
        'about the feed she deliberately ended', (tester) async {
      var now = DateTime.utc(2026, 1, 15, 6, 30);
      final (fake, positions) = await pumpSharing(tester, () => now);

      // She ends the feed on purpose.
      await tester.ensureVisible(find.text('停止'));
      await tester.pump();
      await tester.tap(find.text('停止'));
      await tester.pump();
      final spokenAtStop = List.of(fake.spoken);
      final hapticsAtStop = List.of(fake.haptics);

      // The same 3 silent minutes that degrade+announce in the control.
      now = now.add(const Duration(minutes: 3));
      await tester.pump(const Duration(minutes: 3));

      expect(fake.spoken, spokenAtStop,
          reason: 'stop cancelled the claim of liveness; a "blackout" '
              'warning after it is a phantom about a feed she turned off');
      expect(fake.haptics, hapticsAtStop);
      await positions.close();
    });

    testWidgets(
        're-share after stop: the first watchdog tick must not poll against '
        'the PREVIOUS drive\'s stale timestamp before a fresh fix arrives',
        (tester) async {
      var now = DateTime.utc(2026, 1, 15, 6, 30);
      final (fake, positions) = await pumpSharing(tester, () => now);

      await tester.ensureVisible(find.text('停止'));
      await tester.pump();
      await tester.tap(find.text('停止'));
      await tester.pump();

      // Much later, she shares again; no fix has arrived yet (the
      // permission dialog / first satellite lock can take a while).
      now = now.add(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 10));
      await tester.ensureVisible(find.text('現在地を共有'));
      await tester.pump();
      await tester.tap(find.text('現在地を共有'));
      await tester.pump();
      final spokenAtReshare = List.of(fake.spoken);

      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));

      expect(fake.spoken, spokenAtReshare,
          reason: 'no baseline yet (no event this drive) → the watchdog '
              'must stay quiet, not degrade against last drive\'s clock');
      await positions.close();
    });
  });
}
