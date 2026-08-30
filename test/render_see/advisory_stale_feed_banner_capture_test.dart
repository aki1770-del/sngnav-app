/// OPS-066 render-SEE capture for the STALE-FEED banner.
///
/// The defect this capture exists to make VISIBLE: a publisher document that
/// has stopped being rewritten fails in TWO directions, and neither is visible
/// in the rows beneath it.
///
///   - It still lists warnings  → they render as though live. Akita served a
///     雷注意報 from May for 88 days.
///   - It lists nothing         → the empty list is the identical value a
///     genuinely clear sky produces. Niigata, 90 days, zero warnings.
///
/// `staleSources` already makes `canAssertNoAdvisory` false, so the all-clear
/// branch cannot fire. But SUPPRESSING a false all-clear is silent: she is left
/// reading a dead warning, or reading nothing, with no mark either way. The
/// banner says the quiet part out loud, and this capture is how a human
/// confirms she can actually READ it.
///
/// Produces ja-rendered PNGs into `render_out/` for a human to LOOK at:
///   19a — stale feed WITH a warning still listed → banner ABOVE the warning
///   19b — stale feed with an EMPTY list          → banner instead of a clear
///   19c — staleness measured, AGE not            → 「期間不明」, never 「約0時間」
///
/// 19c is the one a test-only proof would miss. `age` is nullable, and a null
/// is not a zero: a source can be known stale (its document carries no readable
/// timestamp) without its age being measurable. Rendering that as "about 0
/// hours" would report an UNMEASURED quantity as a measured one and understate
/// it maximally — the same defect class as an absent GPS accuracy read as 0.0.
///
/// Run with:
///   flutter test --update-goldens \
///     test/render_see/advisory_stale_feed_banner_capture_test.dart
///
/// On a host without CJK fonts the pixel claim is withdrawn (the render
/// pipeline is still exercised); NOBODY affirms CI PNGs as HER-phone evidence.
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
    // The banner carries a leading ⚠ (U+26A0). Without the app's own bundled
    // subset it renders as TOFU (□) — so this suite loads the SAME bytes the
    // APK ships and mirrors the app's real fallback chain below.
    final symbolsLoaded = await loadBundledSymbolsFont();
    if (!cjkLoaded || !symbolsLoaded) installNoopGoldenComparator();
  });

  Widget host(AdvisoryAggregateResult result) => MaterialApp(
        locale: const Locale('ja'),
        theme: ThemeData(fontFamilyFallback: const ['SnGNavSymbols']),
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
              pointCovered: true,
            ),
          ),
        ),
      );

  testWidgets(
      '19a — a warning from a FROZEN document renders under the banner, '
      'not as live', (tester) async {
    // Akita's real shape: the document stopped moving, and the 雷注意報 it
    // still lists is from May. The row beneath is not removed — we do not know
    // the warning is over — it is QUALIFIED.
    final akita = AdvisoryAggregateResult(
      advisories: [
        Advisory(
          source: AdvisorySource.jmaJapan,
          eventClass: '雷注意報',
          severity: AdvisorySeverity.minor,
          certainty: AdvisoryCertainty.likely,
          urgency: AdvisoryUrgency.expected,
          areaDescription: '秋田県',
          effective: DateTime.utc(2026, 5, 28, 5),
          expires: null,
          headline: '雷注意報',
          description: '落雷や突風に注意してください。',
        ),
      ],
      providerErrors: const [],
      sourcesQueried: 1,
      staleSources: const [
        AdvisoryFeedStaleness(
          source: AdvisorySource.jmaJapan,
          age: Duration(days: 88),
          detail: '050000',
        ),
      ],
    );
    await tester.pumpWidget(host(akita));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advisory_stale_feed_banner')), findsOneWidget);
    expect(find.textContaining('約88日'), findsOneWidget);
    // The warning itself is still shown — a frozen feed is not permission to
    // hide a hazard we cannot rule out.
    expect(find.textContaining('雷注意報'), findsWidgets);

    await expectLater(
      find.byType(AdvisoryCards),
      matchesGoldenFile('../../render_out/19a_stale_feed_with_warning.png'),
    );
  });

  testWidgets(
      '19b — an EMPTY list from a frozen document never renders as a clear sky',
      (tester) async {
    // Niigata: 90 days, zero warnings. This empty list is byte-identical to the
    // one a genuinely clear sky produces. Only the banner separates them.
    const niigata = AdvisoryAggregateResult(
      advisories: [],
      providerErrors: [],
      sourcesQueried: 1,
      staleSources: [
        AdvisoryFeedStaleness(
          source: AdvisorySource.jmaJapan,
          age: Duration(days: 90),
          detail: '150000',
        ),
      ],
    );
    await tester.pumpWidget(host(niigata));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advisory_stale_feed_banner')), findsOneWidget);
    expect(find.textContaining('約90日'), findsOneWidget);
    // The fabricated all-clear must be ABSENT from this surface.
    expect(find.text('この地点に有効な警報・注意報はありません。'), findsNothing);

    await expectLater(
      find.byType(AdvisoryCards),
      matchesGoldenFile('../../render_out/19b_stale_feed_empty_list.png'),
    );
  });

  testWidgets('19c — staleness measured, age NOT: 「期間不明」, never 「約0時間」',
      (tester) async {
    // The adapter established staleness by a content-hash that has not moved,
    // but the document carries no readable timestamp. The staleness is a
    // measurement; the AGE is absent. Absence must not ride the same scale.
    const unmeasuredAge = AdvisoryAggregateResult(
      advisories: [],
      providerErrors: [],
      sourcesQueried: 1,
      staleSources: [
        AdvisoryFeedStaleness(source: AdvisorySource.jmaJapan),
      ],
    );
    await tester.pumpWidget(host(unmeasuredAge));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advisory_stale_feed_banner')), findsOneWidget);
    expect(find.textContaining('期間不明'), findsOneWidget);
    // The understating render this branch exists to prevent.
    expect(find.textContaining('約0時間'), findsNothing);
    expect(find.textContaining('約0日'), findsNothing);

    await expectLater(
      find.byType(AdvisoryCards),
      matchesGoldenFile('../../render_out/19c_stale_feed_age_unknown.png'),
    );
  });
}
