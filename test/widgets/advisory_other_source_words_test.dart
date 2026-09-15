/// A weather-warnings source with no name of its own reads in her language.
///
/// Why this test exists. Read 2026-09-15: the advisory cards name a source
/// with no name of its own 'Source', in both languages. Her page reaches it
/// whenever the warnings fetch throws before any publisher answers (the app
/// reports that under the unnamed source), so her Japanese page read
/// 「配信元 Source から取得できませんでした。」.
///
/// The rule tested here: on the Japanese page the line and the card head carry
/// no English word for it; the English page keeps 'Source'.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show advisoryResultForThrownFetch;
import 'package:sngnav_app/widgets/advisory_cards.dart';

Widget _cards(String lang) => MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja'), Locale('en')],
      home: Scaffold(
        body: AdvisoryCards(
          loading: false,
          result: advisoryResultForThrownFetch(Exception('thrown')),
          errorMessage: null,
          onRefresh: () {},
        ),
      ),
    );

void main() {
  testWidgets('ja: a thrown warnings fetch names no English source',
      (tester) async {
    await tester.pumpWidget(_cards('ja'));
    await tester.pump();
    expect(find.text('配信元 その他 から取得できませんでした。'), findsOneWidget);
    expect(find.textContaining('Source'), findsNothing);
  });

  testWidgets('en: the English page keeps its word', (tester) async {
    await tester.pumpWidget(_cards('en'));
    await tester.pump();
    expect(find.text('Could not fetch from Source.'), findsOneWidget);
  });
}
