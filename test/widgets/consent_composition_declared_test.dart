/// The consent composition is held by an assertion, in both directions.
///
/// ⚑ WHY, written before the act. Forty-two test sites named the disclosure or
/// the share control and none of them asserted any relationship between the
/// two; the composition was carried by two golden captures and a comment, and
/// on 2026-09-23 both pictures went red at once. A picture that has to be
/// looked at is not a guard, and a comment has no exit code.
///
/// ⚑ THIS TEST DECIDES NOTHING ABOUT THE DESIGN. Whether the control and the
/// disclosure SHOULD stand together is the safety review's ruling. This asserts
/// that the page matches its own DECLARATION, failing as loudly when they part
/// as when they come back together, and that the words stay within one scroll
/// of the control whichever way the page is declared.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../render_see/render_see_env.dart';
import '../support/consent_composition.dart';
import '../support/fake_alert_actuators.dart';

/// ⚑ TWO STATES, BECAUSE ONE OF THEM IS THE ONE THIS GUARD FIRST MISSED.
///
/// Until 2026-09-23 this file rendered the clear launch only. A safety review
/// rendered a MEASURED WHITEOUT with no share started, where the caution card
/// grows, and found the gap 15 dp inside the bound in the state the guard could
/// not see. The whiteout now runs here too.
///
/// ⚑ THIS GUARD REFUSES WITHOUT A JAPANESE FACE. A probe that renders kanji with
/// no Japanese face measures character count, not meaning: without a face the
/// whiteout gap read 726 dp, red by 5, and with one it read 710 dp — exactly
/// 16 dp in both states, one variable. A no-font figure is NOT conservative: a
/// missing-glyph layout can err small just as easily, and then this guard
/// passes green while the words are out of her reach. Unmeasured is not a safe
/// direction; it is no direction.
DateTime _now = DateTime.utc(2026, 1, 14, 21);

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

JmaObservation _obs({int? visibilityMeters}) => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: visibilityMeters == null ? 15.0 : 5.0,
      humidityPercent: visibilityMeters == null ? 30 : 50,
      windMetersPerSecond: visibilityMeters == null ? 1.0 : 2.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: visibilityMeters,
      observedAtJstKey: _jstKey(_now),
      fetchedAt: _now,
    );

Future<void> _pumpHerPage(WidgetTester tester, String lang,
    {int? visibilityMeters}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(393 * 2, 852 * 2);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(SngnavApp(
    actuators: FakeAlertActuators(),
    locale: Locale(lang),
    clock: () => _now,
    jmaFetch: () async =>
        JmaSuccess(_obs(visibilityMeters: visibilityMeters)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    final cjk = await loadDiscoveredFace('Roboto', FaceSearch.japanese);
    if (!cjk) {
      throw StateError(
          'CONSENT-COMPOSITION GUARD REFUSES WITHOUT A JAPANESE FACE. Its dp '
          'figures are measurements of PARAGRAPH HEIGHT, and Japanese '
          'paragraphs drawn without Japanese glyphs have a different height — '
          '16 dp of it, measured 2026-09-23. Unmeasured is not a safe '
          'direction.\n${describeFaceSearch(FaceSearch.japanese)}');
    }
  });

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
            'and route the change to the safety review, which holds the ruling '
            'on what the relationship should be. Do not delete this '
            'expectation.',
      );
    });
  }

  for (final (stateName, vis) in const <(String, int?)>[
    ('launch, clear', null),
    // ⚑ THE STATE THE GUARD COULD NOT SEE. A measured 80 m whiteout with no
    // share started raises the rung with no position at all, which grows the
    // caution card and pushes the words down. This is the state the reorder was
    // justified by, and it is where the margin is thinnest.
    ('measured whiteout, no share', 80),
  ]) {
    testWidgets('$stateName: the words stay within one scroll of the control',
        (tester) async {
      await _pumpHerPage(tester, 'ja', visibilityMeters: vis);
      // The bound holds whichever way the page is declared (2026-10-07). Until
      // that date this case returned early when the declaration was not
      // `separated`, printing "N/A is not a pass" — and then counted as a pass.
      // ignore: avoid_print
      print('CONSENT-GAP[$stateName]: declared '
          '${kDeclaredConsentComposition.name}');
      // Control: the state really is the one this case names, so a fixture that
      // silently stopped raising the rung cannot pass as the whiteout.
      final rung = find.byKey(const Key('drive-hud-rung'));
      expect(rung.evaluate().isNotEmpty, vis != null,
          reason: vis == null
              ? 'the clear case must show NO rung; one appeared, so this is not '
                  'the state named'
              : 'the whiteout case must raise a rung; none appeared, so this '
                  'measured nothing about the whiteout');
      final gap = disclosureGapBelowControlDp(tester);
      // ignore: avoid_print
      print('CONSENT-GAP[$stateName]: ${gap.toStringAsFixed(0)}dp below the '
          'control (bound ${kMaxDisclosureGapDp.toStringAsFixed(0)}dp = one '
          'screenful of her page; margin '
          '${(kMaxDisclosureGapDp - gap).toStringAsFixed(0)}dp)');

      expect(gap, greaterThan(0),
          reason: 'the disclosure is ABOVE the control (gap '
              '${gap.toStringAsFixed(0)}dp). She would be told where her '
              'coordinates go before she is offered the control that sends '
              'them, and nothing in this app has ever drawn it that way.');
      expect(gap, lessThanOrEqualTo(kMaxDisclosureGapDp),
          reason: 'in the state "$stateName" the disclosure is '
              '${gap.toStringAsFixed(0)}dp below the control, past the '
              '${kMaxDisclosureGapDp.toStringAsFixed(0)}dp her phone gives the '
              'page. The words may be one scroll on from the control; they may '
              'not come to mean three. Whatever took this space, take it from '
              'somewhere else.');
    });
  }
}
