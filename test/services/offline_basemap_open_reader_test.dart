/// A running copy of the app that already holds the offline basemap is never
/// shown bytes being rewritten under it.
///
/// Why this test exists. The loader copied the bundled archive to one fixed
/// file name in the temporary directory, truncating and rewriting that file in
/// place on every start. On Linux that directory is `$TMPDIR` or `/tmp`,
/// shared by every process of the user (path_provider_linux 2.2.2), and the
/// app's own Linux runner lets a second launch be a second process
/// (G_APPLICATION_NON_UNIQUE). A second start therefore rewrote the file the
/// first one had open in SQLite, and a probe that booted two copies quickly
/// read it half-written.
///
/// The loader now writes the archive under a name of its own and moves it over
/// the fixed name in one step. A reader holding the old file keeps the old
/// file's bytes, and no reader opening the fixed name can find it half-written.
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/offline_basemap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a reader holding the archive keeps its bytes when the loader runs '
      'again, and nothing is left beside the archive', () async {
    final tmp = Directory.systemTemp.createTempSync('offline_basemap_reader');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final data = await rootBundle.load(akitaOfflineMbtilesAsset);
    final archive =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final name = akitaOfflineMbtilesAsset.split('/').last;

    // The file another running copy already holds open.
    final held = List<int>.generate(4096, (i) => (i * 7) % 256);
    final existing = File('${tmp.path}/$name')
      ..writeAsBytesSync(held, flush: true);
    final reader = existing.openSync();
    addTearDown(reader.closeSync);

    final provider = await buildOfflineTileProviderFromBytes(
      archive,
      tempDir: tmp,
      archiveFilename: name,
      allowOnlineFallback: false,
    );
    addTearDown(provider.dispose);

    reader.setPositionSync(0);
    final seen = reader.readSync(held.length + 64);
    expect(seen.length, held.length,
        reason: 'the held file changed length under its reader');
    expect(seen, orderedEquals(held),
        reason: 'the held file was rewritten under its reader');

    expect(File('${tmp.path}/$name').lengthSync(), archive.length,
        reason: 'the fixed name now holds the whole archive');
    expect([for (final e in tmp.listSync()) e.uri.pathSegments.last], [name],
        reason: 'nothing staged is left beside the archive');
  });
}
