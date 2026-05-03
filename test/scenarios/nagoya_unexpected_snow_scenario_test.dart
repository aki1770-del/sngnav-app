import 'package:driving_conditions/driving_conditions.dart'
    show RoadSurfaceState;
import 'package:driving_weather/driving_weather.dart'
    show PrecipitationIntensity, PrecipitationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/scenarios/nagoya_unexpected_snow_scenario.dart';

void main() {
  group('NagoyaUnexpectedSnowScenario — PHIL-001 verbatim narration', () {
    test('at t=0 (06:00 JST) sky is clear, no hazard, no reroute', () async {
      final scenario = NagoyaUnexpectedSnowScenario();
      final frame = await scenario.frameAt(Duration.zero);
      expect(frame.weather.precipType, PrecipitationType.none);
      expect(frame.weather.intensity, PrecipitationIntensity.none);
      expect(frame.surfaceState, RoadSurfaceState.dry);
      expect(frame.anyHazard, isFalse);
      expect(frame.rerouteRecommended, isFalse);
    });

    test('at t=30 min, still clear skies (forecast unchanged)', () async {
      final scenario = NagoyaUnexpectedSnowScenario();
      final frame = await scenario.frameAt(const Duration(minutes: 30));
      expect(frame.weather.precipType, PrecipitationType.none);
      expect(frame.anyHazard, isFalse);
      expect(frame.rerouteRecommended, isFalse);
    });

    test('at t=75 min (mountain pass), heavy snow + ice → hazard fires',
        () async {
      final scenario = NagoyaUnexpectedSnowScenario();
      // Drive scenario through clear → light → heavy so hysteresis
      // filter on the surface classifier sees the progression.
      final frames = await scenario.framesAt(<Duration>[
        Duration.zero,
        const Duration(minutes: 30),
        const Duration(minutes: 60),
        const Duration(minutes: 70),
        const Duration(minutes: 75),
        const Duration(minutes: 80),
        const Duration(minutes: 85),
      ]);
      final tail = frames.last;
      expect(tail.weather.precipType, PrecipitationType.snow);
      expect(tail.weather.intensity, PrecipitationIntensity.heavy);
      expect(tail.weather.iceRisk, isTrue);
      // After the hysteresis filter has seen consistent heavy-snow
      // readings the classified surface state is hazardous (blackIce
      // due to iceRisk=true; or compactedSnow if iceRisk degrades to
      // false). Either is severity-class hazardous.
      expect(
        tail.surfaceState,
        anyOf(
          RoadSurfaceState.blackIce,
          RoadSurfaceState.compactedSnow,
          RoadSurfaceState.slush,
        ),
      );
      expect(tail.anyHazard, isTrue);
    });

    test('reroute recommended when hazard within window + confidence',
        () async {
      final scenario = NagoyaUnexpectedSnowScenario();
      // At minute 75 the forecast covers the route ahead (≤ 30 min
      // window per default config). Confidence at near-zero ETA is
      // 1.0 so the threshold (0.4) is met.
      final frame = await scenario.frameAt(const Duration(minutes: 75));
      expect(frame.anyHazard, isTrue);
      expect(frame.rerouteRecommended, isTrue);
      expect(frame.rerouteDecision.confidence, greaterThan(0.4));
    });

    test('positionAt interpolates from Nagoya to mountain pass', () {
      final scenario = NagoyaUnexpectedSnowScenario();
      final start = scenario.positionAt(Duration.zero);
      final mid = scenario.positionAt(const Duration(minutes: 37, seconds: 30));
      final end = scenario.positionAt(const Duration(minutes: 75));
      // Departure latitude is ~35.17; mountain pass is ~35.68. Linear
      // interpolation puts the midpoint near 35.42.
      expect(start.latitude, closeTo(35.1709, 1e-6));
      expect(end.latitude, closeTo(35.6815, 1e-6));
      expect(mid.latitude, closeTo(35.4262, 1e-3));
    });
  });
}
