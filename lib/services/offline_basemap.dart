/// Offline-basemap PoC wiring (Chair Option A, 2026-07-01).
///
/// HER worst-case is unexpected snow with Maps AND GPS down and no cell
/// signal — the moment the NETWORK basemap goes blank. This wires the
/// mechanism that keeps the Akita basemap rendering when the network is gone:
/// a bundled MBTiles archive consumed through offline_tiles'
/// [OfflineTileProvider], offline-first, with the network TileLayer as
/// fallback for uncovered tiles.
///
/// ***  HONEST BOUND — the bundled tiles are REAL OpenStreetMap cartography
/// in a deliberately MINIMAL style, not a full OSM-carto render.  ***
/// Rendered 2026-07-10 (EIE lane) from the Geofabrik Tohoku extract via
/// `tool/render_akita_mbtiles.py`: roads by class, rail, rivers, water
/// bodies, coastline, ja place labels. Coverage: Akita prefecture z8–z12;
/// z13 at the Akita-city window PLUS, prefecture-wide, every tile carrying
/// a motorway/trunk/primary road or a place label within the 秋田県 boundary
/// (PP4 rural deep-zoom parity, 2026-07-10 — the rural anchor cohort gets
/// the same z13 the city has; minor-road-only tiles and uncovered zooms
/// fall back via the resolver's lower-zoom fallback). No OSM tile server
/// was contacted; data
/// © OpenStreetMap contributors, ODbL 1.0. Buildings, footpaths, POIs and
/// sea fill are NOT rendered — the map orients (real roads, rivers, towns);
/// it is not a substitute for full cartography.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:mbtiles/mbtiles.dart';
import 'package:offline_tiles/offline_tiles.dart';
import 'package:path_provider/path_provider.dart';

/// The bundled real-cartography archive (declared in pubspec `flutter/assets`).
const String akitaOfflineMbtilesAsset = 'assets/tiles/akita_offline.mbtiles';

const String _tempMbtilesFilename = 'akita_offline.mbtiles';

/// Build an [OfflineTileProvider] from raw MBTiles [bytes].
///
/// [MbTiles] wraps sqlite3, which opens a FILE path — so the bundled asset
/// bytes are written to a real file under [tempDir] first, then opened
/// read-only and attached to the resolver.
///
/// [allowOnlineFallback] true ⇒ offline-first: tiles covered by the archive
/// render from the bundle; uncovered tiles fall through to the network
/// (the provider's own [NetworkTileProvider], driven by the TileLayer's
/// urlTemplate). Set false for a hermetic offline-only render.
Future<OfflineTileProvider> buildOfflineTileProviderFromBytes(
  Uint8List bytes, {
  required Directory tempDir,
  bool allowOnlineFallback = true,
}) async {
  final file = File('${tempDir.path}/$_tempMbtilesFilename');
  await file.writeAsBytes(bytes, flush: true);

  // Read-only open; format is 'png' so mbtiles disables gzip decode.
  final archive = MbTiles(path: file.path);

  final resolver = RuntimeTileResolver(
    tileSource: TileSourceType.mbtiles,
    allowOnlineFallback: allowOnlineFallback,
  );
  resolver.attachMbTiles(archive);

  return OfflineTileProvider(resolver: resolver);
}

/// Production entry: load the bundled Akita MBTiles asset, copy it to a
/// temp file, and return an offline-first [OfflineTileProvider].
///
/// Returns `null` on any failure so the caller falls back to the plain
/// network basemap — honest degradation, never a hard crash. A null result
/// means "no offline basemap this run", exactly as before this PoC.
Future<OfflineTileProvider?> loadAkitaOfflineTileProvider() async {
  try {
    final data = await rootBundle.load(akitaOfflineMbtilesAsset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final tempDir = await getTemporaryDirectory();
    return buildOfflineTileProviderFromBytes(bytes, tempDir: tempDir);
  } catch (_) {
    return null;
  }
}
