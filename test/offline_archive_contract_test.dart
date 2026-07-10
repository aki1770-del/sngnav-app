/// Data-contract pins on the bundled offline MBTiles archive: the
/// render-capture golden pins ONE city view and quietly self-disables on
/// hosts without a CJK font — this test pins the archive itself (metadata,
/// provenance, per-zoom coverage, and the load-bearing tiles a driver's
/// route depends on) with no font or widget dependency. It reads the asset
/// FILE directly, same as the render-capture harness, so it needs no
/// asset-bundle wiring.
///
/// If a regenerated asset changes coverage intentionally, update the pinned
/// counts here AND the runbook table in tool/README_TILES.md together.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Web-mercator tile coordinate, mirroring tool/render_akita_mbtiles.py.
({int x, int y}) tileFor(double lon, double lat, int z) {
  final n = 1 << z;
  final x = ((lon + 180.0) / 360.0 * n).floor();
  final s = math.sin(lat * math.pi / 180.0);
  final y = ((0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n).floor();
  return (x: x, y: y);
}

void main() {
  late Database db;

  setUpAll(() {
    final f = File('assets/tiles/akita_offline.mbtiles');
    expect(f.existsSync(), isTrue,
        reason: 'bundled offline basemap asset missing');
    db = sqlite3.open(f.path, mode: OpenMode.readOnly);
  });

  tearDownAll(() => db.dispose());

  String meta(String name) => db
      .select('SELECT value FROM metadata WHERE name = ?', [name])
      .single['value'] as String;

  test('metadata contract: format, zooms, provenance, attribution', () {
    expect(meta('format'), 'png');
    expect(meta('minzoom'), '8');
    expect(meta('maxzoom'), '13');
    // Provenance pin: the shipped map must say which dated cut it was
    // rendered from — 'latest' is a moving target.
    expect(meta('source_cut'), 'geofabrik/tohoku-260709');
    expect(meta('attribution'), contains('OpenStreetMap contributors'));
  });

  test('per-zoom coverage matches the runbook table', () {
    final rows = db.select(
        'SELECT zoom_level z, COUNT(*) c FROM tiles GROUP BY zoom_level');
    final counts = {for (final r in rows) r['z'] as int: r['c'] as int};
    expect(counts, {8: 6, 9: 15, 10: 54, 11: 176, 12: 672, 13: 629});
  });

  test('load-bearing tiles exist (the driver-facing surface)', () {
    bool has(double lon, double lat, int z) {
      final t = tileFor(lon, lat, z);
      final tmsY = (1 << z) - 1 - t.y;
      return db.select(
          'SELECT 1 FROM tiles WHERE zoom_level = ? AND tile_column = ?'
          ' AND tile_row = ?', [z, t.x, tmsY]).isNotEmpty;
    }

    expect(has(140.1025, 39.7186, 13), isTrue,
        reason: 'Akita city z13 (the city window)');
    expect(has(140.566, 39.311, 13), isTrue,
        reason: '横手 Route-13 corridor z13 (rural deep-zoom parity)');
    expect(has(140.663, 39.724, 11), isTrue, reason: '田沢湖 z11');
    expect(has(139.9, 39.9, 9), isTrue, reason: 'coastal z9 (sea fill)');
    // Neighbor-prefecture slivers must stay ABSENT at z13 (boundary clip):
    // no cohort is served by rendering 盛岡 inside an Akita archive.
    expect(has(141.15, 39.70, 13), isFalse,
        reason: 'Iwate sliver must not consume z13 budget');
  });
}
