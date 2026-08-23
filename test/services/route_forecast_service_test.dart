import 'package:driving_weather/driving_weather.dart'
    show ObservationSource, PrecipitationIntensity, PrecipitationType, SafetyVerdict, WeatherCondition;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/route_fetch.dart' as local;
import 'package:sngnav_app/services/route_forecast_service.dart';

void main() {
  final origin = const LatLng(35.180, 136.910); // Nagoya area.
  final dest = const LatLng(35.450, 136.800);
  final ts = DateTime.utc(2026, 1, 1, 6, 0, 0);

  local.RouteSuccess osrmSuccess() => local.RouteSuccess(
        points: [origin, dest],
        distanceMeters: 30000.0,
        durationSeconds: 1800.0,
        fetchedAt: ts,
      );

  group('RouteForecastService', () {
    test('synthesizes route preserves origin + total distance', () {
      final svc = RouteForecastService();
      final synth = svc.synthesizeRouteResult(osrmSuccess());
      expect(synth.shape.first, origin);
      expect(synth.shape.last, dest);
      expect(synth.totalDistanceKm, closeTo(30.0, 1e-9));
      expect(synth.engineInfo.name, 'osrm-direct');
      expect(synth.maneuvers, isNotEmpty);
    });

    test('clear weather → no hazard along route', () async {
      final svc = RouteForecastService(distanceSegmentKm: 5.0);
      final forecast = await svc.project(
        route: osrmSuccess(),
        // A MEASURED clear road, stated field by field. `WeatherCondition.clear()`
        // was removed in driving_weather 0.5.0 precisely because an empty feed
        // returned it, so absence read as a clear road.
        currentWeather: WeatherCondition(
          precipType: PrecipitationType.none,
          intensity: PrecipitationIntensity.none,
          temperatureCelsius: 5.0,
          visibilityMeters: 10000.0,
          windSpeedKmh: 0.0,
          iceRisk: false,
          source: ObservationSource.measured,
          timestamp: ts,
        ),
      );
      expect(forecast.hazard, SafetyVerdict.notHazardous);
      expect(forecast.segments, isNotEmpty);
      // 30 km route at 5 km / segment yields 6 segments.
      expect(forecast.segments.length, 6);
    });

    test('snow + ice → every segment hazardous', () async {
      final svc = RouteForecastService(distanceSegmentKm: 5.0);
      final hazardWeather = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: -3.0,
        visibilityMeters: 400.0,
        windSpeedKmh: 25.0,
        iceRisk: true,
        source: ObservationSource.measured,
        timestamp: ts,
      );
      final forecast = await svc.project(
        route: osrmSuccess(),
        currentWeather: hazardWeather,
      );
      expect(forecast.hazard, SafetyVerdict.hazardous);
      expect(forecast.firstHazardEtaSeconds, isNotNull);
      // Confidence at t=0 is 1.0, degrades with ETA.
      expect(forecast.minimumConfidence, lessThanOrEqualTo(1.0));
      expect(forecast.minimumConfidence, greaterThan(0.5));
    });
  });
}
