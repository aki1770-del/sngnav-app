/// RECORDED, NOT RULED: what a position stream alternating measured and
/// unmeasured samples does to her.
///
/// Why, written before the act (2026-09-14). A sample whose accuracy the
/// platform did not measure is not a fix: the drive brain degrades at it, and
/// the map stops drawing a confident mark. In a measured clear sky a measured
/// fix gives no caution, so a stream alternating the two once a second makes
/// every unmeasured sample a new rise of the caution rung, and the drive brain
/// announces every rise. Measured by the audit before this landing, and again
/// on this landing: 30 spoken cautions, 30 warning haptics and 59 changes of
/// her mark in 60 s, where the same stream all measured gives none, and where
/// the app before this landing gave none because it drew the placeholder as a
/// measured 0 m ring.
///
/// Whether any platform alternates like this is UNVERIFIED: Android decides
/// per fix whether to send an accuracy, iOS and Windows always send one, web
/// and Linux never do. Whether this is acceptable is not decided here. This
/// file pins what the app does, so a decision that changes it changes a named
/// test. Nothing here adds or removes a sound.
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

final _start = DateTime.utc(2026, 1, 14, 21);
var _now = _start;

Position _sample(DateTime t, {required bool measured}) => Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: t,
      accuracy: measured ? 10 : 0,
      hasAccuracy: measured,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Warm, calm, dry and clear: no measured-weather watch fires.
JmaResult _clear1500() => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: 1500,
      observedAtJstKey: '20260115060000',
      fetchedAt: _start,
    ));

const _caution = '速度を落とし、車間を広げて、前方に注意してください。';

/// One sample a second for 60 s; returns (spoken cautions, warning haptics,
/// changes between a confident mark and not).
Future<(int, int, int)> _minute(WidgetTester tester,
    {required bool alternate}) async {
  final a = FakeAlertActuators();
  _now = _start;
  final platform = StreamController<Position>();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: const Locale('ja'),
    clock: () => _now,
    jmaFetch: () async => _clear1500(),
    positionSource: () => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => platform.stream,
    ),
  ));
  await tester.pump();
  await tester.pump();
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  bool? last;
  var changes = 0;
  for (var i = 0; i < 60; i++) {
    platform.add(_sample(_now, measured: !alternate || i.isEven));
    for (var k = 0; k < 5; k++) {
      await tester.pump();
    }
    final m = tester.widget<AkitaMap>(find.byType(AkitaMap));
    final confident =
        m.herPosition != null && !m.positionDegraded && !m.positionLost;
    if (last != null && last != confident) changes++;
    last = confident;
    _now = _now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }
  await platform.close();
  return (
    a.spoken.where((s) => '$s'.contains(_caution)).length,
    a.haptics.where((h) => '$h' == 'HapticCuePattern.warning').length,
    changes,
  );
}

void main() {
  testWidgets(
      'recorded, not decided: in a measured clear 1,500 m, samples alternating '
      'measured and unmeasured once a second give 30 spoken cautions, 30 '
      'warning haptics and 59 changes of her mark in 60 s', (tester) async {
    final allMeasured = await _minute(tester, alternate: false);
    expect(allMeasured, (0, 0, 0),
        reason: 'control: the same stream, every sample measured');
    final alternating = await _minute(tester, alternate: true);
    expect(alternating, (30, 30, 59));
  });
}
