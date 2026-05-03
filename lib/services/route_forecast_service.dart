/// Slice 5b — per-segment forecast for the active OSRM route.
///
/// Bridges the app's local `RouteSuccess` (from `lib/route_fetch.dart`,
/// constructed via the OSRM tap-A-tap-B fetch) into a
/// `route_condition_forecast` `RouteForecast`. Wires in fleet hazard
/// zones from `FleetHazardService` so `forecast.hasFleetHazard`
/// reports correctly.
///
/// Driver-facing loom: "before the driver leaves Nagoya, we project
/// the current weather along each segment of her route and tell her
/// where the trouble will be by the time she arrives. The forecast
/// confidence degrades with horizon — 1.0 at start, ~0.5 at 8 hours."
///
/// We do NOT call any `RoutingEngine` here — the existing OSRM tap-A
/// tap-B pipeline keeps producing `RouteSuccess`; we only synthesize
/// the engine-agnostic `routing_engine.RouteResult` shape because
/// `route_condition_forecast` consumes that interface. Routing
/// continues to live with the incumbent OSRM call.
library;

import 'package:fleet_hazard/fleet_hazard.dart' show HazardZone;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:route_condition_forecast/route_condition_forecast.dart'
    show
        CurrentConditionsForecastProvider,
        RouteConditionForecaster,
        RouteForecast,
        SegmentationStrategy;
import 'package:routing_engine/routing_engine.dart'
    show EngineInfo, RouteManeuver, RouteResult;
import 'package:driving_weather/driving_weather.dart' show WeatherCondition;

import '../route_fetch.dart' as local;

/// Builds a `RouteForecast` from the app's existing OSRM route success.
class RouteForecastService {
  RouteForecastService({
    this.distanceSegmentKm = 5.0,
    this.speedKmh = 60.0,
  });

  /// Length of each segment when subdividing the polyline (km).
  final double distanceSegmentKm;

  /// Assumed driving speed for ETA computation (km/h).
  final double speedKmh;

  /// Synthesizes a `routing_engine.RouteResult` from a local
  /// `RouteSuccess` so `RouteConditionForecaster` can consume it.
  ///
  /// We synthesize one synthetic maneuver per segment of length
  /// [distanceSegmentKm]; this preserves segment-by-distance forecast
  /// granularity even though the OSRM `geometries=geojson` payload we
  /// fetch does not include step-by-step turn instructions.
  RouteResult synthesizeRouteResult(local.RouteSuccess success) {
    final pts = success.points;
    if (pts.length < 2) {
      return RouteResult(
        shape: pts,
        maneuvers: const [],
        totalDistanceKm: success.distanceMeters / 1000.0,
        totalTimeSeconds: success.durationSeconds,
        summary: 'osrm-tap-a-tap-b',
        engineInfo: const EngineInfo(name: 'osrm-direct'),
      );
    }
    final totalKm = success.distanceMeters / 1000.0;
    // Single coarse maneuver covering the whole route — enough for the
    // forecaster's `byManeuver` strategy to produce one segment which
    // `byDistance` then subdivides into [distanceSegmentKm] chunks.
    final maneuvers = <RouteManeuver>[
      RouteManeuver(
        index: 0,
        instruction: 'Follow OSRM route',
        type: 'depart',
        lengthKm: totalKm,
        timeSeconds: success.durationSeconds,
        position: pts.first,
      ),
    ];
    return RouteResult(
      shape: pts,
      maneuvers: maneuvers,
      totalDistanceKm: totalKm,
      totalTimeSeconds: success.durationSeconds,
      summary: 'osrm-tap-a-tap-b',
      engineInfo: const EngineInfo(name: 'osrm-direct'),
    );
  }

  /// Project [currentWeather] along the OSRM [route] and produce a
  /// per-segment forecast. Optional [hazardZones] from the fleet feed
  /// are tested against each segment.
  Future<RouteForecast> project({
    required local.RouteSuccess route,
    required WeatherCondition currentWeather,
    List<HazardZone> hazardZones = const [],
  }) {
    final synthesized = synthesizeRouteResult(route);
    final forecaster = RouteConditionForecaster(
      forecastProvider: CurrentConditionsForecastProvider(currentWeather),
      hazardZones: hazardZones,
      speedKmh: speedKmh,
      segmentationStrategy: SegmentationStrategy.byDistance,
      distanceSegmentKm: distanceSegmentKm,
    );
    return forecaster.forecast(synthesized);
  }

  /// Convenience: ensure [origin] is the first point of [pts].
  ///
  /// Useful for tests that need to assert the synthesized route starts
  /// at a known origin.
  static bool startsAt(List<LatLng> pts, LatLng origin) =>
      pts.isNotEmpty &&
      pts.first.latitude == origin.latitude &&
      pts.first.longitude == origin.longitude;
}
