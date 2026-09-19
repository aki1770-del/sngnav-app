// Smoke tests for sngnav-app Slice 0.
//
// Verifies the app boots, the DriverProfile selector renders, and the
// alpha-banner appears. JMA fetch is NOT exercised in widget tests
// (network-dependent; would slow CI). End-to-end JMA verification is a
// manual try-first action by the first tester.

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

import 'package:sngnav_app/main.dart';

import 'support/developer_page.dart';

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
    // The driver-type selector is on the development page (2026-09-15).
    await tester.pumpWidget(const SngnavApp(developerPageEntry: true));
    await tester.pump();
    await openDeveloperPage(tester);
    // Default profile: an older driver in Akita.
    expect(find.text(DriverProfile.ageingRural.name), findsOneWidget);
  });

  // Until 2026-09-15 this test held the page foot to the project's internal reason for the
  // Akita station. Ruled that day: the foot keeps what she needs from it.
  testWidgets('Footer says routes do not consider snow', (
    tester,
  ) async {
    await tester.pumpWidget(const SngnavApp());
    await tester.pump();
    expect(
      find.textContaining('do not consider snow'),
      findsOneWidget,
    );
  });
}
