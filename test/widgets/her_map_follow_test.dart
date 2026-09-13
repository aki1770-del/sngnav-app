/// HER map's camera follows her on trusted fixes, and only there.
///
/// WHY, written before the act. Measured 2026-09-13 in the real app, driving
/// 144 fixes along Route 13 out of Akita city: the camera never left the
/// station. Her point left the phone map at 7.6 km and no mark of her remained
/// from 8.2 km to 19.9 km, in a real fix, dead reckoning, lost and a stream
/// error alike. Words at the top of the map now say when her mark is off it;
/// this is the other half, under rules set before it was built:
///
/// * the camera moves to her on TRUSTED fixes only. It never moves on dead
///   reckoning, lost, an unavailability, the dev mock or an anchor from a
///   previous session: it holds, and since it followed her until GPS died,
///   the ring stays in view;
/// * a hand on the map pauses follow (the machine yields to the person), and
///   only her return-to-position control resumes it;
/// * zoom stays inside the bundled offline archive: follow never leaves z8 to
///   z12, the band the archive holds across the whole prefecture.
///
/// Road points are from the same drive (OpenStreetMap, ODbL): index, then
/// distance along the road.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

const _r13At0km = LatLng(39.7109369, 140.0902946); // idx 0, 0.0 km
const _r13At4km = LatLng(39.6878127, 140.1243230); // idx 29, 4.0 km
const _r13At8km = LatLng(39.6720544, 140.1572568); // idx 58, 8.1 km
const _r13At8_2km = LatLng(39.6714637, 140.1586867); // idx 59, 8.2 km
const _r13At20km = LatLng(39.6469828, 140.2833640); // idx 143, 19.9 km

const _returnKey = Key('her-map-return-to-position');
const _realDotKey = ValueKey('her-dot-real-fix');
const _ringKey = ValueKey('her-dot-degraded');
const _unknownKey = ValueKey('her-position-unknown-label');
const _offMapKey = ValueKey('her-position-off-map-label');

JmaObservation _clearObs() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 15.0,
      humidityPercent: 30,
      windMetersPerSecond: 1.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260115063000',
      fetchedAt: DateTime(2026, 7, 15, 6, 30),
    );

void main() {
  final start = DateTime.utc(2026, 1, 14, 21, 0);
  var now = start;
  late StreamController<PositionFix> positions;

  Future<void> pumpApp(WidgetTester tester) async {
    now = start;
    positions = StreamController<PositionFix>.broadcast();
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      clock: () => now,
      jmaFetch: () async => JmaSuccess(_clearObs()),
      positionSource: () => positions.stream,
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pump();
    await tester.tap(find.text(text));
    await tester.pump();
  }

  /// A trusted fix at [p], [seconds] after the start of the drive.
  Future<void> fixAt(WidgetTester tester, LatLng p, int seconds) async {
    now = start.add(Duration(seconds: seconds));
    positions.add(PositionAvailable(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyMeters: 15,
      timestamp: now,
    ));
    await tester.pump();
    await tester.pump();
  }

  /// No fix for [silence] after [lastFixSeconds]: the watchdog polls.
  Future<void> silence(
      WidgetTester tester, int lastFixSeconds, Duration silence) async {
    now = start.add(Duration(seconds: lastFixSeconds)).add(silence);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
  }

  final flutterMap = find.byType(FlutterMap);

  MapCamera camera(WidgetTester tester) => MapCamera.of(tester.element(
      find.descendant(of: flutterMap, matching: find.byType(MarkerLayer))));

  void expectCameraAt(WidgetTester tester, LatLng p, {String? reason}) {
    final c = camera(tester).center;
    expect(c.latitude, closeTo(p.latitude, 1e-7), reason: reason);
    expect(c.longitude, closeTo(p.longitude, 1e-7), reason: reason);
  }

  bool onMap(WidgetTester tester, Key key) {
    final f = find.byKey(key);
    return f.evaluate().isNotEmpty &&
        tester.getRect(find.byType(AkitaMap)).overlaps(tester.getRect(f));
  }

  Future<void> handDrag(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(AkitaMap));
    await tester.pump();
    await tester.drag(flutterMap, const Offset(-160, 0));
    for (var k = 0; k < 10; k++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> handWheel(WidgetTester tester, double dy) async {
    await tester.ensureVisible(find.byType(AkitaMap));
    await tester.pump();
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final centre = tester.getCenter(flutterMap);
    await tester.sendEventToBinding(pointer.hover(centre));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  Future<void> tapReturn(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_returnKey));
    await tester.pump();
    await tester.tap(find.byKey(_returnKey));
    await tester.pump();
  }

  group('trusted fixes: the camera follows her', () {
    testWidgets('19.9 km along Route 13, her dot stays on the map at each fix',
        (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      expectCameraAt(tester, akitaStation, reason: 'control: starts there');

      var t = 0;
      for (final p in [_r13At0km, _r13At4km, _r13At8_2km, _r13At20km]) {
        await fixAt(tester, p, t += 10);
        expectCameraAt(tester, p);
        expect(camera(tester).zoom, 12);
        expect(onMap(tester, _realDotKey), isTrue,
            reason: 'her dot is on the map she sees');
        expect(find.byKey(_offMapKey), findsNothing);
      }
      await positions.close();
    });
  });

  group('everything else: the camera holds', () {
    testWidgets(
        'dead reckoning then lost at 19.9 km: the camera holds at her last '
        'trusted fix, so the ring stays in view', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At8km, 10);
      await fixAt(tester, _r13At20km, 20);

      await silence(tester, 20, const Duration(seconds: 60));
      expect(find.byKey(_ringKey), findsOneWidget,
          reason: 'control: dead reckoning');
      expectCameraAt(tester, _r13At20km);
      expect(onMap(tester, _ringKey), isTrue);

      await silence(tester, 20, const Duration(seconds: 180));
      expect(onMap(tester, _unknownKey), isTrue, reason: 'control: lost');
      expectCameraAt(tester, _r13At20km);
      expect(onMap(tester, _ringKey), isTrue);
      await positions.close();
    });

    testWidgets('a GPS stream error: the camera holds', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At8_2km, 10);
      positions.addError(StateError('platform GPS stream failed'));
      await tester.pump();
      await tester.pump();

      expectCameraAt(tester, _r13At8_2km);
      expect(onMap(tester, _ringKey), isTrue);
      await positions.close();
    });

    testWidgets(
        'a trusted fix too imprecise to be confident (lost on arrival): the '
        'camera does not move to it', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At4km, 10);
      now = start.add(const Duration(seconds: 20));
      positions.add(PositionAvailable(
        latitude: _r13At20km.latitude,
        longitude: _r13At20km.longitude,
        accuracyMeters: 900,
        timestamp: now,
      ));
      await tester.pump();
      await tester.pump();

      expect(onMap(tester, _unknownKey), isTrue, reason: 'control: lost');
      expectCameraAt(tester, _r13At4km);
      await positions.close();
    });

    testWidgets(
        'a fix older than her last trusted one looks like a fix and is not '
        'trusted: the camera holds', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At8_2km, 20);
      expectCameraAt(tester, _r13At8_2km, reason: 'control: followed her');
      // Stamped 10 s before the trusted fix above, at another place.
      positions.add(PositionAvailable(
        latitude: _r13At20km.latitude,
        longitude: _r13At20km.longitude,
        accuracyMeters: 15,
        timestamp: start.add(const Duration(seconds: 10)),
      ));
      await tester.pump();
      await tester.pump();
      expectCameraAt(tester, _r13At8_2km);
      await positions.close();
    });

    testWidgets(
        'a fix with accuracy -1 looks like a fix and is not trusted: the '
        'camera holds', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At4km, 10);
      now = start.add(const Duration(seconds: 20));
      positions.add(PositionAvailable(
        latitude: _r13At20km.latitude,
        longitude: _r13At20km.longitude,
        accuracyMeters: -1,
        timestamp: now,
      ));
      await tester.pump();
      await tester.pump();
      expectCameraAt(tester, _r13At4km);
      await positions.close();
    });

    testWidgets(
        'following, then the dev mock: the camera stays at her last fix and '
        'does not go to the station', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At8_2km, 10);
      await tapText(tester, '停止');

      await tester.ensureVisible(find.byKey(const Key('use-mock-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('use-mock-button')));
      await tester.pump();
      await tester.pump();

      expect(tester.widget<AkitaMap>(find.byType(AkitaMap)).herPosition,
          akitaStation,
          reason: 'control: the mock is drawn');
      expectCameraAt(tester, _r13At8_2km);
      expect(find.byKey(_returnKey), findsNothing);
      await positions.close();
    });

    testWidgets(
        'the dev mock never moves the camera, and offers no return, even with '
        'follow paused by hand', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At8_2km, 10);
      expectCameraAt(tester, _r13At8_2km, reason: 'control: followed her');
      await handDrag(tester);
      expect(find.byKey(_returnKey), findsOneWidget, reason: 'control: paused');
      final handPut = camera(tester).center;
      await tapText(tester, '停止');

      await tester.ensureVisible(find.byKey(const Key('use-mock-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('use-mock-button')));
      await tester.pump();

      expect(tester.widget<AkitaMap>(find.byType(AkitaMap)).herPosition,
          akitaStation,
          reason: 'control: the mock is drawn');
      expectCameraAt(tester, handPut);
      expect(find.byKey(_returnKey), findsNothing,
          reason: 'nothing to return to in mock');
      await positions.close();
    });
  });

  group('a hand pauses follow; only her return control resumes it', () {
    // Amended 2026-09-14: a touch on her map sets no route point (ruled that
    // day). Until then this test's control was that the same gesture set
    // route start A, which it did at 7e9cd29: so this gesture resolves as a
    // tap, and a map that set a point on a tap would fail the check below.
    testWidgets(
        'a touch pauses follow the moment her finger lands: a trusted fix '
        'arriving under her finger leaves the camera where it was; the tap '
        'sets no route point; return then brings her back', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At0km, 10);
      expectCameraAt(tester, _r13At0km, reason: 'control: followed her');

      await tester.ensureVisible(find.byType(AkitaMap));
      await tester.pump();
      final touch = await tester
          .startGesture(tester.getCenter(flutterMap) + const Offset(-60, 40));
      await tester.pump(const Duration(milliseconds: 40));
      await fixAt(tester, _r13At8_2km, 20);
      expectCameraAt(tester, _r13At0km,
          reason: 'nothing moves under her finger');
      await touch.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
          find.descendant(
              of: find.byType(AkitaMap), matching: find.text('A')),
          findsNothing,
          reason: 'a touch on her map sets no route point');
      expectCameraAt(tester, _r13At0km, reason: 'still paused after the tap');
      expect(find.byKey(_returnKey), findsOneWidget);

      await fixAt(tester, _r13At20km, 30);
      expectCameraAt(tester, _r13At0km, reason: 'paused: no fix moves it');

      await tapReturn(tester);
      expectCameraAt(tester, _r13At20km, reason: 'return brings her back');
      await positions.close();
    });

    testWidgets(
        'a drag pauses; the next trusted fix leaves the camera where her hand '
        'put it; return brings it to her and follow resumes', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At0km, 10);
      expectCameraAt(tester, _r13At0km);
      expect(find.byKey(_returnKey), findsNothing,
          reason: 'following: no return control');

      await handDrag(tester);
      final handPut = camera(tester).center;
      expect(handPut.longitude, isNot(closeTo(_r13At0km.longitude, 1e-4)),
          reason: 'control: the drag moved the camera');
      expect(find.byKey(_returnKey), findsOneWidget);

      await fixAt(tester, _r13At8_2km, 20);
      expectCameraAt(tester, handPut, reason: 'paused: the camera is hers');
      expect(onMap(tester, _offMapKey), isTrue,
          reason: 'her mark is off the map she moved, and the map says so');

      await tapReturn(tester);
      expectCameraAt(tester, _r13At8_2km);
      expect(camera(tester).zoom, 12);
      expect(find.byKey(_returnKey), findsNothing);
      expect(find.byKey(_offMapKey), findsNothing);

      await fixAt(tester, _r13At20km, 30);
      expectCameraAt(tester, _r13At20km, reason: 'follow resumed');
      await positions.close();
    });

    testWidgets(
        'return while lost: the camera goes back to her last trusted fix, '
        'where the ring is', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At8_2km, 10);
      await handDrag(tester);
      await silence(tester, 10, const Duration(seconds: 180));
      expect(find.byKey(_unknownKey), findsOneWidget, reason: 'control: lost');

      await tapReturn(tester);
      expectCameraAt(tester, _r13At8_2km);
      expect(onMap(tester, _ringKey), isTrue);
      await positions.close();
    });

    testWidgets(
        'return in a new session with no trusted fix yet: the camera does not '
        'go to the previous session\'s place; the next trusted fix moves it',
        (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At20km, 10);
      await tapText(tester, '停止');
      await handDrag(tester);
      final handPut = camera(tester).center;

      await tapText(tester, '現在地を共有');
      positions.add(const PositionUnavailable('Location services disabled'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_returnKey), findsOneWidget,
          reason: 'sharing, and paused by her hand');

      await tapReturn(tester);
      expectCameraAt(tester, handPut,
          reason: 'no position from this session to return to');
      expect(find.byKey(_returnKey), findsNothing, reason: 'follow resumed');

      await fixAt(tester, _r13At0km, 20);
      expectCameraAt(tester, _r13At0km);
      await positions.close();
    });

    testWidgets(
        'a wheel zoom is a hand too; return comes back at z12 at most and z8 '
        'at least, inside the offline archive', (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await fixAt(tester, _r13At4km, 10);

      await handWheel(tester, -400); // two levels in
      expect(camera(tester).zoom, greaterThan(12), reason: 'control: zoomed');
      expect(find.byKey(_returnKey), findsOneWidget);
      await tapReturn(tester);
      expectCameraAt(tester, _r13At4km);
      expect(camera(tester).zoom, 12);

      await handWheel(tester, 1000); // five levels out
      expect(camera(tester).zoom, lessThan(8), reason: 'control: zoomed out');
      await tapReturn(tester);
      expect(camera(tester).zoom, 8);
      expectCameraAt(tester, _r13At4km);
      await positions.close();
    });
  });
}
