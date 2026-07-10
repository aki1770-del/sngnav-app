/// OPS-066 render-SEE captures for the W3 turmoil surface (session-scope;
/// NOT a CI pixel assertion) — produces PNGs into `ladder_out/w3_turmoil/`
/// so the reviewer can LOOK at the new rows before the change lands:
///
///   w3_turmoil_caution_ja.png — both measured channels in caution
///   w3_turmoil_abstain_ja.png — partial abstain (wind unreported)
///
/// Run with:
///   flutter test --update-goldens test/render_see/w3_turmoil_capture_test.dart
///
/// The injected [SngnavApp.jmaFetch] supplies a canned observation, so the
/// REAL panel (verbatim fields + watch rows + derived caption) renders
/// hermetically — the same code path a live fetch drives. On-device render
/// remains the emulator ladder / device hour's job.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';

import '../support/fake_alert_actuators.dart';

JmaObservation _obs({double? precip10m, double? wind}) {
  return JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: 22.5,
    humidityPercent: 85,
    windMetersPerSecond: wind,
    snowDepthCm: null,
    precipitation10mMm: precip10m,
    visibilityMeters: null,
    observedAtJstKey: '20260710143000',
    fetchedAt: DateTime(2026, 7, 10, 14, 32),
  );
}

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    final tmp = await Directory.systemTemp.createTemp('fm_cache_w3');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  Future<void> capture(
    WidgetTester tester, {
    required Future<JmaResult> Function() jmaFetch,
    required String guardRowText,
    required String out,
  }) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: jmaFetch,
    ));
    await tester.pump();
    await tester.pump();
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    // Guard, then bring the JMA card block into view (bottom-most last-wins
    // alignment discipline from w2_fixes_capture_test.dart).
    expect(find.text(guardRowText), findsOneWidget);
    await tester.ensureVisible(find.textContaining('荒天ウォッチ likewise'));
    await tester.pump();
    await tester.ensureVisible(find.text('荒天ウォッチ:'));
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(out));
  }

  testWidgets('w3 — 荒天ウォッチ both-caution render (ja)', (tester) async {
    await capture(
      tester,
      jmaFetch: () async => JmaSuccess(_obs(precip10m: 4.5, wind: 12.3)),
      guardRowText: '⚠ 強い雨・強めの風を観測中',
      out: '../../ladder_out/w3_turmoil/w3_turmoil_caution_ja.png',
    );
  });

  testWidgets('w3 — 荒天ウォッチ honest partial abstain render (ja)',
      (tester) async {
    await capture(
      tester,
      jmaFetch: () async => JmaSuccess(_obs(precip10m: 0.0, wind: null)),
      guardRowText: '該当なし（風は判定不能）',
      out: '../../ladder_out/w3_turmoil/w3_turmoil_abstain_ja.png',
    );
  });
}
