/// OPS-066 render-SEE capture for the 1b tofu fix (plan 2026-07-25 §1) —
/// the ⚠ warning row rendered from the BUNDLED symbols subset, not tofu.
///
/// Produces `ladder_out/symbols_font/subzero_watch_row_symbols_ja.png`: the
/// REAL SngnavApp pumped with the sub-zero Chuo -2.4°C observation, so the
/// 路面凍結ウォッチ verdict row shows 「⚠ 路面凍結のおそれ（気温0°C以下）」.
/// Unlike every earlier capture (whose harness fonts lack U+26A0 and drew
/// □), this suite loads `assets/fonts/SnGNavSymbols.ttf` — the same bytes
/// the APK ships — under the family the app's ThemeData.fontFamilyFallback
/// names, so the PNG shows the actual glyph HER row falls back to.
///
/// HONEST BOUNDS: host-level render evidence only. It proves the shipped
/// bytes resolve ⚠ through the app's own theme fallback in a real widget
/// tree. On-device rendering (HER phone's own fallback chain ahead of ours)
/// is OPS-066 DEFERRED — no device/emulator in this env (AAE env-bound).
/// Existing capture suites deliberately do NOT load this font, so their
/// goldens stay pixel-stable (opt-in per render_see_env.dart).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';

import '../support/fake_alert_actuators.dart';

JmaObservation _subZeroObs() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: -2.4,
      humidityPercent: 95,
      windMetersPerSecond: 2.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260115063000',
      fetchedAt: DateTime(2026, 1, 15, 6, 30),
    );

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    // The point of THIS capture: the app-bundled symbols subset, loaded
    // under the exact family ThemeData.fontFamilyFallback names.
    final symbolsLoaded = await loadBundledSymbolsFont();
    if (!cjkLoaded || !symbolsLoaded) installNoopGoldenComparator();
    final tmp = await Directory.systemTemp.createTemp('fm_cache_symbols_font');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  testWidgets('the sub-zero watch row renders ⚠ from the bundled subset',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_subZeroObs()),
    ));
    await tester.pump();
    await tester.pump();

    // The ⚠-bearing verdict row from the real JMA panel.
    final row = find.text('⚠ 路面凍結のおそれ（気温0°C以下）');
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pump();
    // Capture the row's enclosing panel line so the PNG shows label + verdict
    // (the frame a human affirms per L32).
    await expectLater(
      find.ancestor(of: row, matching: find.byType(Padding)).first,
      matchesGoldenFile(
          '../../ladder_out/symbols_font/subzero_watch_row_symbols_ja.png'),
    );
  });
}
