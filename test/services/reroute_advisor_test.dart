import 'package:adaptive_reroute/adaptive_reroute.dart' show AdaptiveRerouteConfig;
import 'package:driving_weather/driving_weather.dart'
    show PrecipitationIntensity, PrecipitationType, WeatherCondition;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart'
    show
        RouteForecast,
        RouteSegment,
        SegmentConditionForecast;
import 'package:routing_engine/routing_engine.dart' show RouteResult, EngineInfo;
import 'package:sngnav_app/services/reroute_advisor.dart';

/// Helpers building synthetic `RouteForecast` instances WITHOUT
/// invoking `routing_engine` over the network. We construct
/// `RouteResult` directly with synthesized maneuvers + segments to
/// keep this test pure and offline.
void main() {
  final origin = const LatLng(35.180, 136.910); // Nagoya area.
  final dest = const LatLng(35.450, 136.800);
  final ts = DateTime.utc(2026, 1, 1, 6, 0, 0);

  RouteResult buildRoute() => RouteResult(
        shape: <LatLng>[origin, dest],
        maneuvers: const [],
        totalDistanceKm: 30.0,
        totalTimeSeconds: 1800.0,
        summary: 'synthetic',
        engineInfo: const EngineInfo(name: 'mock'),
      );

  RouteForecast forecastOf({
    required bool hazardous,
    required double confidence,
    required double etaSeconds,
  }) {
    final segment = RouteSegment(
      index: 0,
      start: origin,
      end: dest,
      distanceKm: 30.0,
    );
    final cond = WeatherCondition(
      precipType: hazardous ? PrecipitationType.snow : PrecipitationType.none,
      intensity: hazardous
          ? PrecipitationIntensity.heavy
          : PrecipitationIntensity.none,
      temperatureCelsius: hazardous ? -3.0 : 5.0,
      visibilityMeters: hazardous ? 400.0 : 10000.0,
      windSpeedKmh: hazardous ? 25.0 : 0.0,
      iceRisk: hazardous,
      timestamp: ts,
    );
    return RouteForecast(
      route: buildRoute(),
      segments: [
        SegmentConditionForecast(
          segment: segment,
          condition: cond,
          hazardZones: const [],
          etaSeconds: etaSeconds,
          confidence: confidence,
        ),
      ],
      generatedAt: ts,
    );
  }

  group('RerouteAdvisor', () {
    test('clear forecast → shouldReroute=false', () {
      final advisor = RerouteAdvisor();
      final decision = advisor.advise(
        forecast: forecastOf(
          hazardous: false,
          confidence: 0.9,
          etaSeconds: 600.0,
        ),
        currentPosition: origin,
      );
      expect(decision.shouldReroute, isFalse);
      expect(decision.reason, contains('clear'));
    });

    test('hazardous + high confidence + within window → recommends reroute',
        () {
      final advisor = RerouteAdvisor();
      final decision = advisor.advise(
        forecast: forecastOf(
          hazardous: true,
          confidence: 0.85,
          etaSeconds: 600.0, // 10 min — well within default 30 min window.
        ),
        currentPosition: origin,
      );
      expect(decision.shouldReroute, isTrue);
      expect(decision.confidence, closeTo(0.85, 1e-9));
    });

    test('hazardous but low confidence → flags but does not reroute', () {
      final advisor = RerouteAdvisor(
        config: const AdaptiveRerouteConfig(minConfidenceToAct: 0.5),
      );
      final decision = advisor.advise(
        forecast: forecastOf(
          hazardous: true,
          confidence: 0.3,
          etaSeconds: 600.0,
        ),
        currentPosition: origin,
      );
      expect(decision.shouldReroute, isFalse);
      expect(decision.reason, contains('confidence'));
    });
  });
}
