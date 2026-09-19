/// Audit vector for the unmeasured-accuracy decision (2026-09-14).
///
/// Why, written before the act. The decision reads a position's accuracy only
/// when the platform flags it, and says in the same clause: "A flagged 0.0 is
/// believed." The only test of that clause binds a reading function that the
/// decision's own reference landing calls only for the stop reading, never on
/// the path from the position stream to her map. A landing that writes "> 0"
/// where the stream path needs ">= 0" passes every one of the decision's tests
/// (measured). This vector states the clause where it acts: through the app's
/// own position stream, onto what her map is told.
///
/// Audit instrument only: not the fix, and not a re-authoring of the decision.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

void main() {
  testWidgets(
    'V-g: a flagged 0.0 through the position stream is a measurement: the map '
    'is told a confident mark with a 0 m ring',
    (tester) async {
      final start = DateTime.utc(2026, 1, 14, 21);
      final platform = StreamController<Position>();
      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        clock: () => start,
        jmaFetch: () async => const JmaFailure('vector: no observation'),
        positionSource: () => herPositionStream(
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.whileInUse,
          positionStream: () => platform.stream,
        ),
      ));
      await tester.pump();
      await tester.pump();
      final b = find.byKey(const Key('share-location-button'));
      await tester.ensureVisible(b);
      await tester.pump();
      await tester.tap(b);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      platform.add(Position(
        latitude: 39.7186,
        longitude: 140.1024,
        timestamp: start,
        accuracy: 0,
        hasAccuracy: true,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      final m = tester.widget<AkitaMap>(find.byType(AkitaMap));
      expect(
        (
          lat: m.herPosition?.latitude,
          ring: m.herAccuracyMeters,
          degraded: m.positionDegraded,
          lost: m.positionLost,
        ),
        (lat: 39.7186, ring: 0.0, degraded: false, lost: false),
      );
      await platform.close();
    },
  );
}
