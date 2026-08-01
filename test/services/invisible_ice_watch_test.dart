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

    // STAGE-1 ANNOTATION (2026-08-01) — this test is CHARACTERISATION, and its
    // second assertion CURRENTLY DEFENDS A RECORDED DEFECT. Read before editing.
    //
    // The two cells are NOT the same kind of `clear`, and the old test name
    // ('warm or dry-air mornings') described neither of them accurately:
    //
    //  * 8.0 °C / 70 % RH — ambient is ABOVE the classifier's 3.0 °C ceiling
    //    (navigation_safety_calibration humidity_dependent_temperature.dart:159),
    //    which is a DETERMINATION: cal:88-90 gives it an affirmative reason and
    //    cal:135-153's list of every REJECTED input class does not contain it.
    //    A bare 該当なし here is EARNED. This assertion is load-bearing — it is
    //    the proof that a future countermeasure did not re-import
    //    over-abstention. KEEP IT UNCHANGED.
    //
    //  * 2.0 °C / 90 % RH — measured estimate +0.5320 °C. The classifier
    //    DECLINED here: this is the documented non-coverage band that cal:112-115
    //    names verbatim as "a genuine hazard this function does not cover".
    //    The comment below is RIGHT about the model and wrong only about the
    //    model's ENTITLEMENT to have that `false` rendered to a driver as an
    //    affirmative all-clear. It is offender #8 of
    //    test/services/ice_watch_scope_envelope_test.dart GUARD 1, which is RED.
    //    Stage 2 rewrites this assertion to `outsideModelEnvelope`.
    //    DO NOT silently flip it, and do not "fix" the guard to match it.
    test('above the ceiling → clear (EARNED); inside the band with the model '
        'declining → outsideModelEnvelope, never a bare 該当なし', () {
      // 8.0 °C is ABOVE radiativeFrostAmbientCeilingCelsius (3.0), where the
      // classifier makes a DETERMINATION rather than declining: cal:88-90 gives
      // the ceiling an affirmative reason and cal:135-153's list of every
      // REJECTED input class does not contain it. A bare 該当なし here is earned.
      //
      // THIS ASSERTION IS LOAD-BEARING — do not "modernise" it to match its
      // sibling below. It is the proof that Stage 2 did not re-import the
      // over-abstention the first draft of the guard would have caused (that
      // predicate forbade 該当なし up to +35 °C, across ~66% of all above-zero
      // all-clears). If this ever flips to outsideModelEnvelope, the coverage
      // predicate has become unbounded again.
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 8.0, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.clear,
      );

      // EARNED-CLEAR PIN, added 2026-08-01 (review MUST-9, CONFIRMED).
      // 8.0 C alone is NOT a sufficient guard against band widening: measured,
      // widening the band to 0.5 / 5.0 / 35.0 C left this whole file green
      // because 8.0 C is far from every boundary that moves first. 3.2 C is one
      // step OUTSIDE the one-step band, in air dry enough that the model's
      // estimate is still well below freezing — the first cell an over-broad
      // band swallows. If this ever returns outsideModelEnvelope, the app has
      // started refusing to judge roads it can judge.
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 3.2, humidity: 25, precip10m: 0)),
        InvisibleIceWatchResult.clear,
      );

      // REWRITTEN 2026-08-01 (Stage 2). This previously asserted `clear`, with
      // the recorded reasoning "+2°C at 90% RH: dew point is ABOVE 0 → not the
      // radiative window (matches the shared classifier's determination)."
      //
      // That comment was RIGHT about the model and wrong about the model's
      // ENTITLEMENT. Measured estimate here is +0.5320 °C — above the 0 °C
      // surface threshold and under the 3.0 °C ambient ceiling, i.e. exactly
      // the band cal:112-115 states verbatim the model "does not cover":
      // "near-zero SATURATED FREEZING FOG above ~ +1 °C (dew point >= 0) is
      // therefore NOT detected by this model — a genuine hazard this function
      // does not cover." The classifier DECLINED; it did not find the road
      // clear. Rendering that decline as 該当なし was the fabricated-clear
      // failure class, and CI defended it until this rewrite.
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: 90, precip10m: 0)),
        InvisibleIceWatchResult.outsideModelEnvelope,
      );
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: 90, precip10m: 0)),
        isNot(InvisibleIceWatchResult.clear),
      );
    });
  });
}
