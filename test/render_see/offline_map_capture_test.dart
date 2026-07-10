/// OPS-066 render-SEE capture — OFFLINE basemap proof (Chair Option A,
/// 2026-07-01).
///
/// Produces `render_out/05_offline_map_akita.png` so VAA can LOOK at the Akita
/// map rendering tiles from the bundled MBTiles archive with NO network — the
/// proof that the offline_tiles OfflineTileProvider wiring works and the
/// basemap is NOT blank offline. Run with:
///
///   flutter test --update-goldens test/render_see/offline_map_capture_test.dart
///
/// The tiles in the capture are REAL OpenStreetMap cartography (minimal
/// style, Geofabrik Tohoku extract; © OpenStreetMap contributors, ODbL) —
/// the PNG proves BOTH the mechanism (valid archive schema, provider
/// consumption, flutter_map painting offline) AND that the offline map now
/// shows real Akita roads/rivers/labels, not a placeholder grid.
///
/// The provider is built with `allowOnlineFallback: false`, so this test never
/// touches the network — any tile the archive does not cover renders
/// transparent, never a network fetch. The covered Akita corridor renders.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:offline_tiles/offline_tiles.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/services/offline_basemap.dart';



void main() {
  // IPAGothic covers Latin + Japanese (the 秋田 station label); DroidSans is a
  // pan-CJK backup. Loaded under the app's default family so AkitaMap renders
  // real glyphs, not tofu.
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  late Directory tmp;
  late OfflineTileProvider provider;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    // flutter_map / path_provider is called by the map's built-in cache; give
    // it a real temp dir so the mocked channel succeeds.
    tmp = await Directory.systemTemp.createTemp('offline_map_render_see');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );

    // Build the OfflineTileProvider from the bundled asset FILE on disk (read
    // directly here so the test needs no asset-bundle wiring). This exercises
    // the SAME construction path as production: bytes → temp file → MbTiles →
    // resolver.attachMbTiles → OfflineTileProvider. Hermetic offline: no
    // network fallback.
    final assetBytes = await File(akitaOfflineMbtilesAsset).readAsBytes();
    provider = await buildOfflineTileProviderFromBytes(
      Uint8List.fromList(assetBytes),
      tempDir: tmp,
      allowOnlineFallback: false,
    );
  });

  tearDownAll(() async {
    await provider.dispose();
  });

  testWidgets('05 — Akita basemap renders from bundled MBTiles OFFLINE',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(600 * 2, 360 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SizedBox(
            width: 600,
            child: AkitaMap(
              height: 340,
              // The proof: the offline-first provider drives the basemap.
              baseTileProvider: provider,
            ),
          ),
        ),
      ),
    );

    // Real async: sqlite reads + PNG decodes run on the true event loop, so
    // the tile images must be given time to resolve and paint before capture.
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      await tester.pump();
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump(const Duration(milliseconds: 40));
      }
    });

    await expectLater(
      find.byType(AkitaMap),
      matchesGoldenFile('../../render_out/05_offline_map_akita.png'),
    );
  });
}
