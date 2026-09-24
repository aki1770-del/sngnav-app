// HIE glance-paint coverage register.
//
// WHY, written before the act (OPS-070(B)). On 2026-09-20 the Chair ordered an
// RCA on D18. What the RCA measured: the HIE glance gate
// (`scripts/hie-glance-gate.py` in the masterplan repo) was pointed at class
// `AdvisoryCards` while the card HER eyes read is painted by `_AdvisoryCard`
// and by two top-level functions outside every class body. On the class that
// paints, that gate returns `fills found: 0` -- and zero fills and one fill
// were the same state in it, reported as "not a state surface" and, under
// --sweep, SILENT. Reproduced mechanically: with the single pair that gate
// could see unified, --sweep exits 0 and prints "1 state surface(s) checked,
// 0 failing" while `Opacity(opacity: 0.55)`, `_severityColor` and
// `Colors.grey.shade500` are all still in the file. Five severity words sat
// between 1.843:1 and 2.393:1 under that, `moderate` -- the level a 大雪警報
// carries -- at 1.843:1.
//
// The gate's scope was a HAND-TYPED class name and nothing ever compared it to
// the paint. That is fixed in the gate itself (C3b). This file fixes the other
// half, which is larger: THE GATE IS ARMED NOWHERE. Measured 2026-09-20 --
// 0 of 179 crontab rows, nothing in `.github/workflows/ci.yml`, no script
// invokes it. It fires only when a seat chooses to run it, on a file and a
// class that seat chooses. A gate nobody invokes did not go green for eight
// days; it did not run for eight days.
//
// THE RULE, with teeth: a lib file that paints must be covered by a test that
// samples the PAINTED pixels, or be named here as debt with a reason. The
// debt list cannot grow silently, a declaration that names nothing FAILS
// (the --accept-pair discipline), and the outstanding count prints every run.
// Sampling the painted ink rather than the resolved style is the point: a
// style-reading guard sees #616161 where the Opacity paints #A1A3A4, and
// passes a run at 2.292:1.
//
// Owner: HIE. This register measures COVERAGE, never legibility, and coverage
// is not a pass -- see the closing expect.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// A lib file with at least this many paint positions is a surface someone
/// looks at. Measured 2026-09-20 across all 58 lib/*.dart: the population at
/// >=4 is exactly {main.dart 92, advisory_cards.dart 24, akita_map.dart 21,
/// corridor_row.dart 5}; the next file down has 2. The threshold sits in the
/// gap, and it is stated so a later reader can move it on evidence.
const int kPaintThreshold = 4;

// Widened 2026-09-20 to the GATE's nine keys, after AAA's certification found
// this register matching five while hie-glance-gate.py matched nine. Nothing is
// hidden on today's population -- AAA measured that -- but a surface painting
// only through `foregroundColor:` would have been invisible here and visible to
// the gate, and two instruments disagreeing about what counts as paint is how
// this lane's defect started.
final RegExp _paintPos = RegExp(r'(?<![\w])(?:color|backgroundColor|fillColor|fill'
    r'|surfaceTintColor|shadowColor|foregroundColor|barrierColor|cursorColor)\s*:');

/// A test SAMPLES PIXELS only if it reads the raster back. Anything that reads
/// a widget's declared colour is reading the RECIPE.
///
/// AAA found on certification 2026-09-20 that THIS FILE contains that pattern,
/// so it matches itself. Not reachable today -- kCovered names only the real
/// guard -- but a register that can clear itself is OPS-064(C) in miniature,
/// so the path is closed below rather than left latent.
final RegExp _samplesPixels = RegExp(r'toByteData|toImage|getPixel');
const String _selfPath = 'test/widgets/glance_paint_coverage_test.dart';

/// lib path -> the test that samples its painted pixels.
const Map<String, String> kCovered = {
  'lib/widgets/advisory_cards.dart':
      'test/widgets/advisory_card_contrast_floor_test.dart',
  // 2026-09-24 AAE: this register fired on update_notice.dart the turn it was
  // written. The guard samples the raster and measures THE GATE in ink -- zero
  // ink while driving, zero ink once dismissed -- which is the pixel form of
  // WDA's Item 1 refusal. LEGIBILITY IS NOT COVERED AND IS NOT CLAIMED: that
  // is HIE's, and this surface is PROVISIONAL pending WDA's verdict on it.
  'lib/widgets/update_notice.dart':
      'test/widgets/update_notice_pixel_guard_test.dart',
};

/// lib path -> why it has NO PIXEL-SAMPLING guard, and what DOES cover it.
///
/// Renamed 2026-09-20 on AAA's certification, and the correction matters. This
/// map was first named for, and printed as, unmeasured debt. main.dart is NOT
/// unmeasured: test/widgets/text_contrast_floor_test.dart imports it at :34 and
/// holds her whole home page to 4.5:1 text / 3.0:1 icon in both languages.
/// Verified this turn. In this unit that word is load-bearing vocabulary, and
/// using it for a surface that carries a real instrument is the same error as
/// reading an empty search as absence -- the error this lane exists to root.
///
/// What is true is narrower, and is what each line now says: NO GUARD HERE
/// SAMPLES THE PAINTED PIXELS. That gap is real, not pedantry --
/// test/support/painted_text_contrast.dart resolves colours as handed to the
/// PAINTER and contains ZERO handling of Opacity or RenderOpacity (measured: 0
/// occurrences, 0 pixel reads). That is exactly the blindness logs/08 shows:
/// style #616161 passing at 5.604:1 where the painted pixel is #A1A3A4 at
/// 2.292:1. A render-tree floor guard does not discharge a pixel-sampling bound.
const Map<String, String> kNoPixelGuard = {
  'lib/main.dart':
      '2026-09-20 HIE: 92 paint positions, the page she actually opens. Its '
      'TEXT floor IS held, by text_contrast_floor_test.dart, which imports '
      'main.dart at :34 -- but that guard reads the render tree and is blind '
      'to compositing. No guard samples its painted pixels. Owed by HIE.',
  'lib/akita_map.dart':
      '2026-09-20 HIE: 21 paint positions. her_dot_glance_capture_test.dart '
      'samples pixels but covers the dot, not the map surface. Owed by HIE '
      'with AAE on the device path.',
  'lib/corridor_row.dart':
      '2026-09-20 HIE: 5 paint positions, no pixel-sampling guard and no text '
      'floor guard either. Owed by HIE.',
};

Directory _repoRoot() {
  var d = Directory.current;
  while (!File('${d.path}/pubspec.yaml').existsSync()) {
    final up = d.parent;
    if (up.path == d.path) fail('could not find the app root from ${Directory.current.path}');
    d = up;
  }
  return d;
}

void main() {
  final root = _repoRoot();
  String read(String rel) => File('${root.path}/$rel').readAsStringSync();
  bool exists(String rel) => File('${root.path}/$rel').existsSync();

  test('every painting lib file is covered by a pixel-sampling guard, or named as debt', () {
    final painting = <String, int>{};
    for (final e in Directory('${root.path}/lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final rel = e.path.substring(root.path.length + 1);
      final n = _paintPos.allMatches(e.readAsStringSync()).length;
      if (n >= kPaintThreshold) painting[rel] = n;
    }
    expect(painting, isNotEmpty,
        reason: 'found no painting lib file at all. An empty match is UNMEASURED, '
            'never absence -- this register measured nothing.');

    final uncovered = <String>[];
    for (final entry in painting.entries) {
      if (kCovered.containsKey(entry.key)) continue;
      if (kNoPixelGuard.containsKey(entry.key)) continue;
      uncovered.add('${entry.key} (${entry.value} paint positions)');
    }
    expect(uncovered, isEmpty,
        reason: 'These lib files paint and are in neither register. A surface with no '
            'instrument on it is UNMEASURED, never clean. Add a test that samples its '
            'painted pixels, or name it in kNoPixelGuard with a reason and a date:\n'
            '  ${uncovered.join('\n  ')}');

    // A declaration that names nothing is a success-shaped value.
    for (final e in kCovered.entries) {
      expect(exists(e.value), isTrue,
          reason: 'kCovered claims ${e.value} guards ${e.key}; that file does not exist.');
      expect(e.value == _selfPath, isFalse,
          reason: 'kCovered names this register itself, which contains its own detector '
              'pattern and would clear itself. A producer is never its own auditor.');
      expect(_samplesPixels.hasMatch(read(e.value)), isTrue,
          reason: '${e.value} samples no pixels, so it cannot guard what lands on glass. '
              'It reads the recipe.');
      expect(painting.containsKey(e.key), isTrue,
          reason: 'kCovered names ${e.key}, which no longer paints. Stale declaration.');
    }
    for (final k in kNoPixelGuard.keys) {
      expect(painting.containsKey(k), isTrue,
          reason: 'kNoPixelGuard names $k, which no longer paints above the threshold. '
              'Stale debt hides real debt -- remove the line.');
    }

    final totalPaint = painting.values.fold<int>(0, (a, b) => a + b);
    final debtPaint = kNoPixelGuard.keys
        .map((k) => painting[k] ?? 0)
        .fold<int>(0, (a, b) => a + b);
    // ignore: avoid_print
    print('GLANCE-COVERAGE ${painting.length} painting file(s), $totalPaint paint position(s); '
        'covered by a pixel-sampling guard: ${kCovered.length} file(s); '
        'NO PIXEL-SAMPLING GUARD: ${kNoPixelGuard.length} file(s), $debtPaint '
        'paint position(s) -- NOT the same as unmeasured; see kNoPixelGuard.');

    // The register is honest about itself: coverage is not legibility, and this
    // count is not a pass. It is printed so the debt is visible on every run
    // instead of living in a lane return nobody re-reads.
    expect(debtPaint, greaterThan(0),
        reason: 'the debt is zero -- if that is real, delete this expectation and say so '
            'on the record. Until then a silent zero means this register stopped measuring.');
  });
}
