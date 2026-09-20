// HIE R116-22 — nothing on the advisory card may be pushed off the screen at
// the text scales her own driver profile uses.
//
// WHY, before the act: this app's default profile is ageingRural, and she is
// an elderly driver in Akita. Text scale 2.0 is not a corner case for her; it
// is the setting. In R116-17 I reported "a 44 px overflow at text scale 2.0,
// pre-existing" — measured on the JAPANESE card only. Re-measured here across
// both languages and all five severities, the card's head row overflows in
// ENGLISH at text scale 1.0, the DEFAULT, by 21 to 54 px depending on the
// severity word, on her phone's real width. The English page is what this
// round ships. A RenderFlex overflow is not cosmetic: Flutter's own words are
// "there is content that cannot be seen", and what cannot be seen here is the
// warning's start time and part of the publisher's name.
//
// WHAT THIS GUARD PINS — the PROPERTY: the card lays out with no overflow at
// every scale in her profile range, in every language, at every severity, at
// the phone's measured geometry. It names no widget and no width, so a
// re-layout that keeps everything on screen passes however it is built.
//
// WHAT IT CANNOT SEE: a host raster, not the phone's panel. It proves nothing
// was clipped; it does not prove the result is READABLE, which is the floor
// guard beside it, nor that she takes the right meaning in the time she has —
// NO TIMED GLANCE STUDY EXISTS.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

AdvisoryAggregateResult _result(AdvisorySeverity sev) =>
    AdvisoryAggregateResult(
      advisories: [
        Advisory(
          source: AdvisorySource.jmaJapan,
          eventClass: '大雪警報',
          severity: sev,
          certainty: AdvisoryCertainty.likely,
          urgency: AdvisoryUrgency.expected,
          areaDescription: '秋田県',
          effective: DateTime.utc(2026, 5, 28, 5),
          expires: DateTime.utc(2026, 5, 29, 5),
          headline: '大雪警報',
          description: '大雪による交通障害に警戒してください。',
        ),
      ],
      providerErrors: const [],
      sourcesQueried: 1,
      staleSources: const [
        AdvisoryFeedStaleness(
          source: AdvisorySource.jmaJapan,
          age: Duration(days: 88),
          detail: '050000',
        ),
      ],
    );

Widget _host(String lang, AdvisoryAggregateResult r) => MaterialApp(
      locale: Locale(lang),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
        fontFamilyFallback: const ['SnGNavSymbols'],
      ),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AdvisoryCards(
                  loading: false,
                  result: r,
                  errorMessage: null,
                  onRefresh: () {},
                  retainedAgeMinutes: 10,
                  pointCovered: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  // ⚑ ONE testWidgets PER CASE, AND THAT IS NOT A STYLE CHOICE. The first
  // version of this guard looped the five severities inside one test. Flutter
  // reports a RenderFlex overflow ONCE per render-object instance, so the four
  // severities pumped after the first into the same tree came back "clean"
  // while the floor guard beside this one was failing all five. An instrument
  // that prints a success-shaped value over a real failure is the defect this
  // seat keeps recording about itself; a fresh tree per case is what stops it.
  for (final lang in const ['ja', 'en']) {
    for (final scale in const <double>[1.0, 1.5, 2.0]) {
      final st = scale.toStringAsFixed(1).replaceAll('.', 'p');
      for (final sev in AdvisorySeverity.values) {
        testWidgets(
            'the advisory card puts nothing off the screen — '
            '$lang @ $st / ${sev.name}', (tester) async {
          tester.view.devicePixelRatio = 2.75;
          tester.view.physicalSize = const Size(1080, 2340);
          tester.view.padding = const FakeViewPadding(top: 73, bottom: 130);
          tester.view.viewPadding = const FakeViewPadding(top: 73, bottom: 130);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(() {
            tester.platformDispatcher.clearTextScaleFactorTestValue();
            tester.view.reset();
          });

          await tester.pumpWidget(_host(lang, _result(sev)));
          await tester.pumpAndSettle();
          // C3 — the card must actually be on screen, or the run measured
          // nothing and that is never a pass (HIE-3 C3).
          expect(find.byType(AdvisoryCards), findsOneWidget,
              reason: 'the card did not render at $lang/$st/${sev.name}');
          expect(find.textContaining('大雪警報'), findsWidgets);

          final e = tester.takeException();
          final first = e == null ? 'clean' : e.toString().split('\n').first;
          // ignore: avoid_print
          print('SCALE[$lang/$st/${sev.name}] $first');
          expect(e, isNull,
              reason: 'content cannot be seen on the advisory card at '
                  '$lang, text scale $scale, severity ${sev.name}: $first');
        });
      }
    }
  }
}
