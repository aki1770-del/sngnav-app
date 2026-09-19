/// The prefecture observations table at 393 px, read with one face: every
/// value is drawn at 11 px or more, and between the painted extents of two
/// neighbouring columns there are at least 4 px (display review, 2026-09-16).
///
/// Why, written before the act (2026-09-16). The display review's second look at 12bdd13, in
/// IPAGothic: the temperature was drawn at 0.744 of 12 px (~8.9 px), the
/// smallest text on her page, and its pill touched the wind value; the wind
/// value ran into the observed time with no gap. The existing check
/// (prefecture_card_check.dart) reads each value on one line and prints its
/// scale; it does not hold a floor on the drawn size, and it does not read the
/// space between columns.
///
/// What is measured: for each answered row, each column's painted extent in
/// logical px — a text's laid-out glyph width times the scale it is drawn at,
/// and for the temperature the pill when the pill is coloured — and each
/// value's drawn size (its font size times that scale). Printed, then held.
/// Bound: host raster metrics with the named face; not measured on a phone.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/corridor_row.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../render_see/render_see_env.dart';
import 'fake_alert_actuators.dart';

/// Three stations answer (the widest values the card shows in the review's frames),
/// two fail.
http.Client _jmaNetwork() => MockClient((req) async {
      final u = req.url.toString();
      if (u.endsWith('/amedas/data/latest_time.txt')) {
        return http.Response('2026-01-15T06:00:00+09:00', 200);
      }
      final m = RegExp(r'/point/(\d+)/').firstMatch(u);
      if (m != null) {
        const ok = {
          '32286': (-12.1, 130, 17.5),
          '32402': (-1.0, 12, 6.0),
          '32551': (-4.3, 58, 2.1),
        };
        final v = ok[m.group(1)];
        if (v == null) return http.Response('', 500);
        return http.Response(
          '{"20260115060000":{"temp":[${v.$1},0],"snow":[${v.$2},0],'
          '"wind":[${v.$3},0],"humidity":[88,0]}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('', 404);
    });

Future<void> _settleReal(WidgetTester tester, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

typedef _Extent = ({String what, double left, double right, double? drawnPx});

void prefectureGapTests({required String face, required FaceSearch search}) {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('prefecture_gap');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  for (final lang in const ['ja', 'en']) {
    testWidgets(
        '$lang, $face, 393 px: every value drawn at 11 px or more, and 4 px '
        'or more between neighbouring columns', (tester) async {
      final loaded =
          await tester.runAsync(() => loadDiscoveredFace('Roboto', search)) ??
              false;
      expect(loaded, isTrue,
          reason: 'without real glyph metrics the measure cannot fail');
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(393 * 2.0, 852 * 2.0);
      addTearDown(tester.view.reset);

      await http.runWithClient(() async {
        await tester.pumpWidget(SngnavApp(
          actuators: FakeAlertActuators(),
          locale: Locale(lang),
          clock: () => DateTime.utc(2026, 1, 14, 21),
          jmaFetch: () async => const JmaFailure('no network in this test'),
        ));
        await _settleReal(tester);
        final source = find.byKey(const Key('prefecture-observations-source'));
        await Scrollable.ensureVisible(tester.element(source), alignment: 0.7);
        await tester.pump();

        final rows = find.byType(CorridorRow);
        expect(rows, findsNWidgets(corridorStations.length),
            reason: 'precondition: the card has its rows');

        final problems = <String>[];
        var answered = 0;
        for (final rowEl in rows.evaluate()) {
          final flex = _firstFlex(rowEl.renderObject!);
          if (flex == null) continue;
          final cells = <RenderBox>[];
          flex.visitChildren((c) => cells.add(c as RenderBox));
          if (cells.length != 5) continue;
          // Failed rows draw dashes; the answered rows carry the values.
          final paragraphs = [for (final c in cells) _paragraphs(c)];
          if (paragraphs[1].isEmpty ||
              paragraphs[1].first.text.toPlainText() == '—') {
            continue;
          }
          answered++;
          final extents = <_Extent>[];
          for (var i = 0; i < cells.length; i++) {
            var left = double.infinity, right = -double.infinity;
            double? drawn;
            final names = <String>[];
            for (final p in paragraphs[i]) {
              final r = _painted(p);
              left = r.left < left ? r.left : left;
              right = r.right > right ? r.right : right;
              names.add(p.text.toPlainText());
              if (i > 0 && i < 4) {
                final size = _fontSize(p);
                final px = size * _scaleOf(p);
                drawn = drawn == null || px < drawn ? px : drawn;
              }
            }
            final pill = _colouredPill(cells[i]);
            if (pill != null) {
              left = pill.left < left ? pill.left : left;
              right = pill.right > right ? pill.right : right;
            }
            extents.add((
              what: names.join('/'),
              left: left,
              right: right,
              drawnPx: drawn,
            ));
          }
          for (var i = 0; i < extents.length; i++) {
            final e = extents[i];
            final gap = i + 1 < extents.length
                ? extents[i + 1].left - e.right
                : null;
            // ignore: avoid_print
            print('$lang $face 「${e.what}」 painted '
                '${e.left.toStringAsFixed(1)}..${e.right.toStringAsFixed(1)}'
                '${e.drawnPx == null ? '' : ', drawn ${e.drawnPx!.toStringAsFixed(2)} px'}'
                '${gap == null ? '' : ', gap to next ${gap.toStringAsFixed(1)} px'}');
            if (e.drawnPx != null && e.drawnPx! < 11 - 0.01) {
              problems.add('「${e.what}」 drawn at '
                  '${e.drawnPx!.toStringAsFixed(2)} px');
            }
            if (gap != null && gap < 4 - 0.01) {
              problems.add('「${e.what}」 to 「${extents[i + 1].what}」: '
                  '${gap.toStringAsFixed(1)} px');
            }
          }
        }
        expect(answered, 3, reason: 'precondition: three answered rows');
        expect(problems, isEmpty, reason: problems.join('\n'));
      }, _jmaNetwork);
    });
  }
}

RenderFlex? _firstFlex(RenderObject ro) {
  if (ro is RenderFlex) return ro;
  RenderFlex? found;
  ro.visitChildren((c) => found ??= _firstFlex(c));
  return found;
}

List<RenderParagraph> _paragraphs(RenderObject ro) {
  final out = <RenderParagraph>[];
  void walk(RenderObject r) {
    if (r is RenderParagraph) {
      out.add(r);
      return;
    }
    r.visitChildren(walk);
  }

  walk(ro);
  return out;
}

double _fontSize(RenderParagraph p) {
  double? size;
  p.text.visitChildren((span) {
    final s = span.style?.fontSize;
    if (s != null) size = s;
    return true;
  });
  return size ?? 14;
}

/// The scale the paragraph is painted at, in logical px: the ratio of its
/// box's width in global logical coordinates to its laid-out width.
double _scaleOf(RenderParagraph p) {
  if (p.size.width == 0) return 1;
  final a = p.localToGlobal(Offset.zero);
  final b = p.localToGlobal(Offset(p.size.width, 0));
  return (b.dx - a.dx) / p.size.width;
}

/// The glyphs' painted rect in logical px.
Rect _painted(RenderParagraph p) {
  final tp = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
  )..layout(maxWidth: p.softWrap ? p.size.width : double.infinity);
  final w = tp.width < p.size.width ? tp.width : p.size.width;
  tp.dispose();
  final scale = _scaleOf(p);
  final origin = p.localToGlobal(Offset.zero);
  return Rect.fromLTWH(origin.dx, origin.dy, w * scale, p.size.height * scale);
}

Rect? _colouredPill(RenderObject ro) {
  Rect? found;
  void walk(RenderObject r) {
    if (found != null) return;
    if (r is RenderDecoratedBox) {
      final d = r.decoration;
      if (d is BoxDecoration && d.color != null && d.color!.a > 0) {
        found = r.localToGlobal(Offset.zero) & r.size;
        return;
      }
    }
    r.visitChildren(walk);
  }

  walk(ro);
  return found;
}
