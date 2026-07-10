/// W3 turmoil surface — WIRING tests over the injected JMA fetch.
///
/// Max honest in-env verification (same bound as fake_alert_actuators.dart):
/// proves the app EVALUATES the measured watch from a fetched observation,
/// RENDERS the verdict row with honest per-channel bounds, and FIRES the
/// transition-gated announce exactly once in the resolved spoken locale.
/// It does NOT prove the driver hears anything — on-device HEAR is the
/// device hour's job (OPS-066 DEFERRED-honest).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';

import '../support/fake_alert_actuators.dart';

JmaObservation _obs({double? precip10m, double? wind}) {
  return JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: 22.0,
    humidityPercent: 80,
    windMetersPerSecond: wind,
    snowDepthCm: null,
    precipitation10mMm: precip10m,
    visibilityMeters: null,
    observedAtJstKey: '20260710143000',
    fetchedAt: DateTime.now(),
  );
}

void main() {
  testWidgets('caution observation → 荒天ウォッチ row renders the verdict',
      (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_obs(precip10m: 4.0, wind: 12.0)),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('⚠ 強い雨・強めの風を観測中'), findsOneWidget);
    // The verbatim measured rain row renders beside the inference
    // (_kv renders labels with a trailing colon).
    expect(find.text('降水量（10分間）:'), findsOneWidget);
    expect(find.text('4.0 mm'), findsOneWidget);
  });

  testWidgets('partial abstain renders the honest per-channel bound',
      (tester) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_obs(precip10m: 0.0, wind: null)),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('該当なし（風は判定不能）'), findsOneWidget);
  });

  testWidgets(
      'transition gate: announce fires ONCE on rise, not per fetch (ja)',
      (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_obs(precip10m: 4.0, wind: 2.0)),
    ));
    await tester.pump();
    await tester.pump();

    final turmoilLines =
        fake.spoken.where((s) => s.text.contains('強い雨')).toList();
    expect(turmoilLines, hasLength(1),
        reason: 'the rising transition announces exactly once');
    expect(turmoilLines.single.localeTag, 'ja-JP');
    expect(turmoilLines.single.text, contains('おそれ'));

    // Second fetch with the SAME caution: the window persists — no repeat
    // (cry-wolf discipline).
    await tester.tap(find.text('Re-fetch'));
    await tester.pump();
    await tester.pump();
    expect(
      fake.spoken.where((s) => s.text.contains('強い雨')),
      hasLength(1),
      reason: 'no re-announce while the window persists',
    );
  });

  testWidgets('spoken lane follows the resolved locale (en)', (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('en'),
      jmaFetch: () async => JmaSuccess(_obs(precip10m: 4.0, wind: 2.0)),
    ));
    await tester.pump();
    await tester.pump();

    final turmoilLines =
        fake.spoken.where((s) => s.text.contains('Heavy rain')).toList();
    expect(turmoilLines, hasLength(1));
    expect(turmoilLines.single.localeTag, 'en-US');
  });

  testWidgets(
      'fetch failure → honest failure card (no watch rows), and no announce',
      (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      jmaFetch: () async => const JmaFailure('offline'),
    ));
    await tester.pump();
    await tester.pump();

    // On fetch failure the panel shows the explicit failure card (staleness
    // must be visible; cached data is never shown) and NO watch rows — same
    // discipline as the existing 路面凍結ウォッチ behavior.
    expect(find.textContaining('JMA fetch failed'), findsOneWidget);
    expect(find.text('荒天ウォッチ:'), findsNothing);
    expect(fake.spoken, isEmpty);
  });

  testWidgets('success with both fields unreported → 判定不能 row',
      (tester) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_obs(precip10m: null, wind: null)),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('判定不能（降水・風の観測値が不足）'), findsOneWidget);
  });
}
