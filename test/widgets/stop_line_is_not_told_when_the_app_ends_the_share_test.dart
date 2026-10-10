/// When the APP ends a share (a share without its foreground service, as the
/// app leaves the screen), she is told once, with that line alone. The stop
/// confirmation is not told there. It is told only at 停止.
///
/// WHY, written before the act (2026-10-10, carrying the stop confirmation onto
/// main). The stop confirmation was built on a base without the rule for a
/// share without its service (b970dec, 2026-10-06). That rule ends the share by
/// calling the same _clearPosition that 停止 calls, after it has told her
/// 「アプリが画面から離れたため、現在地の警告は止まりました。」 by voice and
/// vibration. Merged as git merged it, with no conflict in lib/main.dart,
/// _clearPosition then also queued 「共有を終了しました。現在地の警告も止まりました。」
/// with the ended cue: two tellings of one end, and the second names an act
/// she did not do. The rule's own tests could not see it: the N1 test reads
/// under fake async only, where the cancel's completion (a root-zone
/// microtask) never runs, and the start-guard test counts only the N1 line.
/// These tests turn the real event loop and read every line and every cue.
///
/// Held here, on both roads into the app's own ending:
///   - the leave in the middle of a share;
///   - the settle window at the subscription, still away when it ends;
/// and, as the instrument's control, that 停止 in the same share without its
/// service does tell the stop confirmation, so "not told" below is a reading,
/// not a blind spot.
///
/// The fake actuators prove the app asked to speak and vibrate, not that she
/// heard or felt it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/notification_permission.dart';

import '../support/fake_alert_actuators.dart';

/// The two lines, verbatim: the words decided for them, not read from the
/// app, so a rewording in the app fails here.
const String _n1 = 'アプリが画面から離れたため、現在地の警告は止まりました。';
const String _ended = '共有を終了しました。現在地の警告も止まりました。';
const double _v = 15;

var _clockNow = DateTime.utc(2026, 1, 14, 21);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

/// Turns of the REAL event loop, then frames. A cancel's completed future
/// resumes its awaiter in a root-zone microtask that fake async never runs
/// (measured 2026-10-05); without these turns a second telling is invisible.
Future<void> _turns(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
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

const _leave = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

/// Boots with a remembered yes and starts a share WITHOUT its service (the
/// notification channel unmocked, which the app reads as "cannot post"), on
/// the app's own position path over a faked platform stream; gives it four
/// fixes 5 s apart.
Future<(FakeAlertActuators, StreamController<Position>)> _driveWithoutService(
  WidgetTester tester,
) async {
  final a = FakeAlertActuators();
  final positions = StreamController<Position>();
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    SngnavApp(
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
  var north = 0.0;
  for (var i = 0; i < 4; i++) {
    if (i > 0) {
      _clockNow = _clockNow.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      north += _v * 5;
    }
    positions.add(_fix(north));
    await _settle(tester);
  }
  expect(
    find.byKey(const Key('share-runs-only-on-screen'), skipOffstage: false),
    findsOneWidget,
    reason: 'control: this share runs without its service',
  );
  expect(
    find.widgetWithText(TextButton, '停止', skipOffstage: false),
    findsWidgets,
    reason: 'control: the share runs',
  );
  return (a, positions);
}

List<String> _spokenSince(FakeAlertActuators a, int from) =>
    [for (final s in a.spoken.skip(from)) s.text];

class _FakeGeolocator extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.denied;
  int requests = 0;
  Completer<LocationPermission>? _answer;
  final positions = StreamController<Position>.broadcast();
  int streamsStarted = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() {
    requests++;
    return (_answer = Completer<LocationPermission>()).future;
  }

  void answer(LocationPermission p) {
    permission = p;
    _answer?.complete(p);
    _answer = null;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamsStarted++;
    return positions.stream;
  }
}

class _NotificationChannel {
  Completer<bool>? _answer;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'read':
        return <String, Object>{
          'granted': false,
          'enabled': true,
          'needsRuntimeRequest': true,
        };
      case 'request':
        final yes = await (_answer = Completer<bool>()).future;
        _answer = null;
        return yes;
    }
    return null;
  }

  void answer({required bool allow}) => _answer?.complete(allow);
}

void main() {
  // The tile cache asks path_provider for its directory. Under fake async alone
  // that call never completes; the real turns above let it, and unmocked it
  // throws a MissingPluginException into the test.
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_stop_line');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets(
    'the leave: a share without its service ends as the app leaves the '
    'screen, and she is told that line alone, never the stop confirmation',
    (tester) async {
      final (a, positions) = await _driveWithoutService(tester);
      final sb = a.spoken.length, fb = a.felt.length;
      for (final s in _leave) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
      await _settle(tester);
      await _turns(tester);
      // Long enough for any line queued behind the first to be handed over.
      await tester.pump(const Duration(seconds: 10));
      await _turns(tester);
      expect(_spokenSince(a, sb), [_n1],
          reason: 'one end, one telling: the app ended this share, and the '
              'line that says so is told; 「共有を終了しました」 names an act '
              'she did not do');
      final felt = a.felt.skip(fb).toList();
      expect(felt, hasLength(1),
          reason: 'one cue with the one line: $felt');
      expect(felt, isNot(contains('ended')),
          reason: 'the ended cue belongs to the stop confirmation');
      unawaited(positions.close());
      await _settle(tester);
    },
  );

  testWidgets(
    'instrument control: 停止 in the same share without its service tells '
    'the stop confirmation with the ended cue, and not the app-left line',
    (tester) async {
      final (a, positions) = await _driveWithoutService(tester);
      final sb = a.spoken.length, fb = a.felt.length;
      final stop = find.widgetWithText(TextButton, '停止');
      expect(stop, findsOneWidget, reason: 'control: 停止 is offered');
      await tester.ensureVisible(stop);
      await tester.pump();
      await tester.tap(stop);
      await _settle(tester);
      await _turns(tester);
      await tester.pump(const Duration(seconds: 10));
      await _turns(tester);
      expect(_spokenSince(a, sb), [_ended],
          reason: 'this harness can see the stop confirmation when it is '
              'told, so its absence in the other tests is a reading');
      expect(a.felt.skip(fb), ['ended']);
      unawaited(positions.close());
      await _settle(tester);
    },
  );

  group('the settle window at the subscription', () {
    late GeolocatorPlatform originalGeolocator;
    late _FakeGeolocator geo;
    late _NotificationChannel notif;

    setUp(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      notif = _NotificationChannel();
      messenger.setMockMethodCallHandler(
        NotificationPermission.channel,
        notif.handle,
      );
      originalGeolocator = GeolocatorPlatform.instance;
      geo = _FakeGeolocator();
      GeolocatorPlatform.instance = geo;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NotificationPermission.channel, null);
      GeolocatorPlatform.instance = originalGeolocator;
    });

    testWidgets(
      'still away when the window ends: the app-left line alone, never the '
      'stop confirmation',
      (tester) async {
        final a = FakeAlertActuators();
        void to(AppLifecycleState s) =>
            tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pumpWidget(
          SngnavApp(
            locale: const Locale('ja'),
            actuators: a,
            clock: () => DateTime.utc(2026, 1, 14, 21),
            jmaFetch: () async => const JmaFailure('test: no observation'),
          ),
        );
        await _turns(tester, rounds: 25);
        final share = find.byKey(const Key('share-location-button'));
        await tester.ensureVisible(share);
        await tester.pump();
        await tester.tap(share);
        await _turns(tester, rounds: 25);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const Key('location-consent-accept')));
        await _turns(tester, rounds: 25);
        to(AppLifecycleState.inactive);
        await tester.pump(const Duration(seconds: 1));
        notif.answer(allow: false);
        to(AppLifecycleState.resumed);
        await _turns(tester, rounds: 25);
        expect(geo.requests, 1, reason: 'control: the location ask is pending');
        for (final s in _leave) {
          to(s);
          await tester.pump();
        }
        await _turns(tester, rounds: 25);
        final sb = a.spoken.length, fb = a.felt.length;
        geo.answer(LocationPermission.whileInUse);
        await _turns(tester, rounds: 25);
        expect(geo.streamsStarted, 1, reason: 'control: it subscribed');
        // Past the settle window, and long enough for a queued second line.
        await tester.pump(const Duration(seconds: 3));
        await _turns(tester, rounds: 25);
        await tester.pump(const Duration(seconds: 10));
        await _turns(tester, rounds: 25);
        expect(_spokenSince(a, sb), [_n1],
            reason: 'one end, one telling, on this road too');
        final felt = a.felt.skip(fb).toList();
        expect(felt, hasLength(1), reason: 'one cue: $felt');
        expect(felt, isNot(contains('ended')));
        // Back the way a return comes: paused, hidden, inactive, resumed.
        to(AppLifecycleState.hidden);
        to(AppLifecycleState.inactive);
        to(AppLifecycleState.resumed);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
