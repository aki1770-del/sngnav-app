// NOTE (2026-08-06, snow_rendering 0.3.0 recall): the no-precipitation
// conditions in this file previously carried NO humidity. That made them
// fabricated readings, and they classified as `dry` — which is precisely the
// recall defect ("no data -> dry -> gripFactor 1.0 -> Conditions normal").
// These tests are about the HYSTERESIS FILTER, not about absence, so each such
// condition now carries a measured `humidityRH` and the `dry` verdicts below
// are EARNED rather than defaulted. The absence behaviour is pinned separately
// and deliberately in `road_surface_absence_exposure_test.dart`.
//
// `classify` now returns `RoadSurfaceState?` — `null` means "cannot judge".

import 'package:driving_conditions/driving_conditions.dart'
    show HysteresisFilter, RoadSurfaceState;
import 'package:driving_weather/driving_weather.dart'
    show ObservationSource, PrecipitationIntensity, PrecipitationType, WeatherCondition;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/road_surface_classifier.dart';

void main() {
  group('RoadSurfaceClassifier', () {
    final ts = DateTime.utc(2026, 1, 1);

    test('first reading sets state immediately', () {
      final classifier = RoadSurfaceClassifier();
      final dryAir = WeatherCondition(
        source: ObservationSource.simulated,
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 5.0,
        visibilityMeters: 10000.0,
        windSpeedKmh: 0.0,
        humidityRH: 40.0,
        source: ObservationSource.measured,
        timestamp: ts,
      );
      expect(classifier.current, isNull);
      final state = classifier.classify(dryAir);
      expect(state, RoadSurfaceState.dry);
      expect(classifier.current, RoadSurfaceState.dry);
    });

    test('hysteresis debounces single oscillation', () {
      final classifier = RoadSurfaceClassifier(
        filter: HysteresisFilter<RoadSurfaceState>(
          windowSize: 3,
          threshold: 2,
        ),
      );
      final dry = WeatherCondition(
        source: ObservationSource.simulated,
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 5.0,
        visibilityMeters: 10000.0,
        windSpeedKmh: 0.0,
        humidityRH: 40.0,
        source: ObservationSource.measured,
        timestamp: ts,
      );
      final wet = WeatherCondition(
        source: ObservationSource.simulated,
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 5.0,
        visibilityMeters: 5000.0,
        windSpeedKmh: 5.0,
        humidityRH: 80.0,
        source: ObservationSource.measured,
        timestamp: ts,
      );

      classifier.classify(dry); // dry
      classifier.classify(dry); // dry
      // Single wet reading does not flip when threshold=2 within window=3
      // because dry has been seen 2 of last 3 (indices 0,1) and only the
      // tail reading is wet.
      final result = classifier.classify(wet);
      expect(result, RoadSurfaceState.dry);
    });

    test('classifies snow + cold + heavy as compactedSnow', () {
      final classifier = RoadSurfaceClassifier();
      final snow = WeatherCondition(
        source: ObservationSource.simulated,
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: -5.0,
        visibilityMeters: 800.0,
        windSpeedKmh: 20.0,
        source: ObservationSource.measured,
        timestamp: ts,
      );
      expect(classifier.classify(snow), RoadSurfaceState.compactedSnow);
    });

    test('reset clears state', () {
      final classifier = RoadSurfaceClassifier();
      final dry = WeatherCondition(
        source: ObservationSource.simulated,
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 5.0,
        visibilityMeters: 10000.0,
        windSpeedKmh: 0.0,
        humidityRH: 40.0,
        source: ObservationSource.measured,
        timestamp: ts,
      );
      classifier.classify(dry);
      expect(classifier.current, RoadSurfaceState.dry);
      classifier.reset();
      expect(classifier.current, isNull);
    });
  });
}
