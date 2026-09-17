/// Audit vectors for the driver with no position in a measured whiteout
/// (the four cases ruled 2026-09-15), for clauses the landing set reaches with
/// no test.
///
/// Why, written before the act. The landing set holds each case's direction
/// against the mutations its producer built. These vectors each hold one
/// clause of the direction that no test in the set reaches, so that a wrong
/// landing of that clause is caught by the machine and not by her:
/// * W1, a later share whose first fix never arrives: told as a first share
///   whose first fix never arrives is (the later-share case and the
///   first-fix case together);
/// * W2, a whiteout that opened while the permission dialog was up, and her
///   no: nothing at her no, and told once by the next refresh;
/// * W3, a turn after 停止: the next-turn section gives the ended driver what
///   it gives the never-shared driver, nothing from the ended share's
///   position;
/// * W4 and W4b, location refused mid-drive after the share told the
///   whiteout (at a refresh, and between refreshes): nothing at the refusal,
///   nothing more at the next refresh, and the card shows what the
///   never-shared driver's card shows.
library;

import 'dart:async';

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show CautionReason, DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart' as re;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/fake_alert_actuators.dart';

const _hud = DriveHudLocalizer();
const _words = AppL10n(Locale('ja'));
final _stopLine = _hud.spokenGuidance(DriveAction.considerStopping, 'ja');
final _slowLine = _hud.spokenGuidance(DriveAction.heightenedCaution, 'ja');
final _lowVisibility = _hud.reasonLabel(CautionReason.lowVisibility, 'ja');

const _top = 'considerStopping';
const _none = 'none';

final _start = DateTime.utc(2026, 1, 14, 21);
var _now = _start;
var _visibilities = <int?>[80];
var _fetches = 0;

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

Future<JmaResult> _jma() async {
  final i = _fetches++;
  return JmaSuccess(JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: 5,
    humidityPercent: 50,
    windMetersPerSecond: 2,
    snowDepthCm: null,
    precipitation10mMm: 0,
    visibilityMeters:
        _visibilities[i < _visibilities.length ? i : _visibilities.length - 1],
    observedAtJstKey: _jstKey(_now),
    fetchedAt: _now,
  ));
}

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

String _rung(WidgetTester tester) {
  final banner = find.byKey(const Key('drive-hud-caution-banner'));
  if (banner.evaluate().isEmpty) return _none;
  final texts = [
    for (final e in find
        .descendant(of: banner, matching: find.byType(Text))
        .evaluate())
      (e.widget as Text).data ?? '',
  ];
  final rungs = <String>{
    for (final s in texts)
      for (final r in DriveAction.values)
        for (final advisory in const [false, true])
          for (final measured in const [false, true])
            for (final calm in const [false, true])
              if (s ==
                  _hud.actionHeadline(r, 'ja',
                      advisoryUnconfirmed: advisory,
                      measuredUnconfirmed: measured,
                      calmNoteInForce: calm))
                r.name,
  };
  return rungs.length == 1 ? rungs.single : 'UNREADABLE $texts';
}

String _name(String line) =>
    line == _stopLine ? 'stop' : (line == _slowLine ? 'slow' : line);

List<String> _spoken(FakeAlertActuators a, int from) =>
    [for (final s in a.spoken.skip(from)) _name(s.text)];

List<String> _felt(FakeAlertActuators a, int from) =>
    [for (final h in a.haptics.skip(from)) '$h'.split('.').last];

bool _cause() => find.textContaining(_lowVisibility).evaluate().isNotEmpty;

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  List<int?> visibilities = const [80],
  bool route = false,
}) async {
  final a = FakeAlertActuators();
  _now = _start;
  _visibilities = [...visibilities];
  _fetches = 0;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: const Locale('ja'),
    clock: () => _now,
    jmaFetch: _jma,
    positionSource: source,
    routingEngineFactory: route ? () => _OneTurnEngine() : null,
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _advance(WidgetTester tester, Duration d,
    {void Function()? each}) async {
  var left = d;
  while (left > Duration.zero) {
    final step =
        left > const Duration(seconds: 15) ? const Duration(seconds: 15) : left;
    _now = _now.add(step);
    each?.call();
    await tester.pump(step);
    left -= step;
  }
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
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
  final s = find.widgetWithText(TextButton, _words.stop);
  expect(s, findsOneWidget, reason: 'control: the row offers 停止');
  await tester.ensureVisible(s);
  await tester.pump();
  await tester.tap(s);
  await tester.pump();
  await tester.pump();
}

Position _position(DateTime at) => Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: at,
      accuracy: 10,
      hasAccuracy: true,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class _Positioned {
  final platform = StreamController<Position>();
  Stream<PositionFix> source() => herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        positionStream: () => platform.stream,
      );
  void fix() => platform.add(_position(_now));
}

Future<void> _routeWithOneTurn(WidgetTester tester) async {
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
  expect(find.byKey(const Key('maneuver-narration-banner')), findsOneWidget,
      reason: 'control: the route has a next maneuver');
}

String _textOfKey(WidgetTester tester, String key) {
  final f = find.byKey(Key(key));
  expect(f, findsOneWidget, reason: '$key is drawn');
  return tester.widget<Text>(f).data ?? '';
}

Future<({String tier, String result, int spokenByPress})> _narration(
    WidgetTester tester, FakeAlertActuators a) async {
  final tier = _textOfKey(tester, 'maneuver-narration-tier');
  final before = a.spoken.length;
  final b = find.byKey(const Key('maneuver-narrate-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  return (
    tier: tier,
    result: _textOfKey(tester, 'maneuver-narration-result'),
    spokenByPress: a.spoken.length - before,
  );
}

void main() {
  testWidgets(
      'W1 a later share whose first fix never arrives, in the same measured '
      '80 m: the top rung, the stop line once and the critical haptic once by '
      '16 s, as a first share whose first fix never arrives', (tester) async {
    final p1 = _Positioned(), p2 = _Positioned();
    var shares = 0;
    final a = await _boot(tester, source: () {
      shares++;
      return shares == 1 ? p1.source() : p2.source();
    });
    await _tapShare(tester);
    p1.fix();
    await _advance(tester, const Duration(seconds: 1), each: p1.fix);
    expect(_spoken(a, 0), contains('stop'),
        reason: 'control: the first share was told');
    await _tapStop(tester);
    await _advance(tester, const Duration(minutes: 20));
    final s = a.spoken.length, f = a.haptics.length;
    await _tapShare(tester);
    expect(shares, 2, reason: 'control: a second share started');
    await _advance(tester, const Duration(seconds: 16)); // p2 never delivers
    expect(_rung(tester), _top, reason: 'the later share at 16 s: the rung');
    expect(_spoken(a, s), ['stop'], reason: 'the later share at 16 s: spoken');
    expect(_felt(a, f), ['critical'], reason: 'the later share at 16 s: felt');
    await _advance(tester, const Duration(minutes: 11));
    expect(_spoken(a, s), ['stop'],
        reason: 'the later share at 11 min: not told again');
  });

  group('W2 the permission dialog, through the platform channels', () {
    const method = MethodChannel('flutter.baseflow.com/geolocator');
    const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
    TestDefaultBinaryMessenger messenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger().setMockMethodCallHandler(method, null);
      messenger().setMockStreamHandler(updates, null);
    });

    testWidgets(
        'a whiteout that opens while the dialog is up, then her no: nothing '
        'while the dialog is up, nothing at her no, told once by the next '
        'refresh, and not again after it', (tester) async {
      messenger().setMockMethodCallHandler(method, (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return 0;
          case 'requestPermission':
            await Future<void>.delayed(const Duration(seconds: 50));
            return 0; // her no
        }
        return null;
      });
      messenger().setMockStreamHandler(
          updates, MockStreamHandler.inline(onListen: (_, _) {}));
      final a = await _boot(tester, visibilities: const [1500, 80]);
      await _advance(tester, const Duration(minutes: 9, seconds: 40));
      expect(a.spoken, isEmpty, reason: 'control: 1,500 m tells nothing');
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 45));
      expect(_fetches, greaterThanOrEqualTo(2),
          reason: 'control: the 10-minute refresh brought 80 m on the dialog');
      expect(_spoken(a, 0), isEmpty, reason: 'on the dialog, at 10 min 25 s');
      expect(_felt(a, 0), isEmpty, reason: 'on the dialog, at 10 min 25 s');
      await _advance(tester, const Duration(seconds: 10)); // her no at 10:30
      expect(_spoken(a, 0), isEmpty, reason: 'after her no, at 10 min 35 s');
      expect(_felt(a, 0), isEmpty, reason: 'after her no, at 10 min 35 s');
      await _advance(tester, const Duration(minutes: 9, seconds: 40));
      expect(_fetches, greaterThanOrEqualTo(3),
          reason: 'control: the 20-minute refresh ran');
      expect(_spoken(a, 0), ['stop'], reason: 'at 20 min 15 s: told once');
      expect(_felt(a, 0), ['critical'], reason: 'at 20 min 15 s: felt once');
      expect(_rung(tester), _top, reason: 'at 20 min 15 s: the rung');
      expect(_cause(), isTrue, reason: 'at 20 min 15 s: the cause on screen');
      await _advance(tester, const Duration(minutes: 10));
      expect(_spoken(a, 0), ['stop'], reason: 'at 30 min 15 s: not again');
    });
  });

  testWidgets(
      'W3 after 停止 the next-turn section gives her what it gives a driver who '
      'never shared: nothing from the ended share\'s position, at once and '
      '10 min later', (tester) async {
    // The never-shared driver, with the same route.
    var a = await _boot(tester, visibilities: const [1500], route: true);
    await _routeWithOneTurn(tester);
    final never = await _narration(tester, a);
    expect(never.spokenByPress, 0,
        reason: 'control: the never-shared driver hears no turn');

    final p = _Positioned();
    a = await _boot(tester,
        source: p.source, visibilities: const [1500], route: true);
    await _routeWithOneTurn(tester);
    await _tapShare(tester);
    p.fix();
    await _advance(tester, const Duration(seconds: 1), each: p.fix);
    final sharing = await _narration(tester, a);
    expect(sharing.spokenByPress, greaterThan(0),
        reason: 'control: a trusted turn in the share is read aloud');
    await _tapStop(tester);
    for (final (at, step) in [
      ('just after 停止', const Duration(seconds: 1)),
      ('10 min after 停止', const Duration(minutes: 10)),
    ]) {
      await _advance(tester, step);
      final ended = await _narration(tester, a);
      expect(ended.tier, never.tier, reason: '$at: the banner\'s state');
      expect(ended.result, never.result, reason: '$at: what her press did');
      expect(ended.spokenByPress, 0, reason: '$at: no turn read aloud');
    }
  });

  testWidgets(
      'W4 location refused mid-drive after the share told a whiteout that '
      'opened during it: nothing at the refusal, nothing more at the next '
      'refresh, and the card shows the top rung with its cause, as the '
      'never-shared driver\'s does', (tester) async {
    final positions = StreamController<PositionFix>.broadcast();
    final a = await _boot(tester,
        source: () => positions.stream, visibilities: const [1500, 80]);
    void fix() => positions.add(PositionAvailable(
        latitude: 39.7186,
        longitude: 140.1024,
        accuracyMeters: 10,
        timestamp: _now));
    await _tapShare(tester);
    fix();
    await _advance(tester, const Duration(minutes: 10, seconds: 15), each: fix);
    expect(_spoken(a, 0), ['stop'],
        reason: 'control: the whiteout opened at the 10-minute refresh, during '
            'the share, and the share told it');
    final s = a.spoken.length, f = a.haptics.length;
    positions.add(const PositionUnavailable('revoked',
        cause: PositionUnavailableCause.permissionDenied));
    await _advance(tester, const Duration(seconds: 1));
    expect(_spoken(a, s), isEmpty, reason: 'at the refusal: spoken');
    expect(_felt(a, f), isEmpty, reason: 'at the refusal: felt');
    await _advance(tester, const Duration(minutes: 10));
    expect(_fetches, greaterThanOrEqualTo(3), reason: 'control: refresh ran');
    expect(_spoken(a, s), isEmpty, reason: 'after the next refresh: spoken');
    expect(_felt(a, f), isEmpty, reason: 'after the next refresh: felt');
    expect(_rung(tester), _top, reason: 'after the next refresh: the rung');
    expect(_cause(), isTrue, reason: 'after the next refresh: the cause');
    await positions.close();
  });

  testWidgets(
      'W4b location refused after a share told the whiteout between refreshes: '
      'the share started before 80 m came, told it at its first check, then '
      'her refusal: nothing at the refusal and nothing at the next refresh',
      (tester) async {
    final positions = StreamController<PositionFix>.broadcast(); // no fix ever
    final a = await _boot(tester,
        source: () => positions.stream, visibilities: const [700, 80]);
    await _advance(tester, const Duration(minutes: 9, seconds: 55));
    expect(a.spoken, isEmpty, reason: 'control: nothing told before she shares');
    await _tapShare(tester);
    await _advance(tester, const Duration(seconds: 25));
    expect(_fetches, greaterThanOrEqualTo(2),
        reason: 'control: the 10-minute refresh brought 80 m');
    expect(_spoken(a, 0), ['stop'],
        reason: 'control: told in the share at its first check, after the '
            'refresh');
    final s = a.spoken.length, f = a.haptics.length;
    positions.add(const PositionUnavailable('revoked',
        cause: PositionUnavailableCause.permissionDenied));
    await _advance(tester, const Duration(seconds: 1));
    expect(_spoken(a, s), isEmpty, reason: 'at the refusal: spoken');
    await _advance(tester, const Duration(minutes: 10));
    expect(_fetches, greaterThanOrEqualTo(3), reason: 'control: refresh ran');
    expect(_spoken(a, s), isEmpty, reason: 'after the next refresh: spoken');
    expect(_felt(a, f), isEmpty, reason: 'after the next refresh: felt');
    await positions.close();
  });
}
