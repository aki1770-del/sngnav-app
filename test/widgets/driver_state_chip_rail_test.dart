import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:sngnav_app/widgets/driver_state_chip_rail.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('rail renders one chip per DriverState value', (tester) async {
    await tester.pumpWidget(_wrap(DriverStateChipRail(
      activeState: DriverState.alert,
      proposedState: null,
      onAffirm: (_) {},
    )));
    for (final state in DriverState.values) {
      expect(
        find.byKey(ValueKey('driver-state-chip-${state.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('tapping a non-active chip calls onAffirm with that state',
      (tester) async {
    DriverState? captured;
    await tester.pumpWidget(_wrap(DriverStateChipRail(
      activeState: DriverState.alert,
      proposedState: null,
      onAffirm: (s) => captured = s,
    )));
    await tester.tap(find.byKey(const ValueKey('driver-state-chip-fatigued')));
    await tester.pump();
    expect(captured, equals(DriverState.fatigued));
  });

  testWidgets('proposal hint text appears when proposedState differs from active',
      (tester) async {
    await tester.pumpWidget(_wrap(DriverStateChipRail(
      activeState: DriverState.alert,
      proposedState: DriverState.fatigued,
      onAffirm: (_) {},
    )));
    expect(find.textContaining('Suggested:'), findsOneWidget);
    expect(find.textContaining('Fatigued'), findsWidgets);
  });

  testWidgets(
      'no proposal hint appears when proposedState equals activeState',
      (tester) async {
    await tester.pumpWidget(_wrap(DriverStateChipRail(
      activeState: DriverState.alert,
      proposedState: DriverState.alert,
      onAffirm: (_) {},
    )));
    expect(find.textContaining('Suggested:'), findsNothing);
  });
}
