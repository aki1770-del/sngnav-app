/// During a GPS blackout, her ring must hold every place she can have reached
/// at the speed the platform last measured.
///
/// Why, written before the act. Measured 2026-09-14 on the app's own drive
/// brain: the app hands it no speed (null where the platform's reading could
/// go), so in a blackout the ring grows at the position package's default
/// 2.0 m/s whatever the car is doing. At 25 m/s, 30 s after her last fix, the
/// map is told a ring of 70 m while she may be 775 m from its centre. A ring
/// that small tells her "you are near here" when the app does not know that.
/// That is the dangerous direction: ambiguity must route toward halt, not
/// pass. The same default at a standstill errs the safe way (a ring larger
/// than the truth), and no reading may shrink it below the default.
///
/// The rules this file pins:
/// * A speed the platform reports as measured (`Position.hasSpeed`), finite
///   and not negative, sets the least rate the ring may grow at: that speed,
///   plus the reported speed accuracy when the platform reports one
///   (`Position.hasSpeedAccuracy`).
/// * A speed the platform did not report is never read, whatever the field
///   holds. `0.0` there is a placeholder, not a stopped car. A non-finite or
///   negative reading is treated the same way.
/// * No reading ever makes the ring smaller than speed-unknown makes it. A
///   measured stop leaves it where speed-unknown leaves it.
/// * Knowing her speed must not make the app speak on an ordinary drive. With
///   no visibility reading, the advisor counts the missing reading as a
///   degraded condition, so any known speed above 13.4 m/s adds the reason
///   "Fast for the conditions" and a spoken caution with a haptic (measured
///   2026-09-14). A missing reading is shown, never announced; until the
///   advisor counts only measured conditions, speed does not reach it.
///
/// Read from what the map is told ([AkitaMap]'s inputs) and what the
/// actuators record, not from words, so a change of wording does not break it.
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

/// Horizontal accuracy of every fix here, in metres.
const double _acc = 10;

/// The app's clock, advanced together with the test's fake time. The blackout
/// watchdog reads it, so under a fixed clock no poll could ever happen.
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

Position _fix(
  DateTime t, {
  double speed = 0,
  bool hasSpeed = false,
  double speedAccuracy = 0,
  bool hasSpeedAccuracy = false,
}) =>
    Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: t,
      accuracy: _acc,
      hasAccuracy: true,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      hasSpeed: hasSpeed,
      speedAccuracy: speedAccuracy,
      hasSpeedAccuracy: hasSpeedAccuracy,
    );

/// Boots the app on the real position stream, with the platform seams
/// answering "services on, permission granted", and presses share.
Future<(FakeAlertActuators, StreamController<Position>)> _bootAndShare(
    WidgetTester tester) async {
  final a = FakeAlertActuators();
  final positions = StreamController<Position>();
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: const Locale('ja'),
    clock: () => _clockNow,
    jmaFetch: () async => const JmaFailure('test: no observation'),
    positionSource: () => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => positions.stream,
    ),
  ));
  await tester.pump();
  await tester.pump();
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  await _settle(tester);
  return (a, positions);
}

typedef _Told = ({double? ring, bool degraded, bool lost});

_Told _mapIsTold(WidgetTester tester) {
  final m = tester.widget<AkitaMap>(find.byType(AkitaMap));
  return (
    ring: m.herAccuracyMeters,
    degraded: m.positionDegraded,
    lost: m.positionLost,
  );
}

/// One fix, then a blackout. Returns what the map is told at each [readAt]
/// (seconds after the fix), plus everything spoken and felt by the end.
Future<({List<_Told> told, String spoken, String haptics})> _blackout(
  WidgetTester tester,
  Position Function(DateTime t) fixAt, {
  List<int> readAt = const [30],
}) async {
  final (a, positions) = await _bootAndShare(tester);
  positions.add(fixAt(_clockNow));
  await _settle(tester);
  final atFix = _mapIsTold(tester);
  expect(atFix.degraded, isFalse,
      reason: 'control: the fix reached the map as a trusted position');
  expect(atFix.ring, _acc, reason: 'control: the ring at the fix');

  final told = <_Told>[];
  var elapsed = 0;
  for (final s in readAt) {
    while (elapsed < s) {
      await _advance(tester, const Duration(seconds: 15));
      elapsed += 15;
    }
    told.add(_mapIsTold(tester));
  }
  expect(told.first.degraded, isTrue,
      reason: 'control: the blackout reached the drive brain by '
          '${readAt.first} s (the watchdog polls on a 30 s drought)');
  await positions.close();
  return (
    told: told,
    spoken: [for (final s in a.spoken) '$s'].join(' | '),
    haptics: [for (final h in a.haptics) '$h'].join(' | '),
  );
}

/// The ring rule: a ring the map draws holds [leastRadius]; `lost` draws words
/// and no circle, so it makes no radius claim.
void _expectRingHolds(_Told told, double leastRadius, String why) {
  expect(
    told.lost || (told.ring ?? 0) >= leastRadius,
    isTrue,
    reason: '$why: the map is told a ring of ${told.ring} m '
        '(lost: ${told.lost}) where she may be up to $leastRadius m from '
        'its centre',
  );
}

void main() {
  group('a measured speed sets how fast her ring grows', () {
    testWidgets(
        '25 m/s, accuracy 0.5 m/s reported: 30 s into a blackout no ring '
        'smaller than 775 m', (tester) async {
      final r = await _blackout(
        tester,
        (t) => _fix(t,
            speed: 25, hasSpeed: true, speedAccuracy: 0.5, hasSpeedAccuracy: true),
      );
      _expectRingHolds(r.told.single, _acc + (25 + 0.5) * 30,
          '25 m/s ±0.5, 30 s');
    });

    testWidgets(
        '25 m/s with no accuracy reported: 30 s into a blackout no ring '
        'smaller than 760 m', (tester) async {
      final r = await _blackout(
        tester,
        (t) => _fix(t, speed: 25, hasSpeed: true),
      );
      _expectRingHolds(r.told.single, _acc + 25 * 30, '25 m/s, 30 s');
    });

    testWidgets(
        '8.3 m/s (30 km/h), accuracy 0.3 m/s: at 30 s and at 45 s no ring '
        'smaller than the distance she can have covered', (tester) async {
      final r = await _blackout(
        tester,
        (t) => _fix(t,
            speed: 8.3, hasSpeed: true, speedAccuracy: 0.3, hasSpeedAccuracy: true),
        readAt: const [30, 45],
      );
      _expectRingHolds(r.told[0], _acc + (8.3 + 0.3) * 30, '8.3 m/s, 30 s');
      _expectRingHolds(r.told[1], _acc + (8.3 + 0.3) * 45, '8.3 m/s, 45 s');
    });
  });

  group('a speed that is not a measurement changes nothing', () {
    Future<String> record(WidgetTester tester, Position Function(DateTime) f) async {
      final r = await _blackout(tester, f, readAt: const [30, 75]);
      return '${r.told} spoken=[${r.spoken}] haptics=[${r.haptics}]';
    }

    testWidgets(
        'a speed the platform did not report is never read, whatever the field '
        'holds; neither is a non-finite or negative one', (tester) async {
      final unknown = await record(tester, (t) => _fix(t));
      for (final (name, f) in <(String, Position Function(DateTime))>[
        ('placeholder field 25, not reported', (t) => _fix(t, speed: 25)),
        (
          'placeholder field 25 with an accuracy, not reported',
          (t) => _fix(t, speed: 25, speedAccuracy: 0.5, hasSpeedAccuracy: true)
        ),
        ('reported NaN', (t) => _fix(t, speed: double.nan, hasSpeed: true)),
        ('reported infinity',
            (t) => _fix(t, speed: double.infinity, hasSpeed: true)),
        ('reported -1', (t) => _fix(t, speed: -1, hasSpeed: true)),
        // Named for what it runs. Until 2026-09-14 this case was named
        // 'reported 25 with a NaN accuracy' while it ran a NaN speed, so the
        // named case never ran. A reported 25 with an unusable accuracy is a
        // measurement (a floor of 25, the speed alone) and does not belong in
        // this group.
        (
          'reported NaN with a NaN accuracy',
          (t) => _fix(t,
              speed: double.nan,
              hasSpeed: true,
              speedAccuracy: double.nan,
              hasSpeedAccuracy: true)
        ),
      ]) {
        expect(await record(tester, f), unknown, reason: name);
      }
    });

    testWidgets(
        'a measured stop never shrinks the ring below speed-unknown, and '
        'raises nothing', (tester) async {
      final unknown = await _blackout(tester, (t) => _fix(t),
          readAt: const [30, 75]);
      final stopped = await _blackout(
        tester,
        (t) => _fix(t,
            speed: 0, hasSpeed: true, speedAccuracy: 0.1, hasSpeedAccuracy: true),
        readAt: const [30, 75],
      );
      for (var i = 0; i < 2; i++) {
        expect(stopped.told[i].ring ?? double.infinity,
            greaterThanOrEqualTo(unknown.told[i].ring ?? double.infinity),
            reason: 'read ${i + 1}: a stop shrank the ring');
        expect(stopped.told[i].lost, unknown.told[i].lost);
      }
      expect(stopped.spoken, unknown.spoken);
      expect(stopped.haptics, unknown.haptics);
    });
  });

  group('knowing her speed does not make an ordinary drive speak', () {
    Future<({String spoken, String haptics, bool fastReason})> drive(
        WidgetTester tester, Position Function(DateTime) fixAt) async {
      final (a, positions) = await _bootAndShare(tester);
      for (var s = 0; s <= 10; s++) {
        positions.add(fixAt(_clockNow));
        await _settle(tester);
        await _advance(tester, const Duration(seconds: 1));
      }
      final fastReason = find
          .textContaining(RegExp('悪条件での速度超過ぎみ|Fast for the conditions'))
          .evaluate()
          .isNotEmpty;
      await positions.close();
      return (
        spoken: [for (final s in a.spoken) '$s'].join(' | '),
        haptics: [for (final h in a.haptics) '$h'].join(' | '),
        fastReason: fastReason,
      );
    }

    testWidgets(
        'trusted fixes at a measured 25 m/s with no visibility reading: '
        'nothing spoken or felt beyond a speed-unknown drive, and no '
        '"Fast for the conditions"', (tester) async {
      final unknown = await drive(tester, (t) => _fix(t));
      final fast = await drive(
        tester,
        (t) => _fix(t,
            speed: 25, hasSpeed: true, speedAccuracy: 0.5, hasSpeedAccuracy: true),
      );
      expect(fast.spoken, unknown.spoken);
      expect(fast.haptics, unknown.haptics);
      expect(fast.fastReason, isFalse,
          reason: 'the only degraded condition is a missing reading');
    });
  });
}
