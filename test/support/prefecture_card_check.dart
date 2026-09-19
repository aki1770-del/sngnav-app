/// The prefecture observations card at phone width, read with one face: the
/// station failure line and the descriptors against the floor, and each value
/// readable, with the scale it is drawn at printed.
///
/// ⚑⚑ R7 IN THIS FILE WAS AMENDED ON 2026-09-18 AND THE AMENDMENT IS A
/// PROPOSAL, NOT A SETTLED CHANGE. This is an audited check; the seat that
/// amended it does not own it and is not clearing it.
///
/// WHY it had to move: R7 asserted that every value is drawn WITH ITS UNIT on
/// one line. The unit no longer sits beside the value — it does not fit a 43 px
/// cell at 393 px, where the cell shrank "-12.1 °C" to 7.93 px with a Japanese
/// face, under this card's own 11 px floor — so it is drawn once in the column
/// head instead. R7's premise is therefore gone, and it fails 4 of 4 with
/// `Expected: <9> Actual: <0>`. It could not be left as it was and it could not
/// be deleted.
///
/// WHAT it became, and the direction matters: STRICTER. The amendment adds
/// three assertions the old R7 did not make — a drawn-size floor (which the old
/// check computed, PRINTED, and never held, so it passed the very defect this
/// change fixes), the unit's presence in a column head, and the unit's presence
/// in what a screen reader says. It is proven capable of failing on four
/// independent paths, each mutated alone: units back in the cells, a head's
/// unit removed, the unit dropped from the cell semantics, and a value scaled
/// under the floor. Logs in the amending seat's record for 2026-09-18.
///
/// WHAT IS OWED: this file's owner and its auditor must accept or refuse the
/// amendment. Until they do, R7 is a proposal that happens to be green.
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
import 'painted_text_contrast.dart';

/// Three stations answer, two fail.
http.Client _jmaNetwork() => MockClient((req) async {
  final u = req.url.toString();
  if (u.endsWith('/amedas/data/latest_time.txt')) {
    return http.Response('2026-01-15T06:00:00+09:00', 200);
  }
  final m = RegExp(r'/point/(\d+)/').firstMatch(u);
  if (m != null) {
    const ok = {
      '32286': (-2.1, 30, 7.5),
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

// PROPOSED (2026-09-18) — the successor to `_valueWithUnit`.
//
// R7 was written when a value carried its own unit, and its purpose was that
// the unit must never be separated from its value: at 393 px "7.5 m/s" had
// broken across two lines with the unit on the second. That purpose is intact.
// What changed is where the unit lives. It does not fit a 43 px cell — the
// cell's FittedBox shrank "-12.1 °C" to 7.93 px with a Japanese face, under
// this card's own 11 px floor — so the unit is now drawn once in the column
// head and the cells carry bare numbers.
//
// This is deliberately a STRICTER check than the one it replaces, not a looser
// one, because a check that is relaxed to let a change through has been bought
// rather than moved. It adds three assertions the old R7 did not make:
//   * a DRAWN-SIZE FLOOR. The old check computed each value's drawn scale and
//     PRINTED it, and asserted nothing about it — so it passed a temperature
//     drawn at 0.744 of 12 px, which is the defect this change exists to fix.
//   * the unit must be present, exactly once, in a column head. A unit taken
//     out of the cells that never arrived in a head has been deleted, and bare
//     numbers with no statement of what they measure would satisfy a regex.
//   * each data cell's SEMANTICS must still carry value AND unit, so a reader
//     who cannot see the column head has not silently lost it.
final _bareValue = RegExp(r'^-?\d+(\.\d+)?$');

/// The unit each data column is drawn in, expected once each in the heads.
const _headUnits = ['cm', '°C', 'm/s'];

/// The smallest a value may be DRAWN, after any scale-down. The card already
/// holds its failure line to 11 px.
const double _valueFloorPx = 11.0;

/// Registers the card's tests with [face] loaded as the app's default family,
/// discovered on this host by [search]. One face per test file: a family
/// loaded once in a test process is not replaced by a second load of the same
/// name.
///
/// [search], not a path: until 2026-09-18 the two callers passed absolute
/// paths, one of them inside one developer's `$HOME`, so on the first CI run
/// (35300438549) all four of these tests failed on a font that was never going
/// to be there. The assertion below is unchanged and still fails closed —
/// only the looking moved.
void prefectureCardTests({required String face, required FaceSearch search}) {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('prefecture_card');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tmp.path,
        );
  });

  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang, $face, 393 px, two stations failed: the failure '
        'line and the descriptors are above the floor, and every value keeps '
        'its unit on one line', (tester) async {
      final fontsLoaded =
          await tester.runAsync(() => loadDiscoveredFace('Roboto', search)) ??
              false;
      expect(
        fontsLoaded,
        isTrue,
        reason: 'without real glyph metrics the line test cannot fail',
      );
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(393 * 2.0, 852 * 2.0);
      addTearDown(tester.view.reset);

      await http.runWithClient(() async {
        await tester.pumpWidget(
          SngnavApp(
            actuators: FakeAlertActuators(),
            locale: Locale(lang),
            clock: () => DateTime.utc(2026, 1, 14, 21),
            jmaFetch: () async => const JmaFailure('no network in this test'),
          ),
        );
        await _settleReal(tester);
        final source = find.byKey(const Key('prefecture-observations-source'));
        await Scrollable.ensureVisible(tester.element(source), alignment: 0.7);
        await tester.pump();

        final rows = find.byType(CorridorRow);
        expect(
          rows,
          findsNWidgets(corridorStations.length),
          reason: 'precondition: the card has its rows',
        );
        final failed = find.byKey(const Key('corridor-station-fetch-failed'));
        expect(
          failed,
          findsNWidgets(2),
          reason: 'precondition: two stations failed',
        );

        final inRows = <RenderObject>{
          for (final e
              in find
                  .descendant(of: rows, matching: find.byType(RichText))
                  .evaluate())
            e.renderObject!,
        };
        final painted = paintedTextOutsideMap(tester);
        final problems = <String>[];

        // R3: the failure line.
        final failureLines = painted.where(
          (p) => p.key == 'corridor-station-fetch-failed',
        );
        expect(failureLines, hasLength(2));
        for (final p in failureLines) {
          if (p.foreground != Colors.red.shade900 ||
              (p.fontSize ?? 0) < 11 ||
              p.ratio == null ||
              p.ratio! < kTextContrastFloor) {
            problems.add('failure line: ${p.describe()}');
          }
          // ignore: avoid_print
          print('$lang $face failure line: ${p.describe()}');
        }

        // R6: the descriptors of the rows that answered.
        final descriptors = {for (final s in corridorStations) s.descriptor};
        final shown = painted.where((p) => descriptors.contains(p.text));
        expect(
          shown,
          hasLength(3),
          reason: 'precondition: three answered rows show a descriptor',
        );
        for (final p in shown) {
          if (p.foreground != Colors.grey.shade700 ||
              p.ratio == null ||
              p.ratio! < kTextContrastFloor) {
            problems.add('descriptor: ${p.describe()}');
          }
          // ignore: avoid_print
          print('$lang $face descriptor: ${p.describe()}');
        }

        // R7 (proposed): every value bare and on one line, drawn at or above
        // the floor, with its unit in the column head and in its semantics.
        var values = 0;
        final drawnValues = <String>[];
        for (final ro
            in tester.allRenderObjects.whereType<RenderParagraph>().toSet()) {
          if (!inRows.contains(ro)) continue;
          final text = ro.text.toPlainText();
          if (!_bareValue.hasMatch(text)) continue;
          values++;
          drawnValues.add(text);
          final tp =
              TextPainter(
                text: ro.text,
                textDirection: ro.textDirection,
                textScaler: ro.textScaler,
                maxLines: ro.maxLines,
              )..layout(
                maxWidth: ro.softWrap
                    ? ro.constraints.maxWidth
                    : double.infinity,
              );
          final lines = tp.computeLineMetrics().length;
          tp.dispose();
          final laidOut = ro.size.width;
          final natural = ro.getMaxIntrinsicWidth(double.infinity);
          // The scale it is drawn at: the fitting box's width over the
          // paragraph's, 1 where no fitting box holds it.
          RenderFittedBox? fit;
          for (
            RenderObject? a = ro.parent;
            a != null && a is! RenderFlex;
            a = a.parent
          ) {
            if (a is RenderFittedBox) {
              fit = a;
              break;
            }
          }
          final scale = fit == null
              ? 1.0
              : (fit.size.width / laidOut).clamp(0.0, 1.0);
          // ignore: avoid_print
          print(
            '$lang $face 「$text」 lines $lines, width ${laidOut.toStringAsFixed(1)}'
            ' of ${natural.toStringAsFixed(1)}, drawn at scale '
            '${scale.toStringAsFixed(3)}',
          );
          if (lines != 1 || laidOut + 0.5 < natural) {
            problems.add(
              '「$text」: $lines lines, laid out '
              '${laidOut.toStringAsFixed(1)} of ${natural.toStringAsFixed(1)}',
            );
          }
          // The floor the old check printed and never held.
          final drawnPx = (ro.text.style?.fontSize ?? 0) * scale;
          if (drawnPx + 0.001 < _valueFloorPx) {
            problems.add(
              '「$text」: drawn at ${drawnPx.toStringAsFixed(2)} px, under the '
              '${_valueFloorPx.toStringAsFixed(0)} px floor',
            );
          }
        }
        expect(
          values,
          9,
          reason: 'precondition: three answered rows, three values each',
        );

        // The unit must be in the head — exactly once each.
        for (final unit in _headUnits) {
          final n = find.text(unit).evaluate().length;
          // ignore: avoid_print
          print('$lang $face unit in head 「$unit」 x$n');
          if (n != 1) {
            problems.add(
              '「$unit」 is drawn $n times; it must appear exactly once, in its '
              'column head',
            );
          }
        }

        // …and it must still reach a reader who cannot see the head.
        //
        // ⚑ Two corrections this rule needed before it measured anything, both
        // found by running it rather than by reading it:
        //  1. Semantics must be turned ON and a frame pumped, or the tree is
        //     empty. The first draft read the owner without enabling it and
        //     threw on a null. A version that had caught the null and counted
        //     zero would have been worse — it would have condemned correct code.
        //  2. A cell's label does NOT become its own node. Flutter merges it
        //     into the row's node, so the row announces
        //     "…130 cm -2.1 °C, coldest in corridor 7.5 m/s 06:00 JST" as one
        //     string. A rule matching labels that END with a unit found zero of
        //     them and was about to fail a card that announces every unit
        //     correctly. The rule now asks the question it actually means:
        //     for every value drawn in a cell, is that value followed by its
        //     unit SOMEWHERE in what a screen reader would say?
        final semantics = tester.ensureSemantics();
        await tester.pump();
        final spoken = <String>[];
        _collectLabels(
          tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!,
          spoken,
        );
        final allSpoken = spoken.join(' \u0000 ');
        for (final v in drawnValues) {
          // ⚑ Boundary-checked, not a bare substring. The first version asked
          // `contains('$v $u')`, so 「2.1」 passed on the 「-2.1 °C」 of another
          // column: a value that was never announced would have been cleared by
          // a different value that was. A check with a path that cannot fail is
          // not a check.
          final heard = _headUnits.where((u) => _saidWithUnit(allSpoken, v, u));
          // ignore: avoid_print
          print('$lang $face announces 「$v」 with '
              '${heard.isEmpty ? 'NO UNIT' : heard.join('/')}');
          if (heard.isEmpty) {
            problems.add(
              'the value 「$v」 is drawn in a cell but no screen-reader label '
              'says it with a unit; the unit is in the column head, which a '
              'reader who cannot see it never reaches',
            );
          }
        }
        semantics.dispose();
        expect(problems, isEmpty, reason: problems.join('\n'));
      }, _jmaNetwork);
    });
  }
}

/// Every semantics label in the subtree, in order.
void _collectLabels(SemanticsNode n, List<String> out) {
  if (n.label.isNotEmpty) out.add(n.label);
  n.visitChildren((c) {
    _collectLabels(c, out);
    return true;
  });
}

/// Whether [all] says [value] immediately followed by [unit], with [value]
/// starting at a boundary — so a shorter value cannot be cleared by a longer
/// one that happens to end with its digits.
bool _saidWithUnit(String all, String value, String unit) {
  final needle = '$value $unit';
  var i = all.indexOf(needle);
  while (i != -1) {
    final before = i == 0 ? ' ' : all[i - 1];
    if (!RegExp(r'[0-9.\-]').hasMatch(before)) return true;
    i = all.indexOf(needle, i + 1);
  }
  return false;
}
