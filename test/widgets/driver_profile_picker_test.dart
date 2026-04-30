import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:sngnav_app/widgets/driver_profile_picker.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('renders a card per DriverProfile value', (tester) async {
    await tester.pumpWidget(_wrap(DriverProfilePicker(
      currentProfile: DriverProfile.ageingRural,
      onPicked: (_) {},
    )));
    for (final profile in DriverProfile.values) {
      expect(
        find.byKey(ValueKey('driver-profile-card-${profile.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('tapping a card calls onPicked with the chosen profile',
      (tester) async {
    DriverProfile? captured;
    await tester.pumpWidget(_wrap(DriverProfilePicker(
      currentProfile: DriverProfile.ageingRural,
      onPicked: (p) => captured = p,
    )));
    await tester.tap(find.byKey(
        const ValueKey('driver-profile-card-foreignTouristSnowZone')));
    await tester.pump();
    expect(captured, equals(DriverProfile.foreignTouristSnowZone));
  });

  testWidgets('motion stream emitting true triggers onAutoDismiss',
      (tester) async {
    final controller = StreamController<bool>();
    addTearDown(controller.close);
    var dismissed = false;
    await tester.pumpWidget(_wrap(DriverProfilePicker(
      onPicked: (_) {},
      motionStream: controller.stream,
      onAutoDismiss: () => dismissed = true,
    )));
    controller.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(dismissed, isTrue);
  });

  testWidgets('motion stream emitting false alone does NOT trigger onAutoDismiss',
      (tester) async {
    final controller = StreamController<bool>();
    addTearDown(controller.close);
    var dismissed = false;
    await tester.pumpWidget(_wrap(DriverProfilePicker(
      onPicked: (_) {},
      motionStream: controller.stream,
      onAutoDismiss: () => dismissed = true,
    )));
    controller.add(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(dismissed, isFalse);
  });
}
