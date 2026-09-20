// HIE R116-22 — a stored golden must carry the ground she sees.
//
// WHY, before the act: in R116-17 I found that render_out/19a..19c store a
// FULLY TRANSPARENT ground — the feed-health banner's 12%-alpha amber saved as
// (255,156,0,31) over nothing. I regenerated those three in `d09afa7d` and
// reported them as regenerated. Re-measured at that tip: the transparency is
// UNCHANGED. Regenerating a golden re-renders it; it does not give it a
// ground. My R116-17 line invites the reading that the defect was closed. It
// was not, and this guard exists so that reading can never be taken on trust
// again.
//
// Why it matters to her: those three frames are the ONLY stored evidence of
// the frozen-feed banner, the block that tells her a warning came from a
// document that stopped being written. A colour or contrast judgement read off
// an unpainted composite judges nothing — which is part of how a 3.54:1 run
// sat inside a golden-covered surface for as long as it did.
//
// ROOT CAUSE, measured: the three suites that produce them capture
// `find.byType(AdvisoryCards)` — the widget alone, which paints no background.
// Every one of the other 22 goldens in render_out/ captures
// `find.byType(MaterialApp)`, which includes the Scaffold's opaque surface.
// 3 of 25, and the 3 are exactly the ones that took the widget.
//
// WHAT THIS GUARD PINS — the PROPERTY, over the WHOLE directory, not the three
// files I happened to find: every stored golden is fully opaque. It names no
// file, so a new capture suite that forgets its ground fails on its first run
// instead of being discovered months later.
//
// WHAT IT CANNOT SEE: that the ground is the RIGHT one. An opaque black
// rectangle would pass. It proves only that a colour read from these pixels is
// a read of a composite, not of a floating widget. And it is a host raster:
// it says nothing about the phone's panel.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every stored golden carries an opaque ground', (tester) async {
    final dir = Directory('render_out');
    expect(dir.existsSync(), isTrue,
        reason: 'render_out/ is absent — the guard measured nothing, and '
            'UNMEASURED is never a pass');

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    // C3 (HIE-3): if the gate cannot find what it checks, it FAILS. An empty
    // directory listing is UNMEASURED, never absence.
    expect(files.length, greaterThan(10),
        reason: 'found only ${files.length} goldens in render_out/; this '
            'guard exists to sweep the whole directory');

    final bad = <String>[];
    for (final f in files) {
      // The bytes are read SYNCHRONOUSLY on purpose. Real async I/O awaited
      // in flutter_test'''s fake-clock zone never resumes: the first version of
      // this guard hung with no summary and no exit code, which is HIE-13'''s
      // defect again -- an await is an input to the instrument too.
      final bytes = f.readAsBytesSync();
      final info = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        final px = data!.buffer.asUint8List();
        var minA = 255;
        var opaque = 0;
        final total = px.length ~/ 4;
        for (var i = 3; i < px.length; i += 4) {
          if (px[i] < minA) minA = px[i];
          if (px[i] == 255) opaque++;
        }
        final out = (minA, opaque / total, img.width, img.height);
        img.dispose();
        codec.dispose();
        return out;
      });
      final (minA, frac, w, h) = info!;
      final name = f.uri.pathSegments.last;
      // ignore: avoid_print
      print('GROUND[$name] ${w}x$h minAlpha=$minA '
          'opaque=${(frac * 100).toStringAsFixed(1)}%');
      if (minA < 255) {
        bad.add('$name: minimum alpha $minA, only '
            '${(frac * 100).toStringAsFixed(1)}% of pixels opaque — the '
            'stored pixels are not the composite she sees');
      }
    }
    expect(bad, isEmpty,
        reason: 'goldens stored without the ground she sees '
            '(capture the MaterialApp, not the bare widget):\n  '
            '${bad.join('\n  ')}');
  });
}
