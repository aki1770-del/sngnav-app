// WS7 — dignity + consent localization tests.
//
// This is the most device-free-verifiable workstream: pure text and layout,
// golden-render-able in-env. It proves the consent gate + data-flow disclosure
// render in HER language (ja), and that the advisory surface leads with the
// authoritative Japanese publisher (JMA) and de-emphasizes the English NWS
// card on the ja surface.
//
// HONESTY (OPS-066 / AAE-1): this verifies the WIDGET TREE renders localized
// text in the test binding. It does NOT verify on-device HEAR/FEEL/SEE — there
// is no Android device/emulator in this env. On-device observation is DEFERRED.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

// headline/description left empty so [eventClass] renders exactly once per
// card — keeps find.text(eventClass) unambiguous for getTopLeft ordering.
Advisory _advisory(AdvisorySource source, String eventClass) => Advisory(
      source: source,
      eventClass: eventClass,
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: source == AdvisorySource.jmaJapan ? '秋田県' : 'Akita',
      effective: null,
      expires: null,
      headline: '',
      description: '',
    );

/// Wraps [child] in the same localization stack the app uses, forced to
/// [locale]. Lets us render AdvisoryCards under ja/en without the full app.
Widget _localizedHost(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja'), Locale('en')],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('Consent gate + disclosure — Locale(ja)', () {
    testWidgets('consent affordance renders in Japanese', (tester) async {
      await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
      await tester.pump();

      // The deny-by-default consent affordance is HER language.
      expect(find.text('現在地を共有'), findsOneWidget); // "Share my location"
      expect(find.text('位置情報はまだ共有されていません。'), findsOneWidget);
      expect(find.text('秋田のモック位置（開発用）'), findsOneWidget);
      // No English consent leak on the ja surface.
      expect(find.text('Share my location'), findsNothing);
      expect(find.text('Location not yet shared.'), findsNothing);
    });

    testWidgets('data-flow disclosure is present + localized', (tester) async {
      await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
      await tester.pump();

      final disclosureFinder = find.byKey(const Key('location-disclosure'));
      expect(disclosureFinder, findsOneWidget);
      final text = tester.widget<Text>(disclosureFinder).data!;
      // Japanese, and states the load-bearing honesty facts (B28-corrected).
      expect(text, contains('気象庁')); // JMA publisher named
      expect(text, contains('都道府県コード')); // what the JMA wire REALLY carries
      expect(text, contains('1km')); // ~1km cadence
      expect(text, contains('任意')); // opt-in
      expect(text, contains('保存されず')); // not persisted
      expect(text, contains('本アプリ独自のサーバー')); // not to our servers
    });

    testWidgets('other-egress disclosure (B27+B30) is on the same card, ja',
        (tester) async {
      await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
      await tester.pump();

      final finder = find.byKey(const Key('egress-disclosure'));
      expect(finder, findsOneWidget);
      final text = tester.widget<Text>(finder).data!;
      // The three real non-advisory egresses, named by host.
      expect(text, contains('router.project-osrm.org')); // B27 route egress
      expect(text, contains('同意するまで送信されません')); // consent-gated pre-send
      expect(text, contains('tile.openstreetmap.org')); // B30 tile fallback
      expect(text, contains('IPアドレス')); // what the tile server sees
      expect(text, contains('音声')); // B30 network-TTS possibility
    });
  });

  group('Consent gate + disclosure — Locale(en)', () {
    testWidgets('consent affordance + disclosure render in English',
        (tester) async {
      await tester.pumpWidget(const SngnavApp(locale: Locale('en')));
      await tester.pump();

      expect(find.text('Share my location'), findsOneWidget);
      final text = tester
          .widget<Text>(find.byKey(const Key('location-disclosure')))
          .data!;
      expect(text, contains('JMA'));
      expect(text, contains('opt-in'));
      expect(text, contains('never stored'));
    });
  });

  group('AppL10n unit', () {
    test('ja/en resolution + disclosure honesty facts', () {
      const ja = AppL10n(Locale('ja'));
      const en = AppL10n(Locale('en'));
      expect(ja.shareMyLocation, '現在地を共有');
      expect(en.shareMyLocation, 'Share my location');
      // Unknown locale falls back to English (honest default).
      expect(const AppL10n(Locale('fr')).shareMyLocation, 'Share my location');
      // gpsUnavailable localizes the known geolocator reason for HER.
      expect(
        ja.gpsUnavailable('Location permission denied'),
        contains('位置情報の許可が拒否されました'),
      );
      // Unknown reason passes through honestly (no fabricated translation).
      expect(ja.gpsUnavailable('weird novel reason'),
          contains('weird novel reason'));
    });

    test(
        'EVERY reason her_position.dart can emit renders in ja — no English '
        'passthrough on a safety-relevant GPS-degraded line (the B20 timeout '
        '/ stream-end reasons were added without extending the map)', () {
      const ja = AppL10n(Locale('ja'));
      // The exact reason strings her_position.dart emits (kept verbatim —
      // the l10n matches on substrings of these).
      const reasons = [
        'Location services disabled',
        'Location service check timed out — platform did not answer',
        'Location permission check timed out — platform did not answer',
        'Location permission request timed out — no answer from the '
            'platform dialog',
        'Location permission denied',
        'Location permission permanently denied — change in OS settings',
        'Degraded GPS fix — non-finite coordinate (lat=NaN, lon=1.0, acc=5.0)',
        'GPS stream error: boom',
        'GPS stream ended by the platform',
        'GPS init error: boom',
      ];
      for (final reason in reasons) {
        final line = ja.gpsUnavailable(reason);
        expect(
          // No ASCII letter runs from the original reason may survive into
          // HER line (the wrapper text itself is pure ja + punctuation).
          RegExp('[A-Za-z]{3,}').hasMatch(line.replaceAll('GPS', '')),
          isFalse,
          reason: 'reason "$reason" leaked English into the ja surface: '
              '"$line"',
        );
      }
    });
  });

  group('Data-flow disclosure is WIRE-ACCURATE (B28 fix)', () {
    // Truth read at the resolved package sources (pubspec.lock):
    // condition_aggregator_jma 0.3.0 maps point→prefecture ON-DEVICE and
    // requests only warning/{prefectureCode}.json — coordinates never leave
    // the device for Japan. noaa_nws_adapter 0.0.8 sends the actual point
    // (?point=lat,lon) for US points. Locale is NOT location, so BOTH
    // locales must state both regional facts (a ja-reading driver in the US
    // hits the NWS point path).
    const ja = AppL10n(Locale('ja'));
    const en = AppL10n(Locale('en'));

    test('JA: Japan = coords never leave the device, only a prefecture code',
        () {
      final d = ja.locationDisclosure;
      expect(d, contains('気象庁'));
      // The load-bearing correction: NOT "coordinates are sent to JMA".
      expect(d, contains('座標が端末の外へ送信されることはありません'));
      expect(d, contains('都道府県コード'));
      // The US fact is stated too (locale ≠ location).
      expect(d, contains('NWS'));
      // Out-of-region services are not contacted.
      expect(d, contains('管轄しない'));
      // It must NOT resurrect the false claim that coordinates go to a
      // weather service unconditionally.
      expect(d, isNot(contains('座標が、その地域を管轄する公的な気象機関へ送信')));
    });

    test('EN: prefecture-code-only for Japan; point coords for the US', () {
      final d = en.locationDisclosure;
      expect(d, contains('JMA'));
      expect(d, contains('never leave the device'));
      expect(d, contains('prefecture code'));
      expect(d, contains('NWS'));
      // States the load-bearing gating fact (out-of-region → not contacted).
      expect(d.toLowerCase(), contains('never contacted'));
      expect(d.toLowerCase(), contains('opt-in'));
    });

    test('egress disclosure names all three non-advisory egresses, both '
        'locales', () {
      for (final l in const [AppL10n(Locale('ja')), AppL10n(Locale('en'))]) {
        final d = l.egressDisclosure;
        expect(d, contains('router.project-osrm.org'));
        expect(d, contains('tile.openstreetmap.org'));
      }
      // Network-TTS possibility, per locale.
      expect(ja.egressDisclosure, contains('ネットワーク音声'));
      expect(en.egressDisclosure, contains('network voice'));
    });
  });

  group('Advisory ordering + NWS de-emphasis (task 4)', () {
    testWidgets('ja surface leads with JMA and de-emphasizes NWS',
        (tester) async {
      final result = AdvisoryAggregateResult(
        advisories: [
          // NWS first in the source list — the ja surface must reorder it.
          _advisory(AdvisorySource.nwsUnitedStates, 'Winter Storm Warning'),
          _advisory(AdvisorySource.jmaJapan, '大雪警報'),
        ],
        providerErrors: const [],
      );

      await tester.pumpWidget(_localizedHost(
        const Locale('ja'),
        AdvisoryCards(
          loading: false,
          result: result,
          errorMessage: null,
          onRefresh: () {},
        ),
      ));
      await tester.pump();

      // Both cards present (NWS is de-emphasized, never dropped).
      expect(find.text('大雪警報'), findsOneWidget);
      expect(find.text('Winter Storm Warning'), findsOneWidget);

      // JMA card renders ABOVE the NWS card (leads the surface).
      final jmaY = tester.getTopLeft(find.text('大雪警報')).dy;
      final nwsY = tester.getTopLeft(find.text('Winter Storm Warning')).dy;
      expect(jmaY, lessThan(nwsY));

      // The NWS card carries the localized "English (reference)" caption
      // and is wrapped in an Opacity (dimmed).
      expect(find.text('英語の情報（参考）'), findsOneWidget);
      expect(find.byType(Opacity), findsWidgets);
    });

    testWidgets('en surface keeps publisher order + no de-emphasis caption',
        (tester) async {
      final result = AdvisoryAggregateResult(
        advisories: [
          _advisory(AdvisorySource.nwsUnitedStates, 'Winter Storm Warning'),
          _advisory(AdvisorySource.jmaJapan, '大雪警報'),
        ],
        providerErrors: const [],
      );

      await tester.pumpWidget(_localizedHost(
        const Locale('en'),
        AdvisoryCards(
          loading: false,
          result: result,
          errorMessage: null,
          onRefresh: () {},
        ),
      ));
      await tester.pump();

      // English surface: no ja-only reference caption; original order kept
      // (NWS above JMA, as returned).
      expect(find.text('英語の情報（参考）'), findsNothing);
      final nwsY = tester.getTopLeft(find.text('Winter Storm Warning')).dy;
      final jmaY = tester.getTopLeft(find.text('大雪警報')).dy;
      expect(nwsY, lessThan(jmaY));
    });
  });

  // Strings are asserted against the ACTUAL emitted l10n values (not hardcoded
  // test literals), so a copy change can't silently pass a stale assertion.
  const jaL10n = AppL10n(Locale('ja'));

  group('WS5 announce affordance localized (task 3a / D4)', () {
    testWidgets('ja surface shows the JA announce label + helper, no EN leak',
        (tester) async {
      await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
      await tester.pump();

      // The button label is HER language...
      expect(find.text(jaL10n.announceToDriver), findsOneWidget);
      // ...and the English label is gone from the surface.
      expect(find.text('Announce to driver (audio + haptic)'), findsNothing);

      // Default condition is ice => critical => the "fires" helper, in JA.
      expect(find.text(jaL10n.announceFiresHelper('critical')), findsOneWidget);
      // No English helper leak.
      expect(
        find.textContaining('On-device HEAR/FEEL not verified in this env.'),
        findsNothing,
      );
    });

    testWidgets('en surface shows the English announce label', (tester) async {
      await tester.pumpWidget(const SngnavApp(locale: Locale('en')));
      await tester.pump();
      expect(
        find.text('Announce to driver (audio + haptic)'),
        findsOneWidget,
      );
    });
  });

  group('Advisory card states localized (task 3b / D4)', () {
    testWidgets('ja empty-state renders the localized no-data line',
        (tester) async {
      await tester.pumpWidget(_localizedHost(
        const Locale('ja'),
        AdvisoryCards(
          loading: false,
          result: const AdvisoryAggregateResult(
            advisories: [],
            providerErrors: [],
          ),
          errorMessage: null,
          onRefresh: () {},
        ),
      ));
      await tester.pump();
      expect(find.text(jaL10n.advisoryNoneActive), findsOneWidget);
      expect(
        find.text('No active advisories at this location.'),
        findsNothing,
      );
    });

    testWidgets('ja error-state renders the localized prefix (message verbatim)',
        (tester) async {
      await tester.pumpWidget(_localizedHost(
        const Locale('ja'),
        AdvisoryCards(
          loading: false,
          result: null,
          errorMessage: 'boom',
          onRefresh: () {},
        ),
      ));
      await tester.pump();
      expect(find.text(jaL10n.advisoryFetchFailed('boom')), findsOneWidget);
      // The Retry action is HER language too.
      expect(find.text(jaL10n.retry), findsOneWidget);
    });

    testWidgets(
        'UNCOVERED point (nobody queried) does NOT render the positive '
        'all-clear — the honest cannot-check-here line renders instead',
        (tester) async {
      await tester.pumpWidget(_localizedHost(
        const Locale('ja'),
        AdvisoryCards(
          loading: false,
          result: const AdvisoryAggregateResult(
            advisories: [],
            providerErrors: [],
          ),
          errorMessage: null,
          onRefresh: () {},
          pointCovered: false,
        ),
      ));
      await tester.pump();
      expect(
        find.byKey(const Key('advisory-no-covering-publisher')),
        findsOneWidget,
      );
      expect(find.text(jaL10n.advisoryNoCoveringPublisher), findsOneWidget);
      // The positive publisher claim nobody made must NOT render.
      expect(find.text(jaL10n.advisoryNoneActive), findsNothing);
    });

    testWidgets('en empty-state keeps the English line', (tester) async {
      await tester.pumpWidget(_localizedHost(
        const Locale('en'),
        AdvisoryCards(
          loading: false,
          result: const AdvisoryAggregateResult(
            advisories: [],
            providerErrors: [],
          ),
          errorMessage: null,
          onRefresh: () {},
        ),
      ));
      await tester.pump();
      expect(
        find.text('No active advisories at this location.'),
        findsOneWidget,
      );
    });
  });
}
