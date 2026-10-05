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

/// [line] as a span to DRAW, in which a line may break only between two of
/// its [phrases] (文節), never inside one; null when [phrases] is null or does
/// not spell [line] exactly, and then the caller draws the plain line, never
/// other words.
///
/// The sibling of [keepTogether] for a line that must not split anywhere but
/// at chosen boundaries, rather than at a few named words (2026-10-04, the
/// next-turn banner). At her width its lines broke inside 可能｜性, ご判｜断 and
/// （現｜在地, and where they broke moved with every text size, so no list of
/// words and no shorter wording held from 1.0 to 2.0.
///
/// Each joiner is a span of its own with no letter spacing. A joiner has no
/// width, but a theme's letter spacing (Material 3 body text adds 0.25 after
/// every character) is added after it too. Measured 2026-10-04 in the app's
/// own theme: the same joiners in a plain string, as [keepTogether] writes
/// them, made 83 of 83 banner lines wider than the plain line; through this
/// span, 0 of 83 differ by a byte. A space at the end of a phrase stays a
/// space, so a line may break after it. A space inside a phrase is drawn as
/// [kNoBreakSpace]: the engine breaks at an ordinary space whatever its
/// neighbours, as [kNoBreakSpace]'s own note records.
///
/// For DRAWING only: pass the plain [line] as the semantics label.
TextSpan? keepPhrasesTogether(String line, List<String>? phrases) {
  if (phrases == null || phrases.join() != line) return null;
  const joiner =
      TextSpan(text: kWordJoiner, style: TextStyle(letterSpacing: 0));
  final children = <InlineSpan>[];
  for (final phrase in phrases) {
    final chars = phrase.characters.toList();
    for (var i = 0; i < chars.length; i++) {
      final inside = i < chars.length - 1;
      children.add(TextSpan(
          text: inside && chars[i] == ' ' ? kNoBreakSpace : chars[i]));
      if (inside) children.add(joiner);
    }
  }
  return TextSpan(children: children);
}
