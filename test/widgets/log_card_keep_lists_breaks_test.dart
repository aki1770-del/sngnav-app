/// Code 15's error-log card: each keep list is drawn on the line it guards and
/// holds its words whole across line breaks, in each state of the card.
///
/// Why, written before the act (2026-10-11). On an emulator frame at text
/// size 2.0 the disclosure ended a line 「…については確かめてい」 ("is being
/// checked") with 「ません）。」 on the next. Laid out on the host at the guard's
/// widths and text sizes, the same card ended 「…位置情報の履歴は含まれ」
/// ("location history is included"), the empty line 「…記録はありま」 ("there
/// are records") and the unavailable line 「…利用でき」 ("can use").
///
/// WHAT A PASS MEANS. In Japanese, at 360, 392.7 and 411.4 dp and text sizes
/// 0.85 to 2.0, with a log holding a record, an empty log, and no log: the
/// status line of each state and the disclosure each lay out with no line
/// break inside a word of that line's list, draw every listed word kept whole
/// (joined), draw exactly their plain words, and give a screen reader their
/// plain words. A control lays the same words out as plain Text at the same
/// width and must split a listed word somewhere in the sweep, for each line,
/// so a pass is not a blind reader; and the split finder must report a planted
/// split.
///
/// The words watched are the lists written out here, not read from the
/// getters under test: a word dropped from a getter is still watched, and the
/// sweep finds it drawn unjoined or split.
///
/// BOUNDS. Drawn with the Japanese face this host and CI discover
/// (render_see_env.dart); his phone's face is unmeasured. Laid out, not seen
/// on a device.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/app_theme.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/widgets/keep_together.dart';

import '../render_see/render_see_env.dart';

const _dpr = 2.75;
const _widths = [360.0, 1080 / _dpr, 411.4285714];
const _scales = [0.85, 1.0, 1.1, 1.15, 1.3, 1.5, 2.0];

/// The lists as set on 2026-10-11, written out.
const _disclosureWords = [
  'ボタン', 'ログ', 'テレメトリ', 'アカウント', 'エラー', 'バックアップ', 'データ移行',
  'スマートフォン', 'メーカー', '含まれません', '確かめていません',
];
const _recordsWords = ['エラー', 'ボタン', 'ベータ・フィードバック', '送れます'];
const _emptyWords = ['ログ', 'クラッシュ', 'エラー', 'ありません'];
const _unavailableWords = ['エラーログ', '利用できません'];

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
    if (text[i] != kWordJoiner) buf.write(text[i] == kNoBreakSpace ? ' ' : text[i]);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

/// Every break in [lines] that falls inside one of [words].
List<String> _splits(List<String> lines, List<String> words) {
  final text = lines.join();
  final out = <String>[];
  var at = 0;
  for (var k = 0; k < lines.length - 1; k++) {
    at += lines[k].length;
    for (final w in words) {
      for (var s = text.indexOf(w); s >= 0; s = text.indexOf(w, s + 1)) {
        if (s < at && at < s + w.length) out.add('$w split: ${lines[k]}|${lines[k + 1]}');
      }
    }
  }
  return out;
}

RenderParagraph _under(WidgetTester t, Finder f) => t.renderObject<RenderParagraph>(
    find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);

void main() {
  setUpAll(() async {
    final ok = await loadDiscoveredFace('Roboto', FaceSearch.japanese);
    if (!ok) fail('no Japanese face on this host:\n  ${describeFaceSearch(FaceSearch.japanese)}');
  });

  const l = AppL10n(Locale('ja'));
  final controlSplits = <String, int>{};

  test('control: the split finder reports a planted split, and none on whole words', () {
    expect(_splits(['（スマートフォンのメーカー独自のバックアップについては確かめてい', 'ません）。'],
        _disclosureWords), hasLength(1));
    expect(_splits(['（スマートフォンのメーカー独自のバックアップについては', '確かめていません）。'],
        _disclosureWords), isEmpty);
  });

  for (final w in _widths) {
    for (final s in _scales) {
      testWidgets('ja ${w.toStringAsFixed(1)} dp x$s: each list holds its words '
          'on its line', (t) async {
        t.view.devicePixelRatio = _dpr;
        t.view.physicalSize = Size(w * _dpr, 2340);
        t.platformDispatcher.textScaleFactorTestValue = s;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final tmp = Directory.systemTemp.createTempSync('log_card_keep_lists');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final bad = <String>[];
        final widths = <String, double>{};

        void read(String name, Finder f, List<String> words, String plain) {
          expect(f, findsOneWidget, reason: name);
          final p = _under(t, f);
          widths[name] = p.constraints.maxWidth;
          bad.addAll(_splits(_lines(p), words).map((x) => '$name: $x'));
          final drawn = t.widget<Text>(find.descendant(of: f, matching: find.byType(Text), matchRoot: true));
          if (plainOf(drawn.data!) != plain) bad.add('$name: draws other words');
          if (drawn.data != plain && drawn.semanticsLabel != plain) {
            bad.add('$name: a screen reader is given ${drawn.semanticsLabel}');
          }
          for (final word in words) {
            if (plain.contains(word) && !drawn.data!.contains(keepTogether(word, [word]))) {
              bad.add('$name: $word is drawn without being kept whole');
            }
          }
        }

        final withRecord = LocalErrorLog(file: File('${tmp.path}/error_log.txt'))
          ..record(StateError('breaks'), null);
        final empty = LocalErrorLog(file: File('${tmp.path}/empty_log.txt'));
        for (final (state, log, words, plain) in [
          ('records', withRecord, _recordsWords, l.logShareHasRecords),
          ('empty', empty, _emptyWords, l.logShareEmpty),
          ('unavailable', null, _unavailableWords, l.logShareUnavailable),
        ]) {
          await t.pumpWidget(SngnavApp(
            key: ValueKey('$state $w $s'),
            locale: const Locale('ja'),
            errorLog: log,
            logShareSink: (_) async {},
          ));
          await t.pump();
          await t.ensureVisible(find.byKey(const Key('log-share-disclosure')));
          await t.pump();
          // The status line, found by the words she reads: the one Text that
          // draws them, joined or not.
          read('status $state',
              find.byWidgetPredicate((x) => x is Text && x.data != null && plainOf(x.data!) == plain),
              words, plain);
          read('disclosure ($state)', find.byKey(const Key('log-share-disclosure')),
              _disclosureWords, l.logShareDisclosure);
        }

        // Controls: the same words as plain Text, same theme, width and size.
        for (final (name, words, plain, size) in [
          ('status records', _recordsWords, l.logShareHasRecords, 12.0),
          ('status empty', _emptyWords, l.logShareEmpty, 12.0),
          ('status unavailable', _unavailableWords, l.logShareUnavailable, 12.0),
          ('disclosure (records)', _disclosureWords, l.logShareDisclosure, 11.0),
        ]) {
          await t.pumpWidget(MaterialApp(
            theme: sngnavTheme(),
            home: Material(
              child: Center(
                child: SizedBox(
                  width: widths[name]!,
                  child: Text(plain,
                      key: const Key('control'),
                      style: TextStyle(fontSize: size, color: Colors.grey.shade700)),
                ),
              ),
            ),
          ));
          controlSplits[name] = (controlSplits[name] ?? 0) +
              _splits(_lines(_under(t, find.byKey(const Key('control')))), words).length;
        }
        expect(bad, isEmpty, reason: 'at ${w.toStringAsFixed(1)} dp x$s');
      });
    }
  }

  tearDownAll(() {
    for (final name in [
      'status records',
      'status empty',
      'status unavailable',
      'disclosure (records)',
    ]) {
      expect(controlSplits[name] ?? 0, greaterThan(0),
          reason: 'the plain-text control never split a word of the $name list: '
              'the reader is blind to it');
    }
  });
}
