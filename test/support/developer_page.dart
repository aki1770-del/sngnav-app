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

/// Returns from the development page to her page by its back button.
Future<void> closeDeveloperPage(WidgetTester tester) async {
  // The back button itself: its tooltip is 戻る in Japanese, and
  // tester.pageBack() looks for "Back".
  await tester.tap(find.byType(BackButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  if (find.byKey(kDeveloperPageKey).evaluate().isNotEmpty) {
    throw TestFailure('the development page did not close');
  }
}

/// On the development page, taps the control under [key] and returns to her
/// page. The live-drive demos (the Akita mock position, the visibility band's
/// items and the GPS blackout simulator) have been there since 2026-09-15;
/// until then a test tapped them on her card.
Future<void> tapOnDeveloperPage(WidgetTester tester, Key key) async {
  await openDeveloperPage(tester);
  final control = find.byKey(key);
  if (control.evaluate().length != 1) {
    throw TestFailure('${control.evaluate().length} controls keyed $key on '
        'the development page');
  }
  await tester.ensureVisible(control);
  await tester.pump();
  await tester.tap(control);
  await tester.pump();
  await tester.pump();
  await closeDeveloperPage(tester);
}

/// On the development page, chooses [meters] in the visibility band (null is
/// no override) and returns to her page.
Future<void> chooseVisibilityBandOnDeveloperPage(
    WidgetTester tester, double? meters) async {
  await openDeveloperPage(tester);
  final band = find.byKey(const Key('drive-hud-visibility'));
  if (band.evaluate().length != 1) {
    throw TestFailure('${band.evaluate().length} visibility bands on the '
        'development page');
  }
  await tester.ensureVisible(band);
  await tester.pump();
  await tester.tap(band);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find
      .byWidgetPredicate(
          (w) => w is DropdownMenuItem<double?> && w.value == meters)
      .last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await closeDeveloperPage(tester);
}
