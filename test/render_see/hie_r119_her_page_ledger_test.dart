/// HIE R119 PROBE — MEASUREMENT ONLY, NOT A GUARD.
///
/// WHY, written before the act (OPS-070(B)). The Chair asked what the app puts
/// in front of a reader and whether the meaning arrives in a glance. Every
/// prior HIE look in this repo rendered ONE card or ONE widget. Nobody had
/// rendered HER WHOLE PAGE at her width and measured how the glance is spent
/// across it. This probe does that and asserts nothing about legibility.
///
/// ⚑ v2. v1 printed a valid ledger and ONE valid frame and then DIED on a
/// path_provider MissingPluginException while flutter_map reached for a tile
/// cache. The frame was on disk and the run had failed — HIE-7's defect, caught
/// only by reading the exit code. v2 mocks the path_provider channel so the
/// failure cannot recur silently, and every frame is written only after the
/// pump that produced it returned.
///
/// BOUNDS, riding the output. Host raster, not her panel: no phone/IVI gamma,
/// backlight, sunlight, windscreen or dirty glass. NO TIME — nothing here is a
/// glance. The offline basemap is unavailable under flutter_test, so the map
/// draws its CHROME over a blank ground: every map-tile judgement is out of
/// reach of this probe and is not made. A tall viewport lays the page out at
/// her WIDTH, which is what governs wrapping; it is not her viewport, and the
/// FOLD figures come from the 852-tall pump, not the tall one.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import 'render_see_env.dart';

const String _out = String.fromEnvironment('HIE_R119_OUT');

const double _w = 393;
const double _h = 852;

/// ⚑ INHERITED, NOT RE-MEASURED THIS TURN. HIE bylaws HIE-14 (2026-09-19):
/// the real phone gives the page 721 dp per screen where a 393x852 raster
/// gives 796. That came from a device frame, not from here. Printed as a
/// SECOND fold line so the raster's own 796 cannot stand in for her phone's.
const double _phoneFoldDp = 721;

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

void _write(String name, Uint8List bytes) {
  if (_out.isEmpty) {
    // ignore: avoid_print
    print('R119: HIE_R119_OUT unset — no frame written for $name');
    return;
  }
  Directory(_out).createSync(recursive: true);
  File('$_out/$name').writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('R119: wrote $name (${bytes.length} bytes)');
}


/// ⚑⚑ THIS PROBE DOES NOT RUN IN THE SUITE, AND HERE IS WHY IT MUST NOT.
///
/// Measured 2026-09-23: run inside a bare `flutter test` this file times out —
/// `TimeoutException after 0:10:00`. Its stalls are real and recorded (a second
/// `pumpWidget` of the app in one file, and a `jumpTo` + `pump` loop that never
/// returns), and I worked around them by running each state in its own process.
/// **What I did not do was connect "it stalls" to "and therefore it fails the
/// suite I am committing it into."** It went in at `9a41c0f`, and the app's CI
/// job runs a bare `flutter test`, so it would have taken CI red and added ~10
/// minutes per case. Caught by reading the FINAL summary of a full run
/// (`+1348 -12`) after having reported a mid-run progress line (`-8`) as the
/// verdict — the same success-shaped-value family, in my own reporting.
///
/// It is a MEASUREMENT PROBE, not a guard: it asserts nothing about the app and
/// only produces frames and figures. So it is gated ON PURPOSE rather than
/// deleted, and it says out loud that it did not run:
///
///   flutter test THIS_FILE --dart-define=HIE_R119_PROBES=1
///
/// ⚑ The stall itself is NOT FIXED. Running it needs `--plain-name` for one case.
const bool _runProbes = bool.fromEnvironment('HIE_R119_PROBES');

void _announceSkipped(String what) {
  // ignore: avoid_print
  print('R119 PROBE NOT RUN: $what. This is a measurement probe, not a guard, '
      'and it STALLS in a shared process (measured: 10-minute timeout). '
      'It measured nothing here, which is not the same as passing. '
      'Re-run with --dart-define=HIE_R119_PROBES=1 and --plain-name for one case.');
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    final cjk = await loadDiscoveredFace('Roboto', FaceSearch.japanese);
    final icons = await loadMaterialIconsFont();
    final symbols = await loadBundledSymbolsFont();
    // ignore: avoid_print
    print('R119 FACES: cjk=$cjk materialIcons=$icons symbols=$symbols');
    // HIE-18(b): a probe that renders kanji with no CJK face measures character
    // count, not meaning. Refuse rather than report.
    if (!cjk) {
      throw StateError('R119 REFUSES WITHOUT A JAPANESE FACE — '
          '${describeFaceSearch(FaceSearch.japanese)}');
    }
    if (!icons) throw StateError('R119 REFUSES WITHOUT MaterialIcons.');
    if (!symbols) throw StateError('R119 REFUSES WITHOUT SnGNavSymbols.');
    installNoopGoldenComparator();

    tmp = Directory.systemTemp.createTempSync('hie_r119_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // a leftover temp dir is not a reason to fail a measurement run
    }
  });

  Future<void> pumpHerPage(WidgetTester tester) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_clearObs()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  const ja = AppL10n(Locale('ja'));
  final sections = <String, String>{
    'banner(alpha legal)': ja.responsibilityBanner,
    'map': ja.mapSectionTitle,
    'driveHud(caution)': ja.driveHudTitle,
    'route': ja.routeSectionTitle,
    'maneuver': ja.maneuverSectionTitle,
    'jma(akita obs)': ja.akitaObservationSectionTitle,
    'prefecture(table)': ja.prefectureObservationsSectionTitle,
    'advisories': ja.advisoriesSectionTitle,
    'logShare': ja.logShareSectionTitle,
    'channelCheck': ja.channelCheckSectionTitle,
    'diary': ja.diarySectionTitle,
  };

  testWidgets('HER PAGE LEDGER at her phone geometry', (tester) async {
    if (!_runProbes) {
      _announceSkipped('hie_r119_her_page_ledger_test.dart');
      return;
    }
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(_w * 2, _h * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpHerPage(tester);
    // PROOF THE PAGE IS THE REAL ONE, before any number is believed.
    expect(find.byType(AkitaMap), findsOneWidget);

    final pos = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final viewport = pos.viewportDimension;
    final extent = pos.maxScrollExtent + viewport;
    // ignore: avoid_print
    print('R119 PAGE: viewport=${viewport.toStringAsFixed(1)}dp '
        'totalExtent=${extent.toStringAsFixed(1)}dp '
        'screens_raster=${(extent / viewport).toStringAsFixed(2)} '
        'screens_phone721=${(extent / _phoneFoldDp).toStringAsFixed(2)}');

    final tops = <String, double>{};
    for (final e in sections.entries) {
      final f = find.text(e.value);
      if (f.evaluate().isEmpty) {
        // ignore: avoid_print
        print('R119 SECTION ${e.key}: NOT FOUND (UNMEASURED, never absence)');
        continue;
      }
      tops[e.key] = tester.getRect(f.first).top + pos.pixels;
    }
    final order = tops.keys.toList()..sort((a, b) => tops[a]!.compareTo(tops[b]!));
    // ignore: avoid_print
    print('R119 LEDGER (dp from the very top of her page):');
    for (var i = 0; i < order.length; i++) {
      final k = order[i];
      final top = tops[k]!;
      final next = i + 1 < order.length ? tops[order[i + 1]]! : extent;
      // ignore: avoid_print
      print('  ${(i + 1).toString().padLeft(2)}. ${k.padRight(20)} '
          'top=${top.toStringAsFixed(0).padLeft(5)}dp '
          'height=${(next - top).toStringAsFixed(0).padLeft(5)}dp '
          '${(100 * (next - top) / extent).toStringAsFixed(1).padLeft(5)}%  '
          '${top < _phoneFoldDp ? 'ABOVE-HER-FOLD' : 'below fold'}');
    }

    final rb = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first);
    final img = await rb.toImage(pixelRatio: 2.0);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    _write('01_her_first_screen_393x852.png', png!.buffer.asUint8List());
    img.dispose();

    // The rest of her page, in her own screenfuls, from the SAME pump — a
    // second pumpWidget of this app in one file hung twice (HIE-13: two app
    // instances in quick succession), so the slices ride the pump that worked.
    var n = 0;
    while (pos.pixels < pos.maxScrollExtent - 1 && n < 8) {
      pos.jumpTo(math.min(pos.pixels + viewport, pos.maxScrollExtent));
      await tester.pump();
      n++;
      final i2 = await rb.toImage(pixelRatio: 2.0);
      final p2 = await i2.toByteData(format: ui.ImageByteFormat.png);
      _write('${(n + 1).toString().padLeft(2, '0')}_scroll_'
          '${pos.pixels.toStringAsFixed(0)}dp.png', p2!.buffer.asUint8List());
      i2.dispose();
    }
    // ignore: avoid_print
    print('R119 SLICES: ${n + 1} screenfuls of ${viewport.toStringAsFixed(0)}dp '
        'covering ${extent.toStringAsFixed(0)}dp');
  });

}
