/// The two cards that say what leaves her phone never break a line inside a
/// negation, a loanword, or before a lone last word.
///
/// Why this test exists. On a 392.7 dp emulator frame the log card's
/// disclosure ended 「…確かめていませ」 with 「ん）。」 alone on the next line, and
/// the left-behind card ended a line 「この版は記録しま」, which reads "this
/// version will record", the opposite of its sentence. A larger text size
/// ended a line 「…位置情報の履歴は含まれ」. Japanese breaks between almost any
/// two characters, so where a word splits moves with the width, the text size
/// and the words; a golden photographs whatever it is given and passed with
/// the orphan in it. This test reads the lines themselves.
///
/// WHAT A PASS MEANS. With a recorded error and a kept code-15 record, in
/// Japanese, at 360, 392.7 and 411.4 dp and at text sizes 0.85 to 2.0, the
/// records-present status line, the log disclosure and the left-behind status
/// each lay out so that no break falls inside a negation (含まれません,
/// 確かめていません, 記録しません, ありません, 利用できません) or a katakana
/// word, no line after the first opens with 「ー」 or a small kana, and no last
/// line holds three characters or fewer. The same holds for the log card's
/// other two status lines, each in its own state of the app: the empty line (a
/// log with no records), which ended 「…記録はありま」, "there are records",
/// and the unavailable line (no log), which ended 「…利用でき」, "can use".
/// A screen reader is given their plain words. A control renders the same
/// words as plain Text at the same width and must find at least one such
/// break, and a split negation in each of those two lines, so a pass is not a
/// blind reader.
///
/// BOUNDS. Drawn with the Japanese face this host and CI discover
/// (render_see_env.dart); her phone's face is unmeasured. Laid out, not seen
/// on a device. Kanji compounds may still split; Japanese typesetting allows it.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/app_theme.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/services/fix_interval_record_keeper.dart';

import '../render_see/render_see_env.dart';

const _dpr = 2.75;
const _widths = [360.0, 1080 / _dpr, 411.4285714];
const _scales = [0.85, 1.0, 1.1, 1.15, 1.3, 1.5, 2.0];
const _negations = [
  '含まれません',
  '確かめていません',
  '記録しません',
  'ありません',
  '利用できません',
];
const _smallStarters = 'ーぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ';

bool _katakana(String c) =>
    c.compareTo('゠') >= 0 && c.compareTo('ヿ') <= 0 && c != '・';

/// The lines [p] draws: glyphs sharing one box top, joiners dropped.
List<String> _lines(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final out = <String>[];
  final buf = StringBuffer();
  double? top;
  for (var i = 0; i < text.length; i++) {
    final b = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (b.isNotEmpty && b.first.right - b.first.left > 0.01) {
      if (top != null && b.first.top > top + 1) {
        out.add(buf.toString());
        buf.clear();
      }
      top = b.first.top;
    }
    if (text[i] != '⁠') buf.write(text[i] == ' ' ? ' ' : text[i]);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

/// Every bad break in [lines], each named with the characters around it.
List<String> _badBreaks(List<String> lines) {
  final text = lines.join();
  final bad = <String>[];
  var at = 0;
  for (var k = 0; k < lines.length - 1; k++) {
    at += lines[k].length;
    final a = text[at - 1], c = text[at];
    final where = '${lines[k]}|${lines[k + 1]}';
    if (_smallStarters.contains(c)) bad.add('line opens with $c: $where');
    if (_katakana(a) && _katakana(c)) bad.add('katakana word split: $where');
    for (final w in _negations) {
      for (var s = text.indexOf(w); s >= 0; s = text.indexOf(w, s + 1)) {
        if (s < at && at < s + w.length) bad.add('negation $w split: $where');
      }
    }
  }
  if (lines.length > 1 && lines.last.trim().length <= 3) {
    bad.add('last line alone: |${lines.last}|');
  }
  return bad;
}

RenderParagraph _under(WidgetTester t, Finder f) => t.renderObject<RenderParagraph>(
    find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);

void main() {
  setUpAll(() async {
    final ok = await loadDiscoveredFace('Roboto', FaceSearch.japanese);
    if (!ok) fail('no Japanese face on this host:\n  ${describeFaceSearch(FaceSearch.japanese)}');
  });

  const l = AppL10n(Locale('ja'));
  var controlBreaks = 0;
  final statusControlNegations = <String, int>{};

  for (final w in _widths) {
    for (final s in _scales) {
      testWidgets('ja ${w.toStringAsFixed(1)} dp x$s: no bad break on either card',
          (t) async {
        final tmp = Directory.systemTemp.createTempSync('log_cards_breaks');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final log = LocalErrorLog(file: File('${tmp.path}/error_log.txt'))
          ..record(StateError('breaks'), null);
        File('${tmp.path}/$kCode15RecordFileName').writeAsStringSync('s=0 t=0 k=launch\n');
        const pp = MethodChannel('plugins.flutter.io/path_provider');
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pp, (_) async => tmp.path);
        addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pp, null));
        t.view.devicePixelRatio = _dpr;
        t.view.physicalSize = Size(w * _dpr, 2340);
        t.platformDispatcher.textScaleFactorTestValue = s;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);

        await t.pumpWidget(SngnavApp(
          locale: const Locale('ja'),
          errorLog: log,
          logShareSink: (_) async {},
          leftBehindRecord: LeftBehindFixIntervalRecord(directory: tmp),
          leftBehindRecordShareSink: (_) async {},
        ));
        await t.pump();
        final disclosure = find.byKey(const Key('log-share-disclosure'));
        await t.ensureVisible(disclosure);
        await t.pump();
        final status = find.byWidgetPredicate((x) =>
            x is RichText &&
            x.text.toPlainText(includeSemanticsLabels: false).replaceAll('⁠', '') ==
                l.logShareHasRecords);
        expect(status, findsOneWidget, reason: 'the records-present status line');
        final bad = <String>[
          ..._badBreaks(_lines(t.renderObject<RenderParagraph>(status))),
          ..._badBreaks(_lines(_under(t, disclosure))),
        ];
        final width = _under(t, disclosure).constraints.maxWidth;
        final left = find.byKey(const Key('left-behind-record-status'));
        await t.ensureVisible(left);
        await t.pump();
        bad.addAll(_badBreaks(_lines(_under(t, left))));

        // The empty and unavailable status lines: what she reads when nothing
        // has gone wrong, and when no log could be opened. Each is its own
        // state of the app, so each is its own pump.
        final statusWidths = <String, double>{};
        for (final (state, emptyLog, words) in [
          ('empty', LocalErrorLog(file: File('${tmp.path}/empty_log.txt')), l.logShareEmpty),
          ('unavailable', null, l.logShareUnavailable),
        ]) {
          await t.pumpWidget(SngnavApp(
            key: ValueKey(state),
            locale: const Locale('ja'),
            errorLog: emptyLog,
            logShareSink: (_) async {},
          ));
          await t.pump();
          await t.ensureVisible(find.byKey(const Key('log-share-disclosure')));
          await t.pump();
          final line = find.byWidgetPredicate((x) =>
              x is RichText &&
              x.text.toPlainText(includeSemanticsLabels: false).replaceAll('\u2060', '') ==
                  words);
          final found = line.evaluate().length;
          if (found != 1) {
            bad.add('the $state status line found $found times');
            continue;
          }
          final p = t.renderObject<RenderParagraph>(line);
          statusWidths[state] = p.constraints.maxWidth;
          bad.addAll(_badBreaks(_lines(p)).map((b) => '$state: $b'));
          final drawn =
              t.widget<Text>(find.ancestor(of: line, matching: find.byType(Text)).first);
          if (drawn.semanticsLabel != words) {
            bad.add('$state: a screen reader is given ${drawn.semanticsLabel}');
          }
        }

        // Control: the same words as plain Text, same theme, width and size.
        // It runs before the assertion below, so a red card never leaves the
        // control unrun and the teardown's "blind" never names a reader that
        // was not asked.
        for (final (words, size) in [
          (l.logShareDisclosure, 11.0),
          (l.leftBehindRecordStatus, 12.0),
        ]) {
          await t.pumpWidget(MaterialApp(
            theme: sngnavTheme(),
            home: Material(
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Text(words,
                      key: const Key('control'),
                      style: TextStyle(fontSize: size, color: Colors.grey.shade700)),
                ),
              ),
            ),
          ));
          controlBreaks += _badBreaks(_lines(_under(t, find.byKey(const Key('control'))))).length;
        }
        // The same control for the two status lines, at their own width: it
        // must split each line's negation somewhere in the sweep.
        for (final (state, words) in [
          ('empty', l.logShareEmpty),
          ('unavailable', l.logShareUnavailable),
        ]) {
          final lineWidth = statusWidths[state];
          if (lineWidth == null) continue;
          await t.pumpWidget(MaterialApp(
            theme: sngnavTheme(),
            home: Material(
              child: Center(
                child: SizedBox(
                  width: lineWidth,
                  child: Text(words,
                      key: const Key('control'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ),
              ),
            ),
          ));
          statusControlNegations[state] = (statusControlNegations[state] ?? 0) +
              _badBreaks(_lines(_under(t, find.byKey(const Key('control')))))
                  .where((b) => b.startsWith('negation'))
                  .length;
        }
        expect(bad, isEmpty, reason: 'at ${w.toStringAsFixed(1)} dp x$s');
      });
    }
  }

  tearDownAll(() {
    // A reader that never finds a bad break in plain text cannot be trusted
    // to find none in the drawn cards.
    expect(controlBreaks, greaterThan(0),
        reason: 'the plain-text control found no bad break anywhere: the reader is blind');
    for (final state in ['empty', 'unavailable']) {
      expect(statusControlNegations[state] ?? 0, greaterThan(0),
          reason: 'the plain-text control never split the $state line\'s negation: '
              'the reader is blind to it');
    }
  });
}
