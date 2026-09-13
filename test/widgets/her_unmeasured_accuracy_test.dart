/// A position accuracy the platform did not measure is never drawn, trusted or
/// anchored as if it had been.
///
/// Why, written before the act. geolocator's `Position` carries `accuracy` and
/// `hasAccuracy`. Its own documentation says that when the flag is false the
/// accuracy "carries no measurement": `0.0` there "is a placeholder, not zero
/// metres of error" (geolocator_platform_interface 4.3.0, position.dart:112-117).
/// On Android the value is omitted when the platform has none
/// (geolocator_android 4.6.2, LocationMapper.java:25). geolocator_web 4.1.4 and
/// geolocator_linux 0.2.x never set the flag at all. The app reads `accuracy`
/// without the flag (her_position.dart:249). A small ring says "I am sure"
/// (her_position.dart:4-6), and nothing measured that.
///
/// What must be true, for a sample whose accuracy is not usable (not flagged as
/// measured, not finite, or negative):
/// * It is never drawn as a confident position, with or without a ring, and the
///   line under the map states no radius for it.
/// * It is never the anchor. After a trusted fix, it neither moves her mark nor
///   restarts her blackout ring from itself.
/// * On its own it adds nothing she hears or feels. With no measured condition
///   raising caution, she is given what a driver who never shared is given.
///   This pin is green today. It goes red if the rule lands before a position
///   failure ahead of the first trusted fix stops raising an alarm by itself,
///   so the rule lands together with that change or after it.
/// * It never takes away a caution a measured condition raises.
///
/// Read from what the map is told ([AkitaMap]'s inputs), whether the line under
/// the map states a radius, and what the actuators record. No sample here
/// reports a speed, so these tests hold whether or not the app reads platform
/// speed.
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

const double _lat = 39.7186;
const double _lon = 140.1024;

/// Horizontal accuracy of every measured fix here, in metres.
const double _acc = 10;

final _start = DateTime.utc(2026, 1, 14, 21);
var _clockNow = _start;

/// Advances the app's clock with the test's fake time, in steps no longer than
/// the watchdog's 15 s tick, so every tick sees the clock move. [feed] runs at
/// the start of every step.
Future<void> _advance(
  WidgetTester tester,
  Duration d, {
  void Function()? feed,
}) async {
  var left = d;
  while (left > Duration.zero) {
    feed?.call();
    await _settle(tester);
    final step = left > const Duration(seconds: 15)
        ? const Duration(seconds: 15)
        : left;
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

Position _sample(
  DateTime t, {
  double accuracy = _acc,
  bool hasAccuracy = true,
  double latitude = _lat,
}) => Position(
  latitude: latitude,
  longitude: _lon,
  timestamp: t,
  accuracy: accuracy,
  hasAccuracy: hasAccuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Position _unmeasured(DateTime t, {double latitude = _lat}) =>
    _sample(t, accuracy: 0, hasAccuracy: false, latitude: latitude);

/// A JMA observation read at boot. Warm and calm, so no measured-weather watch
/// fires: only visibility differs between environments.
JmaResult _observed(int visibilityMeters) => JmaSuccess(
  JmaObservation(
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
  ),
);

/// Boots the app. With [platform], sharing reads that platform stream through
/// the app's own position stream, with the platform answering "services on,
/// permission granted".
Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  StreamController<Position>? platform,
  JmaResult? weather,
}) async {
  final a = FakeAlertActuators();
  _clockNow = _start;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    SngnavApp(
      actuators: a,
      locale: const Locale('ja'),
      clock: () => _clockNow,
      jmaFetch: () async => weather ?? const JmaFailure('test: no observation'),
      positionSource: platform == null
          ? null
          : () => herPositionStream(
              isServiceEnabled: () async => true,
              checkPermission: () async => LocationPermission.whileInUse,
              positionStream: () => platform.stream,
            ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _share(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await _settle(tester);
  expect(
    find.byKey(const Key('share-location-button')),
    findsNothing,
    reason: 'control: sharing started',
  );
}

typedef _Told = ({double? ring, bool degraded, bool lost, double? lat});

_Told _mapIsTold(WidgetTester tester) {
  final m = tester.widget<AkitaMap>(find.byType(AkitaMap));
  return (
    ring: m.herAccuracyMeters,
    degraded: m.positionDegraded,
    lost: m.positionLost,
    lat: m.herPosition?.latitude,
  );
}

/// The solid "you are here" mark, with or without a ring: a claim of a position
/// the app is sure of. The not-confident mark is the hollow ring (degraded) or
/// the words (lost).
bool _confidentMark(_Told t) => t.lat != null && !t.degraded && !t.lost;

/// The line under the map in its "you are here · ±N m" form. The dead-reckoning
/// line also carries a ±, for the anchor's measured radius; it is not matched.
bool _lineStatesARadius() => find
    .textContaining(RegExp(r'(現在地|You are here) · ±'))
    .evaluate()
    .isNotEmpty;

String _panel() {
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

typedef _Felt = ({String spoken, String haptics});

_Felt _felt(FakeAlertActuators a) => (
  spoken: [for (final s in a.spoken) '$s'].join(' | '),
  haptics: [for (final h in a.haptics) '$h'].join(' | '),
);

void main() {
  group('a sample whose accuracy was not measured is not drawn as measured', () {
    for (final (name, Position Function(DateTime) sampleAt)
        in <(String, Position Function(DateTime))>[
          (
            'not flagged, holding the platform placeholder 0.0 (what Android '
                'sends when it has no accuracy)',
            (t) => _unmeasured(t),
          ),
          (
            'not flagged, holding a value (the shape geolocator_web 4.1.4 and '
                'geolocator_linux 0.2.x deliver): the flag rules, not the value',
            (t) => _sample(t, accuracy: 12, hasAccuracy: false),
          ),
        ]) {
      testWidgets(name, (tester) async {
        final platform = StreamController<Position>();
        await _boot(tester, platform: platform);
        await _share(tester);
        for (var i = 1; i <= 3; i++) {
          platform.add(sampleAt(_clockNow));
          await _settle(tester);
          final told = _mapIsTold(tester);
          expect(
            (
              mapToldAConfidentMark: _confidentMark(told),
              mapToldARing: told.ring != null,
              lineStatesARadius: _lineStatesARadius(),
            ),
            (
              mapToldAConfidentMark: false,
              mapToldARing: false,
              lineStatesARadius: false,
            ),
            reason:
                'sample $i, with no measured fix in this share: the map is '
                'told $told',
          );
          await _advance(tester, const Duration(seconds: 1));
        }
      });
    }

    testWidgets(
      'pins: a flagged accuracy that is not finite, or is negative, is not '
      'drawn as measured either',
      (tester) async {
        for (final (name, double accuracy) in <(String, double)>[
          ('NaN', double.nan),
          ('-1', -1),
        ]) {
          final platform = StreamController<Position>();
          await _boot(tester, platform: platform);
          await _share(tester);
          platform.add(_sample(_clockNow, accuracy: accuracy));
          await _settle(tester);
          final told = _mapIsTold(tester);
          expect(
            (
              mapToldAConfidentMark: _confidentMark(told),
              lineStatesARadius: _lineStatesARadius(),
            ),
            (mapToldAConfidentMark: false, lineStatesARadius: false),
            reason: 'flagged $name: the map is told $told',
          );
        }
      },
    );
  });

  testWidgets(
    'after a trusted fix, a sample with no measured accuracy neither moves '
    'her mark nor restarts her blackout ring from itself, and invents no '
    'radius beyond the fix\'s own growth',
    (tester) async {
      final platform = StreamController<Position>();
      final a = await _boot(tester, platform: platform);
      await _share(tester);

      final atFix = _clockNow;
      platform.add(_sample(atFix));
      await _settle(tester);
      expect(
        _mapIsTold(tester),
        (ring: _acc, degraded: false, lost: false, lat: _lat),
        reason: 'control: a measured 10 m fix is drawn as measured',
      );

      await _advance(tester, const Duration(seconds: 10));
      const sampleLat = _lat + 0.001; // about 111 m north of the fix
      platform.add(_unmeasured(_clockNow, latitude: sampleLat));
      await _settle(tester);
      final atSample = _mapIsTold(tester);

      // Silence follows. The watchdog polls once 30 s have passed without an
      // event, so by 40 s after the sample the drive brain has polled at least
      // 30 s after it, 40 s after the fix. From the fix, a ring at that poll is
      // at least 10 m + 2.0 m/s x 40 s. From the sample (0 m) it could be 70 m.
      await _advance(tester, const Duration(seconds: 40));
      final later = _mapIsTold(tester);
      final leastRing = _acc + 2.0 * 40;
      // No poll can be later than now, so no honest ring from the fix exceeds
      // its accuracy plus 2.0 m/s for every second since the fix.
      final mostRing =
          _acc + 2.0 * _clockNow.difference(atFix).inMicroseconds / 1e6;
      final felt = _felt(a);

      expect(
        (
          markStaysOnTheFix: atSample.lat == _lat && later.lat == _lat,
          notTrustedFromTheSample: atSample.degraded || atSample.lost,
          ringHoldsFromTheFix: later.lost || (later.ring ?? 0) >= leastRing,
          ringInventsNothing: later.lost || (later.ring ?? 0) <= mostRing,
          noTopRungYet:
              _panel() != 'considerStopping' &&
              !felt.haptics.contains('critical'),
        ),
        (
          markStaysOnTheFix: true,
          notTrustedFromTheSample: true,
          ringHoldsFromTheFix: true,
          ringInventsNothing: true,
          noTopRungYet: true,
        ),
        reason:
            'at the sample the map is told $atSample; 40 s later $later, '
            'with ${felt.haptics} felt and the panel at ${_panel()}. The fix '
            'is at $_lat, the sample at $sampleLat; a ring that is not lost '
            'must be from $leastRing m to $mostRing m, and 50 s after a 10 m '
            'fix is not the top rung',
      );
      await platform.close();
    },
  );

  for (final (name, Position Function(DateTime) unusableAt)
      in <(String, Position Function(DateTime))>[
        ('not flagged (0.0)', (t) => _unmeasured(t)),
        (
          'flagged -1 (the shape iOS writes when it has no fix)',
          (t) => _sample(t, accuracy: -1),
        ),
      ]) {
    testWidgets(
      'samples whose accuracy is not usable, $name, add nothing she hears or '
      'feels on their own: equal to a driver who never shared, at 1 s, 61 s '
      'and 10 min',
      (tester) async {
        const marks = [
          Duration(seconds: 1),
          Duration(seconds: 61),
          Duration(minutes: 10),
        ];

        Future<List<_Felt>> readAt(
          FakeAlertActuators a,
          void Function()? feed,
        ) async {
          final out = <_Felt>[];
          var at = Duration.zero;
          for (final m in marks) {
            await _advance(tester, m - at, feed: feed);
            at = m;
            out.add(_felt(a));
          }
          return out;
        }

        final control = await readAt(await _boot(tester), null);

        final platform = StreamController<Position>();
        final a = await _boot(tester, platform: platform);
        await _share(tester);
        // A sample every 15 s: a live feed, never a drought.
        final given = await readAt(
          a,
          () => platform.add(unusableAt(_clockNow)),
        );
        for (var i = 0; i < marks.length; i++) {
          expect(given[i], control[i], reason: 'at ${marks[i]}');
        }
      },
    );
  }

  testWidgets(
    'in a measured 80 m whiteout, samples with no measured accuracy still get '
    '停車の検討 and the critical haptic, as measured fixes do',
    (tester) async {
      final whiteout = _observed(80);

      Future<({String panel, String haptics})> drive(
        Position Function(DateTime) sampleAt,
      ) async {
        final platform = StreamController<Position>();
        final a = await _boot(tester, platform: platform, weather: whiteout);
        await _share(tester);
        await _advance(
          tester,
          const Duration(seconds: 1),
          feed: () => platform.add(sampleAt(_clockNow)),
        );
        return (panel: _panel(), haptics: _felt(a).haptics);
      }

      final measured = await drive((t) => _sample(t));
      expect(
        measured.panel,
        'considerStopping',
        reason: 'control: measured fixes in the same whiteout',
      );
      expect(
        measured.haptics,
        contains('critical'),
        reason: 'control: measured fixes in the same whiteout',
      );

      final unmeasured = await drive((t) => _unmeasured(t));
      expect(unmeasured.panel, 'considerStopping');
      expect(unmeasured.haptics, contains('critical'));
    },
  );
}
