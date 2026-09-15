/// The live-drive card and the next-turn section speak in words she can read.
///
/// Why this test exists. Read on 6a72b41 in the real widget tree and in the
/// strings:
///
/// * The card's title and footer were English literals in both languages.
///   The title carried a work-package tag ("WS6"); the footer carried the
///   team's name for the driver ("HER"), a self-description ("honestly
///   degraded") and a team slogan ("driver-always-drives").
/// * The Japanese description carried another work-package tag ("WS5"), and
///   called the position 正直 ("honest"). Two announce lines named the app's
///   own speech routing (実測ウォッチの経路, 音声ゲート), and two English ones a
///   verification code ("HEAR/FEEL").
/// * The footer said the position is real, while the Akita mock position feeds
///   this card; and that visibility is unknown by default, while the JMA Akita
///   station's reading feeds it whenever the station reports one.
/// * The next-turn section's title was English in Japanese mode, and called its
///   narration "honest".
/// * When caution rose only because visibility was not measured, the announce
///   line said the specific hazard is read aloud elsewhere. Nothing spoke.
///
/// Publishers' names stay: NWS and JMA are where the card's advisories and
/// visibility come from. Package names, pub.dev and pubspec.lock are not the
/// team's words either, but they are not for her glance: ruled 2026-09-15,
/// they left her card for the development page.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/app_unknowns.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/developer_page.dart';
import '../support/fake_alert_actuators.dart';

final _cjk = RegExp(r'[぀-ヿ㐀-鿿＀-￯]');

/// Words that exist only inside the team that built the app. "HER" is matched
/// in capitals only, so an English "her" is not caught.
final _teamWords = RegExp(r'\bWS\d+\b|\bHER\b|[Hh]onest|正直|実測ウォッチ|'
    r'音声ゲート|[Vv]oice gate|measured-watch|HEAR/FEEL|driver-always-drives');

final _now = DateTime.utc(2026, 1, 14, 21);

/// A fresh Akita observation that carries no visibility: the station answered,
/// above freezing and dry, and reported no visibility.
JmaObservation _freshObsWithoutVisibility() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5.0,
      humidityPercent: 50,
      windMetersPerSecond: 1.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260115060000',
      fetchedAt: _now,
    );

Future<FakeAlertActuators> _boot(WidgetTester tester, String lang,
    {Future<JmaResult> Function()? jma}) async {
  final a = FakeAlertActuators();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: Locale(lang),
    clock: () => _now,
    jmaFetch: jma ?? () async => const JmaFailure('no network in this test'),
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final b = find.byKey(key);
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await tester.pump();
  await tester.pump();
}

/// The live-drive card, found as the instrument that looks at her map finds
/// it: by the key on its own description, never by its title's words.
Finder _card() => find
    .ancestor(
        of: find.byKey(const Key('drive-hud-description')),
        matching: find.byType(Card))
    .first;

List<String> _cardTexts(WidgetTester tester) => [
      for (final e in find
          .descendant(of: _card(), matching: find.byType(Text))
          .evaluate())
        (e.widget as Text).data ??
            (e.widget as Text).textSpan?.toPlainText() ??
            '',
    ];

void _expectNoTeamWords(List<String> texts, String when) {
  for (final t in texts) {
    expect(_teamWords.hasMatch(t), isFalse, reason: '$when: 「$t」');
  }
}

/// Every card text in three states the card's own controls reach: before
/// sharing, sharing the Akita mock, and after one simulated blackout.
Future<List<String>> _cardTextsThroughStates(WidgetTester tester) async {
  final seen = <String>[];
  seen.addAll(_cardTexts(tester));
  await _tapKey(tester, const Key('use-mock-button'));
  seen.addAll(_cardTexts(tester));
  await _tapKey(tester, const Key('drive-hud-blackout-button'));
  seen.addAll(_cardTexts(tester));
  return seen;
}

void main() {
  testWidgets('Japanese: the title and footer are Japanese, and no card text '
      'carries the team\'s words', (tester) async {
    await _boot(tester, 'ja');
    final title = tester
            .widget<Text>(
                find.descendant(of: _card(), matching: find.byType(Text)).first)
            .data ??
        '';
    expect(_cjk.hasMatch(title), isTrue, reason: 'title 「$title」');
    expect(title, isNot(contains('Live drive')));

    final texts = await _cardTextsThroughStates(tester);
    _expectNoTeamWords(texts, 'ja');
    expect(texts.where((t) => t.startsWith('Position is')), isEmpty,
        reason: 'the English footer is not drawn in Japanese');
    final footer = find.byKey(const Key('drive-hud-footer'));
    expect(footer, findsOneWidget);
    final footerText = tester.widget<Text>(footer).data ?? '';
    expect(_cjk.hasMatch(footerText), isTrue, reason: footerText);
    expect(footerText, contains('秋田のモック位置'),
        reason: 'the mock position feeds this card, so the footer names it');
  });

  testWidgets('English: no card text carries the team\'s words, and the footer '
      'names the mock and the station', (tester) async {
    await _boot(tester, 'en');
    final texts = await _cardTextsThroughStates(tester);
    _expectNoTeamWords(texts, 'en');
    final footerText =
        tester.widget<Text>(find.byKey(const Key('drive-hud-footer'))).data ??
            '';
    expect(footerText, contains('Akita mock'));
    expect(footerText, contains('JMA Akita station'));
    expect(footerText, isNot(contains('UNKNOWN by default')));
    expect(footerText, isNot(contains('未計測')),
        reason: 'the English card reads "No visibility reading", not 未計測');
  });

  // The footer is drawn under every state of the card. A state's own words
  // inside it put that state on her card while the card is in another: a
  // footer quoting 停車の検討 sat under 特段の注意なし. Measured 2026-09-15 on the
  // first draft of these words: 10 tests that read the rung from the card's
  // text read the top rung for a driver who has none, and a precondition in
  // this file that looked for the missing visibility reading found it in the
  // footer instead. English is compared without case: "consider stopping" is
  // the same label as "Consider stopping".
  test('the footer names no state the card can show, in either language', () {
    const text = DriveHudLocalizer();
    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));
      final footer = l.driveHudFooter.toLowerCase();
      final labels = <String>[
        for (final a in DriveAction.values) text.actionHeadline(a, lang),
        for (final a in DriveAction.values) text.spokenGuidance(a, lang),
        for (final r in CautionReason.values) text.reasonLabel(r, lang),
        for (final u in Unknown.values) text.unknownLabel(u, lang),
        for (final m in LocalizationMode.values) text.modeLabel(m, lang),
        for (final u in AppUnknown.values) appUnknownLabel(u, l),
      ].where((s) => s.isNotEmpty);
      for (final label in labels) {
        expect(footer.contains(label.toLowerCase()), isFalse,
            reason: '$lang footer names the state 「$label」: ${l.driveHudFooter}');
      }
    }
  });

  test('every card string the app has, in both languages, is free of the '
      'team\'s words', () {
    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));
      final strings = <String>[
        l.driveHudShareHint,
        l.driveHudNoPositionFed,
        l.driveHudDescription,
        l.driveHudVisibilityOverrideLabel,
        for (final m in const [null, 1500.0, 700.0, 300.0, 80.0])
          l.driveHudVisibilityBand(m),
        l.driveHudSimulateBlackout,
        l.driveHudBlackoutSeconds(60),
        l.driveHudAnnounceCritical,
        l.driveHudAnnounceWarning,
        l.driveHudAnnounceRaisedNotSpoken,
        l.driveHudAnnounceContinue,
        l.driveHudCompoundingNote,
      ];
      _expectNoTeamWords(strings, lang);
    }
  });

  testWidgets('the next-turn section\'s title follows the app\'s language',
      (tester) async {
    await _boot(tester, 'ja');
    expect(find.text('Next maneuver — honest confidence-gated narration'),
        findsNothing);
    expect(find.text('次の案内'), findsOneWidget);

    // No implementation term in English either (2026-09-15).
    await _boot(tester, 'en');
    expect(find.text('Next maneuver'), findsOneWidget);
    expect(find.textContaining('confidence-gated'), findsNothing);
  });

  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang: caution raised only because visibility was not '
        'measured does not say a hazard is read aloud elsewhere',
        (tester) async {
      final a = await _boot(tester, lang,
          jma: () async => JmaSuccess(_freshObsWithoutVisibility()));
      await _tapKey(tester, const Key('use-mock-button'));
      final status = tester
              .widget<Text>(find.byKey(const Key('drive-hud-announce-status')))
              .data ??
          '';
      // Preconditions: this is the line for a raised rung that this rung does
      // not speak; the station answered fresh, above freezing and dry, with no
      // visibility, so the missing reading is what raised caution; and nothing
      // was spoken. (With no observation at all the app does speak: it says it
      // could not get the road's condition.)
      expect(status, AppL10n(Locale(lang)).driveHudAnnounceRaisedNotSpoken,
          reason: 'precondition: the raised, not spoken line');
      expect(a.spoken, isEmpty, reason: 'precondition: nothing spoke');
      // Never counted from the footer, which is drawn in every state.
      final listed = find
          .descendant(
              of: _card(),
              matching: find.textContaining(
                  lang == 'ja' ? '視界の測定値がありません' : 'No visibility reading'))
          .evaluate()
          .where((e) => e.widget.key != const Key('drive-hud-footer'));
      expect(listed, isNotEmpty,
          reason: 'precondition: the card lists the missing visibility reading');

      expect(status, isNot(contains('個別の危険')), reason: status);
      expect(status, isNot(contains('specific hazard')), reason: status);
    });
  }

  // Ruled 2026-09-15: package names are not for her glance. The two the card
  // is built on are named on the development page instead.
  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang: her live-drive card names no package, and the '
        'development page names the two it is built on', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: Locale(lang),
        clock: () => _now,
        jmaFetch: () async => const JmaFailure('no network in this test'),
        developerPageEntry: true,
      ));
      await tester.pump();
      await tester.pump();
      final packageWords = RegExp(r'\b[a-z]+_[a-z_]+\b|pub\.dev|pubspec');
      final texts = await _cardTextsThroughStates(tester);
      final named = [
        for (final t in texts)
          for (final m in packageWords.allMatches(t)) '"${m.group(0)}" in 「$t」',
      ];
      expect(named, isEmpty, reason: '$lang: ${named.join('\n')}');

      await openDeveloperPage(tester);
      for (final name in const ['localization_fallback', 'compound_failure_advisor']) {
        expect(find.textContaining(name), findsWidgets,
            reason: '$lang: the development page names $name');
      }
    });
  }
}
