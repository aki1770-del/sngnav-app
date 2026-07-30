import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('COMPLETE empty result renders honest no-data message',
      (tester) async {
    await tester.pumpWidget(wrap(AdvisoryCards(
      loading: false,
      // B04-2 — `sourcesQueried` is what makes this an all-clear rather than
      // an unknown. Before the gate this test passed WITHOUT it, which is
      // precisely the defect: it pinned the fabricated clear as correct.
      result: const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 1,
      ),
      errorMessage: null,
      onRefresh: () {},
    )));
    expect(find.text('No active advisories at this location.'), findsOneWidget);
  });

  testWidgets('JMA advisory renders eventClass JA verbatim + 気象庁 label',
      (tester) async {
    final advisory = Advisory(
      source: AdvisorySource.jmaJapan,
      eventClass: '大雪警報',
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.unknown,
      urgency: AdvisoryUrgency.unknown,
      areaDescription: '秋田中央',
      effective: DateTime.utc(2026, 1, 15, 4, 23),
      expires: null,
      headline: '秋田県では、大雪に警戒してください。',
      description: '秋田県では、大雪に警戒してください。',
    );
    await tester.pumpWidget(wrap(AdvisoryCards(
      loading: false,
      result: AdvisoryAggregateResult(
        advisories: [advisory],
        providerErrors: const [],
      ),
      errorMessage: null,
      onRefresh: () {},
    )));
    expect(find.text('大雪警報'), findsOneWidget);
    expect(find.text('気象庁'), findsOneWidget);
    expect(find.text('秋田中央'), findsOneWidget);
    expect(find.text('秋田県では、大雪に警戒してください。'), findsOneWidget);
  });

  testWidgets('NWS advisory renders eventClass EN verbatim + NWS label',
      (tester) async {
    final advisory = Advisory(
      source: AdvisorySource.nwsUnitedStates,
      eventClass: 'Winter Storm Warning',
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: 'Upper Peninsula of Michigan',
      effective: DateTime.utc(2026, 1, 15, 4, 23),
      expires: DateTime.utc(2026, 1, 16, 4, 23),
      headline: 'Heavy snow expected.',
      description: 'Total snow accumulations of 8 to 14 inches.',
    );
    await tester.pumpWidget(wrap(AdvisoryCards(
      loading: false,
      result: AdvisoryAggregateResult(
        advisories: [advisory],
        providerErrors: const [],
      ),
      errorMessage: null,
      onRefresh: () {},
    )));
    expect(find.text('Winter Storm Warning'), findsOneWidget);
    expect(find.text('NWS'), findsOneWidget);
    expect(find.text('Heavy snow expected.'), findsOneWidget);
  });

  testWidgets('errorMessage renders with retry button', (tester) async {
    var refreshed = false;
    await tester.pumpWidget(wrap(AdvisoryCards(
      loading: false,
      result: null,
      errorMessage: 'Some transport error',
      onRefresh: () => refreshed = true,
    )));
    expect(find.textContaining('Some transport error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(refreshed, isTrue);
  });

  testWidgets(
      'B04: empty advisories + provider errors does NOT render the '
      'all-clear — warnings are UNKNOWN, not absent', (tester) async {
    await tester.pumpWidget(wrap(AdvisoryCards(
      loading: false,
      result: const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [
          AdvisoryProviderError(
            source: AdvisorySource.jmaJapan,
            message: 'HTTP 503',
          ),
        ],
      ),
      errorMessage: null,
      onRefresh: () {},
    )));
    // The positive all-clear claim must NOT appear.
    expect(find.text('No active advisories at this location.'), findsNothing);
    // The honest degraded state appears, with the per-publisher error note.
    expect(find.byKey(const Key('advisory-unknown-degraded')), findsOneWidget);
    expect(find.textContaining('unknown'), findsOneWidget);
    expect(find.textContaining('HTTP 503'), findsOneWidget);
  });

  testWidgets(
      'B04 (ja surface): degraded state renders the Japanese honest-unknown '
      'line, never the all-clear', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: AdvisoryCards(
          loading: false,
          result: const AdvisoryAggregateResult(
            advisories: [],
            providerErrors: [
              AdvisoryProviderError(
                source: AdvisorySource.jmaJapan,
                message: 'HTTP 503',
              ),
            ],
          ),
          errorMessage: null,
          onRefresh: () {},
        ),
      ),
    ));
    expect(find.text('この地点に有効な警報・注意報はありません。'), findsNothing);
    expect(
      find.textContaining('有効な警報・注意報の有無は不明です'),
      findsOneWidget,
    );
  });

  testWidgets(
      'all-clear still renders when the fetch genuinely succeeded clean '
      '(every source asked, none errored)', (tester) async {
    await tester.pumpWidget(wrap(AdvisoryCards(
      loading: false,
      // B04-2 — this test's original name was "(no provider errors)", which
      // was the B04-era belief that an absence of errors is enough to back
      // the all-clear. It is not: nobody having errored is also true when
      // nobody was ASKED. The rule is `canAssertNoAdvisory` — asked AND
      // answered — so the provenance below is load-bearing, not decoration.
      result: const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 1,
      ),
      errorMessage: null,
      onRefresh: () {},
    )));
    expect(find.text('No active advisories at this location.'), findsOneWidget);
    expect(find.byKey(const Key('advisory-unknown-degraded')), findsNothing);
    expect(find.byKey(const Key('advisory-lookup-incomplete')), findsNothing);
  });

  testWidgets(
      'N10: retained advisories carry a visible stale-age banner',
      (tester) async {
    final advisory = Advisory(
      source: AdvisorySource.jmaJapan,
      eventClass: '大雪警報',
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.unknown,
      urgency: AdvisoryUrgency.unknown,
      areaDescription: '秋田中央',
      effective: DateTime.utc(2026, 1, 15, 4, 23),
      expires: DateTime.utc(2026, 1, 15, 18),
      headline: '秋田県では、大雪に警戒してください。',
      description: '秋田県では、大雪に警戒してください。',
    );
    await tester.pumpWidget(wrap(AdvisoryCards(
      loading: false,
      result: AdvisoryAggregateResult(
        advisories: [advisory],
        providerErrors: const [
          AdvisoryProviderError(
            source: AdvisorySource.jmaJapan,
            message: 'HTTP 503',
          ),
        ],
      ),
      errorMessage: null,
      onRefresh: () {},
      retainedAgeMinutes: 42,
    )));
    // The hazard is still shown (trust the hazard)…
    expect(find.text('大雪警報'), findsOneWidget);
    // …but never masquerades as current.
    expect(find.byKey(const Key('advisory-retained-stale')), findsOneWidget);
    expect(find.textContaining('42 min'), findsOneWidget);
  });

  testWidgets('fresh advisories render no stale banner', (tester) async {
    final advisory = Advisory(
      source: AdvisorySource.jmaJapan,
      eventClass: '大雪警報',
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.unknown,
      urgency: AdvisoryUrgency.unknown,
      areaDescription: '秋田中央',
      effective: DateTime.utc(2026, 1, 15, 4, 23),
      expires: null,
      headline: '',
      description: '',
    );
    await tester.pumpWidget(wrap(AdvisoryCards(
      loading: false,
      result: AdvisoryAggregateResult(
        advisories: [advisory],
        providerErrors: const [],
      ),
      errorMessage: null,
      onRefresh: () {},
    )));
    expect(find.byKey(const Key('advisory-retained-stale')), findsNothing);
  });

  testWidgets('loading + null result renders spinner', (tester) async {
    await tester.pumpWidget(wrap(const AdvisoryCards(
      loading: true,
      result: null,
      errorMessage: null,
      onRefresh: _noop,
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // ===================================================================
  // B04-2 — the fabricated-clear gate.
  //
  // A total feed outage and a genuinely clear sky arrive at this widget as
  // the SAME value: an empty `advisories` list. The positive all-clear
  // ("no advisories are in force") is a CLAIM ABOUT COMPLETENESS, and it
  // may only render when the lookup was complete —
  // `AdvisoryAggregateResult.canAssertNoAdvisory` (condition_aggregator
  // 0.0.8) is the one predicate that answers that, and it is false on all
  // three incomplete shapes: a provider errored, nobody was asked, or the
  // result carries no provenance at all.
  //
  // Before this gate the widget checked only `providerErrors.isNotEmpty` —
  // ONE of those three. The other two rendered 「この地点に有効な警報・注意報は
  // ありません。」 to a driver in unexpected snow when the truth was
  // "we could not look."
  // ===================================================================
  group('fabricated-clear gate — an empty list is not an all-clear', () {
    testWidgets(
        'ZERO sources asked (nobody was queried) does NOT render the '
        'positive all-clear', (tester) async {
      await tester.pumpWidget(wrap(AdvisoryCards(
        loading: false,
        // canAssertNoAdvisory == false: n == 0. No provider ERRORED —
        // there was no provider to error. Absence of a lookup, not calm.
        result: const AdvisoryAggregateResult(
          advisories: [],
          providerErrors: [],
          sourcesQueried: 0,
        ),
        errorMessage: null,
        onRefresh: _noop,
      )));
      expect(
        find.text('No active advisories at this location.'),
        findsNothing,
        reason: 'zero sources asked is not an all-clear',
      );
      expect(
        find.byKey(const Key('advisory-lookup-incomplete')),
        findsOneWidget,
      );
    });

    testWidgets(
        'UNKNOWN provenance (sourcesQueried absent) does NOT render the '
        'positive all-clear', (tester) async {
      await tester.pumpWidget(wrap(AdvisoryCards(
        loading: false,
        // canAssertNoAdvisory == false: n == null. We will not claim
        // completeness on a result that cannot say who answered. This is
        // the fail-safe backstop — any future result-construction site
        // that forgets provenance renders honest-unknown, never a
        // fabricated clear.
        result: const AdvisoryAggregateResult(
          advisories: [],
          providerErrors: [],
        ),
        errorMessage: null,
        onRefresh: _noop,
      )));
      expect(
        find.text('No active advisories at this location.'),
        findsNothing,
        reason: 'a result with no provenance cannot back a completeness claim',
      );
      expect(
        find.byKey(const Key('advisory-lookup-incomplete')),
        findsOneWidget,
      );
    });

    // The anti-cry-wolf pin. This test must pass BEFORE and AFTER the gate:
    // it proves the fix distinguishes "could not look" from "looked and it
    // is clear" rather than blanket-suppressing the all-clear. An
    // instrument that can never say "clear" is as useless to HER as one
    // that always does.
    testWidgets(
        'a COMPLETE lookup with no advisories DOES render the all-clear '
        '(no cry-wolf)', (tester) async {
      await tester.pumpWidget(wrap(AdvisoryCards(
        loading: false,
        // canAssertNoAdvisory == true: every source answered, none errored.
        // The silence is real and she may be told so.
        result: const AdvisoryAggregateResult(
          advisories: [],
          providerErrors: [],
          sourcesQueried: 1,
        ),
        errorMessage: null,
        onRefresh: _noop,
      )));
      expect(
        find.text('No active advisories at this location.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('advisory-lookup-incomplete')),
        findsNothing,
      );
    });
  });
}

void _noop() {}
