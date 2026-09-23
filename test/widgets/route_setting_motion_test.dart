/// On a phone, route setting closes when the platform measures her moving, and
/// opens again only while a stop measured on a trusted fix is current.
///
/// Why, written before the act (2026-09-14). Ruled: a route may not be set by
/// touch while the car moves, and once motion is measured route setting stays
/// closed until a stop is measured, through a tunnel or a GPS loss. Until this
/// landing the phone read no motion at all: the platform's speed was
/// discarded, so route setting stayed open whatever the car was doing.
///
/// The stop rule is the fail-closed one decided that day (it replaced "zero lies
/// inside the reported accuracy", which read 3.0 ±4.0 m/s as stopped): stopped
/// only when speed and speed accuracy are both reported, both finite and not
/// negative, and their sum is at most 0.5 m/s, on a fix the drive brain took
/// as trusted. Everything else measures nothing, straddles included. The
/// 0.5 m/s limit is provisional; no reading at a real stop on a real phone
/// exists.
///
/// The rules pinned here, as decided and audited that day:
/// * A measured moving reading closes route setting: the agreed words stand
///   alone and no route act is offered. An open act closes, keeping the point
///   she chose. Only measured motion closes an open act.
/// * Motion belongs to the sharing session. With no motion reading in it,
///   route setting is open; ending sharing leaves no motion evidence at all.
/// * Once a reading counts in the session (moving from any sample, even one
///   with no measured accuracy; a stop only on a trusted fix), route setting is
///   open only while a stop is current: not on a speed never reported, a
///   straddling reading, or a stop from a fix the brain did not trust.
/// * A stop is current only while the session's latest trusted reading says
///   stopped, and for no longer than the app's 30 s drought cadence from the
///   stop fix's own time. Samples with no measured accuracy, stream errors and
///   silence never extend it: route setting is not open 45 s after the stop's
///   fix, whatever arrives. A stop fix already older than that when it arrives
///   opens nothing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:routing_engine/routing_engine.dart' as re;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

const _openAct = Key('route-act-open');
const _whenStopped = Key('route-setting-when-stopped');

final _start = DateTime.utc(2026, 1, 14, 21);
var _clockNow = _start;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

/// Advances the app's clock with the test's fake time, in steps no longer than
/// the watchdog's 15 s tick.
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

/// A fix one second after the app's clock, so the drive brain takes it as
/// newer; or at [at].
Position _fix({
  double speed = 0,
  bool hasSpeed = false,
  double speedAccuracy = 0,
  bool hasSpeedAccuracy = false,
  double accuracy = 10,
  bool hasAccuracy = true,
  DateTime? at,
}) {
  if (at == null) _clockNow = _clockNow.add(const Duration(seconds: 1));
  return Position(
    latitude: 39.7186,
    longitude: 140.1024,
    timestamp: at ?? _clockNow,
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
}

Position _moving({bool hasAccuracy = true}) => _fix(
    speed: 25,
    hasSpeed: true,
    speedAccuracy: 0.5,
    hasSpeedAccuracy: true,
    accuracy: hasAccuracy ? 10 : 0,
    hasAccuracy: hasAccuracy);

Position _stopped({double accuracy = 10, DateTime? at}) => _fix(
    hasSpeed: true,
    speedAccuracy: 0.1,
    hasSpeedAccuracy: true,
    accuracy: accuracy,
    at: at);

/// A sample whose horizontal accuracy the platform did not measure.
Position _unmeasured() => _fix(accuracy: 0, hasAccuracy: false);

class _FakeEngine implements re.RoutingEngine {
  @override
  Future<re.RouteResult> calculateRoute(re.RouteRequest request) async =>
      re.RouteResult(
        shape: [request.origin, request.destination],
        maneuvers: const [],
        totalDistanceKm: 12.34,
        totalTimeSeconds: 1500,
        summary: 'fake',
        engineInfo: const re.EngineInfo(name: 'mock'),
      );

  @override
  Future<bool> isAvailable() async => true;

  @override
  re.EngineInfo get info => const re.EngineInfo(name: 'mock');

  @override
  Future<void> dispose() async {}
}

Future<StreamController<Position>> _bootAndShare(WidgetTester tester,
    {re.RoutingEngine Function()? engine}) async {
  final platform = StreamController<Position>.broadcast();
  _clockNow = _start;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
      // Not about the consent act; that is guarded in
      // test/widgets/location_consent_act_and_privacy_surface_test.dart.
      locationConsent: true,

    actuators: FakeAlertActuators(),
    locale: const Locale('ja'),
    clock: () => _clockNow,
    jmaFetch: () async => const JmaFailure('no network in this test'),
    routingEngineFactory: engine,
    positionSource: () => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => platform.stream,
    ),
  ));
  await tester.pump();
  await tester.pump();
  await _share(tester);
  return platform;
}

Future<void> _share(WidgetTester tester) async {
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  await _settle(tester);
}

Future<void> _endSharing(WidgetTester tester) async {
  final stop = find.text('停止');
  await tester.ensureVisible(stop.first);
  await tester.pump();
  await tester.tap(stop.first);
  await _settle(tester);
}

Future<void> _send(
    WidgetTester tester, StreamController<Position> platform, Position p) async {
  platform.add(p);
  await _settle(tester);
}

bool _open(WidgetTester tester) {
  expect(find.byKey(_whenStopped), findsOneWidget,
      reason: 'the agreed words are shown either way');
  return find.byKey(_openAct).evaluate().isNotEmpty;
}

Finder get _actMap =>
    find.descendant(of: find.byType(Dialog), matching: find.byType(AkitaMap));

Future<void> _openTheAct(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_openAct));
  await tester.pump();
  await tester.tap(find.byKey(_openAct));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
      'a trusted fix measured moving closes route setting: the agreed words '
      'stand alone, and no route act is offered', (tester) async {
    final platform = await _bootAndShare(tester);
    await _send(tester, platform, _fix());
    expect(_open(tester), isTrue,
        reason: 'control: a fix with no speed reported measures nothing');
    await _send(tester, platform, _moving());
    expect(_open(tester), isFalse);
    await platform.close();
  });

  testWidgets(
      'an open route act closes when motion is measured, and keeps the point '
      'she chose', (tester) async {
    final platform = await _bootAndShare(tester);
    await _send(tester, platform, _fix());
    await _openTheAct(tester);
    await tester.tapAt(tester.getRect(_actMap).center + const Offset(-60, -20));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
        find.descendant(of: _actMap, matching: find.text('A')), findsOneWidget,
        reason: 'control: start A chosen in the act');

    await _send(tester, platform, _moving());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Dialog), findsNothing,
        reason: 'motion was measured while the act was open');

    await _send(tester, platform, _stopped());
    expect(_open(tester), isTrue, reason: 'control: a current stop reopens');
    await _openTheAct(tester);
    expect(
        find.descendant(of: _actMap, matching: find.text('A')), findsOneWidget,
        reason: 'she resumes where she left off');
    await platform.close();
  });

  testWidgets(
      'an open route act closes only on measured motion: a stop that ages out '
      'closes route setting on the page, not the act she is in',
      (tester) async {
    final platform = await _bootAndShare(tester);
    await _send(tester, platform, _stopped());
    expect(_open(tester), isTrue, reason: 'control: a current stop');
    await _openTheAct(tester);
    expect(find.byType(Dialog), findsOneWidget, reason: 'control: act open');
    await _advance(tester, const Duration(seconds: 60));
    expect(find.byType(Dialog), findsOneWidget,
        reason: 'the stop aged out; nothing measured motion');
    platform.add(_moving());
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Dialog), findsNothing);
    await platform.close();
  });

  testWidgets(
      'once a reading counts, only a current stop on a trusted fix opens route '
      'setting: not a speed never reported, a straddling reading, or a '
      'reported 0.0 with no accuracy; and a trusted straddle ends a stop',
      (tester) async {
    final platform = await _bootAndShare(tester);
    await _send(tester, platform, _moving());
    expect(_open(tester), isFalse, reason: 'moving');

    await _send(tester, platform, _fix());
    expect(_open(tester), isFalse,
        reason: 'a 0.0 the platform did not report is not a stop');
    await _send(
        tester,
        platform,
        _fix(
            speed: 0.3,
            hasSpeed: true,
            speedAccuracy: 0.3,
            hasSpeedAccuracy: true));
    expect(_open(tester), isFalse, reason: '0.3 ±0.3 straddles the limit');
    await _send(tester, platform, _fix(hasSpeed: true));
    expect(_open(tester), isFalse,
        reason: 'a reported 0.0 with no accuracy cannot be bounded');

    await _send(tester, platform, _stopped());
    expect(_open(tester), isTrue, reason: 'a current stop on a trusted fix');
    await _send(
        tester,
        platform,
        _fix(
            speed: 0.3,
            hasSpeed: true,
            speedAccuracy: 0.3,
            hasSpeedAccuracy: true));
    expect(_open(tester), isFalse,
        reason: 'the latest trusted reading no longer says stopped');
    await platform.close();
  });

  testWidgets(
      'motion belongs to the sharing session: ending sharing leaves no motion '
      'evidence, and a new session is open until a reading counts in it',
      (tester) async {
    final platform = await _bootAndShare(tester);
    await _send(tester, platform, _moving());
    expect(_open(tester), isFalse, reason: 'moving');
    await _endSharing(tester);
    expect(_open(tester), isTrue, reason: 'not sharing: no motion evidence');
    await _share(tester);
    await _send(tester, platform, _fix());
    expect(_open(tester), isTrue,
        reason: 'a new session with no motion reading in it');
    await _send(tester, platform, _moving());
    expect(_open(tester), isFalse, reason: 'moving, in the new session');
    await platform.close();
  });

  testWidgets(
      'after moving, a stop read from a fix the drive brain did not trust '
      'opens nothing: a replayed fix, one with accuracy -1, and one with no '
      'measured accuracy', (tester) async {
    final platform = await _bootAndShare(tester);
    await _send(tester, platform, _moving());
    final lastTrusted = _clockNow;
    expect(_open(tester), isFalse, reason: 'moving');

    await _send(tester, platform, _stopped(at: lastTrusted));
    expect(_open(tester), isFalse,
        reason: 'a stop on a fix no newer than the trusted one');
    await _send(tester, platform, _stopped(accuracy: -1));
    expect(_open(tester), isFalse,
        reason: 'a stop on a fix whose accuracy is invalid');
    await _send(tester, platform,
        _fix(hasSpeed: true, speedAccuracy: 0.1, hasSpeedAccuracy: true,
            accuracy: 0, hasAccuracy: false));
    expect(_open(tester), isFalse,
        reason: 'a stop on a sample with no measured accuracy');

    await _send(tester, platform, _stopped());
    expect(_open(tester), isTrue,
        reason: 'control: the same stop on a newer trusted fix opens it');
    await platform.close();
  });

  group('a stop is current for no longer than the drought cadence', () {
    for (final (name, void Function(StreamController<Position>)? every10s)
        in <(String, void Function(StreamController<Position>)?)>[
      ('samples with no measured accuracy every 10 s',
          (p) => p.add(_unmeasured())),
      ('stream errors every 10 s', (p) => p.addError(StateError('hiccup'))),
      ('silence', null),
    ]) {
      testWidgets(
          '$name after a trusted stop: not open 45 s after the stop\'s fix, '
          'or at any later moment in 2 min', (tester) async {
        final platform = await _bootAndShare(tester);
        await _send(tester, platform, _moving());
        await _send(tester, platform, _stopped());
        final stopFixAt = _clockNow;
        expect(_open(tester), isTrue, reason: 'control: a current stop');

        var elapsed = Duration.zero;
        const tick = Duration(seconds: 10);
        while (elapsed < const Duration(minutes: 2)) {
          if (every10s != null) {
            every10s(platform);
            await _settle(tester);
          }
          await _advance(tester, tick);
          elapsed += tick;
          final sinceFix = _clockNow.difference(stopFixAt);
          if (sinceFix >= const Duration(seconds: 45)) {
            expect(_open(tester), isFalse,
                reason: '${sinceFix.inSeconds} s after the stop\'s fix');
          }
        }
        await platform.close();
      });
    }

    testWidgets(
        'a stop fix that is already 40 s old when it arrives makes no stop '
        'current', (tester) async {
      final platform = await _bootAndShare(tester);
      final movingAt = _clockNow;
      await _send(tester, platform, _moving());
      await _advance(tester, const Duration(seconds: 70));
      final stale = movingAt.add(const Duration(seconds: 31));
      await _send(tester, platform, _stopped(at: stale));
      expect(_clockNow.difference(stale).inSeconds, greaterThan(30),
          reason: 'control: the stop fix is older than 30 s on arrival');
      expect(_open(tester), isFalse);
      await _send(tester, platform, _stopped());
      expect(_open(tester), isTrue,
          reason: 'control: a stop fix from now opens it');
      await platform.close();
    });
  });

  testWidgets(
      'a moving reading from a sample with no measured accuracy still counts: '
      'two minutes of silence after it do not open route setting',
      (tester) async {
    final platform = await _bootAndShare(tester);
    await _send(tester, platform, _moving(hasAccuracy: false));
    expect(_open(tester), isFalse, reason: 'moving, the only reading');
    for (var i = 0; i < 8; i++) {
      await _advance(tester, const Duration(seconds: 15));
      expect(_open(tester), isFalse, reason: 'after ${(i + 1) * 15} s');
    }
    await platform.close();
  });

  testWidgets(
      'a route she set while stopped stays shown when motion is measured, as '
      'it is: its distance and its "not snow-aware" line, with no route act, '
      'no reset and no consent change', (tester) async {
    final platform = await _bootAndShare(tester, engine: () => _FakeEngine());
    await _send(tester, platform, _fix());
    await _openTheAct(tester);
    final r = tester.getRect(_actMap);
    await tester.tapAt(r.center + const Offset(-80, -30));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tapAt(r.center + const Offset(80, 30));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const Key('route-act-get-route')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The consent question waits out a 2 s store timeout.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('route-consent-accept')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 3));
    const l = AppL10n(Locale('ja'));
    expect(find.byKey(const Key('route-summary')), findsOneWidget,
        reason: 'control: the route is shown');
    expect(find.text(l.routeReset), findsOneWidget,
        reason: 'control: reset is offered while route setting is open');

    await _send(tester, platform, _moving());
    expect(_open(tester), isFalse, reason: 'moving');
    expect(find.byKey(const Key('route-summary')), findsOneWidget,
        reason: 'the route she set is still shown');
    expect(find.text(l.routeSourceOsrmDemo), findsOneWidget,
        reason: 'and still says what it is not');
    expect(find.text(l.routeReset), findsNothing,
        reason: 'no control that changes the route while moving');
    await platform.close();
  });
}
