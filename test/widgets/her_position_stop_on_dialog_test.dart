/// 停止 while the permission dialog is up, then her allow: the platform
/// position stream is not left subscribed.
///
/// Why, written before the act (2026-09-15). Measured on b0f74e7 with a probe
/// against the geolocator channels: allow at 50 s then 停止 subscribed the
/// platform stream once and cancelled it once; 停止 on the dialog at 5 s, then
/// allow at 50 s, subscribed it once and never cancelled it, still after the
/// app was gone. The stream's cancel ran while the request was awaited, when
/// there was no subscription to cancel, and the request then went on to
/// subscribe. She chose to stop sharing, and her position went on being read.
///
/// Two readings: the stream function itself, with a request that answers
/// after its listener is gone; and the app, through the plugin's own channels,
/// as the probe measured it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

void main() {
  group('herPositionStream', () {
    for (final answer in const [
      LocationPermission.whileInUse,
      LocationPermission.always,
    ]) {
      test('cancelled while the request is awaited, then the platform answers '
          '${answer.name}: '
          'no platform stream is subscribed', () async {
        final request = Completer<LocationPermission>();
        var subscribed = 0;
        var platformListens = 0;
        final platform = StreamController<Position>(
            onListen: () => platformListens++);
        final events = <PositionFix>[];
        final sub = herPositionStream(
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.denied,
          requestPermission: () => request.future,
          positionStream: () => platform.stream,
          onPlatformStreamSubscribed: () => subscribed++,
        ).listen(events.add);
        await pumpEventQueue();
        await sub.cancel();
        request.complete(answer);
        await pumpEventQueue();
        expect(platformListens, 0,
            reason: 'the platform stream was listened to after the cancel');
        expect(subscribed, 0);
        expect(platform.hasListener, isFalse);
        // Not awaited: a controller never listened to completes its close
        // only when a listener takes the done event.
        unawaited(platform.close());
      });
    }

    test('control: not cancelled, the same answer subscribes the platform '
        'stream, and a cancel after that ends it', () async {
      final request = Completer<LocationPermission>();
      final platform = StreamController<Position>();
      final sub = herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () => request.future,
        positionStream: () => platform.stream,
      ).listen((_) {});
      await pumpEventQueue();
      request.complete(LocationPermission.whileInUse);
      await pumpEventQueue();
      expect(platform.hasListener, isTrue);
      await sub.cancel();
      await pumpEventQueue();
      expect(platform.hasListener, isFalse);
      await platform.close();
    });

    test('cancelled while the service check is awaited: nothing more is asked '
        'of the platform', () async {
      final service = Completer<bool>();
      var checks = 0;
      var requests = 0;
      var platformListens = 0;
      final sub = herPositionStream(
        isServiceEnabled: () => service.future,
        checkPermission: () async {
          checks++;
          return LocationPermission.whileInUse;
        },
        requestPermission: () async {
          requests++;
          return LocationPermission.whileInUse;
        },
        positionStream: () {
          platformListens++;
          return const Stream<Position>.empty();
        },
      ).listen((_) {});
      await pumpEventQueue();
      await sub.cancel();
      service.complete(true);
      await pumpEventQueue();
      expect((checks, requests, platformListens), (0, 0, 0));
    });
  });

  group('the app, through the plugin channels', () {
    const method = MethodChannel('flutter.baseflow.com/geolocator');
    const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
    TestDefaultBinaryMessenger messenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var listens = 0, cancels = 0;

    setUp(() {
      listens = 0;
      cancels = 0;
      messenger().setMockMethodCallHandler(method, (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return 0; // denied: the dialog is asked for
          case 'requestPermission':
            await Future<void>.delayed(const Duration(seconds: 50));
            return 2; // whileInUse
        }
        return null;
      });
      messenger().setMockStreamHandler(
          updates,
          MockStreamHandler.inline(
              onListen: (_, _) => listens++, onCancel: (_) => cancels++));
    });

    tearDown(() {
      messenger().setMockMethodCallHandler(method, null);
      messenger().setMockStreamHandler(updates, null);
    });

    Future<void> boot(WidgetTester tester) async {
      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        clock: () => DateTime.utc(2026, 1, 14, 21),
        jmaFetch: () async => const JmaFailure('no network in this test'),
      ));
      await tester.pump();
      await tester.pump();
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pump();
      await tester.pump();
    }

    Future<void> advance(WidgetTester tester, Duration d) async {
      for (var left = d; left > Duration.zero;) {
        final step = left > const Duration(seconds: 5)
            ? const Duration(seconds: 5)
            : left;
        await tester.pump(step);
        left -= step;
      }
    }

    final stop = find.widgetWithText(
        TextButton, const AppL10n(Locale('ja')).stop);

    testWidgets('control: allow at 50 s, then 停止: subscribed once, cancelled '
        'once', (tester) async {
      await boot(tester);
      await tap(tester, find.byKey(const Key('share-location-button')));
      await advance(tester, const Duration(seconds: 60));
      expect((listens, cancels), (1, 0), reason: 'sharing after her allow');
      await tap(tester, stop);
      await advance(tester, const Duration(seconds: 5));
      expect((listens, cancels), (1, 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await advance(tester, const Duration(seconds: 10));
    });

    testWidgets('停止 on the dialog at 5 s, then allow at 50 s: the platform '
        'stream is never subscribed, before or after the app is gone',
        (tester) async {
      await boot(tester);
      await tap(tester, find.byKey(const Key('share-location-button')));
      await advance(tester, const Duration(seconds: 5));
      expect(stop, findsOneWidget, reason: 'control: the row offers 停止');
      await tap(tester, stop);
      await advance(tester, const Duration(seconds: 60));
      expect((listens, cancels), (0, 0),
          reason: 'after her allow: listens=$listens cancels=$cancels');
      await tester.pumpWidget(const SizedBox.shrink());
      await advance(tester, const Duration(seconds: 10));
      expect((listens, cancels), (0, 0),
          reason: 'after the app is gone: listens=$listens cancels=$cancels');
    });
  });
}
