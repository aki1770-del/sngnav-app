// Integrator-wiring tests for Wave 1 sub-bundle 3 — GlanceBudgetTracker
// + voice-pace + AlertExplainerExpandableSheet (navigation_safety
// 0.9.0 / voice_guidance 0.6.0).
//
// Article 17 (β): tests verify behaviour at the integrator surface;
// driver-facing wording is package-owned and not exercised here.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:voice_guidance/voice_guidance.dart';

import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart';

import 'support/developer_page.dart';

void main() {
  group('Sub-bundle 3 — package API contract', () {
    test(
      'GlanceBudgetTracker default 12s budget; consumed monotone '
      '(caution-add-only)',
      () {
        final tracker = GlanceBudgetTracker();
        expect(tracker.totalBudget, equals(const Duration(seconds: 12)));
        final start = tracker.consumed;
        tracker.record(GlanceEvent(
          timestamp: DateTime.now(),
          duration: const Duration(milliseconds: 800),
          modalClass: GlanceModalClass.visual,
        ));
        expect(
          tracker.consumed.inMicroseconds,
          greaterThanOrEqualTo(start.inMicroseconds),
        );
        expect(tracker.consumed, equals(const Duration(milliseconds: 800)));
      },
    );

    test(
      'BudgetAwarePaceProfile interpolates pace in [0.7, 1.0] range '
      'over remaining ratio (caution-add-only ≤1.0×)',
      () {
        const profile = BudgetAwarePaceProfile();
        final paceFull = profile.paceForRemainingRatio(1.0);
        final paceEmpty = profile.paceForRemainingRatio(0.0);
        expect(paceFull, equals(1.0));
        expect(paceEmpty, equals(0.7));
        // Caution-add-only invariant: never exceeds 1.0×.
        expect(profile.paceForRemainingRatio(0.5), lessThanOrEqualTo(1.0));
      },
    );

    test(
      'GlanceBudgetTracker fires BudgetExhausted at 100% consumption',
      () async {
        final tracker = GlanceBudgetTracker();
        final events = <GlanceBudgetEvent>[];
        final sub = tracker.budgetEvents.listen(events.add);
        tracker.record(GlanceEvent(
          timestamp: DateTime.now(),
          duration: const Duration(seconds: 13),
          modalClass: GlanceModalClass.visual,
        ));
        // Allow stream to dispatch.
        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<BudgetExhausted>().length, 1);
        await sub.cancel();
        await tracker.dispose();
      },
    );
  });

  group('Sub-bundle 3 — sngnav-app wiring', () {
    testWidgets(
      'Glance budget panel renders with simulate buttons + pace display',
      (tester) async {
        // This card is on the development page (2026-09-15).
        await tester.pumpWidget(const SngnavApp(developerPageEntry: true));
        await tester.pump();
        await openDeveloperPage(tester);
        expect(
          find.text(const AppL10n(Locale('en'))
              .glanceAndVoicePacingSectionTitle),
          findsOneWidget,
        );
        expect(
          find.text('Simulate glance (800 ms)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Effective voice pace'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Tapping simulate-glance increments the events-recorded counter '
      '(integrator wiring fires record() into the package tracker)',
      (tester) async {
        // This card is on the development page (2026-09-15).
        await tester.pumpWidget(const SngnavApp(developerPageEntry: true));
        await tester.pump();
        await openDeveloperPage(tester);
        final btn = find.text('Simulate glance (800 ms)');
        await tester.ensureVisible(btn);
        // Tap once; consumed should be 0.8s; counter goes 0 -> 1.
        await tester.tap(btn);
        await tester.pump();
        expect(find.textContaining('(1 events)'), findsOneWidget);
        await tester.tap(btn);
        await tester.pump();
        expect(find.textContaining('(2 events)'), findsOneWidget);
      },
    );

    testWidgets(
      'AlertExplainerExpandableSheet renders inside sub-bundle 3 panel '
      'with cohort-default expansion state for ageingRural (default)',
      (tester) async {
        // This card is on the development page (2026-09-15).
        await tester.pumpWidget(const SngnavApp(developerPageEntry: true));
        await tester.pump();
        await openDeveloperPage(tester);
        // The sheet renders the source line at the package default.
        // ageingRural defaults to expanded per
        // AlertExplainerExpandableSheet.defaultExpansionForProfile.
        //
        // navigation_safety 0.9.7 changed that default from
        // 'AlertExplainer (JAF / MLIT / NEXCO)' to 'AlertExplainer',
        // because the wording on the card is navigation_safety_core's own
        // and was never taken from those three organisations. This card is
        // on the development page, so the reader is a developer and the
        // Dart class name is the accurate answer to "where did this text
        // come from". A driver-facing surface would pass its own
        // sourceLine, in her language, naming a source the text is
        // actually from.
        expect(
          find.textContaining('AlertExplainer'),
          findsWidgets,
        );
        // The retired attribution must not reappear as a CLAIM. The card
        // still names those three organisations once, in the line that
        // says the wording is not theirs — a developer who read the old
        // attribution needs to be told it was withdrawn, so the words are
        // forbidden as a source claim, not as words.
        expect(
          find.textContaining('AlertExplainer (JAF / MLIT / NEXCO)'),
          findsNothing,
        );
        expect(find.textContaining('relay from JAF'), findsNothing);
        expect(
          find.textContaining("package's own wording"),
          findsOneWidget,
        );
      },
    );
  });
}
