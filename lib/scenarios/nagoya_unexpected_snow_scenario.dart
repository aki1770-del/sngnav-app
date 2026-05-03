/// Slice 5e — first end-to-end demo scenario.
///
/// PHIL-001 scenario verbatim: *"A driver leaves Nagoya at 6:00 AM.
/// The forecast says clear skies. By 7:15 AM, she's on a mountain
/// pass and the sky turns white. Unexpected snow."*
///
/// This module composes the four data-fusion services shipped in
/// Slice 5a..5d into one offline-replayable scenario the integrator
/// can run from a test or a demo screen:
///
/// 1. At t=0 (Nagoya, 6:00 AM JST), the weather is clear.
///    `RoadSurfaceClassifier` classifies dry. The route forecast
///    along the OSRM polyline is hazard-free. No reroute. No alert.
/// 2. At t=75 minutes (mountain pass approach, 7:15 AM JST), the
///    weather flips to heavy snow with ice risk. The classifier
///    eventually flips to compactedSnow (after hysteresis settles).
///    The route forecast reports hazard-on-route. The advisor
///    recommends reroute IF the hazard ETA falls within the lookahead
///    window AND confidence threshold is met. The advisory service
///    surfaces any active NWS-class advisory at the point (in the
///    Nagoya scenario this is empty since NWS covers US territory;
///    the surface is wired symmetrically so the JMA adapter, when
///    shipped, drops in transparently).
///
/// Driver-facing loom (composite): "the driver leaves on a clear
/// morning, drives 75 minutes, the weather turns, and the app
/// surfaces — in time, with calm vocabulary appropriate to her
/// driver profile, not as panic UI — three things: surface state has
/// changed (compactedSnow), the route ahead is hazardous, and a
/// detour is available. The driver decides whether to detour."
///
/// Severity-not-profile invariant: this scenario produces severity-
/// class outputs (RoadSurfaceState, RerouteDecision, RouteForecast).
/// Per-profile rendering is the surface controller's job; this
/// module returns the substrate.
///
/// All ASIL-QM advisory class. Pure-Dart, offline replayable.
library;

import 'package:adaptive_reroute/adaptive_reroute.dart'
    show AdaptiveRerouteConfig, RerouteDecision;
import 'package:driving_conditions/driving_conditions.dart'
    show RoadSurfaceState;
import 'package:driving_weather/driving_weather.dart'
    show PrecipitationIntensity, PrecipitationType, WeatherCondition;
import 'package:latlong2/latlong.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart'
    show RouteForecast;

import '../route_fetch.dart' as local;
import '../services/reroute_advisor.dart';
import '../services/road_surface_classifier.dart';
import '../services/route_forecast_service.dart';

/// Geographic anchors for the demo scenario.
class NagoyaScenarioAnchors {
  /// Nagoya city centre (Sakae area). Departure point.
  static const LatLng departure = LatLng(35.1709, 136.8815);

  /// Mountain pass approach point (~75 minutes north on Highway 19,
  /// representative — the scenario does not depend on exact geometry).
  static const LatLng mountainPass = LatLng(35.6815, 137.5024);

  /// Departure timestamp (06:00 JST as PHIL-001 narrates).
  static DateTime departureTime() => DateTime.utc(2026, 2, 1, 21, 0)
      .add(const Duration(hours: 9))
      .subtract(const Duration(hours: 9)); // construct + leave UTC
}

/// One frame of the scenario — what the driver sees at this moment.
class ScenarioFrame {
  ScenarioFrame({
    required this.elapsed,
    required this.weather,
    required this.surfaceState,
    required this.forecast,
    required this.rerouteDecision,
  });

  /// Time since departure.
  final Duration elapsed;

  /// Weather observed at this frame.
  final WeatherCondition weather;

  /// Debounced surface state from `RoadSurfaceClassifier`.
  final RoadSurfaceState surfaceState;

  /// Per-segment route forecast at this frame.
  final RouteForecast forecast;

  /// The advisor's reroute decision at this frame.
  final RerouteDecision rerouteDecision;

  /// True when the advisor recommends rerouting (severity-class).
  bool get rerouteRecommended => rerouteDecision.shouldReroute;

  /// True when ANY segment of the forecast is hazardous.
  bool get anyHazard => forecast.hasAnyHazard;
}

/// Driver-replayable demo scenario: Nagoya departure → mountain-pass
/// unexpected snow.
///
/// Construct once, then call [framesAt] with elapsed time to advance.
/// The scenario uses a synthesized two-point OSRM-shape `RouteSuccess`
/// so the demo runs offline — no network call.
class NagoyaUnexpectedSnowScenario {
  NagoyaUnexpectedSnowScenario({
    AdaptiveRerouteConfig rerouteConfig = const AdaptiveRerouteConfig(
      hazardWindowSeconds: 1800.0, // 30 min look-ahead
      minConfidenceToAct: 0.4,
    ),
    double speedKmh = 60.0,
    double distanceSegmentKm = 5.0,
  })  : _classifier = RoadSurfaceClassifier(),
        _advisor = RerouteAdvisor(config: rerouteConfig),
        _forecastService = RouteForecastService(
          speedKmh: speedKmh,
          distanceSegmentKm: distanceSegmentKm,
        );

  final RoadSurfaceClassifier _classifier;
  final RerouteAdvisor _advisor;
  final RouteForecastService _forecastService;

  /// The synthetic OSRM route Nagoya → mountain pass.
  ///
  /// ~60 km direct distance; we set the OSRM-pipeline-shape distance
  /// to 75 km / 75 min to mirror the PHIL-001 75-minute travel time.
  local.RouteSuccess _osrmRoute(DateTime fetchedAt) => local.RouteSuccess(
        points: [
          NagoyaScenarioAnchors.departure,
          NagoyaScenarioAnchors.mountainPass,
        ],
        distanceMeters: 75000.0, // 75 km
        durationSeconds: 4500.0, // 75 minutes
        fetchedAt: fetchedAt,
      );

  /// Weather at [elapsed] minutes after departure.
  ///
  /// Phase model:
  /// - 0..60 min: clear skies (PHIL-001 narration "forecast says clear").
  /// - 60..75 min: transition (light snow, no ice risk).
  /// - 75+ min: heavy snow + ice risk (mountain pass white-out).
  WeatherCondition weatherAt(Duration elapsed, DateTime departedAt) {
    final ts = departedAt.add(elapsed);
    final mins = elapsed.inMinutes;
    if (mins < 60) {
      return WeatherCondition.clear(timestamp: ts);
    }
    if (mins < 75) {
      return WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 1.0,
        visibilityMeters: 5000.0,
        windSpeedKmh: 10.0,
        timestamp: ts,
      );
    }
    return WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.heavy,
      temperatureCelsius: -3.0,
      visibilityMeters: 400.0,
      windSpeedKmh: 25.0,
      iceRisk: true,
      timestamp: ts,
    );
  }

  /// Driver position (linear interpolation along the synthetic route)
  /// at [elapsed] minutes.
  LatLng positionAt(Duration elapsed) {
    final t = (elapsed.inSeconds / 4500.0).clamp(0.0, 1.0);
    final dep = NagoyaScenarioAnchors.departure;
    final dst = NagoyaScenarioAnchors.mountainPass;
    return LatLng(
      dep.latitude + (dst.latitude - dep.latitude) * t,
      dep.longitude + (dst.longitude - dep.longitude) * t,
    );
  }

  /// Compute one scenario frame at [elapsed] minutes after departure.
  Future<ScenarioFrame> frameAt(
    Duration elapsed, {
    DateTime? departedAt,
  }) async {
    final dep = departedAt ?? DateTime.utc(2026, 2, 1, 21, 0); // 06:00 JST
    final weather = weatherAt(elapsed, dep);
    final surface = _classifier.classify(weather);
    final route = _osrmRoute(dep);
    final forecast = await _forecastService.project(
      route: route,
      currentWeather: weather,
    );
    final decision = _advisor.advise(
      forecast: forecast,
      currentPosition: positionAt(elapsed),
    );
    return ScenarioFrame(
      elapsed: elapsed,
      weather: weather,
      surfaceState: surface,
      forecast: forecast,
      rerouteDecision: decision,
    );
  }

  /// Convenience: compute a sequence of frames at the supplied [marks].
  Future<List<ScenarioFrame>> framesAt(
    List<Duration> marks, {
    DateTime? departedAt,
  }) async {
    final frames = <ScenarioFrame>[];
    for (final m in marks) {
      frames.add(await frameAt(m, departedAt: departedAt));
    }
    return frames;
  }
}
