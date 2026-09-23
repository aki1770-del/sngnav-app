/// The consent composition is now held by an assertion, in both directions.
///
/// ⚑ WHY, written before the act (OPS-070(B)). Forty-two test sites name the
/// disclosure or the share control and none of them asserts any relationship
/// between the two; the composition was carried by two golden captures and a
/// comment, and on 2026-09-23 both pictures went red at once. A picture that
/// has to be looked at is not a guard, and a comment has no exit code.
///
/// ⚑ THIS TEST DECIDES NOTHING ABOUT THE DESIGN. Whether the control and the
/// disclosure SHOULD stand together is AAA's ruling. This asserts only that the
/// page matches its own DECLARATION, and it fails as loudly when they come back
/// together as when they drift further apart — so whichever way AAA rules, the
/// ruling moves one constant in `consent_composition.dart` and the teeth here
/// are unchanged. Written now, before that ruling, on the coordinator's
/// question of whether an assertion could be framed to survive either outcome.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/consent_composition.dart';
import '../support/fake_alert_actuators.dart';

JmaObservation _obs() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 15.0,
      humidityPercent: 30,
      windMetersPerSecond: 1.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260115063000',
      fetchedAt: DateTime(2026, 7, 15, 6, 30),
    );

Future<void> _pumpHerPage(WidgetTester tester, String lang) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(393 * 2, 852 * 2);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(SngnavApp(
    actuators: FakeAlertActuators(),
    locale: Locale(lang),
    jmaFetch: () async => JmaSuccess(_obs()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

void main() {
  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang: the page matches its DECLARED consent composition',
        (tester) async {
      await _pumpHerPage(tester, lang);

      final rendered = renderedConsentComposition(tester);
      // ignore: avoid_print
      print('CONSENT-COMPOSITION[$lang] declared='
          '${kDeclaredConsentComposition.name} rendered=${rendered.name}');

      expect(
        rendered,
        kDeclaredConsentComposition,
        reason: 'The page and its declaration disagree.\n'
            '  declared: ${kDeclaredConsentComposition.name}\n'
            '  rendered: ${rendered.name}\n'
            'This fails in BOTH directions on purpose. If the control and the '
            'disclosure were deliberately put back together, or deliberately '
            'separated, say so by moving kDeclaredConsentComposition in '
            'test/support/consent_composition.dart WITH ITS REASON AND DATE — '
            'and route the change to AAA, which holds the ruling on what the '
            'relationship should be. Do not delete this expectation.',
      );
    });
  }

  testWidgets('while separated, the words stay within one scroll of the control',
      (tester) async {
    await _pumpHerPage(tester, 'ja');
    if (kDeclaredConsentComposition != ConsentComposition.separated) {
      // N/A is not a pass, and it is PRINTED rather than skipped silently.
      // ignore: avoid_print
      print('CONSENT-GAP: N/A — the declaration is '
          '${kDeclaredConsentComposition.name}, so there is no gap to bound. '
          'N/A is not a pass.');
      return;
    }
    final gap = disclosureGapBelowControlDp(tester);
    // ignore: avoid_print
    print('CONSENT-GAP: ${gap.toStringAsFixed(0)}dp below the control '
        '(bound ${kMaxDisclosureGapDp.toStringAsFixed(0)}dp = one screenful of '
        'her page)');

    expect(gap, greaterThan(0),
        reason: 'the disclosure is ABOVE the control (gap '
            '${gap.toStringAsFixed(0)}dp). She would be told where her '
            'coordinates go before she is offered the control that sends them, '
            'and nothing in this app has ever drawn it that way.');
    expect(gap, lessThanOrEqualTo(kMaxDisclosureGapDp),
        reason: 'the disclosure is ${gap.toStringAsFixed(0)}dp below the '
            'control, past the ${kMaxDisclosureGapDp.toStringAsFixed(0)}dp her '
            'phone gives the page. Separated may mean one scroll on from the '
            'control; it may not come to mean three. Whatever took this space, '
            'take it from somewhere else.');
  });
}
