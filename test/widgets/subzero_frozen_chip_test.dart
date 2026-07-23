/// The sub-zero frozen-surface GLANCE CHIP (Chair ruling 2026-07-23: "add a
/// calm glance chip"). The deaf / HoH / can't-hear-over-the-wind driver cannot
/// receive the spoken sub-zero warning; this chip gives her the frozen-road
/// WHAT on the surface she watches — WITHOUT raising the caution banner/rung
/// (that stays gated on `watch` alone, so sub-zero does not cry-wolf every cold
/// morning).
///
/// This pins three properties end-to-end in the real app tree:
///   1. sub-zero → the chip is PRESENT (the deaf driver gets a visible WHAT);
///   2. a non-sub-zero verdict → the chip is ABSENT (no false frozen-road claim);
///   3. sub-zero does NOT raise the caution banner above its baseline — the
///      calm-treatment / anti-cry-wolf invariant the Chair chose.
///
/// It does NOT prove she SEES it on a phone (OPS-066 / AAE-1 device-deferred).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';

import '../support/fake_alert_actuators.dart';

JmaObservation _obs({
  required double temp,
  int? humidity = 70,
  double? precip10m = 0.0,
}) =>
    JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: temp,
      humidityPercent: humidity,
      windMetersPerSecond: 2.0,
      snowDepthCm: null,
      precipitation10mMm: precip10m,
      visibilityMeters: null,
      observedAtJstKey: '20260115063000',
      fetchedAt: DateTime(2026, 1, 15, 6, 30),
    );

void main() {
  const chipKey = Key('subzero-frozen-chip');
  const bannerKey = Key('drive-hud-caution-banner');

  testWidgets('sub-zero → the calm frozen-road chip is present (ja)',
      (tester) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_obs(temp: -3.0)),
    ));
    await tester.pump();
    await tester.pump();

    final chip = find.byKey(chipKey);
    expect(chip, findsOneWidget,
        reason: 'the deaf/whiteout driver gets a frozen-road WHAT on the '
            'glance surface');
    expect(find.descendant(of: chip, matching: find.text('路面凍結のおそれ')),
        findsOneWidget);

    // Anti-cry-wolf invariant: sub-zero must NOT drive the caution banner to a
    // caution rung. The banner may exist (baseline/unknown-visibility), but it
    // must not read either caution headline purely because it is cold.
    final banner = find.byKey(bannerKey);
    expect(find.descendant(of: banner, matching: find.text('注意して走行')),
        findsNothing,
        reason: 'sub-zero is calm-treatment: the chip carries the meaning, the '
            'rung is not raised');
    expect(find.descendant(of: banner, matching: find.text('停車の検討')),
        findsNothing);
  });

  testWidgets('a warm dry-air CLEAR morning → the chip is absent',
      (tester) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_obs(temp: 8.0)),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(chipKey), findsNothing,
        reason: 'no frozen-road chip when the road is not sub-zero — never a '
            'false frozen-road claim');
  });

  testWidgets('the chip shows even when the humidity leaf dropped (the Chuo '
      'leaf-drop case still reaches the deaf driver visually)', (tester) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_obs(temp: -2.4, humidity: null)),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(chipKey), findsOneWidget,
        reason: 'the sub-zero verdict is robust to a dropped humidity leaf, and '
            'so is the deaf driver\'s visual channel');
  });
}
