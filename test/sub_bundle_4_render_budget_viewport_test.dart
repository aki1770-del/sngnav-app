// Integrator-wiring tests for Wave 1 sub-bundle 4 — PerformanceBudget
// + DataBudget + ViewportRenderBudgetBloc (offline_tiles 0.5.0 /
// snow_rendering 0.2.0 / map_viewport_bloc 0.4.0).
//
// AAA Article 17 (β): tests verify behaviour at the integrator surface;
// driver-facing wording is unaffected at the rendering layer.

import 'package:flutter_test/flutter_test.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:snow_rendering/snow_rendering.dart' as snow_rendering;

import 'package:sngnav_app/main.dart';

void main() {
  group('Sub-bundle 4 — package API contract', () {
    test(
      'PerformanceBudgetConfig.forProfile(ageingRural) returns 22ms '
      '(>= 16ms baseline; caution-add-only)',
      () {
        final config = offline_tiles.PerformanceBudgetConfig.forProfile(
          DriverProfile.ageingRural,
        );
        expect(config.frameBudget,
            equals(const Duration(microseconds: 22000)));
        expect(
          config.frameBudget.inMicroseconds,
          greaterThanOrEqualTo(
            offline_tiles.PerformanceBudgetConfig.baselineFrameBudget
                .inMicroseconds,
          ),
        );
      },
    );

    test(
      'DataBudgetConfig.forProfile(ageingRural) returns 2MB '
      '(<= 4MB baseline; caution-add-only tighter direction)',
      () {
        final config = snow_rendering.DataBudgetConfig.forProfile(
          DriverProfile.ageingRural,
        );
        expect(config.budgetBytes, equals(2 * 1024 * 1024));
        expect(
          config.budgetBytes,
          lessThanOrEqualTo(
              snow_rendering.DataBudgetConfig.baselineBudgetBytes),
        );
      },
    );

    test(
      'ViewportRenderConfig.forProfile(ageingRural) sets MEDIUM floor '
      '(per-cohort visual-cognitive-margin)',
      () {
        final config =
            ViewportRenderConfig.forProfile(DriverProfile.ageingRural);
        expect(config.floor, equals(RenderFidelityFloor.medium));
      },
    );

    test(
      'ViewportRenderBudgetBloc emits RenderFidelity transitions on '
      'composed budget streams (caution-add-direction-wins)',
      () async {
        final bloc = ViewportRenderBudgetBloc(
          config: ViewportRenderConfig.forProfile(
            DriverProfile.professional,
          ),
        );
        // Initial: high.
        expect(bloc.state.fidelity, equals(RenderFidelity.high));
        bloc.add(const ViewportPerformanceBudgetWarning());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.fidelity, equals(RenderFidelity.medium));
        bloc.add(const ViewportDataBudgetExhausted());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.fidelity, equals(RenderFidelity.low));
        await bloc.close();
      },
    );
  });

  group('Sub-bundle 4 — sngnav-app wiring', () {
    testWidgets(
      'Render budget viewport panel renders with frame + fetch buttons '
      '+ RenderFidelity row',
      (tester) async {
        await tester.pumpWidget(const SngnavApp());
        await tester.pump();
        expect(
          find.textContaining('Render budget viewport'),
          findsOneWidget,
        );
        expect(find.text('Frame (in budget)'), findsOneWidget);
        expect(find.text('Frame (over budget)'), findsOneWidget);
        expect(find.text('Fetch 512 KB'), findsOneWidget);
        expect(
          find.text('RenderFidelity:'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Floor row reflects per-cohort default for ageingRural (medium)',
      (tester) async {
        await tester.pumpWidget(const SngnavApp());
        await tester.pump();
        // ageingRural is the default profile; floor row shows medium.
        expect(
          find.textContaining('medium'),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'Tapping Frame (over budget) increments frames-recorded counter '
      '(integrator wiring fires record() into PerformanceBudget)',
      (tester) async {
        await tester.pumpWidget(const SngnavApp());
        await tester.pump();
        final btn = find.text('Frame (over budget)');
        await tester.ensureVisible(btn);
        await tester.tap(btn);
        await tester.pump();
        expect(find.textContaining('(1 recorded)'), findsOneWidget);
      },
    );
  });
}
