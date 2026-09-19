/// The prefecture observations card at phone width, read with one face: the
/// station failure line and the descriptors against the floor, and each value
/// readable, with the scale it is drawn at printed.
///
/// ⚑⚑ R7 IN THIS FILE IS A PROPOSAL, NOT A SETTLED CHANGE. It was amended on
/// 2026-09-18 (7f6928a) and strengthened on 2026-09-19. An independent audit
/// had found that the amendment's WORDS claimed more than its assertions held.
/// In this version the assertions reach the words, and the words claim no more
/// than the assertions. A second read the same day found two places where that
/// still was not so: clause 6 said "the station's measurement" while checking
/// only the quantity, and clause 2 said "every transform" while measuring only
/// its horizontal scale. Both now check what they say. A third read found that
/// clause 4 named a node it does not read and that nothing bound the heads'
/// words; clause 4 now says what it reads, and clause 7 binds the words. It goes
/// back to that audit before it leaves PROPOSED.
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
///   2. each is drawn at >= 11 px: its font size through its own text
///      scaler, times the SMALLER of the horizontal and vertical scale of every
///      transform between it and its row (a FittedBox, a Transform), so a
///      glyph squashed in either direction is held;
///   3. each of cm, °C and m/s is drawn exactly once, as exact text, in a
///      cell of a row of columns: a column head;
///   4. the screen-reader label of the value's row says the value followed
///      by exactly one unit, and a longer value cannot stand in for it (a
///      cell's label is merged into its row's node, and the row is what a
///      screen reader speaks);
///   5. THE BINDING: the unit a value is announced with is the unit of the
///      head over the column it is drawn in. After the units moved to the
///      heads, a bare number takes its meaning only from the head above it. A
///      head over the wrong column would tell her 7.5 °C where the air is
///      -2.1 °C. Before this clause, only pixel goldens of other features stood
///      against that, and those are re-cut in bulk whenever the heads change on
///      purpose;
///   6. each answered row belongs to ONE station and shows THAT station's
///      readings: the station name and the place the row draws both name the
///      same station as the app's own station table and words name it, each
///      answered station is on exactly one row, and the
///      number under each head on that row is that station's own reading of
///      that head's quantity, as this test's fixture serves it. So a row that
///      shows the corridor's warmest temperature in place of its own, which
///      would hide the coldest station's ice, is caught, and so are one
///      station's numbers under another place's name;
///   7. the word over each column names the quantity its unit measures, as the
///      app's own words give it (積雪深 over cm, 気温 over °C, 風速 over m/s, and
///      the English words on the English page), so a head that reads 気温 over
///      the wind is caught even with every unit in place.
/// WHAT IT DOES NOT ASSERT: a scale applied ABOVE the row; a device text scale,
/// which this 1.0-scale test never sets; whether the heads' words read well at
/// a glance, which is a question for the frame and not for this check; any face
/// other than the one each file loads; that the station table's ids, and the
/// names and places the app draws for them, are the right ones —
/// test/corridor_stations_match_jma_table_test.dart holds those against JMA's
/// own station table; a phone.
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
import 'package:sngnav_app/l10n/app_localizations.dart' show AppL10n;
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

/// What the row of the answered station [stationId] should draw under each
/// head (clause 6), formatted as the card formats it: the temperature and the
/// wind to one decimal place, the snow depth to none.
Map<String, String> _readingsOf(String stationId) {
  final v = _answered[stationId]!;
  return {
    '°C': v.$1.toStringAsFixed(1),
    'cm': v.$2.toStringAsFixed(0),
    'm/s': v.$3.toStringAsFixed(1),
  };
}

/// The word the app draws over the column of [unit] on the [lang] page
/// (clause 7), read from the app's own localizations.
String _headWordFor(String unit, String lang) {
  final l = AppL10n(Locale(lang));
  return switch (unit) {
    'cm' => l.prefectureHeadSnow,
    '°C' => l.prefectureHeadTemp,
    'm/s' => l.prefectureHeadWind,
    _ => throw ArgumentError('no head word for $unit'),
  };
}

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
/// scaler, times the smaller of the horizontal and vertical scale of every
/// transform between it and its row (clause 2). The card already holds its
/// failure line to 11 px.
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
      // A station's name and place as the [lang] page draws them, read from
      // the app's own localizations, as the head words are (clause 7). On the
      // ja page these are the station table's own words.
      final page = AppL10n(Locale(lang));

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
        final descriptors = {
          for (final s in corridorStations)
            page.stationDescriptor(s.id, s.descriptor),
        };
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

        // Clauses 3 and 7: each unit drawn exactly once, in a cell of a row
        // of columns, under the word for its quantity. That cell's horizontal
        // span is the unit's column.
        final column = <String, (double, double)>{};
        for (final unit in _headUnits) {
          final drawn = find.text(unit).evaluate().toList();
          if (drawn.length != 1) {
            // ignore: avoid_print
            print('$lang $face unit in head 「$unit」 x${drawn.length}');
            problems.add(
              '「$unit」 is drawn ${drawn.length} times; it must be drawn '
              'exactly once, as the head of its column',
            );
            continue;
          }
          // 7: the word drawn with the unit, in the same head.
          Element? head;
          drawn.single.visitAncestorElements((a) {
            if (a.widget is CorridorColumnHead) {
              head = a;
              return false;
            }
            return true;
          });
          final word = _headWordFor(unit, lang);
          final headWords = head == null
              ? <String>{}
              : {
                  for (final e
                      in find
                          .descendant(
                            of: find.byElementPredicate(
                              (x) => identical(x, head),
                            ),
                            matching: find.byType(Text),
                          )
                          .evaluate())
                    if (((e.widget as Text).data ?? '') != unit)
                      (e.widget as Text).data ?? '',
                };
          // ignore: avoid_print
          print('$lang $face unit in head 「$unit」 x1 under the word '
              '${headWords.isEmpty ? 'NONE' : headWords.map((w) => '「$w」').join('/')}');
          if (!headWords.contains(word)) {
            problems.add(
              'the head over 「$unit」 reads '
              '${headWords.isEmpty ? 'no word' : headWords.map((w) => '「$w」').join('/')}; '
              'it must read 「$word」, the word for what $unit measures',
            );
          }
          final cell = _cellOf(drawn.single.renderObject!);
          if (cell == null) {
            problems.add('「$unit」 is not in a cell of a row of columns');
            continue;
          }
          final left = cell.localToGlobal(Offset.zero).dx;
          column[unit] = (left, left + cell.size.width);
        }

        // Clause 6: the station each row with numbers belongs to, read from
        // what the row draws. Its station name comes with the observation, and
        // its place comes from the station list by position (lib/main.dart), so
        // the two naming different stations is exactly how one station's
        // numbers would reach her under another place's name.
        final stationOfRow = <Element, String?>{};
        String? stationOf(Element rowElement) =>
            stationOfRow.putIfAbsent(rowElement, () {
              final drawn = {
                for (final e
                    in find
                        .descendant(
                          of: find.byElementPredicate(
                            (x) => identical(x, rowElement),
                          ),
                          matching: find.byType(Text),
                        )
                        .evaluate())
                  (e.widget as Text).data ?? '',
              };
              final named = [
                for (final st in corridorStations)
                  if (drawn.contains(page.stationName(st.id, st.name))) st,
              ];
              if (named.length != 1) {
                problems.add(
                  'a row with numbers draws ${named.length} station names '
                  '(${named.map((st) => st.name).join('/')}): $drawn',
                );
                return null;
              }
              final st = named.single;
              final place = page.stationDescriptor(st.id, st.descriptor);
              if (!drawn.contains(place)) {
                problems.add(
                  'the row of ${st.name} does not draw its own place '
                  '「$place」; it draws $drawn',
                );
              }
              return st.id;
            });
        final readingsOn = <String, int>{};

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
          // a Transform passed while the check printed "scale 1.000". The next
          // version took only the horizontal scale, so glyphs squashed to 0.6
          // of their height passed at "12.00 px". The smaller of the two scales
          // is the size she can read.
          RenderObject? row;
          for (RenderObject? a = ro.parent; a != null; a = a.parent) {
            if (rowBoxes.contains(a)) {
              row = a;
              break;
            }
          }
          final (horizontal, vertical) = row == null
              ? (1.0, 1.0)
              : _scales(ro.getTransformTo(row));
          final geometric = horizontal < vertical ? horizontal : vertical;
          final textScale = ro.textScaler.scale(1);
          final drawnPx =
              ro.textScaler.scale(ro.text.style?.fontSize ?? 0) * geometric;
          if (drawnPx + 0.001 < _valueFloorPx) {
            problems.add(
              '「$text」: drawn at ${drawnPx.toStringAsFixed(2)} px, under the '
              '${_valueFloorPx.toStringAsFixed(0)} px floor',
            );
          }

          // 4: the unit the row's screen-reader label says it with. A cell's
          // label is merged into its row's node, so this reads the row, which
          // is what a screen reader speaks. Boundary-checked: 「2.1」 must not
          // be cleared by the 「-2.1 °C」 of another column.
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

          // 6: the row it is drawn on, and that row's station's own reading
          // under this head.
          Element? rowElement;
          el.visitAncestorElements((a) {
            if (a.widget is CorridorRow) {
              rowElement = a;
              return false;
            }
            return true;
          });
          final stationId = rowElement == null ? null : stationOf(rowElement!);
          final stationName = stationId == null
              ? 'NO STATION'
              : corridorStations.firstWhere((st) => st.id == stationId).name;
          if (stationId != null) {
            readingsOn[stationId] = (readingsOn[stationId] ?? 0) + 1;
          }
          final expected =
              stationId == null || !_answered.containsKey(stationId)
              ? null
              : _readingsOf(stationId);
          final want = expected == null || under.length != 1
              ? null
              : expected[under.single];

          // ignore: avoid_print
          print(
            '$lang $face 「$text」 lines $lines, width '
            '${laidOut.toStringAsFixed(1)} of ${natural.toStringAsFixed(1)}, '
            'drawn ${drawnPx.toStringAsFixed(2)} px (text '
            '${textScale.toStringAsFixed(3)} x geometric '
            '${geometric.toStringAsFixed(3)}, the smaller of horizontal '
            '${horizontal.toStringAsFixed(3)} and vertical '
            '${vertical.toStringAsFixed(3)}), announced with '
            '${said.isEmpty ? 'NO UNIT' : said.join('/')}, under the head of '
            '${under.isEmpty ? 'NO UNIT' : under.join('/')}, on the row of '
            '$stationName, whose reading there is ${want ?? 'NONE'}',
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
          if (want != text) {
            problems.add(
              '「$text」 is drawn under the head of '
              '${under.isEmpty ? 'no unit' : under.join('/')} on the row of '
              '$stationName, whose reading there is '
              '${want ?? 'not in the fixture'}: it is not that station\'s '
              'measurement of that quantity',
            );
          }
        }
        expect(
          values,
          9,
          reason: 'precondition: three answered rows, three values each',
        );

        // Clause 6, across rows: each answered station is on exactly one row,
        // and that row carries all three of its readings.
        final rowsOf = <String, int>{};
        for (final id in stationOfRow.values.whereType<String>()) {
          rowsOf[id] = (rowsOf[id] ?? 0) + 1;
        }
        for (final id in _answered.keys) {
          final name = corridorStations.firstWhere((st) => st.id == id).name;
          if (rowsOf[id] != 1) {
            problems.add(
              '$name answered, but its name is on ${rowsOf[id] ?? 0} rows '
              'with numbers; it must be on exactly one',
            );
          } else if (readingsOn[id] != 3) {
            problems.add(
              'the row of $name draws ${readingsOn[id] ?? 0} of its three '
              'readings',
            );
          }
        }
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

/// How long a horizontal and a vertical segment become under [m], as ratios.
/// Translation cancels out, so margins and padding do not count as scale.
(double, double) _scales(Matrix4 m) {
  final o = MatrixUtils.transformPoint(m, Offset.zero);
  final x = MatrixUtils.transformPoint(m, const Offset(100, 0));
  final y = MatrixUtils.transformPoint(m, const Offset(0, 100));
  return ((x - o).distance / 100, (y - o).distance / 100);
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
