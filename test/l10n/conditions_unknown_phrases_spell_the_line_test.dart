/// The phrases the absence line is drawn with spell, byte for byte, the line
/// she hears, and the line drawn through them reads as those words.
///
/// WHY. The screen draws the Japanese absence line so that it breaks only
/// between two phrases (kConditionsUnknownJaPhrases, beside the line in
/// lib/services/staleness_policy.dart). The voice and the screen reader get
/// the plain line; the list is a second source beside it. A list that stopped
/// spelling its line would be drawn plain, never as other words, and would
/// break inside a word again at her text size with nothing failing. This file
/// is what notices.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/staleness_policy.dart';
import 'package:sngnav_app/widgets/keep_together.dart';

void main() {
  test('the phrases spell the line the voice speaks', () {
    expect(kConditionsUnknownJaPhrases.join(), kConditionsUnknownJaSpokenText);
    expect(kConditionsUnknownJaPhrases.every((p) => p.isNotEmpty), isTrue);
  });

  test('drawn through them, the line reads as its own words, with a joiner '
      'inside every phrase and none between two', () {
    final span = keepPhrasesTogether(
        kConditionsUnknownJaSpokenText, kConditionsUnknownJaPhrases);
    expect(span, isNotNull,
        reason: 'a null span is drawn plain, and breaks inside a word');
    final drawn = span!.toPlainText();
    expect(plainOf(drawn), kConditionsUnknownJaSpokenText);
    var joiners = 0;
    for (final p in kConditionsUnknownJaPhrases) {
      joiners += p.characters.length - 1;
    }
    expect(kWordJoiner.allMatches(drawn).length, joiners);
  });

  test('control: a list that does not spell the line gives no span', () {
    final wrong = [...kConditionsUnknownJaPhrases]..removeLast();
    expect(keepPhrasesTogether(kConditionsUnknownJaSpokenText, wrong), isNull);
  });
}
