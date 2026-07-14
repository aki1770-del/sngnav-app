// B27 — the pre-send consent gate at the OSRM coordinate egress.
//
// Proves, in the REAL app widget tree (SngnavApp → HomePage → AkitaMap tap
// path → _fetchRoute):
//   1. Setting A then B raises the ja-primary consent dialog BEFORE any
//      request — no loading spinner, no route result, until she answers.
//   2. Decline → NO fetch: the honest neutral declined state renders (never
//      the red error container), and a change-choice path back exists.
//   3. Change-choice re-asks; accept → the fetch actually fires (in the
//      flutter_test binding every HttpClient call returns HTTP 400, so an
//      attempted fetch surfaces deterministically as the RouteFailure
//      container — which is exactly the proof the wire was tried only
//      after consent).
//   4. en locale renders the English dialog body naming the real host.
//
// HONESTY (OPS-066): this verifies the widget-tree gate in the test binding.
// No device; no real OSRM traffic is possible here (HTTP is stubbed to 400
// by flutter_test). On-device behavior of the dialog and the real send is
// DEFERRED to the next APK pass.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart';

const jaL10n = AppL10n(Locale('ja'));

/// Taps the map twice (A then B) at two distinct on-screen points, then
/// pumps far enough for the consent dialog to be up (if it is going to be).
///
/// Timing is load-bearing (measured with a probe, not guessed):
/// - flutter_map holds each tap ~300 ms for double-tap-zoom disambiguation,
///   so each tap needs a >=350 ms pump before it is delivered as a tap
///   (and two quick taps would otherwise read as a zoom gesture);
/// - the consent path then waits out the 2 s store-construction timeout
///   (getApplicationDocumentsDirectory never completes in the test zone),
///   and the dialog route needs its own build + animation frames.
Future<void> setAThenB(WidgetTester tester) async {
  // The map section can sit below the 800x600 test viewport; a tapAt on an
  // off-screen rect would hit nothing and the gate would never be exercised.
  await tester.ensureVisible(find.byType(AkitaMap));
  await tester.pump();
  final rect = tester.getRect(find.byType(AkitaMap));
  await tester.tapAt(rect.center - const Offset(100, 40));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tapAt(rect.center + const Offset(100, 40));
  await tester.pump(const Duration(milliseconds: 350));
  // Store-construction timeout (2 s) + dialog build + animation.
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
      'tap-route raises the ja consent dialog BEFORE any fetch; '
      'decline → no fetch, honest neutral state + path back', (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
    await tester.pump();

    await setAThenB(tester);

    // The pre-send disclosure is up, in HER language, naming the real host.
    final body = find.byKey(const Key('route-consent-body'));
    expect(body, findsOneWidget);
    expect(tester.widget<Text>(body).data, contains('router.project-osrm.org'));
    expect(tester.widget<Text>(body).data, contains('送信されます'));

    // NOTHING was sent or attempted while the question is open: no spinner,
    // no result of any kind.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Route fetch failed'), findsNothing);
    expect(find.byKey(const Key('route-consent-declined')), findsNothing);

    // Decline.
    await tester.tap(find.byKey(const Key('route-consent-decline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Honest neutral state — the localized "nothing was sent" line, never
    // the red error container (the router did not fail; it was never asked).
    expect(find.byKey(const Key('route-consent-declined')), findsOneWidget);
    expect(find.text(jaL10n.routeConsentDeclinedMessage), findsOneWidget);
    expect(find.textContaining('Route fetch failed'), findsNothing);
    // The path back from a remembered "no".
    expect(find.byKey(const Key('route-consent-change')), findsOneWidget);

    // Drain the fire-and-forget persist's store-construction timeout timer
    // (2 s) so teardown sees no pending timers.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'change-choice re-asks; accept → the fetch fires (only after consent)',
      (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
    await tester.pump();

    await setAThenB(tester);
    await tester.tap(find.byKey(const Key('route-consent-decline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Change choice → the dialog re-appears.
    await tester.ensureVisible(find.byKey(const Key('route-consent-change')));
    await tester.tap(find.byKey(const Key('route-consent-change')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('route-consent-body')), findsOneWidget);

    // Accept → the request is NOW attempted. flutter_test's binding answers
    // every HttpClient call with HTTP 400, so the attempted fetch surfaces
    // deterministically as the RouteFailure container — proof the wire was
    // tried, and tried only after consent.
    await tester.tap(find.byKey(const Key('route-consent-accept')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Let the stubbed HTTP round-trip + setState complete.
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('route-consent-declined')), findsNothing);
    expect(find.textContaining('Route fetch failed'), findsOneWidget);

    // Drain the fire-and-forget persist timers (decline + accept each start
    // a 2 s store-construction timeout) so teardown sees no pending timers.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('dismissing the dialog is "not now": no fetch, and the next '
      'tap-route asks again (a dismissal is not a decision)', (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
    await tester.pump();

    await setAThenB(tester);
    expect(find.byKey(const Key('route-consent-body')), findsOneWidget);

    // Dismiss via barrier tap (top-left corner is outside the dialog).
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('route-consent-body')), findsNothing);
    expect(find.textContaining('Route fetch failed'), findsNothing);

    // Start over: tap sets a new A, then B — the question comes back.
    await setAThenB(tester);
    expect(find.byKey(const Key('route-consent-body')), findsOneWidget);
  });

  testWidgets('en locale renders the English dialog body naming the host',
      (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('en')));
    await tester.pump();

    await setAThenB(tester);

    final body = find.byKey(const Key('route-consent-body'));
    expect(body, findsOneWidget);
    final text = tester.widget<Text>(body).data!;
    expect(text, contains('router.project-osrm.org'));
    expect(text, contains('will be sent'));
  });
}
