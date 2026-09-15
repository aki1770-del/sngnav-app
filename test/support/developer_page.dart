/// Reaching the development page from her page, the way a developer does.
///
/// The cards built to test the app are not on her home page (2026-09-15). A
/// non-release build launched with `--dart-define=SNGNAV_DEVELOPER_PAGE=true`
/// offers them from an entry in her app bar. A test asks for the same entry
/// with `SngnavApp(developerPageEntry: true)` and opens the page here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The entry in her app bar, drawn only in a build that asks for it.
const Key kDeveloperPageEntryKey = Key('developer-page-entry');

/// The development page's own scroll view.
const Key kDeveloperPageKey = Key('developer-page');

/// Taps the entry in her app bar and waits for the development page.
Future<void> openDeveloperPage(WidgetTester tester) async {
  final entry = find.byKey(kDeveloperPageEntryKey);
  if (entry.evaluate().length != 1) {
    throw TestFailure('${entry.evaluate().length} development page entries on '
        'her app bar; pump SngnavApp(developerPageEntry: true)');
  }
  await tester.tap(entry);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  if (find.byKey(kDeveloperPageKey).evaluate().isEmpty) {
    throw TestFailure('the development page did not open');
  }
}

/// The title of each card in the column of the page on top, top to bottom.
///
/// A title is the first text of each card that sits directly in the page's
/// column; a card inside another card is not a card of the page. A page
/// under another route is offstage and is not read.
List<String> cardTitlesOnTopPage(WidgetTester tester) {
  final scroll = find.byType(SingleChildScrollView).first;
  final titles = <String>[];
  for (final e in find
      .descendant(of: scroll, matching: find.byType(Card))
      .evaluate()) {
    var nested = false;
    e.visitAncestorElements((a) {
      if (a.widget is Card) {
        nested = true;
        return false;
      }
      return a.widget is! SingleChildScrollView;
    });
    if (nested) continue;
    String? title;
    void firstText(Element c) {
      if (title != null) return;
      final w = c.widget;
      if (w is RichText) {
        title = w.text.toPlainText();
        return;
      }
      c.visitChildren(firstText);
    }

    e.visitChildren(firstText);
    titles.add(title ?? '(card with no text)');
  }
  return titles;
}
