/// Offline-basemap wiring (2026-07-01).
///
/// The worst case is unexpected snow with Maps AND GPS down and no cell
/// signal — the moment the NETWORK basemap goes blank. This wires the
/// mechanism that keeps the Akita basemap rendering when the network is gone:
/// a bundled MBTiles archive consumed through offline_tiles'
/// [OfflineTileProvider], offline-first, with the network TileLayer as
/// fallback for uncovered tiles.
///
/// ***  HONEST BOUND — the bundled tiles are REAL OpenStreetMap cartography
/// in a deliberately MINIMAL style, not a full OSM-carto render.  ***
/// Rendered 2026-07-10 from the Geofabrik Tohoku extract (cut
/// tohoku-260709, pinned in the archive metadata) via
/// `tool/extract_akita.py` + `tool/render_akita_mbtiles.py` (runbook:
/// `tool/README_TILES.md`). What it renders: sea fill polygonized from the
/// OSM coastline; roads by class; route-number shields styled by verified
/// network (国道 blue plate / 県道 blue hexagon / expressway green — a
/// number whose network is NOT verified by an OSM route relation renders
/// grey, claiming nothing); bridge casings + tunnel dashes at z12+ (map
/// features, never warnings); rail, rivers, lakes (multipolygon relations
/// included — 田沢湖 renders as water), ja place labels; and an explicit
/// grey データ範囲外 tint outside the data bbox (never fake land or sea).
/// Coverage: Akita prefecture z8–z12; z13 at the Akita-city window PLUS,
/// prefecture-wide, every tile carrying a motorway/trunk/primary road or a
/// place label within the 秋田県 boundary (rural deep-zoom parity —
/// the rural anchor cohort gets the same z13 the city has; other tiles and
/// deeper zooms fall back via the resolver's lower-zoom fallback). No OSM
/// tile server was contacted; data © OpenStreetMap contributors, ODbL 1.0.
/// Buildings, footpaths and POIs are NOT rendered — the map orients (real
/// roads, rivers, towns); it is not a substitute for full cartography.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:mbtiles/mbtiles.dart';
import 'package:offline_tiles/offline_tiles.dart';
import 'package:path_provider/path_provider.dart';

/// The bundled real-cartography archive (declared in pubspec `flutter/assets`).
const String akitaOfflineMbtilesAsset = 'assets/tiles/akita_offline.mbtiles';

/// The Kan-Etsu / Minakami approach — Ring 1's Kanto corridor.
///
/// Phase C puts Kanto hands on Oct 20, ahead of Akita on Oct 31: they meet
/// snow on this road before Akita prefecture is in anyone's hand.
const String gunmaOfflineMbtilesAsset = 'assets/tiles/gunma_offline.mbtiles';

/// Keeps two loads in one process from sharing a staging name.
int _stagingSerial = 0;

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
  required String archiveFilename,
  bool allowOnlineFallback = true,
}) async {
  // REQUIRED, never defaulted. Two archives written through one constant
  // filename overwrite each other in tempDir, and the second caller then
  // renders the FIRST archive's cartography — Gunma's roads painted as
  // Akita's, or the reverse. Tiles still appear, so nothing looks broken.
  // A default would let that back in the moment a caller forgot it.
  final file = File('${tempDir.path}/$archiveFilename');
  // Written under a name of this start's own, then moved over the fixed name
  // in one step (2026-09-14). The temporary directory is shared by every
  // process of the user on Linux, and a second start of the app is a second
  // process there: writing the fixed name in place truncated the file another
  // running copy held open in SQLite, and a copy starting at the same moment
  // could open it half-written. A rename replaces the name atomically; a copy
  // that already holds the old file keeps the old file's bytes.
  final staging = File(
      '${tempDir.path}/.$archiveFilename.$pid.${_stagingSerial++}.part');
  try {
    await staging.writeAsBytes(bytes, flush: true);
    await staging.rename(file.path);
  } finally {
    if (staging.existsSync()) {
      try {
        staging.deleteSync();
      } on FileSystemException {
        // Nothing more to do: the load itself reports the failure.
      }
    }
  }

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
Future<OfflineTileProvider?> loadAkitaOfflineTileProvider() =>
    loadOfflineTileProvider(asset: akitaOfflineMbtilesAsset);

/// Production entry for any bundled archive: load [asset], copy it to a temp
/// file named after the asset itself, and return an offline-first provider.
///
/// Returns `null` on any failure so the caller falls back to the plain network
/// basemap — honest degradation, never a hard crash.
Future<OfflineTileProvider?> loadOfflineTileProvider({
  required String asset,
}) async {
  try {
    final data = await rootBundle.load(asset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final tempDir = await getTemporaryDirectory();
    return buildOfflineTileProviderFromBytes(
      bytes,
      tempDir: tempDir,
      archiveFilename: asset.split('/').last,
    );
  } catch (e) {
    // Degradation must be honest, never silent: a swallowed error here left
    // the map blank in airplane mode on-device while host tests painted it
    // (missing bundled native sqlite lib; caught by the 2026-07-10 emulator
    // airplane-mode pass). The null return still fail-softs to the network
    // basemap — but the WHY now reaches the log so a blank offline map is
    // diagnosable in one read.
    debugPrint('offline basemap unavailable, falling back to network: $e');
    return null;
  }
}
