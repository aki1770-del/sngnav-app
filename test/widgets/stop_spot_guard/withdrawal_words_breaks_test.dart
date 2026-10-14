/// The withdrawn note and the consent dialog's reason after a withdrawal hold
/// their key words whole across line breaks (code 16, 2026-10-14).
///
/// Why, written before the act. The note became a live region in code 16, so
/// its words were rewritten to name what was withdrawn and the act at which
/// she is asked again; the dialog gained one line, said first after a
/// withdrawal. The screen review predicted that without keep lists 53 of 66
/// geometries split a watched word in the note and 62 of 66 in the reason
/// line, and 0 of 66 with them. This pins the prediction on the real widgets.
///
/// WHAT A PASS MEANS. In Japanese and English, at 360, 392.7 and 411.4 dp and
/// text sizes 0.85 and 1.00 to 2.00 in 0.05 steps, the note (after a tap on
/// 共有の同意を取り消す) and the reason line (after the next 現在地を共有) lay
/// out so that no line break falls inside a watched word. Two controls: the
/// split finder reports a planted split, and the same words laid out as plain
/// Text at the same width split a watched word somewhere in the sweep, so a
/// pass is not a blind reader.
///
/// The watched words are the screen review's lists, written out here, not read
/// from the getters under test.
///
/// BOUNDS. The host's faces (render_see_env.dart); laid out, not seen on a
/// device.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/widgets/keep_together.dart';

import '../../support/d8_stop_spot_guard.dart';

const _noteWords = {
  'ja': ['「現在地を共有」', '取り消しました', '押したときに', 'もう一度', 'おたずねします'],
  'en': ['Share my location', 'Sharing consent'],
};
const _reasonWords = {
  'ja': ['同意', '取り消したので', 'もう一度', 'おたずね'],
  'en': ['sharing consent', 'asked again'],
};

/// The lines [p] draws: glyphs sharing one box top, joiners dropped.
List<String> _lines(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final out = <String>[];
  final buf = StringBuffer();
  double? top;
  for (var i = 0; i < text.length; i++) {
    final b = p.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1));
    if (b.isNotEmpty && b.first.right - b.first.left > 0.01) {
      if (top != null && b.first.top > top + 1) {
        out.add(buf.toString());
        buf.clear();
      }
      top = b.first.top;
    }
    if (text[i] != kWordJoiner) {
      buf.write(text[i] == kNoBreakSpace ? ' ' : text[i]);
    }
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
        if (s < at && at < s + w.length) {
          out.add('$w split: ${lines[k]}|${lines[k + 1]}');
        }
      }
    }
  }
  return out;
}

RenderParagraph _para(WidgetTester t, Finder f) => t.renderObject<RenderParagraph>(
    find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);

/// The same words as plain Text, at [width] and [style]: the control.
Future<int> _plainSplits(WidgetTester t, String text, TextStyle style,
    double width, List<String> words) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
            width: width,
            child: Text(text, key: const Key('control'), style: style)),
      ),
    ),
  ));
  return _splits(_lines(_para(t, find.byKey(const Key('control')))), words)
      .length;
}

void main() {
  final env = D8Env();
  setUp(env.setUp);
  tearDown(env.tearDown);

  test('control: the split finder reports a planted split, and passes a '
      'clean break', () {
    expect(_splits(['共有の同意を取り消', 'しました。'], _noteWords['ja']!), isNotEmpty);
    expect(_splits(['共有の同意を取り消しました。', '次に'], _noteWords['ja']!), isEmpty);
  });

  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang: the withdrawn note and the reason line keep their '
        'words whole at every covered width and text size', (tester) async {
      final bad = <String>[];
      var measured = 0, plainNote = 0, plainReason = 0;
      for (final dpr in kD8Dprs) {
        for (final scale in [0.85, ...kD8Scales]) {
          final g = D8Geometry(lang, dpr, scale);
          expect(await d8SetGeometry(tester, g), isTrue, reason: 'a real face');
          final app = D8App(env, g);
          await app.launch(tester);
          await app.reveal(tester, app.withdraw);
          await tester.tap(app.withdraw);
          await tester.pump();
          final note = _para(tester, app.withdrawnNote);
          bad.addAll(_splits(_lines(note), _noteWords[lang]!)
              .map((s) => 'note ${g.label}: $s'));
          final noteText = app.l.locationConsentWithdrawnNote;
          final noteStyle = note.text.style!;
          final noteWidth = note.constraints.maxWidth;
          await app.reveal(tester, app.shareButton);
          await tester.tap(app.shareButton);
          await app.settleIO(tester);
          await app.settle(tester);
          final reasonFinder =
              find.byKey(const Key('location-consent-asked-again'));
          expect(reasonFinder, findsOneWidget,
              reason: '${g.label}: control: the reason line is drawn');
          final reason = _para(tester, reasonFinder);
          bad.addAll(_splits(_lines(reason), _reasonWords[lang]!)
              .map((s) => 'reason ${g.label}: $s'));
          final reasonStyle = reason.text.style!;
          final reasonWidth = reason.constraints.maxWidth;
          await app.shares.closeAll();
          plainNote += await _plainSplits(
              tester, noteText, noteStyle, noteWidth, _noteWords[lang]!);
          plainReason += await _plainSplits(tester,
              app.l.locationConsentAskedAgainAfterWithdrawal, reasonStyle,
              reasonWidth, _reasonWords[lang]!);
          measured++;
        }
      }
      // ignore: avoid_print
      print('$lang: $measured geometries; plain Text splits a watched word: '
          'note $plainNote, reason $plainReason');
      expect(measured, kD8Dprs.length * (kD8Scales.length + 1));
      expect(bad, isEmpty, reason: '\n${bad.join('\n')}');
      expect(plainNote, greaterThan(0),
          reason: 'control: plain Text never split a watched word in the '
              'note, so the sweep may not reach a break');
      expect(plainReason, greaterThan(0),
          reason: 'control: the same for the reason line');
    });
  }
}
