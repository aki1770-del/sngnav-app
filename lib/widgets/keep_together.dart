/// Keep a few words whole across line breaks.
///
/// WHY (2026-09-25). A screen review rendered the consent card at her
/// geometry and found the sentence about the drive notification broken at its
/// key words. At text scale 1.0, 通知 split as 「通/知」 and the negation split as
/// 「止まりま/せん」, so a line ended on 「止まりま」: at a glance, "reception
/// stops", the opposite of the sentence. At 1.3, the button's name split as
/// 「停/止」. Japanese breaks between almost any two characters, so which words
/// split depends on the width and the text scale, and no wording holds at all
/// of them.
///
/// The tool is U+2060 WORD JOINER. Unicode line breaking (UAX #14, rule LB11)
/// forbids a break on either side of it, and it draws nothing. Placed between
/// the characters of a word, it makes that word unbreakable. The text she
/// reads is unchanged.
///
/// The joined string is for DRAWING ONLY. A screen reader, a search and a
/// test should see the plain words, so a caller passes the plain string as the
/// widget's semantics label. [KeepTogetherText] does both.
library;

import 'package:flutter/widgets.dart';

/// U+2060 WORD JOINER. Zero width; forbids a line break before and after it.
const String kWordJoiner = '\u2060';

/// U+00A0 NO-BREAK SPACE. Drawn as a space; never a line-break opportunity.
///
/// Needed as well as the joiner, and measured, not assumed: with joiners on
/// both sides of an ordinary space, Flutter's text engine still broke
/// 'Android 14' and 'does not stop' at the space, on lines they would have
/// fitted on whole (test/widgets/keep_together_test.dart). A space is a break
/// opportunity to the engine regardless of its neighbours. The Japanese words,
/// which have no space, never split once joined.
const String kNoBreakSpace = '\u00A0';

/// Returns [text] with every occurrence of every word in [words] made
/// unbreakable: [kWordJoiner] between its characters, and each space inside
/// it replaced by [kNoBreakSpace]. [plainOf] of the result gives [text] back
/// exactly.
///
/// Longer words are joined first, so a word that contains another (止まりません
/// contains 止) is joined whole.
String keepTogether(String text, Iterable<String> words) {
  final ordered = words.where((w) => w.runes.length > 1).toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  var out = text;
  for (final word in ordered) {
    final joined = word.runes
        .map((r) => r == 0x20 ? kNoBreakSpace : String.fromCharCode(r))
        .join(kWordJoiner);
    out = out.replaceAll(word, joined);
  }
  return out;
}

/// The words she reads in a [keepTogether] result: joiners removed, no-break
/// spaces read as spaces.
String plainOf(String shown) =>
    shown.replaceAll(kWordJoiner, '').replaceAll(kNoBreakSpace, ' ');

/// A [Text] whose [words] cannot break across lines, and whose semantics
/// label is the plain [data], so assistive technology reads the words and not
/// the joiners.
class KeepTogetherText extends StatelessWidget {
  const KeepTogetherText(
    this.data, {
    super.key,
    required this.words,
    this.style,
  });

  /// The plain text, exactly as the l10n getter returns it.
  final String data;

  /// Words that must never be split across two lines.
  final List<String> words;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      keepTogether(data, words),
      style: style,
      semanticsLabel: data,
    );
  }
}
