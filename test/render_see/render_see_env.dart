/// Shared environment honesty for the render_see suites.
///
/// The render_see tests serve OPS-066: they produce ja-rendered PNGs a
/// human LOOKS at on the dev host, with golden files as the local
/// regression anchor. Two facts make the golden comparison meaningless
/// off that host:
///
/// 1. The CJK system fonts (IPAGothic / DroidSansFallback) may be
///    absent — glyphs render as tofu, pixels diff wildly.
/// 2. Golden pixels are engine-version-specific — CI pins a different
///    Flutter than the dev host, so text shaping/AA differ even with
///    identical fonts.
///
/// So: when the fonts fail to load, [installNoopGoldenComparator]
/// swaps in a comparator that records an honest per-golden SKIP note
/// instead of failing. The test still builds, pumps, and renders the
/// REAL widgets (a broken pipeline still fails loudly); only the
/// pixel claim is withdrawn. Nobody affirms CI PNGs as OPS-066
/// evidence — that affirmation only ever happens from a human-viewed
/// desktop run.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

Future<ByteData> _fontBytes(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.view(Uint8List.fromList(bytes).buffer);
}

/// Load whichever of [paths] exist on this host under [family].
/// Returns `true` when at least one font loaded (glyph fidelity is
/// verifiable), `false` when none did (env-honest degradation).
Future<bool> loadCjkFamily(String family, List<String> paths) async {
  final present = paths.where((p) => File(p).existsSync()).toList();
  if (present.isEmpty) {
    // ignore: avoid_print
    print('render_see: no CJK system font on this host — ja glyph '
        'fidelity NOT verified in this environment (fonts sought: $paths)');
    return false;
  }
  final loader = FontLoader(family);
  for (final p in present) {
    loader.addFont(_fontBytes(p));
  }
  await loader.load();
  return true;
}

/// Replace the golden comparator with one that SKIPS (pass + honest
/// note) every comparison. Call ONLY when [loadCjkFamily] returned
/// false — on the font-bearing dev host the real comparator stays.
void installNoopGoldenComparator() {
  goldenFileComparator = _SkipNoteComparator();
}

class _SkipNoteComparator extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    // ignore: avoid_print
    print('render_see: golden comparison SKIPPED for $golden — no CJK '
        'fonts on this host, pixel claims are withdrawn (render pipeline '
        'was still exercised).');
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    // Never update goldens from a fontless environment.
  }
}
