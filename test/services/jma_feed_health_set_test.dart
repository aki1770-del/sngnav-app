/// THE TEST THAT IS RED IF THE APP MATCHES ONE FEED-HEALTH CONSTANT.
///
/// The upgrade to `condition_aggregator_jma` 0.7.0 gave her app the live JMA
/// path after 111 days on a frozen one. It also moved a boundary that could
/// have taken the feed-health signal away in the same commit, and a green
/// suite would not have shown it — which is why this file exists and why it
/// asserts the FAILURE as loudly as the fix.
///
/// Through 0.6.0 there was one feed-health identity worth matching:
/// `kJmaStaleFeedEventClass` (気象情報の更新停止). From 0.7.0, a document past
/// `pathRetirementThreshold` is diagnosed differently and carries
/// `kJmaPathRetirementEventClass` (気象情報の提供経路が変更された可能性)
/// instead — because "this path may no longer be served" points at a one-line
/// fix, where "the data is old" points at waiting. The package walked into
/// this trap in its own suite and exports the SET so consumers need not.
///
/// ⚑ **In THIS app the single-constant match sees nothing at all, not merely
/// less.** `buildJmaAdvisoryProvider` sets `staleFeedThreshold` to 7 days and
/// `kJmaDefaultPathRetirementThreshold` is also 7 days, so every read old
/// enough to be flagged is old enough to be called a retirement. The stale
/// class is structurally unreachable here. `_theSingleConstantMatchIsBlind`
/// below proves that against the real 111-day Akita feed rather than asserting
/// it.
///
/// Why: the feed-health notice is the only thing on her screen that says
/// the road ahead is unmeasured rather than clear. At ten metres' visibility
/// she cannot go and check. A signal that silently stops arriving takes the
/// prompt to look out of the windscreen with it.
library;

import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart'
    show kJmaFeedHealthEventClasses;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/services/jma_advisory_provider_factory.dart';
import 'package:sngnav_app/services/jma_feed_health.dart';

/// Spelled out rather than imported, on purpose and in both directions. The
/// app's `isJmaFeedHealthAdvisory` follows the package's set so a new member
/// is picked up without an edit; these literals are the counterweight, so a
/// RENAME or a REMOVAL cannot pass silently the same way.
const String kStaleFeedEventClassLiteral = '気象情報の更新停止';
const String kPathRetirementEventClassLiteral = '気象情報の提供経路が変更された可能性';

const double kAkitaLat = 39.7186;
const double kAkitaLon = 140.1024;

/// The Akita document as the retired path served it, 2026-05-28, re-cut into
/// the r8 shape 0.7.0 parses. 111 days before the day this test was written.
final DateTime kFrozenReportedAt = DateTime.parse('2026-05-28T06:11:00+09:00');
const Duration kFrozenAgeToday = Duration(days: 111);

String _frozenAkita() => File(
      'test/fixtures/jma_warning_r8_akita_050000_frozen_20260528.json',
    ).readAsStringSync();

MockClient _serving(String body, String code) => MockClient((request) async {
      if (request.url.path.contains(code)) {
        return http.Response(body, 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('not found', 404);
    });

Future<AdvisoryAggregateResult> _aggregateFrozenAt(DateTime now) async {
  final provider = buildJmaAdvisoryProvider(
    userAgent: 'sngnav-app test',
    client: _serving(_frozenAkita(), '050000'),
    clock: () => now,
  );
  final aggregator = AdvisoryAggregator(providers: [provider]);
  await aggregator.init();
  return aggregator.fetchActiveAdvisoriesAtPoint(
    latitude: kAkitaLat,
    longitude: kAkitaLon,
  );
}

void main() {
  group('feed-health must be keyed on the SET, never on one member', () {
    test(
        'THE PROOF: on the real 111-day feed the single-constant match finds '
        'NOTHING and the set finds the notice', () async {
      final now = kFrozenReportedAt.add(kFrozenAgeToday);
      final result = await _aggregateFrozenAt(now);

      // What the OLD match would have seen. This assertion is the defect,
      // written as a passing expectation so it cannot be argued with: had the
      // app kept matching `kJmaStaleFeedEventClass` across this upgrade, this
      // is what it would have had on her screen — an empty list.
      final singleConstantMatch = result.advisories
          .where((a) => a.eventClass == kStaleFeedEventClassLiteral);
      expect(
        singleConstantMatch,
        isEmpty,
        reason: 'THE TRAP: matching 気象情報の更新停止 alone returns NOTHING on a '
            '111-day feed. The adapter diagnosed a path retirement instead. A '
            'consumer that did not follow the boundary would have gone silent '
            'on exactly the oldest, most dangerous document, and every test it '
            'had would still have been green.',
      );

      // What the app actually does.
      final setMatch = jmaFeedHealthNotices(result.advisories);
      expect(
        setMatch,
        isNotEmpty,
        reason: 'THE FIX: keying on kJmaFeedHealthEventClasses finds the '
            'notice the single constant missed. If this is ever empty, she is '
            'reading a dead feed with nothing telling her so.',
      );
      expect(
        setMatch.map((a) => a.eventClass),
        contains(kPathRetirementEventClassLiteral),
        reason: 'and it is the RETIREMENT diagnosis specifically — the one '
            'that points at a one-line fix rather than at waiting. That '
            'distinction is why the class changed at all, and the app must be '
            'able to see it.',
      );
    });

    test(
        'and the stale class is not merely rarer here — it is UNREACHABLE, '
        'because this app sets staleFeedThreshold to the retirement threshold',
        () async {
      // Any age old enough to be flagged at all is >= 7 days, which is also
      // kJmaDefaultPathRetirementThreshold. Probed across the whole band
      // rather than asserted from the source.
      for (final days in <int>[7, 8, 30, 88, 111, 365]) {
        final result =
            await _aggregateFrozenAt(kFrozenReportedAt.add(Duration(days: days)));
        final classes =
            jmaFeedHealthNotices(result.advisories).map((a) => a.eventClass);
        expect(
          classes,
          isNotEmpty,
          reason: 'at $days days the feed is stale and SOMETHING must say so',
        );
        expect(
          classes,
          isNot(contains(kStaleFeedEventClassLiteral)),
          reason: 'at $days days this app can never emit the stale class — '
              'staleFeedThreshold (7 d) is not below the retirement threshold '
              '(7 d), so the retirement branch always wins. If this ever '
              'fails, one of those two thresholds moved and the comment in '
              'jma_feed_health.dart is now false.',
        );
      }
    });

    test('the set still contains both identities, spelled out, so a package '
        'rename cannot pass silently', () {
      expect(
        kJmaFeedHealthEventClasses,
        containsAll(<String>[
          kStaleFeedEventClassLiteral,
          kPathRetirementEventClassLiteral,
        ]),
        reason: 'the app keys on this set; if a member is renamed or dropped '
            'upstream, the app stops recognising that signal as feed-health '
            'and would render a channel report as though it were weather',
      );
      expect(
        kJmaFeedHealthEventClasses.length,
        greaterThanOrEqualTo(2),
        reason: 'a set collapsed to one member is the pre-0.7.0 world and the '
            'app would be back in the trap',
      );
    });

    test('CONTROL — a real weather warning is NOT classified as feed-health',
        () async {
      // Without this, `isJmaFeedHealthAdvisory` returning true for everything
      // would pass every assertion above while hiding every warning she needs.
      //
      // ⚑ The first draft of this control used Nagano (200000) and FAILED —
      // correctly. The adapter's catalogue is the snow belt: eight Hokkaido
      // offices plus Aomori, Iwate, Akita, Yamagata and Niigata. A Nagano
      // point never fetches anything; it returns 気象警報の提供対象外地域, which
      // IS a feed-health class, so the weather list was empty. Recorded rather
      // than quietly swapped: the control caught the test author, which is
      // what a control is for.
      final live = File(
        'test/fixtures/jma_warning_r8_niigata_150000_live_inforce_20260916.json',
      ).readAsStringSync();
      final provider = buildJmaAdvisoryProvider(
        userAgent: 'sngnav-app test',
        client: _serving(live, '150000'),
        clock: () => DateTime.parse('2026-09-16T12:30:00+09:00'),
      );
      final aggregator = AdvisoryAggregator(providers: [provider]);
      await aggregator.init();
      final result = await aggregator.fetchActiveAdvisoriesAtPoint(
        latitude: 37.9026, // Niigata city
        longitude: 139.0235,
      );

      expect(
        result.advisories,
        isNotEmpty,
        reason: 'precondition: this fixture is a live document with warnings '
            'genuinely in force, captured 2026-09-16 — if it is empty the '
            'control tests nothing',
      );
      expect(
        weatherAdvisoriesOnly(result.advisories),
        isNotEmpty,
        reason: 'a real 注意報 must survive the feed-health filter and reach '
            'her as weather',
      );
      expect(
        jmaFeedHealthNotices(result.advisories),
        isEmpty,
        reason: 'and a HEALTHY live document raises no feed-health notice at '
            'all — otherwise the notice fires on every read and cannot '
            'distinguish a dead feed from a live one',
      );
    });
  });
}
