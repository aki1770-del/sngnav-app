/// A share that runs without its foreground service is not read as a GPS loss
/// when the app leaves the front.
///
/// Why, written before the act (2026-10-06). The app starts the drive's
/// foreground service only when it can post her a notification (canPostToHer:
/// the Android 13 permission AND notifications switched on for the app, which
/// can be off at any API level). Without the service, Android throttles a
/// background app's location, and geolocator_android 4.6.2 stops the stream
/// outright on any activity detach (StreamHandlerImpl.java:46-52). Either way,
/// fixes stop for a reason that is not the sky. Today the drive brain cannot
/// tell: it reads that silence as a GPS blackout, degrades her position, and
/// tells her the caution for a GPS loss that is not there, while the warnings
/// she believes are running are not.
///
/// The rule these tests hold: while the app is not in front, a share with no
/// foreground service is never read as a GPS loss. The caution the drought
/// tells is not spoken, and on her return the map does not say 「GPS 途絶」 for
/// it. What the app does instead (end the share and say so, or hold it as
/// not running and say so) is the builder's, with the words HIE writes.
///
/// FAULT (red on main 54b00cb): no notification, the app leaves the front, and
/// 75 s pass with no fix.
/// CONTROLS (green on main, must stay green): the same with the service running
/// (the drought still tells her); and no notification with the app kept in
/// front through a real gap (the drought still tells her).
///
/// What these tests do NOT hold: anything on a device, how a real phone
/// throttles, or what words she is told.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/notification_permission.dart';

import '../support/fake_alert_actuators.dart';

const String _slowDown = '速度を落とし、車間を広げて、前方に注意してください。';
const String _stopLine = '安全にできるときは、安全な場所での停車も選べます。';
const double _v = 15;

var _clockNow = DateTime.utc(2026, 1, 14, 21);

Future<void> _advance(WidgetTester tester, Duration d) async {
  _clockNow = _clockNow.add(d);
  await tester.pump(d);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Position _fix(double northM) => Position(
  latitude: 39.7186 + northM / 111194.93,
  longitude: 140.1024,
  timestamp: _clockNow,
  accuracy: 10,
  hasAccuracy: true,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: _v,
  hasSpeed: true,
  speedAccuracy: 1.5,
  hasSpeedAccuracy: true,
);

/// A clear day where no measured-weather watch fires.
JmaObservation _clearObs() => JmaObservation(
  stationId: '32402',
  stationName: '秋田',
  temperatureCelsius: 8.0,
  humidityPercent: 50,
  windMetersPerSecond: 1.0,
  snowDepthCm: null,
  precipitation10mMm: 0.0,
  visibilityMeters: 20000,
  observedAtJstKey: '20260115060000',
  fetchedAt: _clockNow,
);

/// [canPost] true answers the app's notification read as "can post", so the
/// drive starts with its foreground service; false leaves the channel as the
/// test binding has it, which the app reads as "cannot post".
Future<(FakeAlertActuators, StreamController<Position>)> _bootAndShare(
  WidgetTester tester, {
  required bool canPost,
}) async {
  if (canPost) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NotificationPermission.channel,
      (call) async => call.method == 'read'
          ? <String, dynamic>{
              'granted': true,
              'enabled': true,
              'needsRuntimeRequest': false,
            }
          : true,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NotificationPermission.channel,
        null,
      ),
    );
  }
  final a = FakeAlertActuators();
  final positions = StreamController<Position>();
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    SngnavApp(
      // Not about the consent act.
      locationConsent: true,
      actuators: a,
      locale: const Locale('ja'),
      clock: () => _clockNow,
      jmaFetch: () async => JmaSuccess(_clearObs()),
      positionSource: () => herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        positionStream: () => positions.stream,
      ),
    ),
  );
  await _settle(tester);
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  await _settle(tester);
  return (a, positions);
}

Future<void> _drive(
  WidgetTester tester,
  StreamController<Position> positions,
) async {
  var north = 0.0;
  for (var i = 0; i < 4; i++) {
    if (i > 0) {
      await _advance(tester, const Duration(seconds: 5));
      north += _v * 5;
    }
    positions.add(_fix(north));
    await _settle(tester);
  }
}

Future<void> _leaveFront(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

Future<void> _returnToFront(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

/// [seconds] of silence, one second at a time; returns what was told.
Future<(List<String>, int)> _silence(
  WidgetTester tester,
  FakeAlertActuators a,
  int seconds,
) async {
  final sb = a.spoken.length, hb = a.haptics.length;
  for (var s = 0; s < seconds; s++) {
    await _advance(tester, const Duration(seconds: 1));
  }
  await _settle(tester);
  return (a.spoken.skip(sb).map((x) => x.text).toList(), a.haptics.length - hb);
}

/// The drought's own verdict on her position, as the drive card's position
/// row shows it: exactly 「GPS 途絶（推測航法）」 while dead reckoning, exactly
/// 「現在地 不明」 once lost. Exact matches, because the card's description
/// (key drive-hud-description) names the same words inside a sentence on every
/// screen, which a substring match reads as a verdict.
bool _droughtVerdictShown(WidgetTester tester) =>
    find.text('GPS 途絶（推測航法）', skipOffstage: false).evaluate().isNotEmpty ||
    find.text('現在地 不明', skipOffstage: false).evaluate().isNotEmpty;

void main() {
  testWidgets(
    'FAULT: no foreground service, the app leaves the front, 75 s with no '
    'fix: no GPS-loss caution is told, and none is shown on return',
    (tester) async {
      final (a, positions) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, positions);
      await _leaveFront(tester);
      final (spoken, _) = await _silence(tester, a, 75);
      expect(
        spoken,
        isNot(contains(_slowDown)),
        reason: 'the platform stopped her fixes; the sky did not: $spoken',
      );
      expect(
        spoken,
        isNot(contains(_stopLine)),
        reason: 'a stop invitation for a GPS loss that is not there: $spoken',
      );
      await _returnToFront(tester);
      await _settle(tester);
      expect(
        _droughtVerdictShown(tester),
        isFalse,
        reason: 'on her return the map blames the GPS for the platform',
      );
      unawaited(positions.close());
      await _settle(tester);
    },
  );

  testWidgets(
    'CONTROL: with the foreground service, the same silence while away is '
    'still read as a GPS loss and told',
    (tester) async {
      final (a, positions) = await _bootAndShare(tester, canPost: true);
      await _drive(tester, positions);
      await _leaveFront(tester);
      final (spoken, haptics) = await _silence(tester, a, 75);
      expect(
        spoken.contains(_slowDown) || spoken.contains(_stopLine),
        isTrue,
        reason: 'with the service running, silence is the sky: $spoken',
      );
      expect(haptics, greaterThan(0));
      await _returnToFront(tester);
      unawaited(positions.close());
      await _settle(tester);
    },
  );

  testWidgets(
    'CONTROL: no foreground service but the app stays in front through a '
    'real gap: the drought is still told',
    (tester) async {
      final (a, positions) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, positions);
      final (spoken, haptics) = await _silence(tester, a, 75);
      expect(
        spoken.contains(_slowDown) || spoken.contains(_stopLine),
        isTrue,
        reason: 'in front, the stream lives; silence is the sky: $spoken',
      );
      expect(haptics, greaterThan(0));
      expect(_droughtVerdictShown(tester), isTrue);
      unawaited(positions.close());
      await _settle(tester);
    },
  );
}
