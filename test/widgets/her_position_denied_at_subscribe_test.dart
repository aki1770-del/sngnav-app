/// A permission denial the platform sends when the position stream subscribes
/// is her "no", from the typed cause; and no refusal is ever read from text.
///
/// Why this test exists. geolocator_android 4.6.2 checks the permission again
/// when the position stream is listened to, and when it is not held sends the
/// error code PERMISSION_DENIED (`StreamHandlerImpl.java:93-98`), which the
/// plugin's Dart side turns into a typed `PermissionDeniedException`
/// (`geolocator_android.dart:252-253`; the method-channel implementation used
/// on this test host maps the code the same way,
/// `method_channel_geolocator.dart:238-239`). The app wrapped that exception as
/// 'GPS stream error: …', a failure. After her "no" a failure can reach the
/// critical caution rung, which the 2026-09-13 decision on her "no" removed.
///
/// The rules tested here:
///
/// * Ruled 2026-09-13: after her "no" the map says 位置情報オフ, the row offers
///   閉じる, and nothing alarms: she is given what a driver who never shared is
///   given.
/// * The typed cause governs. An exception whose TEXT
///   reads like a denial is not a refusal.
/// * Ruled 2026-09-14: no refusal is read from a reason's text, in
///   either locale; with no typed cause, and for any reason the app's own code
///   did not write, the line under the map is 現在地不明 — 位置を取得できません
///   でした。地図は表示されたままです。 / "Position unknown — this app could not
///   get a position. The map remains."
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart'
    show
        LocationPermission,
        PermissionDefinitionsNotFoundException,
        PermissionDeniedException,
        Position;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import '../support/rung_on_card.dart';

/// geolocator_android 4.6.2, `ErrorCodes.permissionDenied`: the code and the
/// description it sends, byte for byte.
const _deniedCode = 'PERMISSION_DENIED';
const _deniedMessage = "User denied permissions to access the device's location.";

// Ruled bytes, 2026-09-14.
const _noPositionJa = '現在地不明 — 位置を取得できませんでした。地図は表示されたままです。';

const _locationOffWords = ValueKey('her-location-off-label');
const _unknownWords = ValueKey('her-position-unknown-label');

var _clockNow = DateTime.utc(2026, 1, 14, 21);

Future<void> _advance(WidgetTester tester, Duration d) async {
  var left = d;
  while (left > Duration.zero) {
    final step =
        left < const Duration(seconds: 15) ? left : const Duration(seconds: 15);
    _clockNow = _clockNow.add(step);
    await tester.pump(step);
    left -= step;
  }
  await tester.pump();
}

Future<FakeAlertActuators> _boot(WidgetTester tester,
    {Stream<PositionFix> Function()? source}) async {
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  final a = FakeAlertActuators();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: const Locale('ja'),
    clock: () => _clockNow,
    jmaFetch: () async => const JmaFailure('no network in this test'),
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
  await tester.pump();
  await tester.pump();
}

String? _line(WidgetTester tester) {
  final f = find.byKey(const Key('her-status-line'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

bool _rowOffers(String label) =>
    find.widgetWithText(TextButton, label).evaluate().isNotEmpty;

/// Every spoken line, every haptic, and every caution headline the card shows.
String _given(WidgetTester tester, FakeAlertActuators a) {
  // The rung from the caution banner's own headline (2026-09-15), not every
  // text on the screen that names a rung.
  final rungs = [if (rungOnCard() case final rung?) rung.name];
  return 'spoken [${a.spoken.join(' | ')}] haptics [${a.haptics.join(' | ')}] '
      'rungs [${rungs.join(' | ')}]';
}

Stream<PositionFix> _streamFailingWith(Object error) => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => Stream<Position>.error(error),
    );

void main() {
  group('the position stream: an error when the platform stream subscribes', () {
    test('a PermissionDeniedException is a refusal, not for good', () async {
      final e = await _streamFailingWith(
          const PermissionDeniedException(_deniedMessage)).first;
      expect(isLocationRefusal(e), isTrue, reason: '$e');
      expect(isPermanentLocationRefusal(e), isFalse,
          reason: 'the platform said denied, not denied for good');
    });

    test('CONTROL: an exception whose text reads like a denial is no refusal',
        () async {
      final e = await _streamFailingWith(
          Exception('Location permission denied')).first;
      expect(isLocationRefusal(e), isFalse);
    });

    test('CONTROL: a missing manifest permission is a failure, not her no',
        () async {
      final e = await _streamFailingWith(
          const PermissionDefinitionsNotFoundException('no manifest entry')).first;
      expect(isLocationRefusal(e), isFalse);
    });
  });

  group('the app, through the platform channels: denied at subscribe', () {
    const method = MethodChannel('flutter.baseflow.com/geolocator');
    const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
    TestDefaultBinaryMessenger messenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void cannedPlatform({required String code, required String message}) {
      messenger().setMockMethodCallHandler(method, (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return 2; // while in use: the check passes
        }
        return null;
      });
      messenger().setMockStreamHandler(
        updates,
        MockStreamHandler.inline(
          onListen: (_, events) => events.error(code: code, message: message),
        ),
      );
    }

    tearDown(() {
      messenger().setMockMethodCallHandler(method, null);
      messenger().setMockStreamHandler(updates, null);
    });

    testWidgets(
        'the map says 位置情報オフ, the row offers 閉じる, and at 10 min she is '
        'given what a driver who never shared is given', (tester) async {
      var a = await _boot(tester);
      await _advance(tester, const Duration(minutes: 10));
      final neverShared = _given(tester, a);

      cannedPlatform(code: _deniedCode, message: _deniedMessage);
      a = await _boot(tester); // no injected source: the app's own stream
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 1));

      expect(find.byKey(_locationOffWords), findsOneWidget,
          reason: 'line 「${_line(tester)}」');
      expect(find.byKey(_unknownWords), findsNothing);
      expect(_line(tester),
          const AppL10n(Locale('ja')).locationOffStatus(permanently: false, routeSettingOpen: true));
      expect(_rowOffers('閉じる'), isTrue);
      expect(_rowOffers('停止'), isFalse);

      await _advance(tester, const Duration(minutes: 10));
      expect(_given(tester, a), neverShared,
          reason: 'no voice, no haptic, no caution rung after her "no"');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
        'CONTROL: a failure the platform reports at subscribe stays a failure',
        (tester) async {
      cannedPlatform(
          code: 'LOCATION_UPDATE_FAILURE', message: 'provider unavailable');
      await _boot(tester);
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 1));

      expect(find.byKey(_unknownWords), findsOneWidget,
          reason: 'line 「${_line(tester)}」');
      expect(find.byKey(_locationOffWords), findsNothing);
      expect(_rowOffers('停止'), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('no refusal is read from a reason\'s text', () {
    // The line's unit rules are in test/l10n/position_line_words_test.dart.
    testWidgets(
        'in the app: frame 69\'s state, a reason reading like a denial with no '
        'cause, says what the map says', (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => positions.stream);
      await _tapShare(tester);
      positions.add(const PositionUnavailable('Location permission denied'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_unknownWords), findsOneWidget);
      expect(_line(tester), _noPositionJa);
      await positions.close();
    });
  });
}
