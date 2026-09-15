/// Audit vectors for the speed-ring and position-failure rulings (2026-09-14).
///
/// Why, written before the act: the ruling's own tests were shown to fail on
/// bb02b98 and were mutated by their author. An adversarial audit asks the
/// other question: can a landing pass every one of those tests and still break
/// the ruling's own words? Each vector below states one clause of the ruled
/// text (ruled_conditions.txt) that none of those tests pins, in the form a
/// landing must satisfy. Each is run on bb02b98, on the audit's instrument
/// landing, and on one mutation of that landing built to break that clause.
///
/// Audit instruments only: not the fix, and not a re-authoring of the rulings.
/// Read from what the map is told, what the actuators record and the caution
/// panel's words, the way the ruling's own tests read them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import '../support/rung_on_card.dart';

final _start = DateTime.utc(2026, 1, 14, 21);
var _clockNow = _start;

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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

/// Warm, calm, dry: only visibility differs, so no measured-weather watch.
JmaResult _observedNow(int? visibilityMeters) => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: visibilityMeters,
      observedAtJstKey: _jstKey(_clockNow),
      fetchedAt: _clockNow,
    ));

String _panel(WidgetTester tester) {
  // The rung from the caution banner's own headline (2026-09-15). A search of
  // the whole screen for rung words read any text naming a rung as the rung.
  final rung = rungOnCard();
  if (rung != null) return rung.name;
  if (noPositionLineOnCard()) return 'no rung (no position fed yet)';
  return 'UNREADABLE';
}

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  Future<JmaResult> Function()? jma,
}) async {
  final a = FakeAlertActuators();
  _clockNow = _start;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: const Locale('ja'),
    clock: () => _clockNow,
    jmaFetch: jma ?? () async => const JmaFailure('test: no observation'),
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
  await _settle(tester);
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

Position _pos(
  DateTime t, {
  double accuracy = 10,
  bool hasAccuracy = true,
  double speed = 0,
  bool hasSpeed = false,
  double speedAccuracy = 0,
  bool hasSpeedAccuracy = false,
}) =>
    Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: t,
      accuracy: accuracy,
      hasAccuracy: hasAccuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      hasSpeed: hasSpeed,
      speedAccuracy: speedAccuracy,
      hasSpeedAccuracy: hasSpeedAccuracy,
    );

Stream<PositionFix> _failedStart() => herPositionStream(
      isServiceEnabled: () async => throw StateError('no location provider'),
    );

Stream<PositionFix> _granted(StreamController<Position> platform) =>
    herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => platform.stream,
    );

typedef _Told = ({double? ring, bool degraded, bool lost});

_Told _mapIsTold(WidgetTester tester) {
  final m = tester.widget<AkitaMap>(find.byType(AkitaMap));
  return (
    ring: m.herAccuracyMeters,
    degraded: m.positionDegraded,
    lost: m.positionLost
  );
}

void main() {
  // ------------------------------------------- position failure, top rung ----

  testWidgets(
      'V-a landing condition beyond the whiteout: under a measured 300 m, a '
      'failed start keeps the caution that visibility raises for a positioned '
      'driver', (tester) async {
    final platform = StreamController<Position>();
    final ta = await _boot(tester,
        source: () => _granted(platform), jma: () async => _observedNow(300));
    await _tapShare(tester);
    platform.add(_pos(_clockNow));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 1));
    final trustedPanel = _panel(tester);
    expect(trustedPanel, isNot('no rung (no position fed yet)'),
        reason: 'control: a positioned driver under 300 m has a rung');
    expect(ta.haptics, isNotEmpty,
        reason: 'control: 300 m raises a felt caution for a positioned driver');

    final fa = await _boot(tester,
        source: _failedStart, jma: () async => _observedNow(300));
    await _tapShare(tester);
    await _advance(tester, const Duration(seconds: 1));
    expect(_panel(tester), anyOf('heightenedCaution', 'considerStopping'),
        reason: 'the failure took away the rung measured 300 m raises '
            '(positioned driver: $trustedPanel)');
    expect(fa.haptics, isNotEmpty,
        reason: 'the failure took away the felt caution measured 300 m raises');
  });

  testWidgets(
      'V-b a pre-fix stream error that recovers leaves the blackout watchdog '
      'armed: a later 45 s drought still degrades her ring', (tester) async {
    final platform = StreamController<Position>();
    await _boot(tester, source: () => _granted(platform));
    await _tapShare(tester);
    platform.addError(StateError('provider hiccup'));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 2));
    platform.add(_pos(_clockNow));
    await _settle(tester);
    expect(_mapIsTold(tester).degraded, isFalse,
        reason: 'control: the recovered fix reached the map as trusted');
    await _advance(tester, const Duration(seconds: 45));
    expect(_mapIsTold(tester).degraded, isTrue,
        reason: '45 s without a fix after recovery: the map still shows a '
            'trusted ring (${_mapIsTold(tester).ring} m), so the watchdog is '
            'not polling');
    await platform.close();
  });

  testWidgets(
      'V-c landing condition over time: a whiteout measured AFTER the failure '
      '(the 10-min weather refresh) still brings 停車の検討 and the critical '
      'haptic', (tester) async {
    var calls = 0;
    Future<JmaResult> jma() async => ++calls == 1
        ? const JmaFailure('test: no observation yet')
        : _observedNow(80);
    final a = await _boot(tester, source: _failedStart, jma: jma);
    final hapticsAtBoot = a.haptics.length;
    await _tapShare(tester);
    await _advance(tester, const Duration(seconds: 1));
    await _advance(tester, const Duration(minutes: 10, seconds: 15));
    await _settle(tester);
    expect(calls, greaterThanOrEqualTo(2),
        reason: 'control: the 10-min refresh fetched the whiteout');
    expect(_panel(tester), 'considerStopping',
        reason: 'measured 80 m arrived after the failure');
    // Given in this share at any time: on bb02b98 it came at 1 s, from the
    // failure itself, and a rung already at the top does not re-announce.
    expect(a.haptics.skip(hapticsAtBoot).map((h) => '$h'),
        contains('HapticCuePattern.critical'));
  });

  testWidgets(
      'V-d a later share is judged by that share alone: its caution panel does '
      'not show the previous share\'s trusted position (GPS 良好)',
      (tester) async {
    var shares = 0;
    final first = StreamController<Position>();
    Stream<PositionFix> source() =>
        ++shares == 1 ? _granted(first) : _failedStart();
    await _boot(tester, source: source);
    await _tapShare(tester);
    first.add(_pos(_clockNow));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 1));
    expect(find.textContaining('GPS 良好'), findsWidgets,
        reason: 'control: the first share was trusted');
    await _tapStop(tester);
    await _advance(tester, const Duration(minutes: 20));
    await _tapShare(tester);
    expect(shares, 2);
    for (final m in [1, 60]) {
      await _advance(tester, Duration(seconds: m == 1 ? 1 : 59));
      expect(find.textContaining('GPS 良好'), findsNothing,
          reason: 'at $m s the panel still claims the previous share\'s '
              'trusted fix while the map says 現在地不明');
    }
  });

  // ------------------------------------------------------ speed and ring ----

  testWidgets(
      'V-e the honest ring has an upper bound too: 8.3 ±0.3 m/s, not lost and '
      'no larger than accuracy + 8.6 m/s x t at 30 s and 45 s', (tester) async {
    final platform = StreamController<Position>();
    await _boot(tester, source: () => _granted(platform));
    await _tapShare(tester);
    platform.add(_pos(_clockNow,
        speed: 8.3, hasSpeed: true, speedAccuracy: 0.3, hasSpeedAccuracy: true));
    await _settle(tester);
    for (final (s, step) in [(30, 30), (45, 15)]) {
      await _advance(tester, Duration(seconds: step));
      final told = _mapIsTold(tester);
      expect(told.degraded, isTrue, reason: 'control: blackout reached by $s s');
      expect(told.lost, isFalse,
          reason: 'at $s s: lost where 10 + 8.6 x $s = ${10 + 8.6 * s} m is '
              'inside the 500 m horizon');
      expect(told.ring, lessThanOrEqualTo(10 + 8.6 * s + 0.5),
          reason: 'at $s s: the ring overstates the ruled floor');
    }
    await platform.close();
  });

  testWidgets(
      'V-f the vector named in the ruling\'s test and not run there: a '
      'reported 25 m/s with a NaN speed accuracy still sets the floor (speed '
      'alone)', (tester) async {
    final platform = StreamController<Position>();
    await _boot(tester, source: () => _granted(platform));
    await _tapShare(tester);
    platform.add(_pos(_clockNow,
        speed: 25,
        hasSpeed: true,
        speedAccuracy: double.nan,
        hasSpeedAccuracy: true));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 30));
    final told = _mapIsTold(tester);
    expect(told.degraded, isTrue, reason: 'control: blackout reached');
    expect(told.lost || (told.ring ?? 0) >= 10 + 25 * 30, isTrue,
        reason: 'the map is told ${told.ring} m (lost ${told.lost}) where she '
            'may be 760 m away');
    await platform.close();
  });
}
