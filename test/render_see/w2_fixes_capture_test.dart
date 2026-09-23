/// Render-and-look captures for the emulator-ladder fix list (session-scope;
/// NOT a CI assertion) — produces PNGs into `ladder_out/api30_fixed/` so a reviewer
/// can LOOK at the fixed surfaces beside the 2026-07-09 ladder evidence:
///
///   ladder_out/api30/02b_location_consent.png  → w2a_consent_card_en.png
///   (+ the same card on the ja surface         → w2a_consent_card_ja.png)
///
///   ladder_out/api30/05b_airplane_top.png      → w2c_threshold_preview.png
///
/// ⚑⚑ WHAT THE TWO w2a FRAMES HOLD CHANGED ON 2026-09-23 AND THE PIXELS ARE
/// RED UNTIL SOMEONE SAYS SO. They were cut when the consent card was ONE
/// object — the status line, the share control, and both disclosure paragraphs
/// together, which is exactly the 02b ladder defect they exist to show fixed.
/// HIE R119 moved the paragraphs into a card of their own below the caution
/// card, so each frame now holds THREE cards: the control card (status line +
/// 現在地を共有, and nothing else), the caution card, and 端末の外へ出る情報.
/// The reflow is the whole of the pixel diff — 20.47% (ja) and 14.72% (en),
/// each bounding box running from the change point to the frame's bottom edge.
///
/// ⚑ NOT RECUT HERE, DELIBERATELY. A `--update-goldens` sweep would turn these
/// green under a name and a header that had become false, which is worse than
/// the red. Before they are recut, either this description and the test names
/// must say what the frames hold, or the captures must be re-targeted so they
/// hold the control and the words at once. This paragraph is the first of those
/// two, done now; the second is a design question that belongs to AAA's ruling
/// on whether the control and the disclosure should stand together at all. The
/// relationship itself is no longer carried by these pictures: it is asserted
/// in `test/support/consent_composition.dart` and
/// `test/widgets/consent_composition_declared_test.dart`, which fail in BOTH
/// directions.
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
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart';

import '../support/developer_page.dart';

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    // 2026-10-06: this phone CAN post her a notification. The card's drive
    // words now follow what the app knows about posting
    // (test/widgets/drive_promise_follows_can_post_test.dart); these captures
    // record the card under the can-post promise, the words they were taken
    // with. Unmocked, the frame is taken before the notification read
    // answers, so the app has no reading and draws the not-known-yet words
    // (measured 2026-10-07; given real async time, an unmocked read answers
    // "cannot post").
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('sngnav/notification_permission'),
      (call) async => call.method == 'read'
          ? <String, Object>{
              'granted': true,
              'enabled': true,
              'needsRuntimeRequest': false,
            }
          : true,
    );
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded || !goldenPixelsComparableHere()) {
      installNoopGoldenComparator();
    }
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

  // Name states what the frame holds since 2026-09-23: the control card, the
  // caution card, and the disclosure card, in that order. It is NOT "the
  // consent card" any more.
  testWidgets('w2a — the control card, the caution card and the disclosure '
      'card, in that order (en, ladder locale)', (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('en')));
    await tester.pump();
    // Guard before capturing: the status line renders as ONE sentence line
    // above the buttons (the 02b defect was one-syllable-per-line).
    expect(find.text('Location is not being shared.'), findsOneWidget);
    await captureApp(
      tester,
      targets: [
        find.byKey(const Key('location-disclosure')),
        find.text('Location is not being shared.'),
      ],
      logical: const Size(393, 852),
      out: '../../ladder_out/api30_fixed/w2a_consent_card_en.png',
    );
  });

  testWidgets('w2a — the control card, the caution card and the disclosure '
      'card, in that order (ja surface)', (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
    await tester.pump();
    await captureApp(
      tester,
      targets: [
        find.byKey(const Key('location-disclosure')),
        find.text('位置情報は共有されていません。'),
      ],
      logical: const Size(393, 852),
      out: '../../ladder_out/api30_fixed/w2a_consent_card_ja.png',
    );
  });

  testWidgets('w2c — threshold-preview labels readable at phone width',
      (tester) async {
    // The thresholds card is on the development page (2026-09-15); this
    // capture is of that page now. A release build never offers that page,
    // so this golden documents a developer surface, not her screen.
    await tester.pumpWidget(
        const SngnavApp(locale: Locale('en'), developerPageEntry: true));
    await tester.pump();
    await openDeveloperPage(tester);
    final preview =
        find.text(const AppL10n(Locale('en')).warningThresholdsSectionTitle);
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
