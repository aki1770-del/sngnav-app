// Integrator-wiring tests for Wave 1 sub-bundle 3 — GlanceBudgetTracker
// + voice-pace + AlertExplainerExpandableSheet (navigation_safety
// 0.9.0 / voice_guidance 0.6.0).
//
// AAA Article 17 (β): tests verify behaviour at the integrator surface;
// driver-facing wording is package-owned and not exercised here.

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:voice_guidance/voice_guidance.dart';

import 'package:sngnav_app/main.dart';

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
        await tester.pumpWidget(const SngnavApp());
        await tester.pump();
        expect(
          find.textContaining('Glance budget + voice pace'),
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
        await tester.pumpWidget(const SngnavApp());
        await tester.pump();
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
        await tester.pumpWidget(const SngnavApp());
        await tester.pump();
        // The sheet renders the source-line attribution per package
        // default. ageingRural defaults to expanded per
        // AlertExplainerExpandableSheet.defaultExpansionForProfile.
        expect(
          find.textContaining('AlertExplainer (JAF / MLIT / NEXCO)'),
          findsWidgets,
        );
      },
    );
  });
}
