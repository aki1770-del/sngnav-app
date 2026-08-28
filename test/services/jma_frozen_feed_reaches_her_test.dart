/// What HER screen shows when the JMA warning feed has STOPPED BEING REWRITTEN.
///
/// The condition is not hypothetical and it is not history. Measured live
/// 2026-08-24 against the endpoint the shipped app reads:
///
///   GET bosai/warning/data/warning/050000.json  (Akita — HER mother's
///     prefecture) -> reportDatetime 2026-05-28T06:11+09:00, EIGHTY-EIGHT AND
///     A HALF DAYS old, every warning still carrying `status: 発表` (in force).
///   GET bosai/warning/data/r8/050000.json       (the successor path)
///     -> 22.6 hours old.
///
/// JMA retired the first path on 2026-05-29. Nothing in this app noticed for
/// 88 days, because a retired path and a quiet publisher look identical from
/// the outside: both simply stop changing.
///
/// The fixture in this test is that document, byte-for-byte as served.
///
/// WHY THIS TEST EXISTS AT ALL, when the notice is the package's job:
/// condition_aggregator_jma 0.5.0 emits the staleness notice IN-BAND, and its
/// author says why in the source — "a policy an integrator must remember to
/// apply is a policy that will not be applied". This test is the other half of
/// that sentence. In-band only means the fact is IN THE LIST; it does not mean
/// it reaches a driver. An app is free to filter `minor`, to render only the
/// highest severity, or to show the first card and collapse the rest — and any
/// of those would put HER back in front of a 雷注意報 about "the 28th" with
/// nothing to tell her which 28th. Before this file, `grep -rn
/// 'StaleFeed|更新停止|kJmaStaleFeedEventClass' lib/ test/` returned ZERO: the
/// app neither referenced the notice nor was tested against a frozen feed.
///
/// The invariant is NOT "warn about staleness loudly". It is narrower:
///
///   a warning the app cannot vouch for must never reach her ALONE.
///
/// She is allowed to see the 雷注意報. She is not allowed to see it without
/// being told the source stopped talking 88 days ago.
///
/// ⚑ WHAT THIS FILE DOES NOT COVER — added 2026-08-24 evening, against its own
/// author, because the coverage claim above reads wider than the tests are.
///
/// Every fixture here is the RETIRED path's document shape: a single JSON
/// OBJECT with one `reportDatetime`. The successor `/r8/` path returns a LIST
/// of five per-bulletin documents, each with its own timestamp, **not ordered
/// by time** — measured live 2026-08-24: office `015000`'s first element was
/// 862 h old while its newest was 3.7 h, both entirely normal. Nothing in this
/// file exercises that shape, and a reader could reasonably assume it does.
///
/// That is not a latent bug here today: the app pins
/// `condition_aggregator_jma ^0.5.0`, and 0.5.0 reads the RETIRED path. The
/// notice firing on every read is CORRECT right now, because that feed really
/// is dead. **The gap opens the moment an r8-carrying version reaches the app.**
///
/// And it opens onto the failure this unit ranks as worse than silence.
/// Measured live 2026-08-24 20:07 JST across all 13 catalogued offices on the
/// r8 feed, using the newest document per office: **4 of 13 — 31% — exceed the
/// 6-hour default staleness threshold with nothing wrong**, including `050000`,
/// HER mother's prefecture, at 12.2 h. JMA rewrites a WARNING document when
/// something changes; a quiet prefecture is simply not rewritten for days. The
/// 6-hour default was calibrated against the sibling FORECAST path, which is
/// schedule-driven. On the r8 feed this notice would tell her
/// 「安全とは限りません」 about healthy data roughly one office in three.
///
/// The threshold is `condition_aggregator_jma`'s to decide (NDI owns that
/// family) and is open at the time of writing. **What is owed HERE, when an
/// r8-carrying version reaches this app, is the control this file still lacks:
/// a fixture proving the notice does NOT fire on a healthy r8 office.** Until
/// then this file proves the notice APPEARS and does not prove it appears
/// APPROPRIATELY, and those are different claims.
library;

import 'dart:convert';
import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/jma_advisory_provider_factory.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

/// `kJmaStaleFeedEventClass`, condition_aggregator_jma 0.5.0
/// (lib/src/jma_advisory_mapper.dart:760). Deliberately spelled out rather
/// than imported: if the package renames or drops it, this test must FAIL
/// rather than silently follow the rename to a constant that no longer means
/// "the feed has stopped".
const String kStaleFeedEventClass = '気象情報の更新停止';

/// Akita city, in the prefecture the frozen fixture covers.
const double kAkitaLat = 39.7186;
const double kAkitaLon = 140.1024;

/// The fixture's own `reportDatetime`.
final DateTime kFrozenReportedAt = DateTime.parse('2026-05-28T06:11:00+09:00');

String _frozenDocument() => File(
      'test/fixtures/jma_warning_akita_050000_frozen_20260528.json',
    ).readAsStringSync();

MockClient _serving(String body) => MockClient((request) async {
      if (request.url.path.contains('050000')) {
        return http.Response(
          body,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    });

Future<List<Advisory>> _fetchAt(DateTime now) async =>
    (await _aggregateAt(now)).advisories;

/// The AGGREGATE, not just the list. `staleSources` lives here and nowhere
/// else — a hand-built `AdvisoryAggregateResult` cannot carry it, so a widget
/// test that constructs one by hand silently tests a feed with no health
/// signal. That is how the banner assertion first failed against a correct
/// banner, and it is why this goes through the real aggregator.
Future<AdvisoryAggregateResult> _aggregateAt(DateTime now) async {
  final provider = buildJmaAdvisoryProvider(
    userAgent: 'sngnav-app test',
    client: _serving(_frozenDocument()),
    clock: () => now,
  );
  final aggregator = AdvisoryAggregator(providers: [provider]);
  await aggregator.init();
  return aggregator.fetchActiveAdvisoriesAtPoint(
    latitude: kAkitaLat,
    longitude: kAkitaLon,
  );
}

/// HER reads Japanese. A banner proven only in English is not proven for her,
/// and the widget branches on locale — so the wrapper pins `ja` rather than
/// inheriting whatever the harness defaults to.
Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  _fabricatedAllClearGroup();
  group('a frozen JMA feed, at HER mother\'s prefecture', () {
    test('the dead warning still arrives, and it does not arrive alone',
        () async {
      final now = kFrozenReportedAt.add(const Duration(days: 88));
      final out = await _fetchAt(now);

      final dead = out.where((a) => a.eventClass == '雷注意報');
      final notice =
          out.where((a) => a.eventClass == kStaleFeedEventClass);

      expect(
        dead,
        isNotEmpty,
        reason: 'precondition: the frozen document really does still serve a '
            '雷注意報 as in force — if this fails the fixture has changed and '
            'the rest of this file is testing nothing',
      );
      // ⚑ ON THE 0.3.x LINE THE MARKER IS NOT IN THE LIST. 0.3.2 reports
      // freshness OUT-OF-BAND via `AdvisoryFeedFreshnessReporting`; the
      // in-band `Advisory` notice is a 0.5.0 capability, and 0.5.0 pays for it
      // by dropping the interface that feeds `canAssertNoAdvisory`. The app is
      // pinned to the line that keeps the guard fed, so the marker arrives as
      // `staleSources` and is rendered by the banner — asserted below.
      expect(
        notice,
        isEmpty,
        reason: '0.3.2 emits no in-band notice — if this ever becomes '
            'non-empty the pin has moved and the banner assertions below are '
            'no longer the only marker',
      );
    });

    testWidgets('and BOTH reach the rendered surface she looks at',
        (tester) async {
      final now = kFrozenReportedAt.add(const Duration(days: 88));
      final result = await _aggregateAt(now);

      expect(
        result.hasStaleSource,
        isTrue,
        reason: 'precondition: the aggregate really does carry the health '
            'signal — otherwise the banner assertion below tests nothing',
      );

      await tester.pumpWidget(_wrap(AdvisoryCards(
        loading: false,
        result: result,
        errorMessage: null,
        onRefresh: () {},
      )));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('雷注意報'),
        findsWidgets,
        reason: 'precondition: the dead warning does render',
      );
      expect(
        find.byKey(const Key('advisory_stale_feed_banner')),
        findsOneWidget,
        reason: 'THE DEFECT, one layer down: the app KNEW the feed was stale '
            '(staleSources non-empty, which is why canAssertNoAdvisory is '
            'false) and said nothing to her. Suppressing a false all-clear is '
            'silent; she is still reading an 88-day-old warning.',
      );
      expect(
        find.textContaining('更新が止まっています'),
        findsWidgets,
        reason: 'the banner must carry plain language, not a label she has no '
            'reason to understand',
      );
    });

    test('CRY-WOLF CONTROL — a 12-hour-old document is HEALTHY and must not '
        'turn the all-clear off', () async {
      // This is not a hypothetical age. Measured live 2026-08-24 20:07 JST on
      // the r8 feed, Akita's own newest document was 12.2 h old with nothing
      // wrong — one of 16 offices in 58 past the adapter's 6-hour default that
      // same minute, 13 of which were simultaneously serving a warning in
      // force.
      //
      // Under the 6 h default this read would set `staleSources`, which turns
      // `canAssertNoAdvisory` false and raises a banner saying her data may not
      // be safe — about healthy data, in her mother's prefecture, roughly a
      // third of the time. That is the failure this unit ranks as worse than
      // silence, arriving through the guard meant to prevent the other one.
      final out = await _aggregateAt(
        kFrozenReportedAt.add(const Duration(hours: 12)),
      );

      expect(
        out.staleSources,
        isEmpty,
        reason: 'a 12-hour-old JMA warning document is NORMAL — the path is '
            'event-driven, and a quiet prefecture is simply not rewritten. If '
            'this fires, the integrator threshold has slipped back toward the '
            'adapter default and she is being cried wolf at',
      );
      expect(
        out.hasStaleSource,
        isFalse,
        reason: 'and no banner is raised over healthy data',
      );
    });

    test('CONTROL — a FRESH document produces no notice, so the notice above '
        'was caused by staleness and not by construction', () async {
      // Same fixture, same code path, clock moved to one hour after the
      // document's own reportDatetime. Inside the 6-hour default threshold.
      final out = await _fetchAt(kFrozenReportedAt.add(const Duration(hours: 1)));

      expect(
        out.where((a) => a.eventClass == '雷注意報'),
        isNotEmpty,
        reason: 'the warning itself is unaffected by the clock',
      );
      expect(
        out.where((a) => a.eventClass == kStaleFeedEventClass),
        isEmpty,
        reason: 'if a notice fires on a one-hour-old document then this whole '
            'file proves nothing: it would fire on every read, including the '
            'healthy ones, and could not distinguish a dead feed from a live '
            'one',
      );
    });
  });
}

/// ⚑ THE FABRICATED ALL-CLEAR — the failure mode this unit ranks above every
/// other, tested at the exact seam where it reaches her.
///
/// Akita's frozen document still lists 27 warnings `status: 発表`, so its
/// advisory list is non-empty and the all-clear branch never runs. **Niigata's
/// does not.** Measured live 2026-08-24: `warning/150000.json`,
/// `reportDatetime 2026-05-26T15:45+09:00` — NINETY DAYS — and **zero warnings
/// in force**. The fixture below is that document, byte-for-byte.
///
/// That is the shape the package's own author called the worse of the two:
///
///   > "or it reports **nothing**, and an empty list is the identical value a
///   > genuinely clear sky produces… The second is the worse of the two. A false
///   > alarm is contradicted by the windscreen; a false all-clear removes the
///   > prompt to look out of it."
///
/// The app renders its positive all-clear at `advisory_cards.dart:203`:
/// `else if (r.advisories.isEmpty && r.canAssertNoAdvisory)`. So the whole
/// question is what `canAssertNoAdvisory` answers for a document that stopped
/// being written three months ago.
///
/// `condition_aggregator` **0.0.8** — which `origin/main` locked until this
/// change — computes it as `providerErrors.isEmpty && sourcesQueried > 0` and
/// has **no staleness concept at all** (`staleSources` appears in zero files).
/// A frozen publisher is *reachable*: HTTP 200, valid JSON, empty list. So it
/// returned **true**, and she was shown a clear road computed from a corpse.
///
/// 0.0.10 fixed the predicate — but the fix is fed by exactly one thing, an
/// adapter implementing `AdvisoryFeedFreshnessReporting`. `condition_aggregator_jma`
/// **0.3.2 has it; 0.5.0 does not.** Both locks moved to the versions that close
/// this, and both were already inside ranges `origin/main` had declared all
/// along. **No publish was required. It was withheld by a lockfile.**
void _fabricatedAllClearGroup() {
  group('a frozen feed that lists NOTHING must not become an all-clear', () {
    test('90-day-dead Niigata document -> canAssertNoAdvisory is FALSE',
        () async {
      final frozen = File(
        'test/fixtures/jma_warning_niigata_150000_frozen_zero_warnings.json',
      ).readAsStringSync();

      // Precondition, asserted rather than assumed: this really is the
      // dangerous shape — old, and carrying nothing.
      final decoded = jsonDecode(frozen) as Map<String, dynamic>;
      final reported = DateTime.parse(decoded['reportDatetime'] as String);
      final now = reported.add(const Duration(days: 90));

      final provider = buildJmaAdvisoryProvider(
        userAgent: 'sngnav-app test',
        client: MockClient((request) async {
          if (request.url.path.contains('150000')) {
            return http.Response(frozen, 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          return http.Response('not found', 404);
        }),
        clock: () => now,
      );

      final aggregator = AdvisoryAggregator(providers: [provider]);
      await aggregator.init();
      final result = await aggregator.fetchActiveAdvisoriesAtPoint(
        latitude: 37.9026, // Niigata city
        longitude: 139.0235,
      );

      expect(
        result.advisories,
        isEmpty,
        reason: 'precondition: the frozen Niigata document lists no warnings — '
            'this is the empty-list case, not the stale-warning case',
      );
      expect(
        result.providerErrors,
        isEmpty,
        reason: 'precondition: a frozen publisher is REACHABLE. Nothing failed. '
            'That is exactly why the old predicate said yes',
      );
      expect(
        result.canAssertNoAdvisory,
        isFalse,
        reason: 'THE DEFECT: the app would render a POSITIVE ALL-CLEAR at '
            'advisory_cards.dart:203 from a document 90 days dead. A false '
            'all-clear removes the prompt to look out of the windscreen.',
      );
      expect(
        result.hasStaleSource,
        isTrue,
        reason: 'and it must be false FOR THE RIGHT REASON — a measured '
            'staleness report, not an incidental error',
      );
    });

    test('CONTROL — the SAME shape with no staleness report DOES assert an '
        'all-clear, which is exactly the defect and exactly what shipped',
        () {
      // Identical to the case above in every respect the old predicate could
      // see: empty advisory list, no provider errors, one source asked. The
      // ONLY difference is that no adapter reported the feed stale — which is
      // the state `condition_aggregator_jma` 0.3.1 (locked on `origin/main`
      // until this change) and 0.5.0 both produce, because neither implements
      // `AdvisoryFeedFreshnessReporting`.
      //
      // If this returns false, the fix above is not doing what it claims and
      // the passing test above proves nothing.
      const noReport = AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 1,
      );

      expect(
        noReport.canAssertNoAdvisory,
        isTrue,
        reason: 'THE DEFECT, stated as a passing assertion so it cannot be '
            'argued with: a reachable publisher serving an empty list yields a '
            'POSITIVE all-clear. A frozen document is reachable. This is what '
            'the app did with Niigata for 90 days.',
      );
      expect(
        noReport.hasStaleSource,
        isFalse,
        reason: 'and the aggregate carries no health signal at all — there is '
            'nothing for a renderer to surface even if it wanted to',
      );
    });
  });
}
