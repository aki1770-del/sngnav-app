/// Render-and-look captures for the Tier-1 voice-channel hardening surfaces
/// (session-scope; NOT a CI pixel assertion) — produces PNGs into
/// `ladder_out/voice_lane/` so the reviewer can LOOK before the change lands:
///
///   voice_lane_caution_ja.png — pre-drive オフライン音声未インストール caution
///   speech_unverified_chip_ja.png — drive HUD 音声警告を確認できませんでした chip
///
/// Run with:
///   flutter test --update-goldens test/render_see/voice_lane_capture_test.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/voice_lane_readiness.dart';

import '../support/fake_alert_actuators.dart';

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    // ⚑ THE ICON FONT, ADDED 2026-09-23 AFTER HIE LOOKED AT THIS GOLDEN.
    //
    // This capture loaded CJK faces under 'Roboto' and never loaded
    // MaterialIcons, which `flutter test` does not load by itself. So three
    // Icons.* glyphs in the frame rendered as hollow boxes: the caution row's
    // leading Icons.volume_off_outlined, the route-set control, and the map's
    // station pin (a square outline where the app draws a teardrop).
    //
    // WHY THAT IS THE SEVERE CASE AND NOT THE MILD ONE — HIE's own rule,
    // sharpened by this frame. The standing reading was that a glyph which
    // fails to load renders as NOTHING, and nothing looks like a clean design.
    // Here it rendered as an EMPTY CHECKBOX — a control affordance — at the
    // head of a row whose subject is that her spoken warnings may not sound,
    // in place of the one mark that said this row is about SOUND. Something
    // wrong looking like a control is worse than something missing looking
    // like restraint.
    //
    // It compounds with a property of goldens this repo already knows: a
    // golden's null case is pixel-identical to its success case. Once boxes
    // are in the reference, green means only "the boxes are still where they
    // were".
    //
    // ⚑ KEEP SEPARATE: this is a defect in the CAPTURE, not a measurement of
    // her device. Whether that icon renders on a real phone is a different
    // question and this unit carries it as UNMEASURED — the bundled symbol
    // subset has never been verified on hardware. Nothing here is evidence
    // about her screen.
    final iconsLoaded = await loadMaterialIconsFont();
    if (!cjkLoaded || !iconsLoaded || !goldenPixelsComparableHere()) {
      // Fail CLOSED, the same discipline this file already applies to CJK: a
      // frame cut without a font it needs must never become the reference.
      installNoopGoldenComparator();
    }
    // flutter_map's built-in tile cache calls path_provider — mock it the
    // same way w3_turmoil_capture_test.dart does.
    final tmp = await Directory.systemTemp.createTemp('fm_cache_voice_lane');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    VoiceLaneVerdict? verdict,
    ValueNotifier<bool>? speechUnverified,
  }) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      voiceLaneReader: verdict == null ? null : () async => verdict,
      speechUnverified: speechUnverified,
    ));
    await tester.pump();
    await tester.pump();
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
  }

  testWidgets('voice-channel pre-drive caution render (ja)', (tester) async {
    await pump(tester, verdict: VoiceLaneVerdict.jaNetworkOnly);
    await tester.ensureVisible(find.byKey(const Key('voice-lane-caution')));
    await tester.pump();
    expect(
      find.text('オフライン音声が未インストールです。'
          '電波のない場所では音声警告が出ない可能性があります。'),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../ladder_out/voice_lane/voice_lane_caution_ja.png'),
    );
  });

  testWidgets('speech-unverified HUD chip render (ja)', (tester) async {
    final flag = ValueNotifier<bool>(false);
    await pump(tester, speechUnverified: flag);
    flag.value = true;
    await tester.pump();
    await tester.ensureVisible(
        find.byKey(const Key('speech-unverified-chip')));
    await tester.pump();
    expect(find.text('音声警告を確認できませんでした'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
          '../../ladder_out/voice_lane/speech_unverified_chip_ja.png'),
    );
  });
}
