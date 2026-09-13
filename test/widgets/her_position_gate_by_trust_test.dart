/// Before a share's first trusted fix, what reaches the drive brain is decided
/// by whether the event would be that fix, not by what kind of event it is.
///
/// Why, written before the act (2026-09-14). Ruled that day: before her first
/// trusted fix of a share, a position failure does not reach the caution rung
/// by itself, and a measured condition keeps its caution. The ruling's own
/// tests use failures that arrive as unavailabilities. But a sample the drive
/// brain refuses arrives as a position: iOS writes an invalid horizontal
/// accuracy of -1 on the fix itself, and a platform can re-deliver a fix no
/// newer than the previous drive's anchor. Given to the brain, both leave her
/// with no trusted position and the brain rates that its top concern. Keyed on
/// the event being an unavailability, the gate never sees them.
///
/// Also pinned here, because holding an event back from the brain leaves the
/// brain holding an earlier drive: nothing narrates a maneuver as trusted from
/// a position that is not this share's.
///
/// And one choice this landing makes where the ruling is open: under a
/// measured 300 m a failed start is given to the brain, so it reaches the top
/// rung, where a positioned driver there gets heightened caution. Recorded so
/// a later ruling that reads the text the other way changes a named test.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart' as re;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

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

typedef _Given = ({String spoken, String haptics, String panel});

String _panel(WidgetTester tester) {
  bool has(List<String> texts) =>
      texts.any((t) => find.textContaining(t).evaluate().isNotEmpty);
  if (has(['停車の検討', 'Consider stopping'])) return 'considerStopping';
  if (has(['注意して走行', 'Heightened caution'])) return 'heightenedCaution';
  if (has(['特段の注意なし', 'No elevated caution'])) return 'continueDriving';
  if (find
      .text(const AppL10n(Locale('ja')).driveHudNoPositionFed)
      .evaluate()
      .isNotEmpty) {
    return 'no rung';
  }
  return 'UNREADABLE';
}

_Given _given(WidgetTester tester, FakeAlertActuators a) => (
      spoken: [for (final s in a.spoken) '$s'].join(' | '),
      haptics: [for (final h in a.haptics) '$h'].join(' | '),
      panel: _panel(tester),
    );

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

class _OneTurnEngine implements re.RoutingEngine {
  @override
  Future<re.RouteResult> calculateRoute(re.RouteRequest request) async =>
      re.RouteResult(
        shape: [request.origin, request.destination],
        maneuvers: const [
          re.RouteManeuver(
            index: 0,
            instruction: 'Depart',
            type: 'depart',
            lengthKm: 0.3,
            timeSeconds: 30,
            position: LatLng(39.70, 140.09),
          ),
          re.RouteManeuver(
            index: 1,
            instruction: 'Turn right',
            type: 'right',
            lengthKm: 1.2,
            timeSeconds: 90,
            position: LatLng(39.71, 140.10),
          ),
        ],
        totalDistanceKm: 1.5,
        totalTimeSeconds: 120,
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

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  JmaResult? weather,
  re.RoutingEngine Function()? engine,
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
    routingEngineFactory: engine,
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

Position _position(DateTime t, {double accuracy = 10}) => Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: t,
      accuracy: accuracy,
      hasAccuracy: true,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Stream<PositionFix> _granted(StreamController<Position> platform) =>
    herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => platform.stream,
    );

Stream<PositionFix> _failedStart() => herPositionStream(
      isServiceEnabled: () async => throw StateError('no location provider'),
    );

String? _line(WidgetTester tester) {
  final f = find.byKey(const Key('her-status-line'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

Future<void> _fetchRouteThroughAct(WidgetTester tester) async {
  final open = find.byKey(const Key('route-act-open'));
  await tester.ensureVisible(open);
  await tester.pump();
  await tester.tap(open);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final actMap =
      find.descendant(of: find.byType(Dialog), matching: find.byType(AkitaMap));
  final r = tester.getRect(actMap);
  await tester.tapAt(r.center + const Offset(-80, -30));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tapAt(r.center + const Offset(80, 30));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.byKey(const Key('route-act-get-route')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const Key('route-consent-accept')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
}

const _speakTier = 'SPEAK — GPS trusted';

void main() {
  testWidgets(
      'a first fix the drive brain would refuse (accuracy -1) raises nothing '
      'by itself: equal to the never-shared driver at 1 s and 61 s, and the '
      'map and the line claim no position', (tester) async {
    final neverShared = await _boot(tester);
    await _advance(tester, const Duration(seconds: 1));
    final control1 = _given(tester, neverShared);
    await _advance(tester, const Duration(seconds: 60));
    final control61 = _given(tester, neverShared);
    expect(control1.panel, 'no rung', reason: 'control: never shared');

    final platform = StreamController<Position>();
    final a = await _boot(tester, source: () => _granted(platform));
    await _tapShare(tester);
    platform.add(_position(_clockNow, accuracy: -1));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 1));
    expect(_given(tester, a), control1, reason: 'at 1 s');
    final map = tester.widget<AkitaMap>(find.byType(AkitaMap));
    expect(map.herPosition, isNull, reason: 'no mark from a refused sample');
    expect(find.byKey(const ValueKey('her-position-unknown-label')),
        findsOneWidget);
    expect(_line(tester), isNot(contains('±')),
        reason: 'the line states no radius for it');
    await _advance(tester, const Duration(seconds: 60));
    expect(_given(tester, a), control61, reason: 'at 61 s');
    await platform.close();
  });

  testWidgets(
      'a later share whose first fix is no newer than the previous drive\'s '
      'anchor raises nothing by itself, at 1 s and 61 s', (tester) async {
    final first = _clockNow;
    final positions = StreamController<PositionFix>.broadcast();
    final a = await _boot(tester, source: () => positions.stream);
    await _tapShare(tester);
    positions.add(PositionAvailable(
        latitude: 39.7195, longitude: 140.1180, accuracyMeters: 15,
        timestamp: first));
    await _settle(tester);
    expect(find.textContaining('GPS 良好'), findsWidgets,
        reason: 'control: the first drive was trusted');
    await _tapStop(tester);
    await _advance(tester, const Duration(minutes: 20));

    final spokenBefore = a.spoken.length;
    final hapticsBefore = a.haptics.length;
    await _tapShare(tester);
    positions.add(PositionAvailable(
        latitude: 39.7300, longitude: 140.1000, accuracyMeters: 15,
        timestamp: first));
    await _settle(tester);
    for (final (at, step) in [(1, 1), (61, 60)]) {
      await _advance(tester, Duration(seconds: step));
      expect(a.spoken.skip(spokenBefore).map((s) => '$s'), isEmpty,
          reason: 'spoken after the second share, at $at s');
      expect(a.haptics.skip(hapticsBefore).map((h) => '$h'), isEmpty,
          reason: 'felt after the second share, at $at s');
      expect(_panel(tester), 'no rung', reason: 'at $at s');
    }
    await positions.close();
  });

  group('a maneuver is never narrated as trusted from an earlier drive', () {
    /// A route with one turn, then the first share. [sources] are the position
    /// streams of the first and the second share, in order.
    Future<void> routeThenOneDrive(
        WidgetTester tester, List<Stream<PositionFix> Function()> sources) async {
      var shares = 0;
      await _boot(tester,
          source: () => sources[shares++](),
          engine: () => _OneTurnEngine());
      await _fetchRouteThroughAct(tester);
      expect(find.byKey(const Key('maneuver-narration-banner')), findsOneWidget,
          reason: 'control: the route has a next maneuver');
      await _tapShare(tester);
    }

    testWidgets(
        're-shared, before any event of the new share: not narrated as trusted',
        (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await routeThenOneDrive(
          tester, [() => positions.stream, () => positions.stream]);
      positions.add(PositionAvailable(
          latitude: 39.7186, longitude: 140.1024, accuracyMeters: 10,
          timestamp: _clockNow));
      await _settle(tester);
      expect(find.textContaining(_speakTier), findsOneWidget,
          reason: 'control: a trusted fix of this share narrates as trusted');
      await _tapStop(tester);
      await _advance(tester, const Duration(seconds: 5));
      await _tapShare(tester);
      expect(find.textContaining(_speakTier), findsNothing);
      await positions.close();
    });

    testWidgets(
        're-shared, and the new share\'s start fails: not narrated as trusted',
        (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await routeThenOneDrive(tester, [() => positions.stream, _failedStart]);
      positions.add(PositionAvailable(
          latitude: 39.7186, longitude: 140.1024, accuracyMeters: 10,
          timestamp: _clockNow));
      await _settle(tester);
      expect(find.textContaining(_speakTier), findsOneWidget,
          reason: 'control: a trusted fix of this share narrates as trusted');
      await _tapStop(tester);
      await _advance(tester, const Duration(seconds: 5));
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 1));
      expect(find.textContaining(_speakTier), findsNothing);
      await positions.close();
    });
  });

  testWidgets(
      'recorded, not ruled: under a measured 300 m a failed start reaches the '
      'top rung, where a positioned driver there gets heightened caution',
      (tester) async {
    final platform = StreamController<Position>();
    await _boot(tester,
        source: () => _granted(platform), weather: _observed(300));
    await _tapShare(tester);
    platform.add(_position(_clockNow));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 1));
    expect(_panel(tester), 'heightenedCaution',
        reason: 'control: a positioned driver under a measured 300 m');
    await platform.close();

    final a = await _boot(tester, source: _failedStart, weather: _observed(300));
    await _tapShare(tester);
    await _advance(tester, const Duration(seconds: 1));
    expect(_panel(tester), 'considerStopping');
    expect(a.haptics.map((h) => '$h'), contains('HapticCuePattern.critical'));
  });
}
