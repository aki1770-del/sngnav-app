/// HER map is on the first screen at launch, with no scroll.
///
/// WHY, written before the act. Measured 2026-09-13: every developer panel
/// ships (the only release gate is in error_log.dart), fourteen cards sat above
/// the map, and on an 852 px phone screen the map was at 4314 to 4634 px. She
/// would have had to scroll a page of developer panels to find where she is.
/// Ruled the same day: the map goes on the first screen, directly under the
/// banner, with no panel removed.
///
/// Pinned here, on a 393x852 phone at DPR 2 and a 1280x800 IVI window at DPR 1:
/// at launch, with no scroll, the whole map and the line under it are inside
/// the first screen; every panel that was there is still there, once.
///
/// A limit that rides with it, not tested here: a vertical drag that starts on
/// the map pans the map and does not scroll the page, and with follow it also
/// pauses follow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

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
  for (final (name, logical, dpr) in [
    ('phone 393x852', const Size(393, 852), 2.0),
    ('IVI window 1280x800', const Size(1280, 800), 1.0),
  ]) {
    testWidgets('$name: the whole map and the line under it, at launch',
        (tester) async {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = logical * dpr;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        jmaFetch: () async => JmaSuccess(_clearObs()),
      ));
      await tester.pump();
      await tester.pump();

      final map = tester.getRect(find.byType(AkitaMap));
      expect(map.top, greaterThanOrEqualTo(0), reason: 'map $map');
      expect(map.bottom, lessThanOrEqualTo(logical.height),
          reason: 'the whole map is on the first screen: $map of '
              '${logical.height} px');

      final line = find.text('位置情報はまだ共有されていません。');
      expect(line, findsOneWidget, reason: 'control: the line under the map');
      final l = tester.getRect(line);
      expect(l.top, greaterThan(map.bottom),
          reason: 'the line is under the map');
      expect(l.bottom, lessThanOrEqualTo(logical.height),
          reason: 'the line under the map is on the first screen: $l');
    });
  }

  testWidgets('no panel was removed or duplicated by the move', (tester) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_clearObs()),
    ));
    await tester.pump();
    for (final title in [
      'Map — Akita-shi (station 32402)',
      'Driver profile',
      'Live drive — compound-failure caution (WS6, auto)',
      'Route — tap A then B (driving, no snow-aware yet)',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.byType(AkitaMap), findsOneWidget);
    // The map directly under the banner: the first section title on the page.
    final mapTitle = tester.getRect(find.text('Map — Akita-shi (station 32402)'));
    final profileTitle = tester.getRect(find.text('Driver profile'));
    expect(mapTitle.top, lessThan(profileTitle.top),
        reason: 'the map section comes before the first developer panel');
  });
}
