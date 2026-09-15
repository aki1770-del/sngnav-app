/// Every card on her home page is titled in her language, and says what the
/// card is rather than what the team calls it.
///
/// WHY, written before the act (2026-09-15). On 8b445ad fifteen of the twenty
/// card titles were English literals in every language. Three carried the
/// team's own words for things ("HER cohort", "NSC 0.10.0 — #28 / #29 / #30",
/// "LoomFit telemetry"), two carried package names, and one stated a default
/// the dropdown under it does not have: "kei-car-at-65 default" above a value
/// that starts as "unknown / no signal". The helper under the announce button
/// named the app's own gate (音声ゲート, "voice gate") and a severity token
/// ("info-class").
///
/// Read from the rendered page, not from the source: a title is the first text
/// of each card that sits directly in the home page's column. A title that says
/// what a card is in her language cannot also be a title in ours.
///
/// Not ruled here, and named for a ruling instead: the English inside those
/// cards (dropdown values, rows, sources, buttons), the app bar, the banner
/// above the map and the page foot. Public names that stay in a title are the
/// publisher's (気象庁, JMA, AMeDAS).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

final _japanese = RegExp(r'[぀-ヿ㐀-鿿]');
final _latin = RegExp(r'[A-Za-z]');

/// The team's words and code names: its name for the driver, cohort, package
/// and issue tags, versions, identifiers in snake_case or camelCase, station
/// numbers, and the words it uses for its own disciplines.
final _teamWords = RegExp(r'\bHER\b|[Cc]ohort|Loom|\bNSC\b|#\d|'
    r'\b[a-z]+_[a-z_]+\b|\b\d+\.\d+\.\d+\b|[a-z][A-Z][a-z]|\b\d{5}\b|'
    r'verbatim|spine|kei-car|'
    r'ゲート|[Vv]oice gate|info-class|情報クラス|parity');

/// The title of each card in the home page's own column, top to bottom.
List<String> _cardTitles(WidgetTester tester) {
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

Future<List<String>> _titlesIn(WidgetTester tester, String lang) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
      SngnavApp(locale: Locale(lang), actuators: FakeAlertActuators()));
  await tester.pump();
  await tester.pump();
  return _cardTitles(tester);
}

void main() {
  testWidgets('every card title is in Japanese on a Japanese screen, and in '
      'neither language uses the team\'s words', (tester) async {
    final ja = await _titlesIn(tester, 'ja');
    final en = await _titlesIn(tester, 'en');

    expect(ja.length, greaterThanOrEqualTo(20),
        reason: 'precondition: the home page\'s cards were read: $ja');
    expect(en.length, ja.length,
        reason: 'the same cards in both languages: $ja / $en');

    final problems = <String>[
      for (final t in ja)
        if (!_japanese.hasMatch(t) || _latin.hasMatch(t))
          'ja title not in Japanese: 「$t」',
      for (final t in [...ja, ...en])
        for (final m in _teamWords.allMatches(t))
          'team word "${m.group(0)}" in title 「$t」',
      for (var i = 0; i < ja.length && i < en.length; i++)
        if (ja[i] == en[i]) 'title does not follow the language: 「${ja[i]}」',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  testWidgets('the announce button\'s helper says what the button does, in '
      'her words, on her screen', (tester) async {
    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));
      await _titlesIn(tester, lang);
      expect(find.text(l.announceInfoHelper), findsOneWidget,
          reason: 'precondition: the helper for an information-only condition '
              'is on the $lang screen');
      expect(_teamWords.allMatches(l.announceInfoHelper).map((m) => m.group(0)),
          isEmpty,
          reason: '$lang helper: 「${l.announceInfoHelper}」');
    }
  });
}
