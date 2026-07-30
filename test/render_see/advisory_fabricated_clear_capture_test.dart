/// OPS-066 render-SEE capture for B04-2 — the fabricated-clear gate.
///
/// The defect this capture exists to make VISIBLE: a total advisory-feed
/// outage and a genuinely clear sky both arrive at [AdvisoryCards] as the
/// same value — an empty `advisories` list. Before this gate, the two
/// rendered IDENTICALLY: 「この地点に有効な警報・注意報はありません。」 —
/// a positive all-clear shown to a driver in unexpected snow at the exact
/// moment we could not look.
///
/// Produces ja-rendered PNGs into `render_out/` so the reviewer can LOOK at
/// the three states and SEE that they now differ:
///   18a — feed outage, ZERO sources asked   → amber honest-unknown
///   18b — a covering publisher ERRORED      → red degraded-unknown
///   18c — complete lookup, nothing in force → grey all-clear (unchanged)
///
/// 18c is the anti-cry-wolf half of the evidence: an instrument that can
/// never say "clear" is as useless to HER as one that always does. The
/// capture is only honest if it shows BOTH that the false clear is gone and
/// that the true clear survives.
///
/// HONESTY (so the reader can trust the render): the widget under test is
/// the REAL [AdvisoryCards], fed the exact result shapes the production
/// paths now produce — `sourcesQueried: 0` from
/// `AdvisoryService.fetchAtPoint`'s no-covering-provider return and from
/// `_refreshAdvisories`'s thrown path, and the aggregator's own
/// `sourcesQueried: n` on a clean fetch. No stub widget, no hand-written
/// string. Run with:
///   flutter test --update-goldens \
///     test/render_see/advisory_fabricated_clear_capture_test.dart
/// On a host without CJK fonts the pixel claim is withdrawn (the render
/// pipeline is still exercised); NOBODY affirms CI PNGs as HER-phone
/// evidence — that affirmation only happens from a human-viewed desktop run,
/// and on-device verification stays DEFERRED to the device-hour.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

import 'render_see_env.dart';

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
  });

  Widget host(AdvisoryAggregateResult result, {bool pointCovered = true}) =>
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdvisoryCards(
              loading: false,
              result: result,
              errorMessage: null,
              onRefresh: () {},
              pointCovered: pointCovered,
            ),
          ),
        ),
      );

  testWidgets(
      '18a — feed outage (zero sources asked) renders honest-unknown, '
      'NOT the all-clear', (tester) async {
    // The shape `AdvisoryService.fetchAtPoint` returns when no covering
    // provider exists, and the shape a result carries when the lookup never
    // completed. Empty advisories, NO provider error to point at — the
    // hardest case, because nothing looks broken.
    await tester.pumpWidget(host(
      const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 0,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advisory-lookup-incomplete')), findsOneWidget);
    // The fabricated clear is GONE from this surface.
    expect(find.text('この地点に有効な警報・注意報はありません。'), findsNothing);
    // …and what she reads instead names the unknown, not a hazard.
    expect(find.textContaining('不明です'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../render_out/18a_advisory_outage_unknown.png'),
    );
  });

  testWidgets(
      '18b — a covering publisher errored renders the degraded-unknown '
      'banner (B04, unchanged by the new gate)', (tester) async {
    await tester.pumpWidget(host(
      const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [
          AdvisoryProviderError(
            source: AdvisorySource.jmaJapan,
            message: 'HTTP 503',
          ),
        ],
        sourcesQueried: 1,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advisory-unknown-degraded')), findsOneWidget);
    expect(find.text('この地点に有効な警報・注意報はありません。'), findsNothing);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../render_out/18b_advisory_degraded_unknown.png'),
    );
  });

  testWidgets(
      '18d — an un-catalogued JAPANESE point (Tokyo) renders the honest '
      'cannot-check-here line, not the all-clear', (tester) async {
    // The visible consequence of narrowing `jmaCoverage` to the adapter's
    // real six-prefecture catalog. Before it, this exact point rendered the
    // positive all-clear with no request ever sent (the provider answers
    // empty-without-error outside its catalog, so `canAssertNoAdvisory` was
    // true). Now `coversPoint` is false, and she reads the truth: this app
    // cannot check here.
    await tester.pumpWidget(host(
      const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 0,
      ),
      pointCovered: false,
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('advisory-no-covering-publisher')),
      findsOneWidget,
    );
    expect(find.text('この地点に有効な警報・注意報はありません。'), findsNothing);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../render_out/18d_advisory_uncatalogued_jp.png'),
    );
  });

  testWidgets(
      '18c — a COMPLETE lookup with nothing in force still renders the '
      'all-clear (the gate did not blanket-suppress it)', (tester) async {
    await tester.pumpWidget(host(
      const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 1,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('この地点に有効な警報・注意報はありません。'), findsOneWidget);
    expect(find.byKey(const Key('advisory-lookup-incomplete')), findsNothing);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../render_out/18c_advisory_true_all_clear.png'),
    );
  });
}
