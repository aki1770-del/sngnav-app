/// The weather card at her text sizes: the line that says road conditions are
/// unavailable breaks only between its phrases, and every column head of the
/// prefecture table is one whole word inside its column.
///
/// WHY, written before the act (2026-10-04). Rendered at her geometry
/// (1080 x 2340 px at 2.75) at text sizes 1.0, 1.3, 1.5 and 2.0, before this
/// check existed:
/// * at 2.0 the absence line drew 「路面状況を取得できてい｜ません。見える範囲で運｜転してください。」.
///   Its first line ends on the affirmative stem of a warning that says the
///   road was NOT measured, so a glance that stops at the line end reads the
///   opposite; and 運転 was split in two;
/// * the table's data columns are 42.9 dp wide at every text size, because the
///   station and time columns are fixed. At 2.0 an 11 sp head draws 22 dp per
///   kanji, so 積雪深 drew one character per line, and 気温, 風速 and 観測時刻
///   split inside the word too. In English at 2.0, Snow, Temp, Wind and
///   Observed split mid-word in both faces, and with Roboto 「Observe｜d」 split
///   already at 1.5;
/// * every test that held this card ran at text size 1.0, where none of it
///   happens.
///
/// WHAT IT ASSERTS, per language and text size, on the real app:
///   A1. the absence line draws exactly the words the voice speaks;
///   A2. every line of it ends where a phrase ends (Japanese: the phrases
///       below, written here and not read from the app, so the app cannot
///       agree with itself; English: after a space), and no line ends on
///       「取得できてい」;
///   A3. no character of it lies past the width it was given;
///   A4. a screen reader hears it as the plain line: exactly one live region
///       is labelled with it, and no live region's label carries a joiner;
///   H1. each column head's word is one line, as the app's own words give it;
///   H2. no character of it lies outside its column;
///   H3. it is drawn at >= 11 px, this card's floor: its font size through its
///       text scaler, times the smaller of the horizontal and vertical scale
///       between it and its column;
///   H4. the painted words of two neighbouring heads are at least the 4 dp
///       gutter this card holds between columns apart. The first fix for H1
///       scaled each word to exactly its column: H1 to H3 passed, and the
///       frame at 2.0 drew 「積雪深気温風速観測時刻」 as one run of kanji.
/// WHAT IT DOES NOT ASSERT: that a head drawn smaller than her text size to
/// fit its column reads well at a glance; any face but the one each file
/// loads; a phone; and nothing here contains any time.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/corridor_row.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/staleness_policy.dart'
    show kConditionsUnknownJaSpokenText, kConditionsUnknownEnSpokenText;
import 'package:sngnav_app/widgets/keep_together.dart' show plainOf;

import '../render_see/render_see_env.dart';
import 'fake_alert_actuators.dart';

/// Where a line of the Japanese absence line may end: after one of these
/// phrases (文節). Joined, they spell the line; A1's own check holds that.
const _jaAbsencePhrases = [
  '路面状況を',
  '取得できていません。',
  '見える',
  '範囲で',
  '運転してください。',
];

/// The text sizes she can choose that this check reads.
const weatherCardScales = [1.0, 1.3, 1.5, 2.0];

/// The smallest a column head may be DRAWN, in logical px: the floor this card
/// holds its failure line and its values to.
const double _headFloorPx = 11.0;

/// Three stations answer, two fail, as test/support/prefecture_card_check.dart
/// serves them.
const _answered = {
  '32286': (-2.1, 30, 7.5),
  '32402': (-1.0, 12, 6.0),
  '32551': (-4.3, 58, 2.1),
};

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
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The laid-out lines of [rp], each as the plain words she reads on it.
List<String> laidOutLines(RenderParagraph rp) {
  final text = rp.text.toPlainText(includeSemanticsLabels: false);
  final byTop = <double, StringBuffer>{};
  for (var i = 0; i < text.length; i++) {
    final b = rp.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
        boxHeightStyle: ui.BoxHeightStyle.max);
    if (b.isEmpty) continue;
    final top = (b.first.top * 2).roundToDouble() / 2;
    (byTop[top] ??= StringBuffer()).write(text[i]);
  }
  final tops = byTop.keys.toList()..sort();
  return [for (final t in tops) plainOf(byTop[t]!.toString())];
}

/// Characters of [rp] that draw (not a joiner, not a space) whose box,
/// carried into [cell]'s coordinates, lies past [cell]'s width.
List<String> _outside(RenderParagraph rp, RenderBox cell) {
  final text = rp.text.toPlainText(includeSemanticsLabels: false);
  final toCell = rp.getTransformTo(cell);
  final out = <String>[];
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '⁠' || c == ' ' || c == ' ') continue;
    final b = rp.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1));
    if (b.isEmpty) continue;
    final r = MatrixUtils.transformRect(toCell, b.first.toRect());
    if (r.right > cell.size.width + 0.5 || r.left < -0.5) out.add(c);
  }
  return out;
}

/// The painted extent of [rp]'s drawing characters, in global logical px (H4).
Rect _paintedExtent(RenderParagraph rp) {
  final text = rp.text.toPlainText(includeSemanticsLabels: false);
  final toGlobal = rp.getTransformTo(null);
  Rect? ext;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '⁠' || c == ' ' || c == ' ') continue;
    final b = rp.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1));
    if (b.isEmpty) continue;
    final r = MatrixUtils.transformRect(toGlobal, b.first.toRect());
    ext = ext == null ? r : ext.expandToInclude(r);
  }
  if (ext == null) throw StateError('no painted character in ${rp.text}');
  return ext;
}

/// The size [rp] is drawn at in [cell], in logical px (H3).
double _drawnPx(RenderParagraph rp, RenderBox cell) {
  final fs = rp.text.style?.fontSize;
  if (fs == null) throw StateError('no font size on ${rp.text}');
  // Not getMaxScaleOnAxis(): it counts the z axis, which is always 1, so it
  // never reports a shrink.
  final t = rp.getTransformTo(cell);
  final sx = Offset(t.entry(0, 0), t.entry(1, 0)).distance;
  final sy = Offset(t.entry(0, 1), t.entry(1, 1)).distance;
  return rp.textScaler.scale(fs) * (sx < sy ? sx : sy);
}

/// Registers the checks with [face] loaded under the app's family, for each
/// of [langs], at every size in [weatherCardScales].
void weatherCardBreakTests({
  required String face,
  required FaceSearch search,
  required List<String> langs,
}) {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('weather_card_breaks');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  for (final lang in langs) {
    for (final scale in weatherCardScales) {
      testWidgets(
          '$lang, $face, text size $scale, at her geometry: the absence line '
          'breaks only between its phrases, and every column head is one '
          'whole word inside its column at or above the floor', (tester) async {
        final loaded =
            await tester.runAsync(() => loadDiscoveredFace('Roboto', search)) ??
                false;
        expect(loaded, isTrue,
            reason: 'without real glyph metrics no line break here is real');
        tester.view.devicePixelRatio = 2.75;
        tester.view.physicalSize = const Size(1080, 2340);
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await http.runWithClient(() async {
          await tester.pumpWidget(SngnavApp(
            actuators: FakeAlertActuators(),
            locale: Locale(lang),
            clock: () => DateTime.utc(2026, 1, 14, 21),
            jmaFetch: () async => const JmaFailure('no network in this test'),
          ));
          await _settleReal(tester);
        }, _jmaNetwork);

        final problems = <String>[];
        void say(String s) {
          // ignore: avoid_print
          print('$lang $face x$scale | $s');
        }

        // A: the absence line.
        final row = find.byKey(const Key('conditions-unknown-visible'));
        expect(row, findsOneWidget,
            reason: 'precondition: no observation, so the absence line shows');
        final rp = tester.renderObject<RenderParagraph>(
            find.descendant(of: row, matching: find.byType(RichText)).first);
        final spoken = lang == 'ja'
            ? kConditionsUnknownJaSpokenText
            : kConditionsUnknownEnSpokenText;
        final words = plainOf(rp.text.toPlainText());
        if (words != spoken) {
          problems.add('A1: the absence line draws 「$words」; the voice says '
              '「$spoken」');
        }
        final lines = laidOutLines(rp);
        say('absence ${lines.length} lines: '
            '${lines.map((l) => '「$l」').join('｜')}');
        final allowedEnds = <int>{};
        if (lang == 'ja') {
          var at = 0;
          for (final p in _jaAbsencePhrases) {
            at += p.length;
            allowedEnds.add(at);
          }
          expect(_jaAbsencePhrases.join(), spoken,
              reason: 'this check\'s own phrases must spell the line it reads');
        } else {
          for (var i = 0; i < spoken.length; i++) {
            if (spoken[i] == ' ') allowedEnds.add(i + 1);
          }
        }
        var end = 0;
        for (var i = 0; i < lines.length - 1; i++) {
          end += lines[i].length;
          if (!allowedEnds.contains(end)) {
            problems.add('A2: line ${i + 1} ends 「${lines[i]}」, inside a '
                'phrase');
          }
          if (lines[i].endsWith('取得できてい')) {
            problems.add('A2: line ${i + 1} ends on the affirmative stem '
                '「取得できてい」');
          }
        }
        final out = _outside(rp, rp);
        if (out.isNotEmpty) {
          problems.add('A3: ${out.length} characters of the absence line lie '
              'past its width: ${out.join()}');
        }

        // A4: a screen reader hears the plain line. Added 2026-10-04: with the
        // line drawn through joiners, removing its semantics label passed the
        // two tests that read this row (+17, rc 0), and no other test reads
        // its semantics.
        final semantics = tester.ensureSemantics();
        await tester.pump();
        var root = tester.getSemantics(find.byType(Scaffold).first);
        while (root.parent != null) {
          root = root.parent!;
        }
        final live = <String>[];
        void visit(SemanticsNode n) {
          final d = n.getSemanticsData();
          if (d.flagsCollection.isLiveRegion) live.add(d.label);
          n.visitChildren((c) {
            visit(c);
            return true;
          });
        }

        visit(root);
        semantics.dispose();
        if (live.where((l) => l == spoken).length != 1) {
          problems.add('A4: no single live region is labelled with the line '
              'the voice speaks; live regions: $live');
        }
        if (live.any((l) => l.contains('\u2060'))) {
          problems.add('A4: a live region\'s label carries a word joiner: '
              '${live.where((l) => l.contains('\u2060')).toList()}');
        }

        // H: the column heads.
        final heads = find.byType(CorridorColumnHead);
        expect(heads, findsNWidgets(5), reason: 'precondition: five heads');
        final painted = <(String, Rect)>[];
        for (final h in heads.evaluate()) {
          final head = h.widget as CorridorColumnHead;
          final cell = h.renderObject! as RenderBox;
          final labelText = find
              .descendant(
                  of: find.byElementPredicate((e) => identical(e, h)),
                  matching: find.byType(Text))
              .evaluate()
              .first
              .widget as Text;
          if (labelText.data != head.label) {
            problems.add('H1: the head 「${head.label}」 is not drawn as its '
                'own word: Text.data is ${labelText.data}');
          }
          final label = find
              .descendant(
                  of: find.byElementPredicate((e) => identical(e, h)),
                  matching: find.byType(RichText))
              .evaluate()
              .first
              .renderObject! as RenderParagraph;
          final hl = laidOutLines(label);
          final px = _drawnPx(label, cell);
          final outside = _outside(label, cell);
          say('head 「${head.label}」 column ${cell.size.width.toStringAsFixed(1)} dp, '
              '${hl.length} line(s) ${hl.map((l) => '「$l」').join('｜')}, '
              'drawn ${px.toStringAsFixed(2)} px, outside ${outside.length}');
          if (hl.length != 1) {
            problems.add('H1: the head 「${head.label}」 draws ${hl.length} '
                'lines: ${hl.map((l) => '「$l」').join('｜')}');
          }
          if (outside.isNotEmpty) {
            problems.add('H2: ${outside.join()} of 「${head.label}」 lie '
                'outside its ${cell.size.width.toStringAsFixed(1)} dp column');
          }
          if (px < _headFloorPx) {
            problems.add('H3: 「${head.label}」 is drawn at '
                '${px.toStringAsFixed(2)} px, under the $_headFloorPx px floor');
          }
          painted.add((head.label, _paintedExtent(label)));
        }
        // H4: neighbouring heads' painted words stay apart, by the gutter this
        // card holds between columns. Added 2026-10-04 after the first fix,
        // which scaled each word to exactly its column, passed H1 to H3, and on
        // the frame drew 「積雪深気温風速観測時刻」 as one run of kanji.
        painted.sort((a, b) => a.$2.left.compareTo(b.$2.left));
        for (var i = 0; i + 1 < painted.length; i++) {
          final gap = painted[i + 1].$2.left - painted[i].$2.right;
          say('gap 「${painted[i].$1}」→「${painted[i + 1].$1}」 '
              '${gap.toStringAsFixed(2)} dp');
          // 0.05 dp: after scaling, the engine reports the last glyph's box
          // up to 0.02 dp past its line's box (measured: 3.98 dp at the 4 dp
          // gutter). It is under one device pixel (0.36 dp at 2.75), so it
          // cannot hide two words touching: those measured 0.00 dp.
          if (gap < corridorPillInset - 0.05) {
            problems.add('H4: 「${painted[i].$1}」 and 「${painted[i + 1].$1}」 '
                'are ${gap.toStringAsFixed(2)} dp apart, under the '
                '$corridorPillInset dp gutter between columns');
          }
        }

        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }
}
