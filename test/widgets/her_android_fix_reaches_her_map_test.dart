/// A GPS fix from Android reaches her map, parsed by the code that parses it
/// on Android.
///
/// Why, written before the act (2026-09-17). On a real Android 10 phone the
/// GPS fixes arrived, the app had requested them, and her map said
/// 現在地 不明 · 最後の位置 なし. geolocator_android 4.6.2 parses every stream
/// event with `AndroidPosition.fromMap`, which calls `Position.fromMap` and
/// then rebuilds the position from its numbers alone
/// (`lib/src/types/android_position.dart`). `hasAccuracy`, `hasSpeed` and
/// `hasSpeedAccuracy` are therefore false on every Android position. Since
/// 2026-09-14 the app has read an accuracy only when `hasAccuracy` is true, so
/// every Android fix was a sample with no measured accuracy: never a fix, never
/// given to the drive brain, never on her map. Her ring's speed floor and her
/// motion were lost the same way.
///
/// No earlier test could see it. They parse with `Position.fromMap`, hand-build
/// a `Position` with the flags set, or mock the default channels
/// (`flutter.baseflow.com/geolocator_updates`), whose parser keeps the flags.
/// Android registers `GeolocatorAndroid`, which uses its own channels and its
/// own parser. These tests register it and send the map geolocator_android's
/// `LocationMapper.toHashMap` writes: the four keys it always writes, and one
/// key for each value the platform measured.
///
/// Coordinates are synthetic: Akita city, inside the bundled map, and Helsinki,
/// far outside Japan. Where she is must not decide whether her position
/// reaches her map.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_android/geolocator_android.dart'
    show GeolocatorAndroid;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

const _method = MethodChannel('flutter.baseflow.com/geolocator_android');
const _updates =
    EventChannel('flutter.baseflow.com/geolocator_updates_android');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

const _places = <(String, double, double)>[
  ('inside the bundled Akita map', 39.7186, 140.1024),
  ('far outside Japan, in Helsinki', 60.1699, 24.9384),
];

/// What geolocator_android 4.6.2's `LocationMapper.toHashMap` writes for one
/// `android.location.Location`: always latitude, longitude, timestamp and
/// is_mocked; `accuracy`, `speed` and `speed_accuracy` only when the platform
/// measured them.
Map<String, Object> _androidLocation({
  required double latitude,
  required double longitude,
  required DateTime at,
  double? accuracy,
  double? speed,
  double? speedAccuracy,
}) =>
    {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': at.millisecondsSinceEpoch,
      'is_mocked': false,
      'accuracy': ?accuracy,
      'speed': ?speed,
      'speed_accuracy': ?speedAccuracy,
    };

/// The app's own position stream, with its own defaults, on Android: location
/// on, permission held while in use, and [location] sent the moment the
/// platform stream is listened to.
Future<PositionAvailable> _onlyFixThroughAndroid(
    Map<String, Object> location) async {
  _messenger.setMockStreamHandler(
    _updates,
    MockStreamHandler.inline(onListen: (_, sink) {
      sink.success(location);
    }),
  );
  final events =
      await herPositionStream().take(1).toList().timeout(const Duration(seconds: 5));
  expect(events.single, isA<PositionAvailable>(),
      reason: 'a location the platform sent is a position');
  return events.single as PositionAvailable;
}

final _start = DateTime.utc(2026, 1, 14, 21);
var _clockNow = _start;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<void> _boot(WidgetTester tester) async {
  _clockNow = _start;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: FakeAlertActuators(),
    locale: const Locale('ja'),
    clock: () => _clockNow,
    jmaFetch: () async => const JmaFailure('test: no observation'),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _tapShare(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await _settle(tester);
}

String? _line(WidgetTester tester) {
  final f = find.byKey(const Key('her-status-line'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GeolocatorAndroid.registerWith();
    _messenger.setMockMethodCallHandler(_method, (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
          return 2; // while in use
      }
      return null;
    });
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_method, null);
    _messenger.setMockStreamHandler(_updates, null);
  });

  group('the app\'s own position stream, parsed by geolocator_android', () {
    for (final (place, latitude, longitude) in _places) {
      test(
          'a fix $place keeps its accuracy, and its speed and speed accuracy '
          'floor her ring and read as moving', () async {
        final fix = await _onlyFixThroughAndroid(_androidLocation(
          latitude: latitude,
          longitude: longitude,
          at: _start,
          accuracy: 30,
          speed: 13.9,
          speedAccuracy: 0.5,
        ));
        expect((fix.latitude, fix.longitude), (latitude, longitude));
        expect(fix.accuracyMeters, 30);
        expect(fix.speedFloorMps, closeTo(14.4, 1e-9));
        expect(fix.motion, GroundMotion.moving);
      });
    }

    test('a stop Android measured on a fix with an accuracy is a stop',
        () async {
      final fix = await _onlyFixThroughAndroid(_androidLocation(
        latitude: 39.7186,
        longitude: 140.1024,
        at: _start,
        accuracy: 5,
        speed: 0.2,
        speedAccuracy: 0.2,
      ));
      expect(fix.accuracyMeters, 5);
      expect(fix.speedFloorMps, closeTo(0.4, 1e-9));
      expect(fix.motion, GroundMotion.stopped);
    });

    test(
        'what Android did not measure is still not read (decided 2026-09-14): '
        'no accuracy, no speed floor, motion unknown', () async {
      final fix = await _onlyFixThroughAndroid(_androidLocation(
        latitude: 39.7186,
        longitude: 140.1024,
        at: _start,
      ));
      expect(fix.accuracyMeters, isNull);
      expect(fix.speedFloorMps, isNull);
      expect(fix.motion, GroundMotion.unknown);
    });

    test(
        'bound: on Android a measured 0.0 cannot be told from no measurement, '
        'so it reads as none: no 0 m ring, and no stop from a speed of 0.0',
        () async {
      final fix = await _onlyFixThroughAndroid(_androidLocation(
        latitude: 39.7186,
        longitude: 140.1024,
        at: _start,
        accuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ));
      expect(fix.accuracyMeters, isNull);
      expect(fix.speedFloorMps, isNull);
      expect(fix.motion, GroundMotion.unknown);
    });
  });

  group('her map, from the app\'s own stream on Android', () {
    for (final (place, latitude, longitude) in _places) {
      testWidgets(
          'a 30 m fix $place: the line under her map names it and the map '
          'draws her, never 現在地 不明', (tester) async {
        MockStreamHandlerEventSink? platform;
        _messenger.setMockStreamHandler(
          _updates,
          // A block body: an arrow would return the sink as the reply to the
          // platform's `listen` call, which the codec cannot encode.
          MockStreamHandler.inline(onListen: (_, sink) {
            platform = sink;
          }),
        );
        await _boot(tester);
        await _tapShare(tester);
        expect(platform, isNotNull,
            reason: 'control: the app listened on geolocator_android\'s own '
                'channel');

        platform!.success(_androidLocation(
          latitude: latitude,
          longitude: longitude,
          at: _clockNow,
          accuracy: 30,
        ));
        await _settle(tester);

        expect(_line(tester), '現在地 · ±30 m');
        expect(find.byKey(const ValueKey('her-position-unknown-label')),
            findsNothing);
        expect(tester.widget<AkitaMap>(find.byType(AkitaMap)).herPosition,
            isNotNull,
            reason: 'her map draws the fix');
      });
    }
  });
}
