/// Her home page carries her cards; the cards built to test the app are on a
/// page of their own, which a developer reaches only in a build that asks.
///
/// WHY, written before the act (2026-09-15). On 6d530fc her home page held
/// twenty cards, and eleven exist for the people who build the app:
///
/// * five are titled 開発用, and one is the tuning record;
/// * the driver-type and vehicle selectors feed only development cards. The
///   live drive reads neither: its controller is built with no driver type and
///   no vehicle (main.dart:1268-1275 at 6d530fc);
/// * three more show only what a moved selector chose: the warning thresholds,
///   which no live drive applies, and the chosen road condition's names and
///   guidance, with the announce button that speaks that guidance.
///
/// The move keeps every value where it was, in the home page's state, so a
/// choice made on the development page reaches the same code it reached
/// before. That the live drive gives her the same rung and speech whatever is
/// chosen there is test/services/live_drive_thresholds_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show DriverProfile, RoadSurfaceCondition;
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/developer_page.dart';
import '../support/fake_alert_actuators.dart';

List<String> _herTitles(AppL10n l) => [
      l.mapSectionTitle,
      l.driveHudTitle,
      l.routeSectionTitle,
      l.maneuverSectionTitle,
      l.akitaObservationSectionTitle,
      l.prefectureObservationsSectionTitle,
      l.advisoriesSectionTitle,
      l.logShareSectionTitle,
      l.diarySectionTitle,
    ];

List<String> _developmentTitles(AppL10n l) => [
      l.driverTypeSectionTitle,
      l.simulatedRoadConditionSectionTitle,
      l.vehicleTypeSectionTitle,
      l.driverStateInputsSectionTitle,
      l.warningThresholdsSectionTitle,
      l.roadConditionNamesSectionTitle,
      l.roadConditionGuidanceSectionTitle,
      l.alertRateLimitSectionTitle,
      l.tuningRecordSectionTitle,
      l.glanceAndVoicePacingSectionTitle,
      l.mapDrawingAndDataSectionTitle,
    ];

Future<void> _launch(WidgetTester tester, String lang,
    {bool entry = false}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(entry
      ? SngnavApp(
          locale: Locale(lang),
          actuators: FakeAlertActuators(),
          developerPageEntry: true)
      : SngnavApp(locale: Locale(lang), actuators: FakeAlertActuators()));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('her home page shows her cards only, in this order, in both '
      'languages', (tester) async {
    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));
      await _launch(tester, lang);
      expect(cardTitlesOnTopPage(tester), _herTitles(l), reason: lang);
      final left = [
        for (final t in _developmentTitles(l))
          if (find.text(t).evaluate().isNotEmpty) t,
        if (find.byType(DropdownButton<DriverProfile>).evaluate().isNotEmpty)
          'the driver-type selector',
        if (find
            .byType(DropdownButton<RoadSurfaceCondition>)
            .evaluate()
            .isNotEmpty)
          'the simulated road-condition selector',
        if (find.byKey(const Key('announce-alert-button')).evaluate().isNotEmpty)
          'the announce button',
      ];
      expect(left, isEmpty, reason: '$lang: still on her page: $left');
    }
  });

  testWidgets('with no entry asked for, nothing on her page leads to the '
      'development page', (tester) async {
    await _launch(tester, 'ja');
    expect(find.byKey(kDeveloperPageEntryKey), findsNothing);
    expect(find.byKey(kDeveloperPageKey), findsNothing);
  });

  testWidgets('a build that asks for it reaches every development card from '
      'her app bar, in the order they had, and returns to her page',
      (tester) async {
    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));
      await _launch(tester, lang, entry: true);
      expect(cardTitlesOnTopPage(tester), _herTitles(l),
          reason: '$lang: the entry adds no card to her page');
      await openDeveloperPage(tester);
      expect(find.text(l.developerPageTitle), findsOneWidget, reason: lang);
      expect(cardTitlesOnTopPage(tester), _developmentTitles(l), reason: lang);
      // The back button itself: its tooltip is 戻る in Japanese, and
      // tester.pageBack() looks for "Back".
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(kDeveloperPageKey), findsNothing, reason: lang);
      expect(cardTitlesOnTopPage(tester), _herTitles(l), reason: lang);
    }
  });

  testWidgets('a choice made on the development page reaches the cards that '
      'read it while the page is open', (tester) async {
    await _launch(tester, 'ja', entry: true);
    await openDeveloperPage(tester);
    const ja = AppL10n(Locale('ja'));

    // The vehicle type feeds the warning thresholds card beside it.
    expect(find.text('350 m (+50)'), findsNothing,
        reason: 'precondition: no vehicle override before the choice');
    final vehicle = find.byType(DropdownButton<String?>);
    await tester.ensureVisible(vehicle);
    await tester.pump();
    await tester.tap(vehicle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find
        .byWidgetPredicate(
            (w) => w is DropdownMenuItem<String?> && w.value == 'kei-car')
        .last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('350 m (+50)'), findsOneWidget,
        reason: 'the thresholds card redrew with the chosen vehicle');

    // The simulated road condition feeds the announce button's helper.
    expect(find.text(ja.announceInfoHelper), findsOneWidget,
        reason: 'precondition: the default condition is information only');
    final condition = find.byType(DropdownButton<RoadSurfaceCondition>);
    await tester.ensureVisible(condition);
    await tester.pump();
    await tester.tap(condition);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find
        .byWidgetPredicate((w) =>
            w is DropdownMenuItem<RoadSurfaceCondition> &&
            w.value == RoadSurfaceCondition.ice)
        .last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(ja.announceFiresHelper('critical')), findsOneWidget,
        reason: 'the guidance card redrew with the chosen condition');
  });
}
