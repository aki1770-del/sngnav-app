/// THE STANDING TEST: if the app has no live warning source, this file is RED.
///
/// ## Why it exists
///
/// For 111 days her app read `bosai/warning/data/warning/050000.json` and was
/// served a document written on 2026-05-28. It answered HTTP 200 every time.
/// Nothing failed, no test went red, no log line appeared. JMA retired that
/// path on 2026-05-29 and the app went on reading it all summer, and what
/// finally surfaced it was a version-alignment question — not an instrument.
///
/// That is the whole defect: **a dead feed is not an error, it is a silence**,
/// and this repository had nothing that could tell the two apart. Naming it in
/// a document would leave the next migration exactly as invisible as this one.
/// So it is a test, and it fails.
///
/// ## ⚑ WHAT THIS TEST CANNOT DO, said before what it can
///
/// **It cannot tell you JMA is up.** It runs on a host with no network and
/// must keep doing so: a suite that reaches the internet is a suite that goes
/// red on a train, and a flaky guard gets deleted, which is how a repository
/// ends up with no guard at all. It cannot see the driver's device, her network, or a
/// publisher outage this morning.
///
/// A live-endpoint probe is a different instrument and is genuinely owed. This
/// is not that instrument and does not stand in for it.
///
/// ## WHAT IT ASSERTS, all three offline and all three load-bearing
///
/// 1. **The app is POINTED at a path that can be live.** The URL the provider
///    actually requests is observed through a mock client — not read from a
///    constant, not assumed from a version number. If a future resolve, a
///    revert or a range widening puts the app back on the retired path, this
///    is red on the next run.
/// 2. **A document past the freshness bound reaches the driver as a NAMED STATE.**
///    Not a blank panel, not a quiet all-clear: a banner she can read and a
///    notice card in her own language.
/// 3. **The same document reaches the DEVELOPER as a FAILURE.**
///    `canAssertNoAdvisory` false, a feed-health notice in the list. The two
///    audiences are asserted separately on purpose — the 111 days happened
///    because the app was honest to the driver and silent to us.
library;

import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/jma_advisory_provider_factory.dart';
import 'package:sngnav_app/services/jma_feed_health.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

/// The path JMA retired on 2026-05-29. Spelled out rather than imported so the
/// assertion survives the package dropping the constant.
const String kRetiredWarningPathSegment = '/bosai/warning/data/warning/';

/// The path JMA serves today.
const String kLiveWarningPathSegment = '/bosai/warning/data/r8/';

const double kAkitaLat = 39.7186;
const double kAkitaLon = 140.1024;

/// The real Akita document as served 2026-09-16, byte-for-byte.
String _liveAkita() => File(
      'test/fixtures/jma_warning_r8_akita_050000_live_20260916.json',
    ).readAsStringSync();

/// The same document, timestamps shifted back to 2026-05-28 and its 濃霧 kinds
/// set in force — the frozen shape, derived, as its own fixture header records.
String _frozenAkita() => File(
      'test/fixtures/jma_warning_r8_akita_050000_frozen_20260528.json',
    ).readAsStringSync();

Widget _wrapJa(Widget child) => MaterialApp(
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
  group('the app must have a live warning source', () {
    test(
        '1. THE POINTING TEST — the app fetches the LIVE path, and the retired '
        'one is never requested', () async {
      final requested = <String>[];
      final provider = buildJmaAdvisoryProvider(
        userAgent: 'sngnav-app test',
        client: MockClient((request) async {
          requested.add(request.url.toString());
          return http.Response(_liveAkita(), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
        clock: () => DateTime.parse('2026-09-16T10:00:00+09:00'),
      );
      final aggregator = AdvisoryAggregator(providers: [provider]);
      await aggregator.init();
      await aggregator.fetchActiveAdvisoriesAtPoint(
        latitude: kAkitaLat,
        longitude: kAkitaLon,
      );

      expect(
        requested,
        isNotEmpty,
        reason: 'precondition: a point inside the adapter catalogue must '
            'actually cause a fetch. If this is empty the app is asking '
            'nobody about her road, and every assertion below is vacuous.',
      );
      expect(
        requested.where((u) => u.contains(kRetiredWarningPathSegment)),
        isEmpty,
        reason: 'THE 111-DAY DEFECT, as a red test. This path was retired '
            '2026-05-29 and answers 200 with a 2026-05-28 document forever. '
            'If the app is fetching it again, a version moved backwards and '
            'she is reading a corpse.',
      );
      expect(
        requested.every((u) => u.contains(kLiveWarningPathSegment)),
        isTrue,
        reason: 'every warning fetch must go to the path JMA actually writes. '
            'Observed from the request the client received, not read off a '
            'constant — the constant is what was right last time.',
      );
    });

    testWidgets(
        '2. DRIVER HALF — a document past the freshness bound reaches her as a '
        'NAMED STATE, never as a quiet screen', (tester) async {
      final provider = buildJmaAdvisoryProvider(
        userAgent: 'sngnav-app test',
        client: MockClient((request) async => http.Response(
            _frozenAkita(), 200,
            headers: {'content-type': 'application/json; charset=utf-8'})),
        // 111 days after the frozen document — the real elapsed time on
        // 2026-09-16, not a round number chosen to pass.
        clock: () => DateTime.parse('2026-05-28T06:11:00+09:00')
            .add(const Duration(days: 111)),
      );
      final aggregator = AdvisoryAggregator(providers: [provider]);
      await aggregator.init();
      final result = await aggregator.fetchActiveAdvisoriesAtPoint(
        latitude: kAkitaLat,
        longitude: kAkitaLon,
      );

      await tester.pumpWidget(_wrapJa(AdvisoryCards(
        loading: false,
        result: result,
        errorMessage: null,
        onRefresh: () {},
      )));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('advisory_stale_feed_banner')),
        findsOneWidget,
        reason: 'she must SEE that the source stopped. A screen that renders a '
            'May warning with no banner is the 111 days, drawn.',
      );
      expect(
        find.textContaining('更新が止まっています'),
        findsWidgets,
        reason: 'and in words she reads, not a class name or a code. She is '
            'the driver, not an integrator.',
      );
    });

    test(
        '3. OUR HALF — the same document reaches the DEVELOPER as a failure, '
        'not only the driver as a banner', () async {
      final provider = buildJmaAdvisoryProvider(
        userAgent: 'sngnav-app test',
        client: MockClient((request) async => http.Response(
            _frozenAkita(), 200,
            headers: {'content-type': 'application/json; charset=utf-8'})),
        clock: () => DateTime.parse('2026-05-28T06:11:00+09:00')
            .add(const Duration(days: 111)),
      );
      final aggregator = AdvisoryAggregator(providers: [provider]);
      await aggregator.init();
      final result = await aggregator.fetchActiveAdvisoriesAtPoint(
        latitude: kAkitaLat,
        longitude: kAkitaLon,
      );

      expect(
        result.providerErrors,
        isEmpty,
        reason: 'precondition, and the whole reason this file exists: NOTHING '
            'FAILED. The publisher answered 200 with well-formed JSON. A '
            'frozen feed does not look absent, it looks calm — which is why '
            'an error-count guard would have caught none of the 111 days.',
      );
      expect(
        result.hasStaleSource,
        isTrue,
        reason: 'the aggregate must carry the health signal out-of-band, which '
            'is what feeds canAssertNoAdvisory. This is the capability 0.5.0 '
            'and 0.6.0 dropped, and it is why the constraint floor is pinned '
            'at >=0.7.0 rather than widened from 0.3.0.',
      );
      expect(
        result.canAssertNoAdvisory,
        isFalse,
        reason: 'and NO POSITIVE ALL-CLEAR may be computed from it. A false '
            'all-clear removes the prompt to look out of the windscreen.',
      );
      expect(
        jmaFeedHealthNotices(result.advisories),
        isNotEmpty,
        reason: 'and the in-band notice must be in the list too — keyed on the '
            'SET. At this age the class is the path-retirement one, so a match '
            'on the stale class alone finds nothing; see '
            'jma_feed_health_set_test.dart.',
      );
    });

    test(
        'CONTROL — a HEALTHY live document raises none of it, so the three '
        'assertions above are caused by staleness and not by construction',
        () async {
      // Without this control the file would pass just as happily if the app
      // shouted "source stopped" on every read, healthy or not. That is the
      // cry-wolf failure, which this unit ranks beside silence: measured this
      // day, 27 of 58 JMA offices were past the adapter's 6-hour default with
      // nothing whatever wrong.
      final provider = buildJmaAdvisoryProvider(
        userAgent: 'sngnav-app test',
        client: MockClient((request) async => http.Response(
            _liveAkita(), 200,
            headers: {'content-type': 'application/json; charset=utf-8'})),
        // Twenty minutes after the real document's real timestamp.
        clock: () => DateTime.parse('2026-09-16T10:10:00+09:00'),
      );
      final aggregator = AdvisoryAggregator(providers: [provider]);
      await aggregator.init();
      final result = await aggregator.fetchActiveAdvisoriesAtPoint(
        latitude: kAkitaLat,
        longitude: kAkitaLon,
      );

      expect(
        result.hasStaleSource,
        isFalse,
        reason: 'a document twenty minutes old is healthy and must raise no '
            'banner. If this fires, she is being cried wolf at and will stop '
            'reading the banner that matters.',
      );
      expect(
        jmaFeedHealthNotices(result.advisories),
        isEmpty,
        reason: 'and no feed-health notice at all — otherwise the notice fires '
            'on every read and cannot distinguish a dead feed from a live one',
      );
    });
  });
}
