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
library;

import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

Future<List<Advisory>> _fetchAt(DateTime now) async {
  final provider = buildJmaAdvisoryProvider(
    userAgent: 'sngnav-app test',
    client: _serving(_frozenDocument()),
    now: () => now,
  );
  await provider.init();
  return provider.fetchActiveAdvisoriesAtPoint(
    latitude: kAkitaLat,
    longitude: kAkitaLon,
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
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
      expect(
        notice,
        isNotEmpty,
        reason: 'THE DEFECT: an 88-day-dead 雷注意報 reached the app with '
            'nothing marking it as unvouched-for. She would read a warning '
            'about "the 28th" as current weather.',
      );
      expect(
        notice.single.severity,
        AdvisorySeverity.minor,
        reason: 'the notice must stay below isHighImpact — it is a '
            'feed-health fact, not weather, and must never be able to '
            'masquerade as a hazard or cry wolf',
      );
    });

    testWidgets('and BOTH reach the rendered surface she looks at',
        (tester) async {
      final now = kFrozenReportedAt.add(const Duration(days: 88));
      final out = await _fetchAt(now);

      await tester.pumpWidget(_wrap(AdvisoryCards(
        loading: false,
        result: AdvisoryAggregateResult(
          advisories: out,
          providerErrors: const [],
          sourcesQueried: 1,
        ),
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
        find.textContaining(kStaleFeedEventClass),
        findsWidgets,
        reason: 'THE DEFECT, one layer down: the notice was in the list and '
            'was dropped between the list and her eyes. In-band delivery is '
            'not arrival.',
      );
      expect(
        find.textContaining('更新されていません'),
        findsWidgets,
        reason: 'the notice must carry its plain-language body, not just an '
            'event-class label she has no reason to understand',
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
