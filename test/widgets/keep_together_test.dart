// The drive sentence's key words cannot break across lines (2026-09-25).
//
// WHY: a screen review rendered the consent card at her geometry and found
// 通知 split as 「通/知」 and the negation split as 「止まりま/せん」 at text scale
// 1.0, so a line ended on "reception stops"; at 1.3 the button name split as
// 「停/止」.
// Which words split depends on width and scale, so this sweeps both.
//
// WHAT A PASS MEANS: the text engine's line breaker, which is the one the app
// uses, found no break inside any protected word at any width and scale swept.
// It does not mean anyone has looked at the card on a device. The negative control proves the
// sweep can see a split: without the joiners, the same words DO split.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/widgets/keep_together.dart';

const _style = TextStyle(fontSize: 12);

/// The width [word] needs on one line at [scale].
double _wordWidth(String word, double scale) {
  final p = TextPainter(
    text: TextSpan(text: keepTogether(word, [word]), style: _style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  final w = p.width;
  p.dispose();
  return w;
}

/// Every place, across the sweep, where a line boundary falls strictly inside
/// an occurrence of one of [words] in the laid-out [shown] text.
///
/// A line narrower than the word itself is skipped for that word: there the
/// engine MUST break it somewhere (an emergency break), with or without
/// joiners, and that is not the defect the review saw. Its splits happened on
/// lines the word could have fitted on whole.
List<String> _splits(String shown, List<String> words) {
  final found = <String>[];
  for (final scale in const [1.0, 1.15, 1.3, 1.5, 2.0]) {
    final needs = {for (final w in words) w: _wordWidth(w, scale)};
    for (var width = 60.0; width <= 420.0; width += 1.0) {
      final painter = TextPainter(
        text: TextSpan(text: shown, style: _style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(scale),
      )..layout(maxWidth: width);
      for (final word in words) {
        if (needs[word]! >= width) continue;
        final pattern = keepTogether(word, [word]);
        // Search for the word as it is drawn: joined, or plain.
        for (final needle in {pattern, word}) {
          var at = shown.indexOf(needle);
          while (at >= 0) {
            final first = painter.getLineBoundary(TextPosition(offset: at));
            final last = painter.getLineBoundary(
                TextPosition(offset: at + needle.length - 1));
            if (first != last) {
              found.add('"$word" at width $width, scale $scale');
            }
            at = shown.indexOf(needle, at + needle.length);
          }
        }
      }
      painter.dispose();
    }
  }
  return found;
}

void main() {
  group('keepTogether (pure)', () {
    test('joins every character of each word and nothing else', () {
      const text = '消しても受信は止まりません。「停止」を押してください。';
      final shown = keepTogether(text, const ['止まりません', '停止']);
      expect(shown, contains('止\u2060ま\u2060り\u2060ま\u2060せ\u2060ん'));
      expect(shown, contains('停\u2060止'));
      expect(plainOf(shown), text,
          reason: 'she must read exactly the words the getter holds');
    });

    test('a word inside a longer word is joined as part of the longer one',
        () {
      final shown = keepTogether('止まりません', const ['止', 'まり', '止まりません']);
      expect(shown, '止\u2060ま\u2060り\u2060ま\u2060せ\u2060ん');
    });

    test('Latin phrases keep their spaces, joined', () {
      final shown = keepTogether('that does not stop the drive',
          const ['does not stop']);
      expect(plainOf(shown), 'that does not stop the drive');
      // Every character is joined, and each space inside the phrase is a
      // no-break space: the engine breaks at an ordinary space even between
      // joiners (measured by the sweep below before the no-break space was
      // added).
      expect(shown,
          contains('s\u2060\u00A0\u2060n\u2060o\u2060t\u2060\u00A0\u2060s'));
      // The space OUTSIDE the phrase stays an ordinary, breakable space.
      expect(shown, startsWith('that '));
    });
  });

  group('the drive sentence cannot break inside a protected word', () {
    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));

      test('$lang: joined text never splits a protected word across lines',
          () {
        final shown = keepTogether(l.driveDisclosure, l.driveDisclosureKeepTogether);
        expect(_splits(shown, l.driveDisclosureKeepTogether), isEmpty);
      });
    }

    test('NEGATIVE CONTROL: without the joiners the same sweep finds splits '
        '(the check can see the defect it guards)', () {
      const ja = AppL10n(Locale('ja'));
      final splits = _splits(ja.driveDisclosure, ja.driveDisclosureKeepTogether);
      expect(splits, isNotEmpty,
          reason: 'if the plain Japanese text never splits at any width, this '
              'sweep is blind and its pass above means nothing');
    });

    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));
      test('$lang: the dead-zone forecast caption never splits its negation',
          () {
        final plain = l.forecastMemoryCaption('06:35');
        for (final w in l.forecastMemoryCaptionKeepTogether) {
          expect(plain, contains(w));
        }
        final shown = keepTogether(plain, l.forecastMemoryCaptionKeepTogether);
        expect(_splits(shown, l.forecastMemoryCaptionKeepTogether), isEmpty);
      });
    }

    test('every protected word actually occurs in the sentence it protects',
        () {
      for (final lang in const ['ja', 'en']) {
        final l = AppL10n(Locale(lang));
        for (final w in l.driveDisclosureKeepTogether) {
          expect(l.driveDisclosure, contains(w),
              reason: '$lang: "$w" protects nothing if it is not in the text');
        }
      }
    });
  });

  testWidgets('KeepTogetherText is read as the plain words', (tester) async {
    final handle = tester.ensureSemantics();
    const plain = '消しても受信は止まりません。';
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: KeepTogetherText(plain, words: ['止まりません']),
    ));
    expect(find.bySemanticsLabel(plain), findsOneWidget,
        reason: 'a screen reader must hear the words, never the joiners');
    handle.dispose();
  });
}
