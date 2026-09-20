/// When a retained advisory sits under a frozen-feed banner, the PUBLISHER'S
/// clock is the loud one and OUR fetch clock is the quiet one.
///
/// WHY, written before the act (2026-09-20). The retention fix at 5dffeca made
/// a state reachable that had never been rendered: the feed-health banner and
/// the retained-age label on screen together, each carrying a different age.
/// The banner says the publisher's document stopped moving about 88 days ago.
/// The label says our own last successful fetch was 10 minutes ago. Only the
/// first is the hazard; the second is provenance.
///
/// Rendered at the phone's geometry and looked at, the surface said the
/// opposite. Measured on those pixels:
///   * the banner's words were #B26A00 w400 on its composited fill #F2EADA —
///     3.54:1, BELOW the 4.5:1 floor this app holds itself to;
///   * the label's words were #6B4600 w600 on #FFF8E1 — 7.90:1, and 2.63x
///     darker in luminance than the banner's;
///   * the two fills differed by 1.126:1, so they did not read as two blocks;
///   * the label's line began 未更新 ("not updated") immediately before
///     「10分前」, so the loudest reading on the screen composed
///     "not updated - 10 minutes" over a document three months old.
///
/// A driver has about two seconds. The number she was given loudest was the
/// wrong one, and it was wrong in the unsafe direction: a feed that has been
/// dead since May read as a fetch that failed a moment ago.
///
/// This test holds the correction in place. It is deliberately about ORDER OF
/// EMPHASIS and not about one colour constant: a later hand may repaint either
/// block, and what must survive is that the older clock outranks the newer one
/// and that both are readable.
///
/// It also closes a named gap. test/widgets/text_contrast_floor_test.dart says
/// in its own words that it does not cover "advisory and weather rows with
/// data" - which is exactly where the 3.54:1 lived. This holds that state to
/// the same floor, with the same helper, rather than starting a second one.
///
/// Bounds: these are framework colours on a host raster, not a phone panel.
/// Nothing here measures whether a human reads the right meaning in the time
/// she has; no timed glance study has been run, and this test does not claim
/// one.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

import '../support/painted_text_contrast.dart';

/// Runs in the advisory CARD's own chrome that were already below the floor
/// when this test was written, measured 2026-09-20 on this exact state:
///
///   #1976D2 @ 11 px  3.45:1  the severity pill's word (軽微 / Minor), on its
///                            own colour at 15% alpha
///   #757575 @ 11 px  4.17:1  the 開始 / Effective timestamp — which is a
///                            THIRD age fact on this screen, and the faintest
///                            of the three
///   #9E9E9E @ 10 px  2.42:1  the publisher attribution line
///
/// They are NOT fixed here and they are NOT cleared. They are a separate
/// finding of their own class: the pill's colour comes from `_severityColor`,
/// which also paints the card border and the pill fill and is mirrored
/// one-for-one by `_severityLabel`, so moving it is its own round with its own
/// render and its own controls. Hiding them inside a commit about the two
/// clocks would be the scope creep that makes a diff unreviewable.
///
/// They are written here WITH their numbers so that (a) they cannot be quietly
/// forgotten, and (b) a FOURTH below-floor run — including any regression in
/// the two blocks this test exists for — still turns this red.
const _knownOwed = <({String foreground, double size})>[
  (foreground: '#FF1976D2', size: 11.0),
  (foreground: '#FF757575', size: 11.0),
  (foreground: '#FF9E9E9E', size: 10.0),
];

bool _isKnownOwed(PaintedText p) => _knownOwed.any((k) =>
    p.describe().contains(k.foreground) && p.fontSize == k.size);

final _frozenJmaWarning = Advisory(
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
);

/// Akita's real shape: the only covering publisher's document has been frozen
/// for 88 days, and the fetch 10 minutes after the last good one failed.
AdvisoryAggregateResult _retainedUnderFrozenFeed() => AdvisoryAggregateResult(
      advisories: [_frozenJmaWarning],
      providerErrors: const [
        AdvisoryProviderError(
            source: AdvisorySource.jmaJapan, message: 'fetch failed'),
      ],
      sourcesQueried: 1,
      staleSources: const [
        AdvisoryFeedStaleness(
            source: AdvisorySource.jmaJapan,
            age: Duration(days: 88),
            detail: '050000'),
      ],
    );

/// The publisher is healthy; only our own fetch failed. The label is then the
/// ONLY staleness line on the surface and must keep its own full weight.
AdvisoryAggregateResult _retainedWithHealthyFeed() => AdvisoryAggregateResult(
      advisories: [_frozenJmaWarning],
      providerErrors: const [
        AdvisoryProviderError(
            source: AdvisorySource.jmaJapan, message: 'fetch failed'),
      ],
      sourcesQueried: 1,
      staleSources: const [],
    );

/// The app's own section chrome (lib/main.dart:4144), so the ground behind a
/// 12%-alpha fill composites over the real card surface and not over nothing.
Widget _host(
  AdvisoryAggregateResult r,
  int? retainedAgeMinutes,
  String lang,
) =>
    MaterialApp(
      locale: Locale(lang),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
        fontFamilyFallback: const ['SnGNavSymbols'],
      ),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AdvisoryCards(
                loading: false,
                result: r,
                errorMessage: null,
                onRefresh: () {},
                retainedAgeMinutes: retainedAgeMinutes,
                pointCovered: true,
              ),
            ),
          ),
        ),
      ),
    );

/// The style and laid-out geometry actually used to paint the first paragraph
/// inside the block with [key].
({FontWeight weight, Color? colour, double width, Color? fill}) _painted(
  WidgetTester tester,
  String key,
) {
  final block = find.byKey(Key(key));
  expect(block, findsOneWidget, reason: 'precondition: $key is on the screen');
  final para = tester.renderObject<RenderParagraph>(
      find.descendant(of: block, matching: find.byType(RichText)).last);
  Color? fill;
  final ctr = find
      .descendant(of: block, matching: find.byType(Container))
      .evaluate()
      .map((e) => e.widget as Container)
      .followedBy([tester.widget<Container>(block)]);
  for (final c in ctr) {
    if (c.color != null) {
      fill = c.color;
      break;
    }
  }
  return (
    weight: para.text.style?.fontWeight ?? FontWeight.normal,
    colour: para.text.style?.color,
    width: para.size.width,
    fill: fill,
  );
}

void main() {
  for (final lang in const ['ja', 'en']) {
    testWidgets(
        '$lang — the publisher\'s 88-day clock outranks our 10-minute clock',
        (tester) async {
      await tester.pumpWidget(_host(_retainedUnderFrozenFeed(), 10, lang));
      await tester.pumpAndSettle();

      final banner = _painted(tester, 'advisory_stale_feed_banner');
      final label = _painted(tester, 'advisory-retained-stale');

      // Every finding is GATHERED and asserted once at the end, so a single
      // red names everything that moved rather than only the first thing. The
      // first run of this test against the unfixed code stopped at the weight
      // and never printed the 3.54:1, which is half the defect.
      final found = <String>[];

      // 1. EMPHASIS. The older fact is the heavier one. Stated as a
      //    comparison, not as a constant, so a later repaint of either block
      //    still has to keep the order.
      if (banner.weight.value <= label.weight.value) {
        found.add('$lang: the feed-health banner carries the publisher\'s age '
            'and must be heavier than the label carrying our own fetch age; '
            'banner ${banner.weight}, label ${label.weight}');
      }

      // 2. ONE BLOCK, NOT TWO COMPETING ONES. Two amber fills 1.126:1 apart
      //    read as one slab anyway, so they are made literally the same and
      //    the hierarchy inside it does the work.
      if (banner.fill == null) found.add('$lang: banner fill not found');
      if (label.fill != banner.fill) {
        found.add('$lang: when both are on screen they are one block with a '
            'headline and a subline, not two blocks of nearly-equal amber; '
            'banner ${banner.fill}, label ${label.fill}');
      }

      // 3. ALIGNED EDGES. The subline began 20 logical px left of the
      //    headline's text - left of even the warning mark - and its first
      //    word jutted out as if a new block started there. Equal laid-out
      //    widths means equal left and right edges inside an equal-width box.
      if ((label.width - banner.width).abs() > 0.5) {
        found.add('$lang: the subline must sit on the headline\'s text edge; '
            'banner ${banner.width}, label ${label.width}');
      }

      // 4. READABLE. Every painted run in this state, against its own real
      //    composited ground, at or above the app's floor. This is the state
      //    text_contrast_floor_test.dart names as not covered.
      final held =
          paintedTextOutsideMap(tester).where((p) => !p.inactive).toList();
      expect(held, isNotEmpty, reason: 'precondition: something was measured');
      for (final p in held.where((p) => !_isKnownOwed(p))) {
        if (p.ground == null) {
          found.add('$lang: ground unknown, contrast unmeasured: '
              '${p.describe()}');
        } else if (p.belowFloor) {
          found.add('$lang: below the floor: ${p.describe()}');
        }
      }

      // The two blocks this test is FOR are held with NO exemption at all:
      // the owed list above can never quietly grow to cover them.
      for (final k in const [
        'advisory_stale_feed_banner',
        'advisory-retained-stale'
      ]) {
        final runs = held.where((p) => p.key == k).toList();
        if (runs.isEmpty) found.add('$lang: nothing measured on $k');
        for (final p in runs) {
          if (p.ground == null || p.belowFloor) {
            found.add('$lang: $k: ${p.describe()}');
          }
        }
      }

      expect(found, isEmpty, reason: '\n${found.join('\n')}');
    });
  }

  testWidgets(
      'ja — ALONE (publisher healthy, our fetch failed) the label keeps its '
      'own full weight: there is no older clock to yield to', (tester) async {
    await tester.pumpWidget(_host(_retainedWithHealthyFeed(), 10, 'ja'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advisory_stale_feed_banner')), findsNothing);
    final label = _painted(tester, 'advisory-retained-stale');
    expect(label.weight, FontWeight.w600,
        reason: 'the only staleness line on the surface is not demoted');
    expect(label.fill, Colors.amber.shade50,
        reason: 'unchanged when it stands alone');

    final held =
        paintedTextOutsideMap(tester).where((p) => !p.inactive).toList();
    final problems = [
      for (final p in held.where((p) => !_isKnownOwed(p)))
        if (p.ground == null)
          'alone: ground unknown: ${p.describe()}'
        else if (p.belowFloor)
          'alone: below the floor: ${p.describe()}',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
