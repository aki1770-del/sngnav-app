/// OPS-066 render-SEE captures for the W2 ladder fix-list (session-scope;
/// NOT a CI assertion) — produces PNGs into `ladder_out/api30_fixed/` so VAA
/// can LOOK at the fixed surfaces beside the 2026-07-09 ladder evidence:
///
///   ladder_out/api30/02b_location_consent.png  → w2a_consent_card_en.png
///   (+ the same card on HER ja surface         → w2a_consent_card_ja.png)
///   ladder_out/api30/05b_airplane_top.png      → w2c_threshold_preview.png
///
/// Run with:
///   flutter test --update-goldens test/render_see/w2_fixes_capture_test.dart
///
/// The viewport is phone-shaped (393 logical wide — the ladder emulator's
/// 1080 px at 2.75x) so the captures reproduce the geometry the defects
/// were seen in. The 路面凍結ウォッチ row (03_jma_card.png) rides the same
/// `_kv` code path as the threshold preview; it only renders on a live JMA
/// success, so its re-render is verified on the next emulator ladder.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/main.dart';

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    // flutter_map's tile cache calls path_provider on first build; give it a
    // real temp dir (same env note as capture_test.dart).
    final tmp = await Directory.systemTemp.createTemp('fm_cache_w2_fixes');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  /// Scroll each of [targets] into view IN ORDER (the last call wins the
  /// final minimal alignment, so list the block's TOP element last), then
  /// capture the whole app frame.
  Future<void> captureApp(
    WidgetTester tester, {
    required List<Finder> targets,
    required Size logical,
    required String out,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = Size(logical.width * 2, logical.height * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    for (final target in targets) {
      await tester.ensureVisible(target);
      await tester.pump();
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(out));
  }

  testWidgets('w2a — consent card reflowed (en, ladder locale)',
      (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('en')));
    await tester.pump();
    // Guard before capturing: the status line renders as ONE sentence line
    // above the buttons (the 02b defect was one-syllable-per-line).
    expect(find.text('Location not yet shared.'), findsOneWidget);
    await captureApp(
      tester,
      targets: [
        find.byKey(const Key('location-disclosure')),
        find.text('Location not yet shared.'),
      ],
      logical: const Size(393, 852),
      out: '../../ladder_out/api30_fixed/w2a_consent_card_en.png',
    );
  });

  testWidgets('w2a — consent card reflowed (ja, HER surface)', (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
    await tester.pump();
    await captureApp(
      tester,
      targets: [
        find.byKey(const Key('location-disclosure')),
        find.text('位置情報はまだ共有されていません。'),
      ],
      logical: const Size(393, 852),
      out: '../../ladder_out/api30_fixed/w2a_consent_card_ja.png',
    );
  });

  testWidgets('w2c — threshold-preview labels readable at phone width',
      (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('en')));
    await tester.pump();
    final preview = find.textContaining('Threshold preview');
    await captureApp(
      tester,
      targets: [
        // Bottom-most row first, then the title — the block lands in view.
        find.text('With-vehicle warning temperature:'),
        preview,
      ],
      logical: const Size(393, 852),
      out: '../../ladder_out/api30_fixed/w2c_threshold_preview.png',
    );
  });
}
