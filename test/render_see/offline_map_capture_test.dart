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
/// HONEST BOUND: the tiles in the capture are HONEST PLACEHOLDERS (grid +
/// "PLACEHOLDER (EIE: real tiles)" text), NOT real Akita cartography. What the
/// PNG proves is the MECHANISM — the archive schema is valid, the provider
/// consumes it, and flutter_map paints the tiles offline. It does NOT show real
/// Akita; real raster coverage is EIE's Geofabrik ODbL-render production.
///
/// The provider is built with `allowOnlineFallback: false`, so this test never
/// touches the network — any tile the archive does not cover renders
/// transparent, never a network fetch. The covered Akita corridor renders.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tiles/offline_tiles.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/services/offline_basemap.dart';

Future<ByteData> _fontBytes(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.view(Uint8List.fromList(bytes).buffer);
}

/// Load whichever of [paths] exist on this host. Env-honest: a CI runner
/// without the CJK system fonts must not CRASH the suite (the render-see
/// captures are desktop-host evidence generators); it renders with the
/// default test font instead and says so — a tofu PNG on CI is harmless
/// because nobody affirms CI PNGs as OPS-066 evidence.
Future<void> _loadFamily(String family, List<String> paths) async {
  final present = paths.where((p) => File(p).existsSync()).toList();
  if (present.isEmpty) {
    // ignore: avoid_print
    print('render_see: no CJK system font on this host — ja glyph '
        'fidelity NOT verified in this environment (fonts sought: $paths)');
    return;
  }
  final loader = FontLoader(family);
  for (final p in present) {
    loader.addFont(_fontBytes(p));
  }
  await loader.load();
}

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
    await _loadFamily('Roboto', [ipa, droid]);
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
