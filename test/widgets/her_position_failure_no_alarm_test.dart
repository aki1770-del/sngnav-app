/// Before her first trusted fix of a share, a position failure raises no
/// alarm by itself.
///
/// Why, written before the act. Measured 2026-09-14 with recording actuators:
/// with no trusted fix, the app's drive brain rates "no position at all" its
/// top concern. A failed start (a platform call throwing) or location services
/// off, as the first event of a share, got the critical haptic, the line
/// inviting her to stop and 停車の検討, and got them identically under a
/// measured clear 1,500 m and a measured 80 m whiteout: the alarm said nothing
/// about the road. A driver who never pressed share is given nothing, in the
/// same places. The map already tells her in words that the app does not know
/// where she is, and stopping does not bring a position back. An alarm for a
/// cause the app has not measured spends her attention; the machine catching
/// its own failure is the words on the map, not a buzz asking her to act.
///
/// What must be true:
/// * With no measured condition raising caution (no visibility reading or a
///   clear one, no advisory, no measured-weather watch firing), what she is
///   given after such a failure equals what a driver who never shared is
///   given, at 1 s, 61 s and 10 minutes: the watchdog must not raise it later.
/// * A first position that never arrives is the same case: nothing alarms at
///   61 s, 76 s or 10 minutes, whatever the map's words say by then.
/// * A later share whose first event fails is judged by that share alone: the
///   previous drive's position does not turn the failure into an alarm.
/// * The failure never takes away a caution a measured condition raises. In a
///   measured whiteout she is still given the top rung, as a driver with a
///   trusted position is there.
///
/// Not covered: a failure after a trusted fix in the same share. That is the
/// loss of a position she was relying on, and its alarm is unchanged.
///
/// "What she is given" is read the way `her_location_off_no_alarm_test.dart`
/// reads it: every spoken line, every haptic, and the caution panel's rung.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

typedef _Given = ({String spoken, String haptics, String panel});

String _panel(WidgetTester tester) {
  bool has(List<String> texts) =>
      texts.any((t) => find.textContaining(t).evaluate().isNotEmpty);
  if (has(['停車の検討', 'Consider stopping'])) return 'considerStopping';
  if (has(['注意して走行', 'Heightened caution'])) return 'heightenedCaution';
  if (has(['特段の注意なし', 'No elevated caution'])) return 'continueDriving';
  if (has(['（まだ現在地が届いていません）', '(no position fed yet)'])) {
    return 'no rung (no position fed yet)';
  }
  return 'UNREADABLE';
}

_Given _given(WidgetTester tester, FakeAlertActuators a) => (
      spoken: [for (final s in a.spoken) '$s'].join(' | '),
      haptics: [for (final h in a.haptics) '$h'].join(' | '),
      panel: _panel(tester),
    );

final _start = DateTime.utc(2026, 1, 14, 21);
var _clockNow = _start;

/// Advances the app's clock with the test's fake time, in steps no longer
/// than the watchdog's 15 s tick, so every tick sees the clock move.
Future<void> _advance(WidgetTester tester, Duration d) async {
  var left = d;
  while (left > Duration.zero) {
    final step =
        left > const Duration(seconds: 15) ? const Duration(seconds: 15) : left;
    _clockNow = _clockNow.add(step);
    await tester.pump(step);
    left -= step;
  }
}

/// A JMA observation read at boot. Warm and calm, so no measured-weather watch
/// fires: only visibility differs between environments.
JmaResult _observed(int visibilityMeters) => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: visibilityMeters,
      observedAtJstKey: '20260115060000',
      fetchedAt: _start,
    ));

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  JmaResult? weather,
}) async {
  final a = FakeAlertActuators();
  _clockNow = _start;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: const Locale('ja'),
    clock: () => _clockNow,
    jmaFetch: () async => weather ?? const JmaFailure('test: no observation'),
    positionSource: source,
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _tapShare(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  expect(find.byKey(const Key('share-location-button')), findsNothing,
      reason: 'control: sharing started');
}

Future<void> _tapStop(WidgetTester tester) async {
  final s = find.text('停止');
  await tester.ensureVisible(s.first);
  await tester.pump();
  await tester.tap(s.first);
  await tester.pump();
}

Position _position(DateTime t) => Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: t,
      accuracy: 10,
      hasAccuracy: true,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// A share whose platform start throws: the stream's "GPS init error".
Stream<PositionFix> _failedStart() => herPositionStream(
      isServiceEnabled: () async => throw StateError('no location provider'),
    );

/// A share with location services off.
Stream<PositionFix> _servicesOff() =>
    herPositionStream(isServiceEnabled: () async => false);

/// A share that is granted and subscribed, and never gets an event.
Stream<PositionFix> _neverArrives() => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => StreamController<Position>().stream,
    );

/// A share that gets one trusted fix at the app's clock and stays open (a
/// closed platform stream would add its own "stream ended" event).
Stream<PositionFix> _oneFix() {
  final platform = StreamController<Position>()..add(_position(_clockNow));
  return herPositionStream(
    isServiceEnabled: () async => true,
    checkPermission: () async => LocationPermission.whileInUse,
    positionStream: () => platform.stream,
  );
}

/// Reads what she is given after each of [marks], counted from now.
Future<List<_Given>> _readAt(
    WidgetTester tester, FakeAlertActuators a, List<Duration> marks) async {
  final out = <_Given>[];
  var at = Duration.zero;
  for (final m in marks) {
    await _advance(tester, m - at);
    at = m;
    out.add(_given(tester, a));
  }
  return out;
}

Future<List<_Given>> _neverShared(WidgetTester tester, List<Duration> marks,
        {JmaResult? weather}) async =>
    _readAt(tester, await _boot(tester, weather: weather), marks);

Future<List<_Given>> _sharedOn(WidgetTester tester,
    Stream<PositionFix> Function() source, List<Duration> marks,
    {JmaResult? weather}) async {
  final a = await _boot(tester, source: source, weather: weather);
  await _tapShare(tester);
  return _readAt(tester, a, marks);
}

void main() {
  const s1 = Duration(seconds: 1);
  const s61 = Duration(seconds: 61);
  const s76 = Duration(seconds: 76);
  const min10 = Duration(minutes: 10);

  group('no measured condition: equal to the never-shared driver', () {
    for (final (name, source) in <(String, Stream<PositionFix> Function())>[
      ('a failed start', _failedStart),
      ('location services off', _servicesOff),
    ]) {
      testWidgets('$name, no visibility reading, at 1 s, 61 s and 10 min',
          (tester) async {
        final marks = [s1, s61, min10];
        final control = await _neverShared(tester, marks);
        expect(control.first.panel, 'no rung (no position fed yet)',
            reason: 'control: the never-shared driver has no rung');
        final given = await _sharedOn(tester, source, marks);
        for (var i = 0; i < marks.length; i++) {
          expect(given[i], control[i], reason: 'at ${marks[i]}');
        }
      });
    }

    testWidgets('a failed start under a measured clear 1,500 m, at 1 s and 61 s',
        (tester) async {
      final marks = [s1, s61];
      final clear = _observed(1500);
      final control = await _neverShared(tester, marks, weather: clear);
      final given =
          await _sharedOn(tester, _failedStart, marks, weather: clear);
      for (var i = 0; i < marks.length; i++) {
        expect(given[i], control[i], reason: 'at ${marks[i]}');
      }
    });

    testWidgets(
        'a first position that never arrives: nothing alarms at 61 s, 76 s or '
        '10 minutes', (tester) async {
      final marks = [s61, s76, min10];
      final control = await _neverShared(tester, marks);
      final given = await _sharedOn(tester, _neverArrives, marks);
      for (var i = 0; i < marks.length; i++) {
        expect(given[i], control[i], reason: 'at ${marks[i]}');
      }
    });
  });

  testWidgets(
      'a later share whose first event fails is judged by that share alone, '
      'at 1 s and 61 s', (tester) async {
    var shares = 0;
    Stream<PositionFix> firstAFixThenAFailedStart() =>
        ++shares == 1 ? _oneFix() : _failedStart();

    final a = await _boot(tester, source: firstAFixThenAFailedStart);
    await _tapShare(tester);
    await _advance(tester, s1);
    expect(_panel(tester), isNot('no rung (no position fed yet)'),
        reason: 'control: the first drive\'s fix reached the drive brain');
    await _tapStop(tester);
    await _advance(tester, const Duration(minutes: 20));

    final spokenBefore = a.spoken.length;
    final hapticsBefore = a.haptics.length;
    await _tapShare(tester);
    expect(shares, 2, reason: 'control: the second share failed to start');
    for (final m in [s1, s61]) {
      await _advance(tester, m == s1 ? s1 : s61 - s1);
      expect(a.spoken.skip(spokenBefore).map((s) => '$s').toList(), isEmpty,
          reason: 'spoken after the second share, at $m');
      expect(a.haptics.skip(hapticsBefore).map((h) => '$h').toList(), isEmpty,
          reason: 'felt after the second share, at $m');
      expect(_panel(tester), isNot('considerStopping'), reason: 'at $m');
    }
  });

  testWidgets(
      'a measured 80 m whiteout keeps the top rung for a failed start, as it '
      'gives a driver with a trusted position there', (tester) async {
    final whiteout = _observed(80);
    final trusted = await _sharedOn(tester, _oneFix, [s1], weather: whiteout);
    expect(trusted.single.panel, 'considerStopping',
        reason: 'control: a driver with a trusted position, same whiteout');
    final failed =
        await _sharedOn(tester, _failedStart, [s1], weather: whiteout);
    expect(failed.single.panel, 'considerStopping');
    expect(failed.single.haptics, contains('critical'));
  });
}
