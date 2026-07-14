/// B20 — position-pipeline liveness: a hang is not a throw.
///
/// herPositionStream's error paths were guarded by try/catch, but a platform
/// call that never ANSWERS threw nothing — it just left HER staring at a
/// screen that silently never got a dot. These tests pin the recovery: every
/// raw platform await is timeout-bounded and resolves to an honest
/// [PositionUnavailable], and a platform stream that terminates (onDone)
/// surfaces as unavailability, never as the last dot frozen forever.
///
/// All seams are injected (same idiom as PlayAsset / VoicesProvider) — no
/// geolocator plugin, no device; timeouts are shrunk to keep the suite fast.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';

/// A future that never completes — the hang these tests exist to recover from.
Future<T> never<T>() => Completer<T>().future;

Position positionAt({
  double latitude = 39.7186,
  double longitude = 140.1024,
  double accuracy = 12,
}) =>
    Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.utc(2026, 1, 15, 6, 30),
      accuracy: accuracy,
      altitude: 20,
      altitudeAccuracy: 5,
      heading: 0,
      headingAccuracy: 10,
      speed: 8,
      speedAccuracy: 1,
    );

void main() {
  const shortTimeout = Duration(milliseconds: 40);

  group('herPositionStream — platform-call timeouts (B20)', () {
    test('a service-enabled check that never answers becomes an honest '
        'PositionUnavailable, not silence', () async {
      final stream = herPositionStream(
        isServiceEnabled: never<bool>,
        platformCallTimeout: shortTimeout,
      );
      final fix = await stream.first.timeout(const Duration(seconds: 5));
      expect(fix, isA<PositionUnavailable>());
      expect(
        (fix as PositionUnavailable).reason,
        contains('service check timed out'),
      );
    });

    test('a permission CHECK that never answers becomes PositionUnavailable',
        () async {
      final stream = herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: never<LocationPermission>,
        platformCallTimeout: shortTimeout,
      );
      final fix = await stream.first.timeout(const Duration(seconds: 5));
      expect(fix, isA<PositionUnavailable>());
      expect(
        (fix as PositionUnavailable).reason,
        contains('permission check timed out'),
      );
    });

    test('a permission REQUEST that never answers becomes PositionUnavailable '
        '(bounded by its own, separate, generous timeout)', () async {
      final stream = herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: never<LocationPermission>,
        permissionRequestTimeout: shortTimeout,
      );
      final fix = await stream.first.timeout(const Duration(seconds: 5));
      expect(fix, isA<PositionUnavailable>());
      expect(
        (fix as PositionUnavailable).reason,
        contains('permission request timed out'),
      );
    });

    test('the permission-request timeout is the LONG one — a human reading a '
        'system dialog is not timed out by the 10 s programmatic bound',
        () async {
      // The programmatic timeout is tiny; the request timeout is long. If the
      // request were (wrongly) bounded by platformCallTimeout, this would
      // emit a timeout unavailability. It must instead deliver her answer.
      final stream = herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          return LocationPermission.whileInUse; // she said yes, slowly
        },
        positionStream: () => Stream<Position>.fromIterable([positionAt()]),
        platformCallTimeout: shortTimeout,
        permissionRequestTimeout: const Duration(seconds: 10),
      );
      final fix = await stream.first.timeout(const Duration(seconds: 5));
      expect(fix, isA<PositionAvailable>(),
          reason: 'Her slow-but-granted permission must yield her position, '
              'not a fabricated timeout.');
    });
  });

  group('herPositionStream — stream termination (B20 onDone)', () {
    test('platform stream ending surfaces as PositionUnavailable, never as '
        'the last dot frozen in silence', () async {
      final platform = StreamController<Position>();
      final events = <PositionFix>[];
      final sub = herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.always,
        positionStream: () => platform.stream,
      ).listen(events.add);

      platform.add(positionAt());
      await pumpEventQueue();
      expect(events.single, isA<PositionAvailable>());

      // The platform tears the stream down (provider gone, service killed).
      await platform.close();
      await pumpEventQueue();

      expect(events, hasLength(2));
      expect(events.last, isA<PositionUnavailable>());
      expect(
        (events.last as PositionUnavailable).reason,
        contains('GPS stream ended'),
      );
      await sub.cancel();
    });

    test('healthy path is untouched: fixes relay with the finite-coordinate '
        'chokepoint intact', () async {
      final events = <PositionFix>[];
      final sub = herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.always,
        positionStream: () => Stream<Position>.fromIterable([
          positionAt(),
          positionAt(latitude: double.nan), // degraded fix
        ]),
      ).listen(events.add);
      await pumpEventQueue();

      // 2 fixes + the onDone termination notice = 3 events.
      expect(events, hasLength(3));
      expect(events[0], isA<PositionAvailable>());
      expect(events[1], isA<PositionUnavailable>(),
          reason: 'NaN latitude must become honest unavailability '
              '(fixFromSample chokepoint), never a wrong dot.');
      expect(events[2], isA<PositionUnavailable>());
      await sub.cancel();
    });
  });
}
