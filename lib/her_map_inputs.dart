/// What HER map is told about her position, decided in one place.
///
/// HER-trace: in unexpected snow, with GPS failing, the map is the surface her
/// eyes snap to. When the app does not know where she is, the map must say so
/// in words, and it must never go blank because the GPS stream died.
///
/// Before 2026-09-13 `main.dart` handed the map the raw last event (`_herFix`).
/// HIE rendered what that drew, from states the real position controller
/// produces (`outputs/hie/r2_her_position_surface_2026_09_13/`):
///
/// * `lost` was pixel-identical to dead reckoning: after 90 minutes the only
///   loud mark on the map spanned 500 m while the controller said ±10.8 km.
/// * A GPS stream error replaced `_herFix` with an unavailability, so the map
///   was byte-identical to having no position at all.
/// * With no trusted fix ever, the ring was drawn at a sample the controller
///   had refused.
///
/// The rule here is HIE's candidate mapping, landed. In dead-reckoning or
/// `lost` the map draws from the CONTROLLER's estimate, the only position the
/// loom still vouches for, and never from the raw event. Pure and synchronous,
/// so the mapping the app runs is the mapping the tests check. HIE's render
/// harness replicates it rather than calling it, so
/// `test/her_map_inputs_test.dart` pins this function to HIE's rule, scenario
/// by scenario.
library;

import 'package:latlong2/latlong.dart';
import 'package:localization_fallback/localization_fallback.dart';

import 'her_position.dart';

/// The position inputs [AkitaMap] draws from.
class HerMapInputs {
  const HerMapInputs({
    this.position,
    this.accuracyMeters,
    this.degraded = false,
    this.lost = false,
  });

  /// Nothing to draw: no position event has arrived in this sharing session.
  static const HerMapInputs none = HerMapInputs();

  /// Where the dot or ring goes, or `null` for no position mark.
  final LatLng? position;

  /// Radius of the accuracy circle. May be non-finite; [AkitaMap] never hands
  /// a non-finite radius to the painter and draws no circle in `lost`.
  final double? accuracyMeters;

  /// Dead-reckoning or lost: the hollow ring, not the solid dot.
  final bool degraded;

  /// Past the controller's honesty horizon: words on the map, no circle.
  final bool lost;
}

/// Decide what the map draws from the last position event [fix], the position
/// controller's current [estimate], and whether the position is the dev mock.
///
/// * [fix] `null` → nothing. No event has arrived in this sharing session: she
///   has not shared, has stopped, or the first event is still on its way. The
///   controller is not reset on stop, so its estimate may still be the last
///   drive's, and a feed she turned off makes no claim about where she is now.
/// * Mock → the mock point, never degraded or lost. The mock is a static dev
///   tool, not a live position claim (same rule as `_herPositionDegraded`).
/// * Estimate dead-reckoning or `lost` → the ESTIMATE's position and radius.
///   That keeps a ring on the map after a stream error, and puts it where the
///   controller last trusted rather than at a refused or stale sample. With no
///   trusted baseline (an unanchored guess, or no coordinates at all) there is
///   no ring, and in `lost` the map's words stand alone.
/// * Otherwise → the raw fix, as before.
HerMapInputs herMapInputs({
  required PositionFix? fix,
  required LocalizationEstimate? estimate,
  required bool isMock,
}) {
  if (fix == null) return HerMapInputs.none;

  final (LatLng? fixPosition, double? fixAccuracy) = switch (fix) {
    PositionAvailable(:final latitude, :final longitude, :final accuracyMeters) =>
      (LatLng(latitude, longitude), accuracyMeters),
    PositionUnavailable() => (null, null),
  };

  final mode = estimate?.mode;
  final unlocatable =
      mode == LocalizationMode.deadReckoning || mode == LocalizationMode.lost;
  if (isMock || estimate == null || !unlocatable) {
    return HerMapInputs(position: fixPosition, accuracyMeters: fixAccuracy);
  }

  // A ring marks a position the controller trusted, never a guess from a
  // sample it refused.
  final anchored =
      estimate.hasPosition && estimate.basis != EstimateBasis.unanchoredGuess;
  return HerMapInputs(
    position: anchored ? LatLng(estimate.latitude, estimate.longitude) : null,
    accuracyMeters: estimate.confidenceRadiusMeters,
    degraded: true,
    lost: mode == LocalizationMode.lost,
  );
}
