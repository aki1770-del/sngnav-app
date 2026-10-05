/// The words a [Text] draws, as she reads them, for tests.
///
/// The next-turn banner draws its Japanese lines through a span with word
/// joiners between the characters of each phrase (keepPhrasesTogether in
/// lib/widgets/keep_together.dart, 2026-10-04). Those words are then not in
/// `Text.data`, and `find.text` and `find.textContaining` never match them:
/// a finder expecting one goes red, and a finder expecting NONE passes on any
/// screen. Every test that looks for the banner's words looks through these,
/// in both directions.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/widgets/keep_together.dart' show plainOf;

/// The plain words [text] draws, whether it carries them as a string or as a
/// span with word joiners.
String wordsOf(Text text) =>
    plainOf(text.data ?? text.textSpan?.toPlainText() ?? '');

/// Every [Text] whose plain words are exactly [words].
Finder findWords(String words) => find.byWidgetPredicate(
      (w) => w is Text && wordsOf(w) == words,
      description: 'Text reading "$words"',
    );

/// Every [Text] whose plain words contain [part].
Finder findWordsContaining(String part) => find.byWidgetPredicate(
      (w) => w is Text && wordsOf(w).contains(part),
      description: 'Text containing "$part"',
    );
