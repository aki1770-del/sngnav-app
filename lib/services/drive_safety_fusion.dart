/// WS6 — the fusion seam: honest localization × in-drive compound-failure
/// caution, wired for HER live drive.
///
/// **Why this exists (mission trace, <=4 hops).** HER — the Chair's mother in
/// Akita — is driving in unexpected snow. Maps AND GPS have failed at once and
/// she cannot see where the road is (the PHIL-001 compound worst-case). Two
/// pure-Dart catalog packages already answer the two halves honestly:
///   - `localization_fallback` turns raw GPS fixes into ONE honest position
///     estimate that degrades truthfully (trusted → dead-reckoning → `lost`)
///     and NEVER a confidently-wrong dot; and
///   - `compound_failure_advisor` fuses that position-trust with what she can
///     see into one advisory-only caution rung (its ceiling is *consider
///     stopping*, never *turn back*).
/// This seam is where the app feeds the first into the second, so the live
/// drive HUD can tell her the honest truth and — via the WS5 actuators — speak
/// and buzz the caution she cannot look up to read. It is wired live in
/// `SngnavApp` (`main.dart`) through `DriveHudController`.
///   fusion (this file) → honest caution reaches HER on screen+audio+haptic
///   (code-path; on-device HEAR/FEEL DEFERRED per OPS-066 / AAE-1, no device in
///   this env) → she eases / pauses → HER survives the whiteout.
///
/// Pure logic, no Flutter, no timers, no IO — every function here is total and
/// synchronous, so it is fully testable off a device.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:localization_fallback/localization_fallback.dart';

import '../her_position.dart';

/// Map `localization_fallback`'s honest [LocalizationMode] to the compound
/// advisor's mirror [PositionTrust] with one explicit switch at the seam.
///
/// The two packages are DELIBERATELY decoupled (each publishes on its own
/// cadence; `compound_failure_advisor` mirrors the enum rather than importing
/// it — see its `mirror_enums.dart`), so the integrator owns this one mapping.
PositionTrust positionTrustFromMode(LocalizationMode mode) => switch (mode) {
      LocalizationMode.gpsTrusted => PositionTrust.trusted,
      LocalizationMode.gpsSuspect => PositionTrust.suspect,
      LocalizationMode.deadReckoning => PositionTrust.degraded,
      LocalizationMode.lost => PositionTrust.lost,
    };

/// Wraps a [LocalizationController] and feeds it the app's own [PositionFix]
/// events (from `her_position.dart`), producing one honest
/// [LocalizationEstimate] per input.
///
/// The load-bearing behaviour (the WS6 audit flag): a [PositionUnavailable] —
/// which `her_position.dart` emits on permission denial, a **revoked-mid-drive**
/// permission, a GPS stream error, or the non-finite chokepoint — is NOT a
/// position. It is never blended in as a fix. We advance the controller with
/// [LocalizationController.poll] instead, so the dot degrades from last-known
/// with a MONOTONICALLY GROWING confidence radius and honestly reaches `lost`
/// — never a frozen, stale, confidently-wrong dot left sitting where GPS last
/// worked.
class DriveLocalizer {
  DriveLocalizer({LocalizationController? controller})
      : controller = controller ?? LocalizationController();

  /// The wrapped honest-position state machine.
  final LocalizationController controller;

  /// The most recently emitted estimate, or `null` before any input.
  LocalizationEstimate? get current => controller.current;

  /// Feed one [PositionFix].
  ///
  /// - [PositionAvailable]: a trusted raw fix — `her_position.dart` already ran
  ///   the finite-coordinate chokepoint, so its geometry is real. Fed as
  ///   [TrustSignal.trusted] (the controller re-guards non-finite geometry
  ///   anyway). [speedMps], if known, floors the radius-growth rate while the
  ///   dot is frozen at last-known.
  /// - [PositionUnavailable]: NOT a position (denied / revoked / error /
  ///   non-finite). We [poll] at [now] so the estimate degrades honestly toward
  ///   `lost` rather than presenting a stale confident dot.
  LocalizationEstimate onPositionFix(
    PositionFix fix,
    DateTime now, {
    double? speedMps,
  }) {
    switch (fix) {
      case PositionAvailable a:
        return controller.onFix(
          RawFix(
            latitude: a.latitude,
            longitude: a.longitude,
            accuracyMeters: a.accuracyMeters,
            timestamp: a.timestamp,
            speedMps: speedMps,
          ),
        );
      case PositionUnavailable _:
        return controller.poll(now);
    }
  }

  /// Advance during a blackout (no fix arrived this tick) so the radius keeps
  /// growing and the mode can reach `lost`.
  LocalizationEstimate poll(DateTime now) => controller.poll(now);
}

/// Build the in-drive [DriveSituation] from an honest localization [estimate]
/// plus the environment the app already holds (visibility × advisory severity
/// × speed), and fuse to one advisory-only [DriveAdvice].
///
/// This is the whole point of the WS6 wiring: the caution the driver sees is
/// grounded in the SAME honest position estimate drawn on her map — not a
/// separate, more-optimistic read. When position is `lost` AND visibility is
/// low at once, the advisor's compounding rule raises the caution to its
/// ceiling (*consider stopping*) — the honest answer to the compound failure.
DriveAdvice adviseFromEstimate(
  LocalizationEstimate estimate, {
  double? visibilityMeters,
  double? visibilityAgeSeconds,
  AdvisoryLevel? advisorySeverity,
  double? speedMetersPerSecond,
}) {
  final situation = DriveSituation(
    positionTrust: positionTrustFromMode(estimate.mode),
    confidenceRadiusMeters: estimate.confidenceRadiusMeters,
    secondsSinceTrustedFix: estimate.secondsSinceTrustedFix,
    hasPosition: estimate.hasPosition,
    visibilityMeters: visibilityMeters,
    visibilityAgeSeconds: visibilityAgeSeconds,
    advisorySeverity: advisorySeverity,
    speedMetersPerSecond: speedMetersPerSecond,
  );
  return adviseInDrive(situation);
}
