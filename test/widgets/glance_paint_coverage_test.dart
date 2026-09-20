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

final RegExp _paintPos = RegExp(
    r'(?<![\w])(?:color|backgroundColor|fillColor|surfaceTintColor|shadowColor)\s*:');

/// A test SAMPLES PIXELS only if it reads the raster back. Anything that reads
/// a widget's declared colour is reading the RECIPE.
final RegExp _samplesPixels = RegExp(r'toByteData|toImage|getPixel');

/// lib path -> the test that samples its painted pixels.
const Map<String, String> kCovered = {
  'lib/widgets/advisory_cards.dart':
      'test/widgets/advisory_card_contrast_floor_test.dart',
};

/// lib path -> why it is NOT covered, and by whom. UNMEASURED, never cleared.
/// Every line here is a surface HER eyes may read with no instrument on it.
const Map<String, String> kUnmeasuredDebt = {
  'lib/main.dart':
      '2026-09-20 HIE: 92 paint positions, the largest unmeasured surface in '
      'the app and the page she actually opens. No rendered-pixel floor guard '
      'exists for it. Owed by HIE.',
  'lib/akita_map.dart':
      '2026-09-20 HIE: 21 paint positions. her_dot_glance_capture_test.dart '
      'samples pixels but covers the dot, not the map surface. Owed by HIE '
      'with AAE on the device path.',
  'lib/corridor_row.dart':
      '2026-09-20 HIE: 5 paint positions, no rendered-pixel guard. Owed by HIE.',
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
      if (kUnmeasuredDebt.containsKey(entry.key)) continue;
      uncovered.add('${entry.key} (${entry.value} paint positions)');
    }
    expect(uncovered, isEmpty,
        reason: 'These lib files paint and are in neither register. A surface with no '
            'instrument on it is UNMEASURED, never clean. Add a test that samples its '
            'painted pixels, or name it in kUnmeasuredDebt with a reason and a date:\n'
            '  ${uncovered.join('\n  ')}');

    // A declaration that names nothing is a success-shaped value.
    for (final e in kCovered.entries) {
      expect(exists(e.value), isTrue,
          reason: 'kCovered claims ${e.value} guards ${e.key}; that file does not exist.');
      expect(_samplesPixels.hasMatch(read(e.value)), isTrue,
          reason: '${e.value} samples no pixels, so it cannot guard what lands on glass. '
              'It reads the recipe.');
      expect(painting.containsKey(e.key), isTrue,
          reason: 'kCovered names ${e.key}, which no longer paints. Stale declaration.');
    }
    for (final k in kUnmeasuredDebt.keys) {
      expect(painting.containsKey(k), isTrue,
          reason: 'kUnmeasuredDebt names $k, which no longer paints above the threshold. '
              'Stale debt hides real debt -- remove the line.');
    }

    final totalPaint = painting.values.fold<int>(0, (a, b) => a + b);
    final debtPaint = kUnmeasuredDebt.keys
        .map((k) => painting[k] ?? 0)
        .fold<int>(0, (a, b) => a + b);
    // ignore: avoid_print
    print('GLANCE-COVERAGE ${painting.length} painting file(s), $totalPaint paint position(s); '
        'covered by a pixel-sampling guard: ${kCovered.length} file(s); '
        'UNMEASURED DEBT: ${kUnmeasuredDebt.length} file(s), $debtPaint paint position(s).');

    // The register is honest about itself: coverage is not legibility, and this
    // count is not a pass. It is printed so the debt is visible on every run
    // instead of living in a lane return nobody re-reads.
    expect(debtPaint, greaterThan(0),
        reason: 'the debt is zero -- if that is real, delete this expectation and say so '
            'on the record. Until then a silent zero means this register stopped measuring.');
  });
}
