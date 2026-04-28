// Smoke tests for sngnav-app Slice 0.
//
// Verifies the app boots, the DriverProfile selector renders, and the
// alpha-banner appears. JMA fetch is NOT exercised in widget tests
// (network-dependent; would slow CI). End-to-end JMA verification is a
// manual try-first action by Komada-as-first-tester.

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

import 'package:sngnav_app/main.dart';

void main() {
  testWidgets('App boots and shows alpha banner', (tester) async {
    await tester.pumpWidget(const SngnavApp());
    await tester.pump(); // first frame
    expect(find.text('sngnav-app (alpha)'), findsOneWidget);
    expect(
      find.textContaining('Alpha software'),
      findsOneWidget,
    );
  });

  testWidgets('DriverProfile selector defaults to ageingRural (V21)', (
    tester,
  ) async {
    await tester.pumpWidget(const SngnavApp());
    await tester.pump();
    // Default profile per V21 — HER's mother in Akita.
    expect(find.text(DriverProfile.ageingRural.name), findsOneWidget);
  });

  testWidgets('Footer shows Akita station provenance (V21 trace)', (
    tester,
  ) async {
    await tester.pumpWidget(const SngnavApp());
    await tester.pump();
    expect(
      find.textContaining("HER's mother lives there"),
      findsOneWidget,
    );
  });
}
