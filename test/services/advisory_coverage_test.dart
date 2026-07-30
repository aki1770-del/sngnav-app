/// Region-gating tests for AdvisoryService + provider_coverage.
///
/// Proves the load-bearing HER-relevant fix: for HER Akita point
/// (39.7167, 140.0983) the US NWS provider is NEVER queried (no HTTP
/// request, no error card, no coordinate sent to a service that cannot
/// help her), while JMA IS queried; symmetrically a US point queries NWS
/// and not JMA; a point covered by neither queries no one.
///
/// The no-NWS-call proof is direct: an INSTRUMENTED fake NWS provider
/// records whether its `fetchActiveAdvisoriesAtPoint` was ever invoked,
/// and the JP-point test asserts it was NOT — proving gating happens
/// BEFORE the network call, not that a call merely returned empty.
library;

import 'package:condition_aggregator/condition_aggregator.dart'
    show
        Advisory,
        AdvisoryCertainty,
        AdvisoryProvider,
        AdvisorySeverity,
        AdvisorySource,
        AdvisoryUrgency;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/advisory_service.dart';
import 'package:sngnav_app/services/provider_coverage.dart';

/// A fake provider that RECORDS whether it was init'd / fetched, so a test
/// can assert a region-excluded provider is never contacted.
class _InstrumentedProvider implements AdvisoryProvider {
  _InstrumentedProvider({required this.src, this.advisories = const []});

  final AdvisorySource src;
  final List<Advisory> advisories;

  int initCount = 0;
  int fetchCount = 0;

  @override
  AdvisorySource get source => src;

  @override
  Future<void> init() async {
    initCount++;
  }

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    fetchCount++;
    return advisories;
  }
}

/// A fake provider that THROWS on fetch (models the NWS HTTP-400 for a
/// Japan point, or any transport failure) — used to prove per-provider
/// isolation survives region-gating.
class _ThrowingProvider implements AdvisoryProvider {
  _ThrowingProvider({required this.src});

  final AdvisorySource src;
  int fetchCount = 0;

  @override
  AdvisorySource get source => src;

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    fetchCount++;
    throw Exception('HTTP 400 — point outside coverage');
  }
}

Advisory _adv(AdvisorySource source, String evt) => Advisory(
      source: source,
      eventClass: evt,
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: '秋田県',
      effective: DateTime.utc(2026, 1, 15, 4),
      expires: DateTime.utc(2026, 1, 16, 4),
      headline: '',
      description: '',
    );

void main() {
  // HER point.
  const akitaLat = 39.7167;
  const akitaLon = 140.0983;
  // A representative US point (Grand Forks, North Dakota).
  const usLat = 47.9;
  const usLon = -97.0;

  group('AdvisoryService region-gating (the HER fix)', () {
    test(
        'Akita (JP) point → queries JMA, does NOT query NWS '
        '(no request sent to the US service)', () async {
      final nws = _InstrumentedProvider(src: AdvisorySource.nwsUnitedStates);
      final jma = _InstrumentedProvider(
        src: AdvisorySource.jmaJapan,
        advisories: [_adv(AdvisorySource.jmaJapan, '大雪警報')],
      );
      final svc = AdvisoryService(providers: [
        CoveredProvider(provider: nws, covers: nwsCoverage),
        CoveredProvider(provider: jma, covers: jmaCoverage),
      ]);
      await svc.init();

      final result =
          await svc.fetchAtPoint(latitude: akitaLat, longitude: akitaLon);

      // The load-bearing assertion: NWS fetch was NEVER called for HER point.
      expect(nws.fetchCount, 0,
          reason: 'NWS must not be queried for a Japan coordinate');
      // JMA WAS queried and its advisory reached the driver.
      expect(jma.fetchCount, 1);
      expect(result.advisories, hasLength(1));
      expect(result.advisories.single.source, AdvisorySource.jmaJapan);
      expect(result.advisories.single.eventClass, '大雪警報');
      // And crucially: NO provider error card (the old HTTP-400 is gone
      // because NWS was never contacted).
      expect(result.providerErrors, isEmpty);
    });

    test('a would-throw NWS provider still never fires for a JP point',
        () async {
      // Models the real defect: NWS returns HTTP 400 for a Japan point. With
      // gating it is not even called, so no error surfaces.
      final nws = _ThrowingProvider(src: AdvisorySource.nwsUnitedStates);
      final jma = _InstrumentedProvider(
        src: AdvisorySource.jmaJapan,
        advisories: [_adv(AdvisorySource.jmaJapan, '暴風雪警報')],
      );
      final svc = AdvisoryService(providers: [
        CoveredProvider(provider: nws, covers: nwsCoverage),
        CoveredProvider(provider: jma, covers: jmaCoverage),
      ]);
      await svc.init();

      final result =
          await svc.fetchAtPoint(latitude: akitaLat, longitude: akitaLon);

      expect(nws.fetchCount, 0);
      expect(result.providerErrors, isEmpty); // no HTTP-400 card
      expect(result.advisories.single.eventClass, '暴風雪警報');
    });

    test('US point → queries NWS, does NOT query JMA', () async {
      final nws = _InstrumentedProvider(
        src: AdvisorySource.nwsUnitedStates,
        advisories: [_adv(AdvisorySource.nwsUnitedStates, 'Winter Storm Warning')],
      );
      final jma = _InstrumentedProvider(src: AdvisorySource.jmaJapan);
      final svc = AdvisoryService(providers: [
        CoveredProvider(provider: nws, covers: nwsCoverage),
        CoveredProvider(provider: jma, covers: jmaCoverage),
      ]);
      await svc.init();

      final result =
          await svc.fetchAtPoint(latitude: usLat, longitude: usLon);

      expect(jma.fetchCount, 0,
          reason: 'JMA must not be queried for a US coordinate');
      expect(nws.fetchCount, 1);
      expect(result.advisories.single.source, AdvisorySource.nwsUnitedStates);
      expect(result.providerErrors, isEmpty);
    });

    test('point covered by NEITHER → no provider queried, empty result',
        () async {
      // Mid-Pacific: neither the US nor Japan box contains it.
      final nws = _InstrumentedProvider(src: AdvisorySource.nwsUnitedStates);
      final jma = _InstrumentedProvider(src: AdvisorySource.jmaJapan);
      final svc = AdvisoryService(providers: [
        CoveredProvider(provider: nws, covers: nwsCoverage),
        CoveredProvider(provider: jma, covers: jmaCoverage),
      ]);
      await svc.init();

      final result = await svc.fetchAtPoint(latitude: 0.0, longitude: -160.0);

      expect(nws.fetchCount, 0);
      expect(jma.fetchCount, 0);
      expect(result.advisories, isEmpty);
      expect(result.providerErrors, isEmpty);
    });

    test(
        'B04-2 end-to-end: an un-catalogued JAPANESE point queries NOBODY '
        'and cannot assert an all-clear', () async {
      // Tokyo. Inside the old hand-drawn all-Japan box, outside the six
      // prefectures `condition_aggregator_jma` actually catalogs.
      //
      // Before the fix this point was "covered": JMA was queried, returned
      // an empty list WITHOUT throwing, and the result
      // (`sourcesQueried: 1`, no errors) satisfied `canAssertNoAdvisory` —
      // so the card rendered the positive all-clear having sent no request.
      // This is the full chain, through the REAL AdvisoryService, not the
      // predicate alone.
      final nws = _InstrumentedProvider(src: AdvisorySource.nwsUnitedStates);
      final jma = _InstrumentedProvider(src: AdvisorySource.jmaJapan);
      final svc = AdvisoryService(providers: [
        CoveredProvider(provider: nws, covers: nwsCoverage),
        CoveredProvider(provider: jma, covers: jmaCoverage),
      ]);
      await svc.init();

      const tokyoLat = 35.68;
      const tokyoLon = 139.69;
      expect(svc.coversPoint(tokyoLat, tokyoLon), isFalse);

      final result =
          await svc.fetchAtPoint(latitude: tokyoLat, longitude: tokyoLon);

      expect(jma.fetchCount, 0,
          reason: 'the adapter has no data for Tokyo — asking it would only '
              'manufacture a silent empty answer');
      expect(nws.fetchCount, 0);
      expect(result.advisories, isEmpty);
      expect(result.providerErrors, isEmpty);
      // The load-bearing assertion: an empty list that CANNOT be read as calm.
      expect(result.canAssertNoAdvisory, isFalse,
          reason: 'nobody was asked, so nothing may be claimed');
      expect(result.isUnavailable, isTrue);
    });

    test(
        'B04-2 contrast: HER Akita point IS catalogued — JMA is queried and '
        'a clean answer still yields a real all-clear', () async {
      final nws = _InstrumentedProvider(src: AdvisorySource.nwsUnitedStates);
      final jma = _InstrumentedProvider(src: AdvisorySource.jmaJapan);
      final svc = AdvisoryService(providers: [
        CoveredProvider(provider: nws, covers: nwsCoverage),
        CoveredProvider(provider: jma, covers: jmaCoverage),
      ]);
      await svc.init();

      expect(svc.coversPoint(akitaLat, akitaLon), isTrue);
      final result =
          await svc.fetchAtPoint(latitude: akitaLat, longitude: akitaLon);

      expect(jma.fetchCount, 1, reason: 'HER prefecture is in the catalog');
      expect(nws.fetchCount, 0);
      // Asked and answered — she may honestly be told nothing is in force.
      expect(result.canAssertNoAdvisory, isTrue);
    });

    test('per-provider isolation survives gating: a covering provider that '
        'throws is surfaced via providerErrors, not swallowed', () async {
      // Two US-covering providers; one throws. At a US point both are queried
      // and the failure is isolated (the aggregator contract still holds).
      final okUs = _InstrumentedProvider(
        src: AdvisorySource.nwsUnitedStates,
        advisories: [_adv(AdvisorySource.nwsUnitedStates, 'Blizzard Warning')],
      );
      final badUs = _ThrowingProvider(src: AdvisorySource.other);
      final svc = AdvisoryService(providers: [
        CoveredProvider(provider: okUs, covers: nwsCoverage),
        CoveredProvider(provider: badUs, covers: nwsCoverage),
      ]);
      await svc.init();

      final result =
          await svc.fetchAtPoint(latitude: usLat, longitude: usLon);

      expect(badUs.fetchCount, 1); // it WAS covered, so it was queried
      expect(result.advisories, hasLength(1));
      expect(result.providerErrors, hasLength(1));
      expect(result.providerErrors.single.source, AdvisorySource.other);
    });

    test('fetchAtPoint before init throws StateError', () async {
      final svc = AdvisoryService(providers: [
        CoveredProvider(
          provider: _InstrumentedProvider(src: AdvisorySource.jmaJapan),
          covers: jmaCoverage,
        ),
      ]);
      expect(
        () => svc.fetchAtPoint(latitude: akitaLat, longitude: akitaLon),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('coverage predicates', () {
    test('nwsCoverage includes US regions, excludes Japan', () {
      expect(nwsCoverage(47.9, -97.0), isTrue); // North Dakota (CONUS)
      expect(nwsCoverage(40.7, -74.0), isTrue); // New York
      expect(nwsCoverage(64.8, -147.7), isTrue); // Fairbanks, Alaska
      expect(nwsCoverage(21.3, -157.8), isTrue); // Honolulu, Hawaii
      expect(nwsCoverage(akitaLat, akitaLon), isFalse); // HER Akita point
      expect(nwsCoverage(35.68, 139.69), isFalse); // Tokyo
    });

    test(
        'jmaCoverage covers the prefectures the adapter ACTUALLY catalogs, '
        'and disclaims the Japanese points it cannot answer for', () {
      // HER Akita point, and the rest of the snow-zone catalog.
      expect(jmaCoverage(akitaLat, akitaLon), isTrue); // Akita  (050000)
      expect(jmaCoverage(43.06, 141.35), isTrue); // Sapporo    (010000)
      expect(jmaCoverage(40.82, 140.74), isTrue); // Aomori     (020000)
      expect(jmaCoverage(39.70, 141.15), isTrue); // Morioka    (030000)
      expect(jmaCoverage(38.24, 140.36), isTrue); // Yamagata   (060000)
      expect(jmaCoverage(37.90, 139.02), isTrue); // Niigata    (150000)

      // B04-2 — the fabricated-clear seam. `condition_aggregator_jma` 0.3.1
      // ships a SIX-PREFECTURE bounding-box catalog and, for a point outside
      // it, returns an EMPTY advisory list WITHOUT throwing
      // (jma_advisory_provider.dart:169-175). Under region-gating no other
      // provider is queried for a Japanese point (the NWS boxes are disjoint
      // in longitude), so the adapter's own stated fallback — "the
      // aggregator's other providers cover points outside the catalog" — does
      // not hold here.
      //
      // A too-wide JMA box therefore does NOT cost "one wasted query near a
      // border" as the generous-box rationale assumes. It produces
      // `advisories: [], providerErrors: [], sourcesQueried: 1` →
      // `canAssertNoAdvisory == true` → the positive all-clear
      // 「この地点に有効な警報・注意報はありません。」 rendered to a driver in
      // unexpected snow WITHOUT A SINGLE REQUEST HAVING BEEN SENT.
      //
      // `canAssertNoAdvisory` cannot catch this: the provider lied by
      // silence — it counted as asked-and-answered while never asking.
      // The only honest coverage claim is the adapter's real catalog.
      expect(jmaCoverage(35.68, 139.69), isFalse); // Tokyo — not catalogued
      expect(jmaCoverage(35.18, 136.91), isFalse); // Nagoya — not catalogued
      expect(jmaCoverage(34.69, 135.50), isFalse); // Osaka  — not catalogued
      expect(jmaCoverage(26.2, 127.7), isFalse); // Naha   — not catalogued

      expect(jmaCoverage(47.9, -97.0), isFalse); // North Dakota
      expect(jmaCoverage(21.3, -157.8), isFalse); // Honolulu
    });

    test('the two coverages are disjoint (no point is claimed by both)', () {
      // Sample a coarse global grid; assert no point is covered by BOTH.
      for (var lat = -80.0; lat <= 80.0; lat += 5.0) {
        for (var lon = -179.0; lon <= 179.0; lon += 5.0) {
          expect(nwsCoverage(lat, lon) && jmaCoverage(lat, lon), isFalse,
              reason: 'point ($lat,$lon) claimed by both NWS and JMA');
        }
      }
    });
  });
}
