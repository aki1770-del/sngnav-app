/// The page foot and the prefecture weather card's source line keep what she
/// needs, in her language, and none of the project's internal words.
///
/// WHY, written before the act (2026-09-15). On 6d530fc the foot of her home
/// page was one English paragraph in every language: why the Akita station was
/// chosen, in the project's internal shorthand, "honest accuracy", "mock dot is
/// amber (dev)", "5-station JMA verbatim (op-(e) aggregation only)" and seven
/// package names. Beside them sat the one thing she needs from it, that routes
/// do not consider snow, and where routes and weather come from. The
/// prefecture weather card's source line cited one of the project's internal
/// decisions by its article number. Decided 2026-09-15: those words and the package
/// names go; the foot keeps that routing does not consider snow and the
/// attribution; the card keeps its data source.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

final _cjk = RegExp(r'[぀-ヿ㐀-鿿]');

/// The team's words and code names seen on these lines on 6d530fc, and the
/// words the project uses for its own disciplines.
final _teamWords = RegExp(r'\bHER\b|\bV\d+\b|op-\(|Article|verbatim|'
    r'[Hh]onest|\(dev\)|[Cc]orridor|derivation');

/// Package names, where they come from, and where their versions are kept.
final _packageWords = RegExp(r'\b[a-z]+_[a-z_]+\b|pub\.dev|pubspec|SNGNav');

Future<void> _launch(WidgetTester tester, String lang) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
      SngnavApp(locale: Locale(lang), actuators: FakeAlertActuators()));
  await tester.pump();
  await tester.pump();
}

/// The foot of the page: in the page's scroll view, so not the app bar's title.
String _foot(WidgetTester tester) {
  final f = find.descendant(
      of: find.byType(SingleChildScrollView).first,
      matching: find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').startsWith('sngnav-app ')));
  expect(f, findsOneWidget, reason: 'precondition: the page foot is drawn');
  return tester.widget<Text>(f).data!;
}

/// The texts inside the prefecture weather card other than its title.
List<String> _prefectureCardLines(WidgetTester tester, AppL10n l) {
  final title = find.text(l.prefectureObservationsSectionTitle);
  expect(title, findsOneWidget, reason: 'precondition: the card is drawn');
  final card = find.ancestor(of: title, matching: find.byType(Card)).first;
  return [
    for (final e
        in find.descendant(of: card, matching: find.byType(Text)).evaluate())
      if ((e.widget as Text).data != l.prefectureObservationsSectionTitle)
        (e.widget as Text).data ?? '',
  ];
}

void main() {
  testWidgets('the page foot says routes do not consider snow and where routes '
      'and weather come from, in her language, with no team word or package '
      'name', (tester) async {
    final feet = <String, String>{};
    for (final lang in const ['ja', 'en']) {
      await _launch(tester, lang);
      final foot = _foot(tester);
      feet[lang] = foot;
      final problems = [
        for (final m in _teamWords.allMatches(foot)) 'team word "${m.group(0)}"',
        for (final m in _packageWords.allMatches(foot))
          'package word "${m.group(0)}"',
      ];
      expect(problems, isEmpty, reason: '$lang foot 「$foot」: $problems');
      expect(foot, contains('OSRM'), reason: '$lang: where routes come from');
    }
    final ja = feet['ja']!, en = feet['en']!;
    expect(_cjk.hasMatch(ja), isTrue, reason: 'ja foot 「$ja」');
    final latinLeft = ja
        .replaceAll(RegExp(r'sngnav-app|OSRM|\d'), '')
        .replaceAll(RegExp(r'[^A-Za-z]'), '');
    expect(latinLeft, isEmpty,
        reason: 'ja foot carries English beyond the app and router names: 「$ja」');
    expect(ja, contains('雪を考慮しません'), reason: 'ja 「$ja」');
    expect(ja, contains('気象庁'), reason: 'ja 「$ja」');
    expect(en, contains('do not consider snow'), reason: 'en 「$en」');
    expect(en, contains('JMA'), reason: 'en 「$en」');
  });

  testWidgets('the prefecture weather card keeps its source, in her language, '
      'and cites no internal decision of the project', (tester) async {
    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));
      await _launch(tester, lang);
      final lines = _prefectureCardLines(tester, l);
      final problems = [
        for (final t in lines)
          for (final m in _teamWords.allMatches(t))
            'team word "${m.group(0)}" in 「$t」',
      ];
      expect(problems, isEmpty, reason: '$lang: $problems');
      final source = lines.where((t) => lang == 'ja'
          ? t.contains('出典') && t.contains('気象庁アメダス')
          : t.contains('Source') && t.contains('JMA AMeDAS'));
      expect(source, hasLength(1),
          reason: '$lang: one line names the source: $lines');
    }
  });
}
