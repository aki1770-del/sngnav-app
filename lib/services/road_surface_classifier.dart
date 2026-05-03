/// Slice 5a — road surface classification from current weather.
///
/// Wraps `RoadSurfaceState.fromCondition` (re-exported by
/// `driving_conditions` 0.3.0 from `snow_rendering`) plus a
/// `HysteresisFilter<RoadSurfaceState>` so the surface state does not
/// oscillate at temperature / intensity boundaries.
///
/// Driver-facing loom: "the driver does not see the surface state flip
/// twice per second when the temperature crosses 0 °C — the hysteresis
/// filter holds the state for a debounce window before flipping."
///
/// Severity-not-profile invariant (Slice 4 anchor): the classifier
/// produces severity-class output (RoadSurfaceState + grip factor); the
/// downstream `AlertSurfaceController` decides per-profile rendering.
///
/// Pure Dart, no Flutter dependency in this file.
library;

import 'package:driving_conditions/driving_conditions.dart'
    show RoadSurfaceState, HysteresisFilter;
import 'package:driving_weather/driving_weather.dart' show WeatherCondition;

/// Classifies an incoming `WeatherCondition` into a debounced
/// `RoadSurfaceState`.
///
/// Construction notes:
/// - The hysteresis filter defaults to window 3, threshold 2 — a new
///   state must be observed in 2 of the last 3 readings before it
///   replaces the current state. Tuning is configurable.
/// - The first reading always sets the state (the filter has no prior
///   to debounce against).
class RoadSurfaceClassifier {
  RoadSurfaceClassifier({
    HysteresisFilter<RoadSurfaceState>? filter,
  }) : _filter = filter ?? HysteresisFilter<RoadSurfaceState>();

  final HysteresisFilter<RoadSurfaceState> _filter;

  /// The current debounced surface state. `null` until [classify] has
  /// been called at least once.
  RoadSurfaceState? get current => _filter.current;

  /// Classify [condition] and return the debounced state.
  RoadSurfaceState classify(WeatherCondition condition) {
    final raw = RoadSurfaceState.fromCondition(condition);
    return _filter.add(raw);
  }

  /// Reset the filter — useful when leaving a region or restarting a
  /// session.
  void reset() => _filter.reset();
}
