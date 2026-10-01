/// The first drive after a fresh install asks for two permissions, one at a
/// time (2026-10-02).
///
/// WHY. Android shows one permission dialog at a time. On Android 13 and
/// later the drive start asks for the notification permission and then for
/// location. The notification ask was started and not waited for, so the
/// location request was made while the notification dialog was still on her
/// screen. Android drops a second request made while a dialog is up
/// (`W/Activity: Can request only one set of permissions at a time`, seen on
/// an API 34 emulator in two release builds), and geolocator_android 4.6.2
/// answers a dropped request with nothing at all (`PermissionManager.java`
/// returns on an empty result without calling back). So on her first drive:
/// she allowed notifications, no location dialog followed, and she waited
/// two minutes on 現在地を取得しています… before a message told her a
/// confirmation screen was still open, when none was.
///
/// These tests drive the real share path (no injected position source) and
/// replace only the two platform edges: geolocator's platform instance, and
/// the app's notification-permission channel. The notification dialog
/// covering the app is modelled by the app's lifecycle going inactive, as it
/// does on Android while a permission dialog is in front.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/notification_permission.dart';

import '../support/fake_alert_actuators.dart';

final _start = DateTime.utc(2026, 1, 14, 21);

Future<void> _settleIO(WidgetTester tester, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// geolocator's platform edge. Location starts not granted, as on a fresh
/// install; every request is recorded and answered only when the test says.
class _FakeGeolocator extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.denied;
  int requests = 0;

  /// Whether the notification ask was still unanswered at each request.
  final notificationAskPendingAtRequest = <bool>[];
  bool Function() notificationAskPending = () => false;
  Completer<LocationPermission>? _answer;
  final positions = StreamController<Position>.broadcast();
  int streamsStarted = 0;
  LocationSettings? lastSettings;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() {
    requests++;
    notificationAskPendingAtRequest.add(notificationAskPending());
    return (_answer = Completer<LocationPermission>()).future;
  }

  /// Her answer to the location dialog.
  void answer(LocationPermission p) {
    permission = p;
    _answer?.complete(p);
    _answer = null;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamsStarted++;
    lastSettings = locationSettings;
    return positions.stream;
  }
}

/// The app's own notification-permission channel, as on a fresh API 33+
/// install: not granted, and a request is answered only when the test says.
class _NotificationChannel {
  bool granted = false;
  int requests = 0;
  Completer<bool>? _answer;

  bool get pending => _answer != null;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'read':
        return <String, Object>{
          'granted': granted,
          'enabled': true,
          'needsRuntimeRequest': true,
        };
      case 'request':
        requests++;
        final yes = await (_answer = Completer<bool>()).future;
        _answer = null;
        granted = yes;
        return yes;
    }
    return null;
  }

  void answer({required bool allow}) => _answer?.complete(allow);
}

Position _akita() => Position(
  latitude: 39.7186,
  longitude: 140.1024,
  timestamp: _start,
  accuracy: 12,
  hasAccuracy: true,
  altitude: 20,
  altitudeAccuracy: 5,
  heading: 0,
  headingAccuracy: 10,
  speed: 8,
  speedAccuracy: 1,
);

bool _carriesDriveNotification(LocationSettings? s) =>
    s is AndroidSettings && s.foregroundNotificationConfig != null;

void main() {
  late Directory tmp;
  late GeolocatorPlatform originalGeolocator;
  late _FakeGeolocator geo;
  late _NotificationChannel notif;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_first_drive');
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
    geo = _FakeGeolocator()..notificationAskPending = () => notif.pending;
    GeolocatorPlatform.instance = geo;
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

  /// A fresh install: no stored consent, nothing granted. Opens the app,
  /// taps 現在地を共有, and agrees on the app's own consent.
  Future<void> startFirstDrive(WidgetTester tester) async {
    await tester.pumpWidget(
      SngnavApp(
        locale: const Locale('ja'),
        actuators: FakeAlertActuators(),
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
  }

  /// Android puts the permission dialog in front of the app.
  void dialogCoversApp(WidgetTester tester) =>
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

  void appInFront(WidgetTester tester) =>
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  Future<void> end(WidgetTester tester) async {
    appInFront(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
    'location is not requested while the notification ask is unanswered; '
    'after her answer it is, and her position arrives',
    (tester) async {
      await startFirstDrive(tester);
      expect(
        notif.requests,
        1,
        reason: 'the first drive asks for notifications',
      );
      expect(notif.pending, isTrue);
      dialogCoversApp(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(
        geo.requests,
        0,
        reason:
            'THE DEFECT: a location request made while the notification '
            'dialog is up is dropped by Android, and she is never asked',
      );

      notif.answer(allow: true);
      appInFront(tester);
      await _settleIO(tester);
      expect(geo.requests, 1, reason: 'after her answer, location is asked');
      expect(geo.notificationAskPendingAtRequest, [false]);

      geo.answer(LocationPermission.whileInUse);
      await _settleIO(tester);
      expect(geo.streamsStarted, 1, reason: 'her position stream starts');
      expect(
        _carriesDriveNotification(geo.lastSettings),
        isTrue,
        reason:
            'she allowed notifications before the drive started, so this '
            'drive already runs with the notification she can see',
      );
      expect(
        find.byKey(const ValueKey('her-dot-real-fix')),
        findsNothing,
        reason: 'control: no dot before a fix has arrived',
      );
      geo.positions.add(_akita());
      await _settleIO(tester);
      expect(
        find.byKey(const ValueKey('her-dot-real-fix')),
        findsOneWidget,
        reason: 'her position arrived on the map',
      );
      await end(tester);
    },
  );

  testWidgets(
    'a slow reader: 30 s on the notification dialog does not start the '
    'location request underneath it',
    (tester) async {
      await startFirstDrive(tester);
      dialogCoversApp(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(
        geo.requests,
        0,
        reason:
            'a person reading a system dialog is not timed out by the '
            '10 s bound for a platform that does not answer; while the '
            'dialog covers the app, the location request waits',
      );

      notif.answer(allow: true);
      appInFront(tester);
      await _settleIO(tester);
      expect(geo.requests, 1);
      expect(geo.notificationAskPendingAtRequest, [false]);
      geo.answer(LocationPermission.whileInUse);
      await _settleIO(tester);
      expect(geo.streamsStarted, 1);
      await end(tester);
    },
  );

  testWidgets(
    'she declines notifications: location is still asked and the drive '
    'still starts, without the notification',
    (tester) async {
      await startFirstDrive(tester);
      dialogCoversApp(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(geo.requests, 0);

      notif.answer(allow: false);
      appInFront(tester);
      await _settleIO(tester);
      expect(
        geo.requests,
        1,
        reason:
            'her "no" to notifications is not a "no" '
            'to location',
      );
      geo.answer(LocationPermission.whileInUse);
      await _settleIO(tester);
      expect(geo.streamsStarted, 1);
      expect(
        _carriesDriveNotification(geo.lastSettings),
        isFalse,
        reason: 'no foreground service behind a notification she declined',
      );
      await end(tester);
    },
  );

  testWidgets(
    'a notification ask that never answers, with nothing in front of the '
    'app, does not strand her: location is asked after 10 s',
    (tester) async {
      await startFirstDrive(tester);
      appInFront(tester);
      await tester.pump(const Duration(seconds: 9));
      expect(geo.requests, 0);
      await tester.pump(const Duration(seconds: 2));
      await _settleIO(tester);
      expect(
        geo.requests,
        1,
        reason: 'a platform that never answers costs her 10 s, not her drive',
      );
      geo.answer(LocationPermission.whileInUse);
      await _settleIO(tester);
      expect(geo.streamsStarted, 1);
      expect(
        _carriesDriveNotification(geo.lastSettings),
        isFalse,
        reason: 'nothing said yes to notifications',
      );
      notif.answer(allow: false);
      await end(tester);
    },
  );

  testWidgets('停止 while the ask is unanswered: nothing is requested or started '
      'afterwards', (tester) async {
    await startFirstDrive(tester);
    appInFront(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(geo.requests, 0);
    final stop = find.text('停止');
    await tester.ensureVisible(stop);
    await tester.pump();
    await tester.tap(stop);
    await _settleIO(tester);

    notif.answer(allow: true);
    await _settleIO(tester);
    await tester.pump(const Duration(seconds: 15));
    expect(geo.requests, 0, reason: 'she ended this drive; it asks nothing');
    expect(geo.streamsStarted, 0);
    await end(tester);
  });
}
