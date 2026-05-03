import 'package:driving_conditions/driving_conditions.dart'
    show HysteresisFilter, RoadSurfaceState;
import 'package:driving_weather/driving_weather.dart'
    show PrecipitationIntensity, PrecipitationType, WeatherCondition;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/road_surface_classifier.dart';

void main() {
  group('RoadSurfaceClassifier', () {
    final ts = DateTime.utc(2026, 1, 1);

    test('first reading sets state immediately', () {
      final classifier = RoadSurfaceClassifier();
      final dryAir = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 5.0,
        visibilityMeters: 10000.0,
        windSpeedKmh: 0.0,
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
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 5.0,
        visibilityMeters: 10000.0,
        windSpeedKmh: 0.0,
        timestamp: ts,
      );
      final wet = WeatherCondition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 5.0,
        visibilityMeters: 5000.0,
        windSpeedKmh: 5.0,
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
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: -5.0,
        visibilityMeters: 800.0,
        windSpeedKmh: 20.0,
        timestamp: ts,
      );
      expect(classifier.classify(snow), RoadSurfaceState.compactedSnow);
    });

    test('reset clears state', () {
      final classifier = RoadSurfaceClassifier();
      final dry = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 5.0,
        visibilityMeters: 10000.0,
        windSpeedKmh: 0.0,
        timestamp: ts,
      );
      classifier.classify(dry);
      expect(classifier.current, RoadSurfaceState.dry);
      classifier.reset();
      expect(classifier.current, isNull);
    });
  });
}
