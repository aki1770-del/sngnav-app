/// D10 — an ERROR on HER position feed must reach her surface as the honest
/// "GPS unavailable" line, at the instant it is known.
///
/// Why this test exists. `herPositionStream` (her_position.dart) documents its
/// own contract in its library doc: it "Emits [PositionUnavailable] on
/// permission denial, service-disabled, stream error, ... never silently
/// stalls on a stale fix." That contract is honoured by exactly one
/// implementation and enforced by nothing. The app's single position ingest
/// takes a SWAPPABLE source (`SngnavApp.positionSource`, and the dead-reckoning
/// fallback her_position.dart's library doc names as deferred), so the day the
/// source changes, an errored event arriving at the widget boundary with no
/// `onError` goes to the zone — invisible to her in a release build — while her
/// last dot stays on screen looking measured.
///
/// The measured harm is not "the dot freezes forever": Dart leaves a
/// subscription live through an unhandled error (cancelOnError defaults to
/// false), and the N8 watchdog degrades a silent feed on its own 30 s cadence.
/// The harm is that the app owns a distinct, localized, honest state for "we do
/// not know where you are" and the error path is the one path that bypasses it
/// — she is shown a confident dot for up to a cadence after the loom knew
/// better. AAE-6/AAE-7: the last inch carries the abstention it was handed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import 'support/fake_alert_actuators.dart';

// Clear, warm: the JMA lane stays silent so nothing else moves the surface.
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

/// HER-facing lines, verbatim from AppL10n (ja).
const _honestUnavailable = 'GPSストリームのエラー';
const _confidentDot = '現在地 · ±20 m';

void main() {
  group('D10 — HER position feed: an error reaches her surface', () {
    Future<StreamController<PositionFix>> pumpSharing(
      WidgetTester tester,
      DateTime Function() clock,
    ) async {
      final positions = StreamController<PositionFix>();
      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        clock: clock,
        jmaFetch: () async => JmaSuccess(_clearObs()),
        positionSource: () => positions.stream,
      ));
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('現在地を共有'));
      await tester.pump();
      await tester.tap(find.text('現在地を共有'));
      await tester.pump();
      return positions;
    }

    testWidgets(
        'CONTROL — the same unavailability delivered as DATA does reach her '
        'surface (proves this harness can see the state at all)',
        (tester) async {
      final now = DateTime.utc(2026, 1, 15, 6, 30);
      final positions = await pumpSharing(tester, () => now);

      positions.add(const PositionUnavailable('GPS stream error: boom'));
      await tester.pump();

      expect(
        find.textContaining(_honestUnavailable),
        findsOneWidget,
        reason: 'if this fails the test below proves nothing — the assertion '
            'itself would be blind',
      );
      await positions.close();
    });

    testWidgets(
        'a stream ERROR after a good fix must replace the confident dot with '
        'the honest GPS-unavailable line', (tester) async {
      final now = DateTime.utc(2026, 1, 15, 6, 30);
      final positions = await pumpSharing(tester, () => now);

      positions.add(PositionAvailable(
        latitude: 39.7167,
        longitude: 140.0983,
        accuracyMeters: 20,
        timestamp: now,
      ));
      await tester.pump();
      expect(find.textContaining(_confidentDot), findsOneWidget,
          reason: 'baseline: a good fix renders as a confident dot');

      // The source errors. Her screen must stop claiming to know where she is.
      positions.addError(StateError('platform GPS stream failed'));
      await tester.pump();

      expect(
        find.textContaining(_confidentDot),
        findsNothing,
        reason: 'the loom knows it lost her position; the screen must not '
            'still say ±20 m',
      );
      expect(
        find.textContaining(_honestUnavailable),
        findsOneWidget,
        reason: 'her_position.dart promises PositionUnavailable on a stream '
            'error; the app boundary must honour that promise, not trust it',
      );
      await positions.close();
    });

    testWidgets(
        'an error is one bad event, not the end of the drive: a later real '
        'fix still reaches her', (tester) async {
      final now = DateTime.utc(2026, 1, 15, 6, 30);
      final positions = await pumpSharing(tester, () => now);

      positions.addError(StateError('transient platform GPS stream failure'));
      await tester.pump();
      expect(find.textContaining(_honestUnavailable), findsOneWidget);

      positions.add(PositionAvailable(
        latitude: 39.7167,
        longitude: 140.0983,
        accuracyMeters: 20,
        timestamp: now,
      ));
      await tester.pump();

      expect(find.textContaining(_confidentDot), findsOneWidget,
          reason: 'cancelOnError must stay false — a recovered feed must be '
              'able to tell her she is found again');
      await positions.close();
    });
  });
}
