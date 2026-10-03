/// Render-and-look capture for the sub-zero frozen-surface GLANCE CHIP
/// (session-scope; NOT a CI pixel assertion) — decided 2026-07-23.
///
/// Produces `ladder_out/subzero_chip/subzero_frozen_chip_ja.png` so a human
/// LOOKS at the actual chip the deaf/whiteout driver would see on the glance
/// surface. Unlike a reproduced-widget capture, this pumps the REAL SngnavApp
/// with a sub-zero JMA observation and captures the REAL
/// `Key('subzero-frozen-chip')` widget from `_driveHudPanel` — so the pixels
/// are the app's own, icon (Icons.ac_unit, a Material glyph — never tofu) and
/// contrast (blue.900 on lightBlue.50, ~7.7:1) included.
///
/// The icons in this frame (the Icons.ac_unit snowflake, and the route control
/// further down) are drawn from MaterialIcons, which the app ships
/// (`uses-material-design: true`). From 2026-07-23 until 2026-10-02 this
/// capture drew both as empty squares, because `flutter test` leaves the app's
/// fonts out and this suite never loaded them. test/flutter_test_config.dart
/// now loads every font the app ships for every test, so the stored image
/// carries the real glyphs.
///
/// On-device render remains the emulator ladder / device hour's job (on-device
/// verification): nobody affirms this PNG as phone evidence, and on a fontless
/// host the comparator is a no-op.
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
      temperatureCelsius: -2.4, // the Chuo -2.4 C morning
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
    if (!cjkLoaded || !goldenPixelsComparableHere()) {
      installNoopGoldenComparator();
    }
    final tmp = await Directory.systemTemp.createTemp('fm_cache_subzero_chip');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  testWidgets('the sub-zero frozen-road glance chip, from the real app tree',
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

    final chip = find.byKey(const Key('subzero-frozen-chip'));
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.pump();
    // Capture the chip's own subtree (the Align that wraps the pill), so the
    // frame is the chip the driver sees, not the whole scroll.
    await expectLater(
      chip,
      matchesGoldenFile('../../ladder_out/subzero_chip/subzero_frozen_chip_ja.png'),
    );
  });
}
