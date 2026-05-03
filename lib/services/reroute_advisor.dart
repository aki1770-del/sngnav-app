/// Slice 5a — reroute advisor wiring.
///
/// Thin wrapper around `RerouteEvaluator` (from `adaptive_reroute`
/// 0.1.0) that takes a `RouteForecast` and current position and returns
/// a typed `RerouteDecision`. The advisor decides; it never routes.
///
/// Driver-facing loom: "when the route ahead is becoming hazardous AND
/// the forecast confidence is sufficient, propose (not impose) a
/// detour. The driver always decides whether to follow it."
///
/// Severity-not-profile invariant: the advisor returns the typed
/// decision; per-profile UX (silent overlay vs voiced suggestion) is
/// the surface layer's job.
///
/// Pure Dart, no Flutter dependency.
library;

import 'package:adaptive_reroute/adaptive_reroute.dart'
    show AdaptiveRerouteConfig, RerouteDecision, RerouteEvaluator;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:route_condition_forecast/route_condition_forecast.dart'
    show RouteForecast;

/// Convenience facade over `RerouteEvaluator`.
class RerouteAdvisor {
  RerouteAdvisor({
    AdaptiveRerouteConfig config = const AdaptiveRerouteConfig(),
  }) : _evaluator = RerouteEvaluator(config: config);

  final RerouteEvaluator _evaluator;

  /// Evaluate [forecast] from [currentPosition] and return a decision.
  ///
  /// The decision is advisory only (ASIL-QM): the driver always drives.
  RerouteDecision advise({
    required RouteForecast forecast,
    required LatLng currentPosition,
  }) {
    return _evaluator.evaluate(forecast, currentPosition: currentPosition);
  }
}
