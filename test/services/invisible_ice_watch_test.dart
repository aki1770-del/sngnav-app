import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/services/invisible_ice_watch.dart';

JmaObservation _obs({
  double? temp,
  int? humidity,
  double? precip10m,
}) {
  return JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: temp,
    humidityPercent: humidity,
    windMetersPerSecond: 2.0,
    snowDepthCm: null,
    precipitation10mMm: precip10m,
    visibilityMeters: null,
    observedAtJstKey: '20260115063000',
    fetchedAt: DateTime(2026, 1, 15, 6, 30),
  );
}

void main() {
  group('evaluateInvisibleIceWatch', () {
    test('HER founding scenario (+2°C / 70% / measured no precip) → watch',
        () {
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.watch,
      );
    });

    test('missing temperature or precip → unknown; but ABOVE zero also '
        'needs humidity', () {
      // Temp and precip are required on every branch.
      expect(
        evaluateInvisibleIceWatch(_obs(temp: null, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.unknown,
      );
      expect(
        evaluateInvisibleIceWatch(
            _obs(temp: 2.0, humidity: 70, precip10m: null)),
        InvisibleIceWatchResult.unknown,
      );
      // ABOVE zero, no precip: the radiative-frost classifier needs humidity,
      // so a missing humidity abstains here (unchanged).
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: null, precip10m: 0)),
        InvisibleIceWatchResult.unknown,
      );
    });

    test('sub-zero ambient → subZeroFrozen (Chair calibration 2026-07-23; '
        'was outOfScope, was clear before that)', () {
      // The Chair ruled sub-zero SHOULD warn. It now returns a DISTINCT
      // verdict — not `watch` (that names the above-zero surprise), not
      // `clear`/`outOfScope` (an affirmative all-clear / non-coverage on a
      // very likely frozen surface, the fabricated-clear class of Andon
      // 2026-07-20T13:40Z).
      for (final obs in [
        _obs(temp: -5.0, humidity: 70, precip10m: 0),
        _obs(temp: 0.0, humidity: 90, precip10m: 0),
      ]) {
        final result = evaluateInvisibleIceWatch(obs);
        expect(result, InvisibleIceWatchResult.subZeroFrozen);
        expect(result, isNot(InvisibleIceWatchResult.clear));
        expect(result, isNot(InvisibleIceWatchResult.outOfScope));
        expect(result, isNot(InvisibleIceWatchResult.watch));
      }
    });

    test('sub-zero fires EVEN when humidity is missing — the Chuo leaf-drop '
        'case must not go silent', () {
      // Humidity is a drop-prone JMA leaf, and the sub-zero verdict does not
      // consult it. A sub-zero reading with humidity==null must STILL warn,
      // never abstain into silence (critic Finding, 2026-07-23).
      final result =
          evaluateInvisibleIceWatch(_obs(temp: -2.4, humidity: null, precip10m: 0));
      expect(result, InvisibleIceWatchResult.subZeroFrozen);
      expect(result, isNot(InvisibleIceWatchResult.unknown));
    });

    test('sub-zero fires EVEN when the PRECIP gauge dropped — a rimed gauge '
        'must not silence the Chuo morning', () {
      // The AMeDAS precip gauge rimes/ices over on exactly a clear sub-zero
      // morning (QC-flagged → null). The frozen road is present regardless, so
      // a dropped precip leaf must NOT return silent `unknown` at temp<=0.
      // (impl-review SHOULD, 2026-07-23 — the same leaf-drop-not-silence
      // discipline as humidity, which was left open for precip.)
      final result = evaluateInvisibleIceWatch(
          _obs(temp: -2.4, humidity: 70, precip10m: null));
      expect(result, InvisibleIceWatchResult.subZeroFrozen);
      expect(result, isNot(InvisibleIceWatchResult.unknown));
      // But ABOVE zero, a dropped precip leaf still abstains (the radiative
      // window needs no-precip confirmed).
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: 70, precip10m: null)),
        InvisibleIceWatchResult.unknown,
      );
    });

    test('exactly 0.0 °C fires the sub-zero warning (boundary is inclusive)',
        () {
      // The predicate is temp <= 0; 0.0 °C roads freeze, so it must warn — the
      // wording says 0°C以下 (at or below), matching the predicate, not 氷点下.
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 0.0, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.subZeroFrozen,
      );
    });

    test('a non-finite temperature abstains — never a fabricated all-clear',
        () {
      // NaN <= 0 is false; without the isFinite guard a NaN would fall through
      // to the above-zero classifier and return `clear` = 該当なし on garbage.
      expect(
        evaluateInvisibleIceWatch(
            _obs(temp: double.nan, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.unknown,
      );
    });

    test('measured precipitation → outOfScope (visible-hazard lanes own it)',
        () {
      // The comment this test has always carried — the visible-hazard lanes
      // OWN precipitation — is a statement of SCOPE, and `outOfScope` says
      // it faithfully where `clear` claimed a measurement never made.
      final result =
          evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: 70, precip10m: 0.5));
      expect(result, InvisibleIceWatchResult.outOfScope);
      expect(result, isNot(InvisibleIceWatchResult.clear));
    });

    test('warm or dry-air mornings → clear', () {
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 8.0, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.clear,
      );
      // +2°C at 90% RH: dew point is ABOVE 0 → not the radiative window
      // (matches the shared classifier's determination).
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: 90, precip10m: 0)),
        InvisibleIceWatchResult.clear,
      );
    });
  });
}
