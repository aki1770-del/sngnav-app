/// What the map is told about the driver's position, decided in one place.
///
/// Why: in unexpected snow, with GPS failing, the map is the surface the
/// driver's eyes snap to. When the app does not know where she is, the map must say so
/// in words, and it must never go blank because the GPS stream died.
///
/// Before 2026-09-13 `main.dart` handed the map the raw last event (`_herFix`).
/// A render review drew what that showed, from states the real position
/// controller produces:
///
/// * `lost` was pixel-identical to dead reckoning: after 90 minutes the only
///   loud mark on the map spanned 500 m while the controller said ±10.8 km.
/// * A GPS stream error replaced `_herFix` with an unavailability, so the map
///   was byte-identical to having no position at all.
/// * With no trusted fix ever, the ring was drawn at a sample the controller
///   had refused.
///
/// The rule here is the mapping that review proposed, landed. In dead-reckoning or
/// `lost` the map draws from the CONTROLLER's estimate, the only position the
/// loom still vouches for, and never from the raw event. Pure and synchronous,
/// so the mapping the app runs is the mapping the tests check. The review's
/// render harness replicates it rather than calling it, so
/// `test/her_map_inputs_test.dart` pins this function to that rule, scenario
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
    this.refused = false,
    this.noPositionYet = false,
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

  /// Past the controller's honesty horizon, or degraded from an anchor no
  /// event of this session set: words on the map, no circle.
  final bool lost;

  /// The last event says location is off for this app: permission denied,
  /// now or for good ([isLocationRefusal], read from the typed cause only).
  /// The map then says 位置情報オフ / "No location access", not 現在地不明, and
  /// draws no mark of her, whatever [lost] is (decided 2026-09-13). `_PositionWords`
  /// in akita_map.dart is the one place that decides the words.
  ///
  /// Corrected 2026-09-14: this comment said the flag "changes nothing" on the
  /// map. That was true when it was written and stopped being true when the
  /// refusal got its own words.
  final bool refused;

  /// She is sharing, the position stream subscribed, and no position event of
  /// any kind has arrived within `kFirstPositionWait` (60 s) of the
  /// subscription. Set together with [lost], so the map says 現在地不明 with
  /// no mark; the map also announces the words once to a screen reader, as a
  /// live region (decided 2026-09-14).
  final bool noPositionYet;
}

/// Whether the position [fix] that the drive brain has just taken became the
/// controller's trusted anchor, in the estimate it emitted for it.
///
/// This, and not "a fix arrived", is what makes an anchor this session's. The
/// controller is not reset when she stops sharing, and it refuses a fix no
/// newer than its anchor: it degrades from the anchor it already holds, which
/// may be the previous drive's. Only the trusted path of the controller emits
/// [EstimateBasis.trustedGpsFix], so that basis on the estimate for this very
/// event means the anchor is this event. A trusted fix too imprecise to be
/// confident (`lost` on arrival) is still adopted as the anchor, and counts.
/// The dev mock never counts: it was never measured.
bool anchorsThisSession({
  required PositionFix fix,
  required LocalizationEstimate? estimate,
  required bool isMock,
}) =>
    !isMock &&
    fix is PositionAvailable &&
    estimate != null &&
    estimate.basis == EstimateBasis.trustedGpsFix;

/// Decide what the map draws from the last position event [fix], the position
/// controller's current [estimate], whether the position is the dev mock, and
/// whether the controller's anchor was set in this sharing session.
///
/// * [fix] `null` and [noPositionYet] → the words 現在地不明 and no ring. She
///   is sharing, the position stream subscribed after the permission answer,
///   and no event has arrived for 60 s since (`kFirstPositionWait`, decided
///   2026-09-14). Before this, a map with no words read the same as a driver
///   who never shared (measured 2026-09-13: 10 minutes, 0.000% different).
/// * [fix] `null` → nothing. No event has arrived in this sharing session: she
///   has not shared, has stopped, or the first event is still on its way. The
///   controller is not reset on stop, so its estimate may still be the last
///   drive's, and a feed she turned off makes no claim about where she is now.
/// * Mock → the mock point, never degraded or lost. The mock is a static dev
///   tool, not a live position claim (same rule as `_herPositionDegraded`).
/// * An unavailability that is not a refusal, with [anchoredThisSession] false
///   → the words 現在地不明 and no ring, whatever [estimate] is, even null.
/// * [notGivenToDriveBrain], with [anchoredThisSession] false → the words
///   現在地不明 and no mark, whatever [estimate] is: a position the drive brain
///   was not given, because it would not have been a trusted fix (a sample
///   the controller would refuse, or one no newer than its anchor).
/// * Estimate dead-reckoning or `lost`, and [anchoredThisSession] false → no
///   ring and the words 現在地不明. The controller is degrading from an anchor
///   no event of this session set (the previous drive, or the dev mock), and
///   that makes no claim about where she is now. Measured 2026-09-13: on a
///   re-share with location services off, the map drew the previous drive's
///   ring, 20 hours old, pixel-identical to a 3-minute loss.
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
  required bool anchoredThisSession,
  bool noPositionYet = false,
  bool notGivenToDriveBrain = false,
}) {
  if (fix == null) {
    return noPositionYet
        ? const HerMapInputs(degraded: true, lost: true, noPositionYet: true)
        : HerMapInputs.none;
  }

  final (LatLng? fixPosition, double? fixAccuracy) = switch (fix) {
    PositionAvailable(:final latitude, :final longitude, :final accuracyMeters) =>
      (LatLng(latitude, longitude), accuracyMeters),
    PositionUnavailable() => (null, null),
  };

  final refused = isLocationRefusal(fix);

  // With no trusted fix this session, an unavailability that is not a refusal
  // says 現在地不明, whatever the drive brain holds or does not hold (decided
  // 2026-09-13). Before this the words depended on the controller reporting
  // dead reckoning or lost; an unavailability that did not reach it, or found
  // it holding nothing, would leave the map with no mark and no words.
  if (fix is PositionUnavailable && !refused && !anchoredThisSession) {
    return const HerMapInputs(degraded: true, lost: true);
  }

  // An event the drive brain was not given (decided 2026-09-14): before this
  // session's first trusted fix, one that would not become that fix is held
  // back from the drive brain. It is not a position the loom vouches for, so
  // the map draws no mark of it and says 現在地不明, whatever [estimate] still
  // holds from an earlier session. Fed, the same event reads here as
  // dead reckoning or lost from no anchor of this session: the same words.
  if (notGivenToDriveBrain && !isMock && !refused && !anchoredThisSession) {
    return const HerMapInputs(degraded: true, lost: true);
  }

  final mode = estimate?.mode;
  final unlocatable =
      mode == LocalizationMode.deadReckoning || mode == LocalizationMode.lost;
  if (isMock || estimate == null || !unlocatable) {
    // A sample with no measured accuracy is never drawn from its own
    // coordinates, whatever the drive brain holds (decided 2026-09-14): not a
    // mark, not a ring. Given to the brain, it degrades from the anchor, and
    // the branch below draws that anchor's ring, not confident.
    if (!isMock && fix is PositionAvailable && fix.accuracyMeters == null) {
      return HerMapInputs(degraded: true, lost: true, refused: refused);
    }
    return HerMapInputs(
      position: fixPosition,
      accuracyMeters: fixAccuracy,
      refused: refused,
    );
  }

  if (!anchoredThisSession) {
    return HerMapInputs(degraded: true, lost: true, refused: refused);
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
    refused: refused,
  );
}
