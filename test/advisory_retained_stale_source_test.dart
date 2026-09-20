/// The seam between RETENTION and the STALE-SOURCE guard.
///
/// Two guards exist, each pinned by its own suite, and nothing pinned the seam
/// between them:
///
///  - `advisory_axis.dart:174-180` drops an advisory whose SOURCE reported its
///    own document stale, so a 雷注意報 from a May document cannot set the rung
///    that fires audio + haptic (`main.dart:1441`).
///  - `advisory_cards.dart:176` renders the feed-health banner on
///    `hasStaleSource` — 「気象情報の更新が止まっています（約88日）」 — above
///    everything, because it qualifies every row beneath it.
///
/// Both read `AdvisoryAggregateResult.staleSources`. Both rebuilds in
/// `main.dart` — `retainAdvisoriesOnFailure` and `cullExpiredRetainedAdvisories`
/// — construct a new result WITHOUT that field, and it defaults to `const []`
/// (condition_aggregator 0.0.10, `advisory_aggregator.dart:103`). So the moment
/// a result is retained, the corpse stands back up: it sets the rung again, and
/// the one line on her screen that said the feed had stopped moving disappears.
///
/// `canAssertNoAdvisory` stays false throughout (retention only fires with a
/// non-empty `providerErrors`), so there is no fabricated all-clear here. That
/// is asserted as a CONTROL below, in both directions, so a future change that
/// buys the rung back by inventing calm fails this file.
///
/// The Akita shape is the reachable one: JMA is the only covering publisher
/// (`advisory_service.dart:89-93`), its warnings carry `expires: null`, and the
/// 10-minute refresh ticker means the first errored fetch lands well inside
/// `kSlowHazardRetainWindow`.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show AdvisoryLevel;
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart'
    show cullExpiredRetainedAdvisories, retainAdvisoriesOnFailure;
import 'package:sngnav_app/services/advisory_axis.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

/// Akita's real one: listed by a document that stopped being rewritten in May,
/// and carrying no publisher validity bound of its own.
Advisory _jmaThunder({AdvisorySeverity severity = AdvisorySeverity.severe}) =>
    Advisory(
      source: AdvisorySource.jmaJapan,
      eventClass: '雷注意報',
      severity: severity,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: '秋田県',
      effective: DateTime.utc(2026, 5, 28, 5),
      expires: null,
      headline: '雷注意報',
      description: '落雷や突風に注意してください。',
    );

/// A LIVE advisory from a publisher that has not gone quiet, with its own
/// declared validity bound.
Advisory _nwsLive(DateTime expires) => Advisory(
      source: AdvisorySource.nwsUnitedStates,
      eventClass: 'Winter Weather Advisory',
      severity: AdvisorySeverity.minor,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: 'Akita',
      effective: DateTime.utc(2026, 8, 24, 2),
      expires: expires,
      headline: 'Winter Weather Advisory',
      description: 'Snow expected.',
    );

const _jma88d = AdvisoryFeedStaleness(
  source: AdvisorySource.jmaJapan,
  age: Duration(days: 88),
  detail: '050000',
);
const _jmaDown = AdvisoryProviderError(
  source: AdvisorySource.jmaJapan,
  message: 'HTTP 503',
);
const _nwsDown = AdvisoryProviderError(
  source: AdvisorySource.nwsUnitedStates,
  message: 'HTTP 503',
);

final _lastFreshAt = DateTime.utc(2026, 8, 24, 3);
final _now = _lastFreshAt.add(const Duration(minutes: 10));

void main() {
  group('a RETAINED result keeps what the fresh one measured about staleness',
      () {
    test(
        'Akita, JMA the only publisher: the retained 雷注意報 still cannot set '
        'the rung, and the feed-health fact survives the rebuild', () {
      final prior = AdvisoryAggregateResult(
        advisories: [_jmaThunder()],
        providerErrors: const [],
        sourcesQueried: 1,
        staleSources: const [_jma88d],
      );
      // CONTROL — on the fresh result the guard is doing its job.
      expect(readAdvisoryAxis(prior).level, isNull);
      expect(prior.hasStaleSource, isTrue);

      const fresh = AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [_jmaDown],
        sourcesQueried: 1,
      );
      final applied = retainAdvisoriesOnFailure(
        prior: prior,
        fresh: fresh,
        now: _now,
        lastFreshAt: _lastFreshAt,
      );

      expect(applied.retained, isTrue);
      // The row is NOT dropped — we do not know the warning is over.
      expect(applied.result.advisories, hasLength(1));

      expect(
        applied.result.hasStaleSource,
        isTrue,
        reason: 'the retained advisory came out of a document measured 88 days '
            'old; dropping that fact removes the banner from her screen',
      );
      expect(
        readAdvisoryAxis(applied.result).level,
        isNull,
        reason: 'a warning from a document that stopped moving in May must not '
            'fire the audio + haptic rung on a retained cycle either',
      );
      // CONTROL, the other direction: the honest state is "unknown", never
      // "clear". Withholding the reassurance does not depend on this fix and
      // must not be traded for it.
      expect(readAdvisoryAxis(applied.result).completenessProven, isFalse);
    });

    test(
        'partial failure: an UNRELATED retained advisory must not switch the '
        'exclusion off for the stale one — per source, not blanket', () {
      final prior = AdvisoryAggregateResult(
        advisories: [_nwsLive(_lastFreshAt.add(const Duration(hours: 3)))],
        providerErrors: const [],
        sourcesQueried: 2,
      );
      final fresh = AdvisoryAggregateResult(
        advisories: [_jmaThunder()],
        providerErrors: const [_nwsDown],
        sourcesQueried: 2,
        staleSources: const [_jma88d],
      );
      // CONTROL — with nothing retained, this very result already excludes the
      // stale JMA warning.
      expect(readAdvisoryAxis(fresh).level, isNull);

      final applied = retainAdvisoriesOnFailure(
        prior: prior,
        fresh: fresh,
        now: _now,
        lastFreshAt: _lastFreshAt,
      );

      expect(applied.retained, isTrue);
      expect(applied.result.advisories, hasLength(2));
      expect(
        readAdvisoryAxis(applied.result).level,
        AdvisoryLevel.minor,
        reason: 'the LIVE NWS advisory sets the rung; the 88-day-old severe '
            'JMA one does not. A blanket suppression would read null here and '
            'would be its own false silence',
      );
      expect(applied.result.hasStaleSource, isTrue);
    });

    test(
        'the stationary-expiry cull drops the expired hazard and keeps the '
        'feed-health fact', () {
      final retainedResult = AdvisoryAggregateResult(
        advisories: [
          _jmaThunder(),
          _nwsLive(_lastFreshAt.add(const Duration(minutes: 5))),
        ],
        providerErrors: const [_nwsDown],
        sourcesQueried: 2,
        staleSources: const [_jma88d],
      );

      final culled = cullExpiredRetainedAdvisories(
        retainedResult,
        _now,
        lastFreshAt: _lastFreshAt,
      );

      expect(culled, isNotNull);
      expect(culled!.advisories, hasLength(1));
      expect(
        culled.hasStaleSource,
        isTrue,
        reason: 'a cull drops expired hazards; it re-reads no document, so '
            'what was measured stale is still measured stale',
      );
      expect(readAdvisoryAxis(culled).level, isNull);
      expect(readAdvisoryAxis(culled).completenessProven, isFalse);
    });
  });

  group('her screen on a retained cycle', () {
    Widget host(AdvisoryAggregateResult result, int retainedAgeMinutes) =>
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
                retainedAgeMinutes: retainedAgeMinutes,
              ),
            ),
          ),
        );

    testWidgets(
        'the feed-health banner renders over a RETAINED warning — the two age '
        'facts are both hers', (tester) async {
      final prior = AdvisoryAggregateResult(
        advisories: [_jmaThunder()],
        providerErrors: const [],
        sourcesQueried: 1,
        staleSources: const [_jma88d],
      );
      const fresh = AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [_jmaDown],
        sourcesQueried: 1,
      );
      final applied = retainAdvisoriesOnFailure(
        prior: prior,
        fresh: fresh,
        now: _now,
        lastFreshAt: _lastFreshAt,
      );

      await tester.pumpWidget(host(applied.result, 10));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('advisory_stale_feed_banner')),
        findsOneWidget,
        reason: 'without it she reads 「10分前に取得」 over a document from May',
      );
      expect(find.textContaining('約88日'), findsOneWidget);
      // The retained-age label is the OTHER fact and stays; the warning row is
      // qualified, never hidden.
      expect(find.byKey(const Key('advisory-retained-stale')), findsOneWidget);
      expect(find.textContaining('雷注意報'), findsWidgets);
      // The fabricated all-clear must be absent from this surface.
      expect(find.text('この地点に有効な警報・注意報はありません。'), findsNothing);
    });
  });
}
