// Exposure test for the snow_rendering 0.3.0 SAFETY RECALL, at the app's own
// classifier seam.
//
// The recall, in the package's own words (snow_rendering 0.3.0 CHANGELOG):
//
//   "Up to and including 0.2.7, this package told drivers 'Conditions normal'
//    about roads it had no data for."
//        no data -> RoadSurfaceState.dry -> gripFactor 1.0 (MAXIMUM GRIP)
//                -> RecommendedResponse.proceed -> "Conditions normal"
//
// This app is pinned `snow_rendering: ^0.2.0` (= >=0.2.0 <0.3.0) and resolves
// 0.2.9 — BELOW its own safety package's recall — and cannot take the recall
// today: three PUBLISHED siblings cap it (measured 2026-08-06 against the live
// pub.dev API; see pubspec.yaml for the exact caps). So the fix cannot come
// from the type system. It has to be enforced HERE, at our call site — which
// is what snow_rendering 0.2.9's own dartdoc instructs, verbatim:
//
//   "Never call this with fields you did not measure; gate absence at your
//    call site and tell your user 'unknown'."
//
// That is the contract this file pins. Every assertion is written to compile
// against BOTH the 0.2.x non-nullable return and the 0.3.x nullable one, so it
// keeps its teeth across the migration instead of being rewritten by it.
//
// The invariant under test is NOT "always warn". A fabricated alarm is worse
// than none — it teaches HER to ignore the app. The invariant is narrower and
// strictly honest:
//
//   an ABSENCE of data must never be rendered as a BENIGN DETERMINATION.
//
// `null` / "cannot judge" is the correct answer. It is not an alarm.

import 'package:driving_conditions/driving_conditions.dart'
    show HysteresisFilter, RoadSurfaceState;
import 'package:driving_weather/driving_weather.dart'
    show PrecipitationIntensity, PrecipitationType, WeatherCondition;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/scenarios/nagoya_unexpected_snow_scenario.dart';
import 'package:sngnav_app/services/road_surface_classifier.dart';

/// The states that tell HER the road is FINE. If an absent-data reading lands
/// on any of these, the app has fabricated an all-clear.
const benign = <RoadSurfaceState>{RoadSurfaceState.dry};

final _ts = DateTime.utc(2026, 2, 1, 6);

/// A no-precipitation reading with NO humidity — the radiative-frost check,
/// which is the only hazard discriminator on this branch above -3 C, cannot
/// run. Whatever comes back is not a determination.
WeatherCondition noHumidity(double tempC) => WeatherCondition(
      precipType: PrecipitationType.none,
      intensity: PrecipitationIntensity.none,
      temperatureCelsius: tempC,
      visibilityMeters: 10000.0,
      windSpeedKmh: 0.0,
      timestamp: _ts,
      // humidityRH deliberately omitted -> null.
    );

void main() {
  group('absence is never a benign surface (snow_rendering 0.3.0 recall)', () {
    test(
      'WeatherCondition.clear() — the recall\'s NAMED fabrication vector — '
      'must not classify as dry',
      () {
        // driving_weather 0.4.5 weather_condition.dart:90-97 hardcodes
        // temperatureCelsius = 5.0, visibilityMeters = 10000, windSpeedKmh = 0,
        // iceRisk = false, humidityRH = null. Not one of those is a
        // measurement. driving_weather 0.5.0 REMOVED this constructor for
        // exactly that reason.
        final classifier = RoadSurfaceClassifier();
        final fabricated = WeatherCondition.clear(timestamp: _ts);

        expect(
          fabricated.humidityRH,
          isNull,
          reason: 'precondition: .clear() reports no humidity',
        );
        expect(
          classifier.classify(fabricated),
          isNot(isIn(benign)),
          reason: 'a condition in which NOTHING was measured was rendered as '
              'a benign road — this is the recall defect verbatim',
        );
      },
    );

    test('absent humidity inside the radiative-frost band is not dry', () {
      // At/below the +3.0 C ceiling humidity is load-bearing: without it the
      // frost check is REJECTED input, never a finding of "no frost".
      for (final t in <double>[0.1, 1.0, 2.0, 3.0]) {
        final classifier = RoadSurfaceClassifier();
        expect(
          classifier.classify(noHumidity(t)),
          isNot(isIn(benign)),
          reason: 'at $t C with no humidity the frost check DECLINED; '
              'a decline is not an all-clear',
        );
      }
    });

    test('a sub-zero road with no humidity is not dry', () {
      // snow_rendering 0.2.9 returns `dry` for -3 < temp <= 0 on the
      // no-precipitation branch. The app's own invisible-ice watch treats
      // temp <= 0 as frozen UNCONDITIONALLY (invisible_ice_watch.dart:320).
      // Full grip on a possibly-frozen road is the worst cell in the table.
      for (final t in <double>[-0.1, -1.0, -2.9]) {
        final classifier = RoadSurfaceClassifier();
        expect(
          classifier.classify(noHumidity(t)),
          isNot(isIn(benign)),
          reason: '$t C is at or below freezing; maximum grip is not honest',
        );
      }
    });

    test('the hysteresis filter never debounces TOWARD a fabricated state', () {
      // The filter's job is to stop oscillation between real determinations.
      // If abstentions are fed into it, it will happily settle on the
      // fabricated value and then report it with the authority of a
      // debounced reading. Three absent readings must not manufacture a
      // surface state.
      final classifier = RoadSurfaceClassifier(
        filter: HysteresisFilter<RoadSurfaceState>(windowSize: 3, threshold: 2),
      );

      classifier.classify(noHumidity(1.0));
      classifier.classify(noHumidity(1.0));
      classifier.classify(noHumidity(1.0));

      expect(
        classifier.current,
        isNot(isIn(benign)),
        reason: 'the debounced state was fabricated out of three abstentions',
      );
    });

    test('an abstention does not erase a hazard already determined', () {
      // Caution-add-only, in the other direction: honesty about absence must
      // not become a channel for SUPPRESSING a real hazard. A dropped sensor
      // reading after a blackIce determination must not read as "recovered".
      final classifier = RoadSurfaceClassifier();
      final icy = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: -8.0,
        visibilityMeters: 10000.0,
        windSpeedKmh: 0.0,
        timestamp: _ts,
      );

      expect(classifier.classify(icy), RoadSurfaceState.blackIce);
      classifier.classify(noHumidity(1.0)); // sensor drops out
      expect(
        classifier.current,
        isNot(isIn(benign)),
        reason: 'an absent reading turned a known-icy road benign',
      );
    });
  });

  group('positive determinations still pass through (no cry-wolf, no loss)', () {
    test('measured hazards are unchanged by the absence guard', () {
      final classifier = RoadSurfaceClassifier();

      // Explicit ice risk — positive evidence, fires whatever else is absent.
      expect(
        classifier.classify(WeatherCondition(
          precipType: PrecipitationType.none,
          intensity: PrecipitationIntensity.none,
          temperatureCelsius: 2.0,
          visibilityMeters: 10000.0,
          windSpeedKmh: 0.0,
          iceRisk: true,
          timestamp: _ts,
        )),
        RoadSurfaceState.blackIce,
      );

      // Heavy snow, well below freezing.
      final snow = RoadSurfaceClassifier();
      expect(
        snow.classify(WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -5.0,
          visibilityMeters: 800.0,
          windSpeedKmh: 20.0,
          timestamp: _ts,
        )),
        RoadSurfaceState.compactedSnow,
      );
    });

    test('a fully MEASURED warm dry road is still dry', () {
      // The guard must not turn every warm road into "unknown" — that is the
      // cry-wolf inverse and a defect of its own. Humidity present, well above
      // the frost ceiling, no precipitation: `dry` here is EARNED.
      final classifier = RoadSurfaceClassifier();
      expect(
        classifier.classify(WeatherCondition(
          precipType: PrecipitationType.none,
          intensity: PrecipitationIntensity.none,
          temperatureCelsius: 18.0,
          visibilityMeters: 10000.0,
          windSpeedKmh: 3.0,
          humidityRH: 40.0,
          timestamp: _ts,
        )),
        RoadSurfaceState.dry,
      );
    });
  });

  group('the scenario path does not narrate a fabricated all-clear', () {
    test('t=0 clear-sky frame is driven by MEASURED weather', () async {
      // The PHIL-001 narration is "the forecast said clear". The scenario may
      // model that belief — but it must not manufacture a MEASUREMENT to do
      // it. This is the only lib/ construction site of RoadSurfaceClassifier.
      //
      // The invariant is NOT "the demo must never say dry". A clear morning
      // IS dry, and asserting otherwise would be the manufactured alarm this
      // file exists to avoid. The invariant is that the benign verdict must be
      // EARNED from fields that were actually reported — so this pins the
      // input, which is where the recall defect entered.
      final scenario = NagoyaUnexpectedSnowScenario();
      final frame = await scenario.frameAt(Duration.zero);

      expect(
        frame.weather.humidityRH,
        isNotNull,
        reason: 'the demo fed a fabricated condition (no humidity) to the '
            'classifier — the recall vector, WeatherCondition.clear()',
      );
      expect(
        frame.surfaceState,
        isNotNull,
        reason: 'a frame built from measured fields should yield a real '
            'determination, not an abstention',
      );
    });
  });
}
