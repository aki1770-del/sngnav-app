/// The rule for a share WITHOUT its foreground service never fires before the
/// share's platform stream has subscribed. If she is away (hidden or paused) at
/// the moment it subscribes, it fires then.
///
/// WHY (ruled 2026-10-06, amended twice the same day). The share is marked
/// running at her tap, before its permission asks. A permission screen that
/// stops the activity (an OEM's full-screen one) takes the app to hidden and
/// paused. Told there, 「アプリが画面から離れたため」 is false, and the share would
/// end at its own start. Only the subscription makes the platform's silence the
/// platform's. And at the subscription itself, a report of hidden or paused may
/// be stale (her answer can arrive before her return is reported), so it starts
/// a settle window on its own timer: inside it, inactive or resumed cancels it
/// untold; still away at its end, the rule fires then.
///
/// This runs through the REAL position path (the geolocator platform and the
/// app's notification channel faked), because an injected position source
/// counts as subscribed at the tap (main.dart, "An injected source is the
/// position stream itself: it is subscribed now"), so it cannot show the guard.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/route_act.dart' show kPositionDrought;
import 'package:sngnav_app/services/share_without_service.dart'
    show kShareAwaySettle;
import 'package:sngnav_app/services/notification_permission.dart';

import '../support/fake_alert_actuators.dart';

const String _n1 = 'アプリが画面から離れたため、現在地の警告は止まりました。';
final _start = DateTime.utc(2026, 1, 14, 21);

Future<void> _settleIO(WidgetTester tester, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

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
  late Directory tmp;
  late GeolocatorPlatform originalGeolocator;
  late _FakeGeolocator geo;
  late _NotificationChannel notif;
  late FakeAlertActuators a;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_start_guard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    notif = _NotificationChannel();
    messenger.setMockMethodCallHandler(
      NotificationPermission.channel,
      notif.handle,
    );
    originalGeolocator = GeolocatorPlatform.instance;
    geo = _FakeGeolocator();
    GeolocatorPlatform.instance = geo;
    a = FakeAlertActuators();
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(NotificationPermission.channel, null);
    GeolocatorPlatform.instance = originalGeolocator;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void to(WidgetTester tester, AppLifecycleState s) =>
      tester.binding.handleAppLifecycleStateChanged(s);

  /// Taps share and agrees; declines notifications, so this share will run
  /// without its service; leaves the location request pending.
  Future<void> startAndReachLocationAsk(WidgetTester tester) async {
    await tester.pumpWidget(
      SngnavApp(
        locale: const Locale('ja'),
        actuators: a,
        clock: () => _start,
        jmaFetch: () async => const JmaFailure('test: no observation'),
      ),
    );
    await _settleIO(tester);
    final share = find.byKey(const Key('share-location-button'));
    await tester.ensureVisible(share);
    await tester.pump();
    await tester.tap(share);
    await _settleIO(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('location-consent-accept')));
    await _settleIO(tester);
    to(tester, AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 1));
    notif.answer(allow: false);
    to(tester, AppLifecycleState.resumed);
    await _settleIO(tester);
    expect(geo.requests, 1, reason: 'control: the location ask is pending');
  }

  Iterable<String> n1Told() => a.spoken.map((x) => x.text).where((t) => t == _n1);

  bool running(WidgetTester tester) => find
      .widgetWithText(TextButton, '停止', skipOffstage: false)
      .evaluate()
      .isNotEmpty;

  Future<void> end(WidgetTester tester) async {
    to(tester, AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
    'T-b: a full-screen permission screen (hidden, paused) at the share\'s own '
    'start tells nothing; if she is still away when it subscribes, the rule '
    'fires then, once',
    (tester) async {
      await startAndReachLocationAsk(tester);
      for (final s in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        to(tester, s);
        await tester.pump();
      }
      await _settleIO(tester);
      expect(n1Told(), isEmpty,
          reason: 'THE GUARD: nothing has subscribed yet; she has not left '
              'a running share, she is answering its own question');
      expect(running(tester), isTrue, reason: 'the share is not ended');

      geo.answer(LocationPermission.whileInUse);
      await _settleIO(tester);
      expect(geo.streamsStarted, 1, reason: 'control: it subscribed');
      expect(n1Told(), isEmpty,
          reason: 'inside the settle window nothing is told yet: the report '
              'of being away may be stale');
      await tester.pump(kShareAwaySettle);
      await _settleIO(tester);
      expect(n1Told(), hasLength(1),
          reason: 'still away when the settle window ends: the rule fires '
              'then, once');
      // No frames are drawn while paused: the page is read on her return.
      to(tester, AppLifecycleState.hidden);
      to(tester, AppLifecycleState.inactive);
      to(tester, AppLifecycleState.resumed);
      await _settleIO(tester);
      expect(running(tester), isFalse,
          reason: 'on her return nothing claims the share runs');
      expect(n1Told(), hasLength(1), reason: 'no repeat on her return');
      await end(tester);
    },
  );

  testWidgets(
    "T-b': her answer arrives before her return is reported: subscribed while "
    'paused, then inactive and resumed half a second later -- nothing is '
    'told, and the share runs',
    (tester) async {
      await startAndReachLocationAsk(tester);
      for (final s in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        to(tester, s);
        await tester.pump();
      }
      geo.answer(LocationPermission.whileInUse);
      await _settleIO(tester);
      expect(geo.streamsStarted, 1, reason: 'subscribed while paused');
      await tester.pump(const Duration(milliseconds: 500));
      for (final s in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        to(tester, s);
        await tester.pump();
      }
      await tester.pump(kShareAwaySettle * 2);
      await _settleIO(tester);
      expect(n1Told(), isEmpty,
          reason: 'THE FALSE LINE: told as she comes back to her own share, '
              '「アプリが画面から離れたため」 is not true');
      expect(running(tester), isTrue, reason: 'the share runs');
      await end(tester);
    },
  );

  test('the settle window stays below the drought bound less one second', () {
    expect(
      kShareAwaySettle,
      lessThan(kPositionDrought - const Duration(seconds: 1)),
      reason: 'no GPS-loss reading may fall inside the settle window',
    );
  });

  testWidgets(
    'T-a: the start dialog (inactive, then back) tells nothing, and the share '
    'runs once subscribed',
    (tester) async {
      await startAndReachLocationAsk(tester);
      to(tester, AppLifecycleState.inactive);
      await tester.pump();
      geo.answer(LocationPermission.whileInUse);
      to(tester, AppLifecycleState.resumed);
      await _settleIO(tester);
      expect(geo.streamsStarted, 1);
      expect(n1Told(), isEmpty);
      expect(running(tester), isTrue);
      await end(tester);
    },
  );
}
