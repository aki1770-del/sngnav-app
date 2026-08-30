/// Every tracked tile archive must be DECLARED, and every declared archive must
/// be LOADABLE.
///
/// `assets/tiles/gunma_offline.mbtiles` was committed on 5915647 — 11 MB, with a
/// written reason (Ring 1's Kan-Etsu / Minakami approach) — and was never added
/// to `pubspec.yaml`. Nothing failed. The repo carried it, every clone paid for
/// it, and no build could load it: `rootBundle.load` on an undeclared asset
/// throws, so the corridor it exists to serve had no cartography at all.
///
/// A tracked-but-undeclared asset is invisible in exactly the way that matters:
/// the file is right there in the tree, so a human reading the directory
/// concludes it ships. Only the bundle knows otherwise, and nobody asks it.
///
/// This is a yokoten test, not a gunma test — it enumerates the directory, so
/// the NEXT prefecture cut cannot repeat it.
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/offline_basemap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every .mbtiles in assets/tiles is declared in pubspec assets', () {
    final dir = Directory('assets/tiles');
    expect(dir.existsSync(), isTrue, reason: 'assets/tiles must exist');

    final onDisk = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.mbtiles'))
        .toList()
      ..sort();
    expect(onDisk, isNotEmpty, reason: 'no archives found to check');

    final pubspec = File('pubspec.yaml').readAsStringSync();
    final undeclared =
        onDisk.where((p) => !pubspec.contains('- $p')).toList();

    expect(
      undeclared,
      isEmpty,
      reason: 'these archives are on disk but NOT declared in pubspec '
          "flutter/assets, so rootBundle cannot load them and they ship "
          'nowhere: $undeclared',
    );
  });

  test('both declared archives load from the bundle and are real SQLite', () async {
    for (final asset in [akitaOfflineMbtilesAsset, gunmaOfflineMbtilesAsset]) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(1000000),
          reason: '$asset loaded but is implausibly small');

      // MBTiles IS a SQLite database. The first 16 bytes are the format magic;
      // a truncated or LFS-pointer file passes a size check and fails here.
      final head = data.buffer
          .asUint8List(data.offsetInBytes, 16)
          .map((b) => b == 0 ? '' : String.fromCharCode(b))
          .join();
      expect(head, startsWith('SQLite format 3'),
          reason: '$asset is declared and loadable but is not an MBTiles '
              'archive — header was "$head"');
    }
  });

  test('the two archives derive DISTINCT temp filenames', () {
    // `buildOfflineTileProviderFromBytes` writes to `tempDir/archiveFilename`.
    // A shared constant there made the second archive overwrite the first, and
    // the caller then rendered the wrong prefecture's roads with no error.
    final akita = akitaOfflineMbtilesAsset.split('/').last;
    final gunma = gunmaOfflineMbtilesAsset.split('/').last;
    expect(akita, isNot(equals(gunma)));
  });
}
