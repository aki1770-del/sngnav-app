import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('empty result renders honest no-data message', (tester) async {
    await tester.pumpWidget(wrap(AdvisoryCards(
      loading: false,
      result: const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
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

  testWidgets('loading + null result renders spinner', (tester) async {
    await tester.pumpWidget(wrap(const AdvisoryCards(
      loading: true,
      result: null,
      errorMessage: null,
      onRefresh: _noop,
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

void _noop() {}
