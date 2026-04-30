/// Slice 4 — alert surface controller.
///
/// **Architectural invariant:** this controller accepts ONLY a
/// NavigationSafetyConfig. It does not import DriverProfile or
/// DriverState; it does not branch on which profile or which state
/// produced the config. Every driver — ageing rural, snow-zone
/// experienced, novice urban, professional, agricultural-forestry,
/// foreign-tourist snow-zone — receives the same alert surface for
/// the same severity-tier output. The differentiation lives upstream
/// in the thresholds carried by the config; downstream of
/// this controller every driver is treated identically.
///
/// The widget tree consumes severity-tier outputs from this controller
/// and renders them. The widget tree is forbidden from importing
/// DriverProfile or DriverState; the architectural grep test
/// `test/architectural/severity_not_profile_test.dart` enforces the
/// ban. The byte-identical-render widget tests in
/// `test/widgets/driver_state_chip_rail_test.dart` confirm the runtime
/// invariant: same severity output, same rendered bytes, regardless
/// of profile or state.
///
/// The controller is intentionally pure. It takes thresholds and
/// observed values; it returns severity-tier classifications. It does
/// not own state, does not own a config — the upstream service owns
/// the config and hands a fresh instance to this controller per
/// alert evaluation.
library;

import 'package:navigation_safety_core/navigation_safety_core.dart';

/// A surfaced alert: severity tier plus a short reason string for the
/// presentation layer. The reason intentionally does not name the
/// driver profile or state — it describes the observed condition only.
/// This keeps the widget tree from being able to read profile / state
/// information out of the surfaced alert string.
class SurfacedAlert {
  final AlertSeverity severity;
  final String reason;
  const SurfacedAlert({required this.severity, required this.reason});

  @override
  bool operator ==(Object other) =>
      other is SurfacedAlert &&
      other.severity == severity &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(severity, reason);

  @override
  String toString() => 'SurfacedAlert(severity: $severity, reason: $reason)';
}

/// Pure controller. The single input is a NavigationSafetyConfig
/// (already trait + state + environment-resolved upstream). Every
/// classification takes the config plus the live measurement and
/// returns a severity tier; null means "no alert at this tier".
class AlertSurfaceController {
  final NavigationSafetyConfig config;
  const AlertSurfaceController({required this.config});

  /// Classify a temperature observation. Returns the highest tier the
  /// observation crosses into per the config's three temperature
  /// thresholds, or null when the observation is above all of them.
  SurfacedAlert? classifyTemperature(double observedCelsius) {
    if (observedCelsius <= config.criticalTemperatureCelsius) {
      return SurfacedAlert(
        severity: AlertSeverity.critical,
        reason:
            'Surface temperature near or below freezing — black ice risk.',
      );
    }
    if (observedCelsius <= config.warningTemperatureCelsius) {
      return SurfacedAlert(
        severity: AlertSeverity.warning,
        reason: 'Surface temperature low — watch for ice patches.',
      );
    }
    if (observedCelsius <= config.infoTemperatureCelsius) {
      return SurfacedAlert(
        severity: AlertSeverity.info,
        reason: 'Surface temperature cool — surface may glaze tonight.',
      );
    }
    return null;
  }

  /// Classify a visibility observation. Returns the highest tier the
  /// observation crosses into per the config's three visibility
  /// thresholds, or null when visibility is above all of them.
  SurfacedAlert? classifyVisibility(int observedMeters) {
    if (observedMeters <= config.criticalVisibilityMeters) {
      return SurfacedAlert(
        severity: AlertSeverity.critical,
        reason: 'Visibility very low — slow significantly or pull over.',
      );
    }
    if (observedMeters <= config.warningVisibilityMeters) {
      return SurfacedAlert(
        severity: AlertSeverity.warning,
        reason: 'Visibility reduced — increase following distance.',
      );
    }
    if (observedMeters <= config.infoVisibilityMeters) {
      return SurfacedAlert(
        severity: AlertSeverity.info,
        reason: 'Visibility softening — headlight on, attention up.',
      );
    }
    return null;
  }
}
