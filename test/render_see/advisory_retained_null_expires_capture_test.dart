/// OPS-066 render-SEE capture for HER-POV #3 — a null-expires JMA warning
/// (`condition_aggregator_jma` emits `expires: null` as its ONLY value) now
/// SURVIVES a failed refresh inside the bounded synthetic window and renders
/// as a RETAINED card under the visible stale-age banner — instead of
/// vanishing to an empty (false-clear) surface on the first errored fetch.
///
/// Produces a fresh ja-rendered PNG into `render_out/` so the reviewer can
/// LOOK at the thing the fix makes reachable:
///   16 — retained JMA 大雪警報 (expires:null) + 「stale」 age banner
///
/// HONESTY (so the reader can trust the render): the widget under test is the
/// REAL [AdvisoryCards] fed the exact shape the production retain path now
/// produces on a total JMA failure — a null-expires JMA advisory in the
/// advisories list, a JMA provider error alongside it, and the caller's
/// `retainedAgeMinutes` stale stamp. No synthetic `expires` is stamped into
/// the advisory (the card would otherwise render a fabricated "expires …"
/// line); the honesty is carried by the stale banner. Run with:
///   flutter test --update-goldens \
///     test/render_see/advisory_retained_null_expires_capture_test.dart
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
    if (!cjkLoaded) installNoopGoldenComparator();
  });

  testWidgets(
      '16 — retained null-expires JMA 大雪警報 renders under the stale banner '
      '(the fix: not dropped to a false-clear)', (tester) async {
    // The exact shape the production retain path now produces on a total JMA
    // failure that stays inside the synthetic window: a null-expires JMA
    // warning kept in the list, with its provider error visible alongside.
    final retainedJma = Advisory(
      source: AdvisorySource.jmaJapan,
      eventClass: '大雪警報',
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.unknown,
      urgency: AdvisoryUrgency.unknown,
      areaDescription: '秋田中央',
      effective: DateTime.utc(2026, 1, 15, 4, 23),
      expires: null, // JMA warnings carry no publisher expiry
      headline: '秋田県では、大雪に警戒してください。',
      description: '秋田県では、大雪に警戒してください。',
    );

    await tester.pumpWidget(MaterialApp(
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
            result: AdvisoryAggregateResult(
              advisories: [retainedJma],
              providerErrors: const [
                AdvisoryProviderError(
                  source: AdvisorySource.jmaJapan,
                  message: 'HTTP 503',
                ),
              ],
            ),
            errorMessage: null,
            onRefresh: () {},
            // The caller's honest stale stamp (now - lastFreshAt), here +30 min
            // — well inside the 60-min synthetic window.
            retainedAgeMinutes: 30,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The hazard is present (fed to the drive brain + shown)…
    expect(find.text('大雪警報'), findsOneWidget);
    // …under the visible stale banner — never masquerading as current…
    expect(find.byKey(const Key('advisory-retained-stale')), findsOneWidget);
    expect(find.textContaining('30分'), findsOneWidget); // ja stale-age stamp
    // …and NO fabricated "expires …" line (null-expires stays null on-card).
    expect(find.textContaining('expires'), findsNothing);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
          '../../render_out/16_advisory_retained_null_expires_jma.png'),
    );
  });
}
