/// A failed fetch on her page is said in her language and nothing after it.
///
/// WHY, written before the act (2026-09-15). The route line was decided on
/// 2026-09-14: "ルートを取得できませんでした。 / Route fetch failed., with nothing
/// after it" (held in route_act_fetch_test.dart). The same page still showed
/// three other failure lines with the fetch's reason after them: the advisory
/// card named the publisher and then the exception class, its status code and
/// the request's URL; the Akita observation card and each station row of the
/// prefecture card showed the endpoint's name and the HTTP status. None of that
/// is something she can act on in a glance. The lines now carry the app's own
/// words only. This file holds that: each line is read by its key and equals
/// the words, and a marker planted in every reason reaches no text on the page.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/widgets/advisory_cards.dart';

import '../support/fake_alert_actuators.dart';

const _marker = 'MARKER-5e0f';
const _reason = 'JmaAdvisoryFetchException: JMA returned non-2xx (status 400) '
    '[https://www.jma.go.jp/bosai/warning/data/warning/050000.json] $_marker';

/// Every text painted on the screen, one entry per paragraph.
List<String> _paintedTexts(WidgetTester tester) => [
      for (final ro in tester.allRenderObjects.whereType<RenderParagraph>())
        ro.text.toPlainText(),
    ];

/// What a failure line must not carry: the planted marker, and the shapes of
/// the reasons the app's fetches really produce.
final _forbidden = RegExp(
    '$_marker|Exception|https?://|HTTP|status \\d|latest_time|'
    'fetch failed:|でエラー:|に失敗しました:');

Widget _cards(String lang, {String? errorMessage, AdvisoryAggregateResult? r}) =>
    MaterialApp(
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
          result: r,
          errorMessage: errorMessage,
          onRefresh: () {},
        ),
      ),
    );

void main() {
  const words = {
    'ja': (
      advisory: '警報・注意報を取得できませんでした。',
      publisher: '配信元 気象庁 から取得できませんでした。',
      observation: '気象観測を取得できませんでした。',
      station: '取得できませんでした。',
    ),
    'en': (
      advisory: 'Advisory fetch failed.',
      // Since 2026-09-18 the publisher's name reads in the
      // page's language. This line was an English sentence with a Japanese
      // subject, beside nine English strings that all say JMA.
      publisher: 'Could not fetch from JMA.',
      observation: 'The weather observation could not be read.',
      station: 'Fetch failed.',
    ),
  };

  for (final lang in words.keys) {
    final w = words[lang]!;

    testWidgets('$lang: a failed advisory fetch shows the words only',
        (tester) async {
      await tester.pumpWidget(_cards(lang, errorMessage: _reason));
      final line = find.byKey(const Key('advisory-fetch-failed'));
      expect(line, findsOneWidget, reason: 'precondition: the error state');
      expect(tester.widget<Text>(line).data, w.advisory);
      final bad = _paintedTexts(tester).where(_forbidden.hasMatch).toList();
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    testWidgets('$lang: a publisher that failed is named, and its exception '
        'is not shown', (tester) async {
      await tester.pumpWidget(_cards(lang,
          r: const AdvisoryAggregateResult(
            advisories: [],
            providerErrors: [
              AdvisoryProviderError(
                  source: AdvisorySource.jmaJapan, message: _reason),
            ],
          )));
      expect(find.text(w.publisher), findsOneWidget);
      final bad = _paintedTexts(tester).where(_forbidden.hasMatch).toList();
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    testWidgets('$lang: her page after every weather fetch failed shows no '
        'reason', (tester) async {
      await tester.pumpWidget(SngnavApp(
        locale: Locale(lang),
        actuators: FakeAlertActuators(),
        jmaFetch: () async => const JmaFailure('latest_time HTTP 400 $_marker'),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final observation = find.byKey(const Key('jma-fetch-failed'));
      expect(observation, findsOneWidget,
          reason: 'precondition: the Akita observation fetch failed');
      expect(tester.widget<Text>(observation).data, w.observation);

      // Under test every network request is answered 400, so each station of
      // the prefecture card fails for real.
      final stations = find.byKey(const Key('corridor-station-fetch-failed'));
      expect(stations, findsWidgets,
          reason: 'precondition: the prefecture stations failed');
      for (final e in stations.evaluate()) {
        expect((e.widget as Text).data, w.station);
      }

      final bad = _paintedTexts(tester).where(_forbidden.hasMatch).toList();
      expect(bad, isEmpty, reason: bad.join('\n'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
