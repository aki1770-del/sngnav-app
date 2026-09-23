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

import '../render_see/render_see_env.dart';
import '../support/consent_composition.dart';
import '../support/fake_alert_actuators.dart';

/// ⚑ TWO STATES, BECAUSE ONE OF THEM IS THE ONE THIS GUARD NEARLY MISSED.
///
/// Until 2026-09-23 this file pinned `visibilityMeters: null` only — the clear
/// launch state — where the gap is 420 dp against a 721 dp bound, 301 dp of
/// margin. AAA rendered the state the whole change was justified by, a MEASURED
/// WHITEOUT with no share started, and measured the gap there at 706 dp:
/// **15 dp inside my own bound, in the state the guard could not see.** One more
/// line of rung prose carries it over and nobody would have known.
/// V9 — the operator must not be the last line of defence, the machine must
/// catch it — and the machine had been built and then pointed away from the
/// case. The whiteout now runs here.
/// ⚑⚑ THIS GUARD REFUSES WITHOUT A JAPANESE FACE, AND IT DID NOT UNTIL
/// 2026-09-23 — MY OWN RULE, NOT APPLIED TO MY NEWEST INSTRUMENT.
///
/// Four probes of mine already carry it verbatim: *a probe that renders kanji
/// with no CJK face measures character count, not meaning* (HIE-18(b)). This
/// file, written last, had no `setUpAll`, imported no render environment and
/// loaded no face — and then pumped a Japanese locale and measured the HEIGHT
/// of 352 dp of Japanese paragraphs drawn without Japanese glyphs.
///
/// What it cost, measured: without a face the whiteout gap reads **726 dp** and
/// this guard is RED by 5; with the face it reads **710 dp** and passes by 11.
/// Exactly 16 dp in both states, one variable. I reported 726 as a finding
/// against my own build and it was an artefact of my own instrument.
///
/// ⚑ AND THE TEMPTING READING IS WRONG: a no-font figure is NOT "conservative".
/// A missing-glyph layout can err small just as easily, and then this guard
/// passes green while the words are genuinely out of her reach. Unmeasured is
/// not a safe direction; it is no direction.
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
            'and route the change to AAA, which holds the ruling on what the '
            'relationship should be. Do not delete this expectation.',
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
      if (kDeclaredConsentComposition != ConsentComposition.separated) {
        // N/A is not a pass, and it is PRINTED rather than skipped silently.
        // ignore: avoid_print
        print('CONSENT-GAP[$stateName]: N/A — the declaration is '
            '${kDeclaredConsentComposition.name}, so there is no gap to bound. '
            'N/A is not a pass.');
        return;
      }
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
              'page. Separated may mean one scroll on from the control; it may '
              'not come to mean three. Whatever took this space, take it from '
              'somewhere else.');
    });
  }
}
