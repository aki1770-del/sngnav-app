/// The prefecture observations card at phone width, read with one face: the
/// station failure line and the descriptors against the floor, and each value
/// readable, with the scale it is drawn at printed.
///
/// ⚑⚑ R7 IN THIS FILE IS A PROPOSAL, NOT A SETTLED CHANGE. It was amended on
/// 2026-09-18 (7f6928a) and strengthened on 2026-09-19. An independent audit
/// had found that the amendment's WORDS claimed more than its assertions held.
/// In this version the assertions reach the words, and the words claim no more
/// than the assertions. It goes back to that audit before it leaves PROPOSED.
/// Until 2026-09-19 it was called an audited check in several places, but no
/// audit had read it before that day.
///
/// WHY it had to move: R7 asserted that every value is drawn WITH ITS UNIT on
/// one line. The unit no longer sits beside the value — it does not fit a 43 px
/// cell at 393 px, where the cell shrank "-12.1 °C" to 7.93 px with a Japanese
/// face, under this card's own 11 px floor — so it is drawn once in the column
/// head instead. R7's premise is gone, and the old check fails 4 of 4 with
/// `Expected: <9> Actual: <0>`. It could not stay as written, and it could not
/// be deleted, because its purpose stands: a driver never reads a value cut
/// off from what it measures.
///
/// WHAT R7 ASSERTS, on the 393 px frame, ja and en, one face per file, three
/// answered stations:
///   1. each of the nine values is bare, on one line, and not truncated;
///   2. each is drawn at >= 11 px, measured through its own text scaler and
///      every transform between it and its row (a FittedBox, a Transform);
///   3. each of cm, °C and m/s is drawn exactly once, as exact text, in a
///      cell of a row of columns: a column head;
///   4. each value's own semantics node says it followed by exactly one unit,
///      and a longer value cannot stand in for it;
///   5. THE BINDING: the unit a value is announced with is the unit of the
///      head over the column it is drawn in. After the units moved to the
///      heads, a bare number takes its meaning only from the head above it. A
///      head over the wrong column would tell her 7.5 °C where the air is
///      -2.1 °C. Before this clause, only pixel goldens of other features stood
///      against that, and those are re-cut in bulk whenever the heads change on
///      purpose;
///   6. the number under each head is the station's measurement OF that head's
///      quantity in this test's fixture, so a wind reading moved into the snow
///      column together with its label is caught too.
/// WHAT IT DOES NOT ASSERT: a scale applied ABOVE the row; a device text scale,
/// which this 1.0-scale test never sets; anything about the heads' own words
/// (積雪深 / 気温 / 風速); any face other than the one each file loads; a phone.
/// On 2026-09-19 each clause was proven able to fail: its defect was planted
/// and the check went red.
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

/// The three stations that answer, and what each reports: (temperature °C,
/// snow depth cm, wind m/s). The other two stations fail.
const _answered = {
  '32286': (-2.1, 30, 7.5),
  '32402': (-1.0, 12, 6.0),
  '32551': (-4.3, 58, 2.1),
};

/// Each number the card should draw for [_answered], with the unit of the
/// quantity the station measured it as (clause 6). The nine are distinct.
final Map<String, String> _measuredAs = {
  for (final v in _answered.values) ...{
    v.$1.toStringAsFixed(1): '°C',
    v.$2.toStringAsFixed(0): 'cm',
    v.$3.toStringAsFixed(1): 'm/s',
  },
};

/// Three stations answer, two fail.
http.Client _jmaNetwork() => MockClient((req) async {
  final u = req.url.toString();
  if (u.endsWith('/amedas/data/latest_time.txt')) {
    return http.Response('2026-01-15T06:00:00+09:00', 200);
  }
  final m = RegExp(r'/point/(\d+)/').firstMatch(u);
  if (m != null) {
    final v = _answered[m.group(1)];
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

// PROPOSED — the successor to `_valueWithUnit`. What each clause asserts is in
// the banner at the head of this file. What is kept from the 2026-09-18
// amendment is its direction, a check made STRICTER rather than looser. A check
// relaxed to let a change through has been bought, not moved.
final _bareValue = RegExp(r'^-?\d+(\.\d+)?$');

/// The unit each data column is drawn in, expected once each in the heads.
const _headUnits = ['cm', '°C', 'm/s'];

/// The smallest a value may be DRAWN: its font size through its own text
/// scaler, times every transform between it and its row (clause 2). The card
/// already holds its failure line to 11 px.
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
        'line and the descriptors are above the floor, and every value is on '
        'one line, at or above the floor, under the head of the unit it is '
        'announced with', (tester) async {
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

        // R7 (PROPOSED): six clauses, stated in the banner at the head of this
        // file. Semantics are turned ON before the values are read, because
        // clause 4 reads each value's own node. The first draft of this check
        // found two corrections by running it: the tree stays empty until
        // semantics are enabled and a frame is pumped, and a cell's label is
        // merged into its row's node rather than becoming a node of its own.
        final semantics = tester.ensureSemantics();
        await tester.pump();

        // Clause 3: each unit drawn exactly once, in a cell of a row of
        // columns. That cell's horizontal span is the unit's column.
        final column = <String, (double, double)>{};
        for (final unit in _headUnits) {
          final drawn = find.text(unit).evaluate().toList();
          // ignore: avoid_print
          print('$lang $face unit in head 「$unit」 x${drawn.length}');
          if (drawn.length != 1) {
            problems.add(
              '「$unit」 is drawn ${drawn.length} times; it must be drawn '
              'exactly once, as the head of its column',
            );
            continue;
          }
          final cell = _cellOf(drawn.single.renderObject!);
          if (cell == null) {
            problems.add('「$unit」 is not in a cell of a row of columns');
            continue;
          }
          final left = cell.localToGlobal(Offset.zero).dx;
          column[unit] = (left, left + cell.size.width);
        }

        // Clauses 1, 2, 4, 5 and 6, value by value.
        final rowBoxes = <RenderObject>{
          for (final e in rows.evaluate()) e.renderObject!,
        };
        var values = 0;
        for (final el
            in find
                .descendant(of: rows, matching: find.byType(RichText))
                .evaluate()) {
          final ro = el.renderObject! as RenderParagraph;
          final text = ro.text.toPlainText();
          if (!_bareValue.hasMatch(text)) continue;
          values++;

          // 1: one line, not truncated.
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
          if (lines != 1 || laidOut + 0.5 < natural) {
            problems.add(
              '「$text」: $lines lines, laid out '
              '${laidOut.toStringAsFixed(1)} of ${natural.toStringAsFixed(1)}',
            );
          }

          // 2: the size it is drawn at. The 2026-09-18 version took only a
          // FittedBox's width ratio, so a value shrunk by its text scaler or by
          // a Transform passed while the check printed "scale 1.000".
          RenderObject? row;
          for (RenderObject? a = ro.parent; a != null; a = a.parent) {
            if (rowBoxes.contains(a)) {
              row = a;
              break;
            }
          }
          final geometric = row == null ? 1.0 : _xScale(ro.getTransformTo(row));
          final textScale = ro.textScaler.scale(1);
          final drawnPx =
              ro.textScaler.scale(ro.text.style?.fontSize ?? 0) * geometric;
          if (drawnPx + 0.001 < _valueFloorPx) {
            problems.add(
              '「$text」: drawn at ${drawnPx.toStringAsFixed(2)} px, under the '
              '${_valueFloorPx.toStringAsFixed(0)} px floor',
            );
          }

          // 4: the unit its own semantics node says it with. Boundary-checked:
          // 「2.1」 must not be cleared by the 「-2.1 °C」 of another column.
          final label = tester
              .getSemantics(find.byElementPredicate((e) => identical(e, el)))
              .getSemanticsData()
              .label;
          final said = [
            for (final u in _headUnits)
              if (_saidWithUnit(label, text, u)) u,
          ];

          // 5: the head whose column it is drawn in.
          final cx = ro.localToGlobal(ro.size.center(Offset.zero)).dx;
          final under = [
            for (final c in column.entries)
              if (cx >= c.value.$1 && cx <= c.value.$2) c.key,
          ];

          // 6: what the station measured it as.
          final measuredAs = _measuredAs[text];

          // ignore: avoid_print
          print(
            '$lang $face 「$text」 lines $lines, width '
            '${laidOut.toStringAsFixed(1)} of ${natural.toStringAsFixed(1)}, '
            'drawn ${drawnPx.toStringAsFixed(2)} px (text '
            '${textScale.toStringAsFixed(3)} x geometric '
            '${geometric.toStringAsFixed(3)}), announced with '
            '${said.isEmpty ? 'NO UNIT' : said.join('/')}, under the head of '
            '${under.isEmpty ? 'NO UNIT' : under.join('/')}, measured as '
            '${measuredAs ?? 'NOT A FIXTURE VALUE'}',
          );
          if (said.length != 1) {
            problems.add(
              said.isEmpty
                  ? 'the value 「$text」 is drawn in a cell but its '
                        'screen-reader label says it with no unit; the unit '
                        'is in the column head, which a reader who cannot see '
                        'it never reaches'
                  : 'the value 「$text」 is announced with more than one unit '
                        '(${said.join('/')})',
            );
          } else if (under.length != 1 || under.single != said.single) {
            problems.add(
              '「$text」 is announced in ${said.single} but drawn under the '
              'head of ${under.isEmpty ? 'no unit' : under.join('/')}: the eye '
              'and the ear are told different things',
            );
          }
          if (measuredAs == null ||
              under.length != 1 ||
              under.single != measuredAs) {
            problems.add(
              '「$text」 is the station\'s ${measuredAs ?? 'unknown'} reading '
              'but is drawn under the head of '
              '${under.isEmpty ? 'no unit' : under.join('/')}',
            );
          }
        }
        expect(
          values,
          9,
          reason: 'precondition: three answered rows, three values each',
        );
        semantics.dispose();
        expect(problems, isEmpty, reason: problems.join('\n'));
      }, _jmaNetwork);
    });
  }
}

/// The cell of a row of columns that holds [r]: the child of the nearest
/// horizontal Flex above it, or null when there is none.
RenderBox? _cellOf(RenderObject r) {
  var child = r;
  for (RenderObject? a = r.parent; a != null; a = a.parent) {
    if (a is RenderFlex && a.direction == Axis.horizontal) {
      return child is RenderBox ? child : null;
    }
    child = a;
  }
  return null;
}

/// How long a horizontal segment becomes under [m], as a ratio. Translation
/// cancels out, so margins and padding do not count as scale.
double _xScale(Matrix4 m) {
  final a = MatrixUtils.transformPoint(m, Offset.zero);
  final b = MatrixUtils.transformPoint(m, const Offset(100, 0));
  return (b - a).distance / 100;
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
