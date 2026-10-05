/// WS6 — the fusion seam: honest localization × in-drive compound-failure
/// caution, wired for the live drive.
///
/// **Why this exists.** The driver — an older driver in
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
///   fusion (this file) → honest caution reaches the driver on screen+audio+haptic
///   (code path; on-device HEAR/FEEL DEFERRED, no device in
///   this env) → she eases off or pauses → she gets through the whiteout.
///
/// Pure logic, no Flutter, no timers, no IO — every function here is total and
/// synchronous, so it is fully testable off a device.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:localization_fallback/localization_fallback.dart';

import '../her_position.dart';
import 'gps_trust.dart';
import 'measured_hazard_floor.dart';

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
  /// [assessor] is injectable only so a test can make it fail. Every drive
  /// brain judges its fixes: a default-constructed one assesses, and there is
  /// no way to construct one that does not (decided 2026-10-05). A verdict
  /// each caller had to remember to supply would be the same believe-by-default
  /// hole one layer up: forgotten once, and every fix is trusted again.
  DriveLocalizer({
    LocalizationController? controller,
    GpsTrustAssessor? assessor,
  })  : controller = controller ?? LocalizationController(),
        _assessor = assessor ?? GpsTrustAssessor();

  /// The wrapped honest-position state machine.
  final LocalizationController controller;

  final GpsTrustAssessor _assessor;

  /// The verdict for the fix last asked about with [wouldTrust] and not yet
  /// fed: feeding that same fix uses it, so asking and then feeding advances
  /// the assessor once and gives the same answer both times (decided
  /// 2026-10-05). position_integrity has no way to ask without advancing.
  /// Asking DOES advance it, on purpose: a fix the app holds back before a
  /// share has anchored is still the base the next fix is judged against, or
  /// the share could never anchor.
  ({PositionAvailable fix, GpsTrustVerdict verdict})? _asked;

  /// The verdict on the last fix fed, or `null` before any. Kept for the
  /// record: [GpsTrustVerdict.shadow] is what the gates kept in shadow said,
  /// which nothing acts on.
  GpsTrustVerdict? get lastVerdict => _lastVerdict;
  GpsTrustVerdict? _lastVerdict;

  /// How many times the assessor could not be built or threw.
  int get assessorFaults => _assessor.faultCount;

  /// Forget the fixes judged so far: the next fix is a first fix again, held
  /// rather than trusted. Called where a share begins (decided 2026-10-05): a
  /// new share's first fix judged against the last fix of an earlier share,
  /// any length of time before, would be a check that could not fail.
  void resetAssessment() {
    _assessor.reset();
    _asked = null;
  }

  GpsTrustVerdict _verdictFor(PositionAvailable fix, double accuracy) {
    final asked = _asked;
    if (asked != null && _sameFix(asked.fix, fix)) return asked.verdict;
    final verdict = _assessor.assess(fix, accuracy);
    _asked = (fix: fix, verdict: verdict);
    return verdict;
  }

  static bool _sameFix(PositionAvailable a, PositionAvailable b) =>
      identical(a, b) ||
      (a.latitude == b.latitude &&
          a.longitude == b.longitude &&
          a.accuracyMeters == b.accuracyMeters &&
          a.timestamp == b.timestamp &&
          a.speedLowerBoundMps == b.speedLowerBoundMps);

  /// The most recently emitted estimate, or `null` before any input.
  LocalizationEstimate? get current => controller.current;

  /// When [controller] last took a fix as trusted, or `null` if it never has.
  ///
  /// Recorded from what the controller emitted, never assumed: only its
  /// trusted path emits [EstimateBasis.trustedGpsFix], and that path takes the
  /// fix's own timestamp as its clock (localization_fallback 0.1.4,
  /// `localization_controller.dart:101-143`). A controller injected with a
  /// fix already taken reads `null` here until it takes one through this
  /// localizer.
  DateTime? _lastTrustedFixAt;

  /// Whether [fix] would be taken as a trusted fix if it were fed now: a
  /// position with finite geometry and a non-negative accuracy
  /// ([RawFix.hasFiniteGeometry], the controller's own guard), newer than the
  /// last fix the controller trusted, that the GPS trust verdict trusts. A fix
  /// no newer than that is refused as replayed
  /// (`localization_controller.dart:108-110`), and an unavailability is never
  /// a fix.
  ///
  /// Asked BEFORE feeding, so the app can decline to give the drive brain an
  /// event that would not anchor it (decided 2026-09-14). The same answer as
  /// feeding it and reading the basis back, pinned against the real controller
  /// in `test/services/drive_localizer_would_trust_test.dart`. Asking twice
  /// gives the same answer; see [_asked] for what asking advances.
  bool wouldTrust(PositionFix fix) => switch (fix) {
        PositionAvailable(
          :final latitude,
          :final longitude,
          accuracyMeters: final double accuracy,
          :final timestamp,
        ) =>
          RawFix(
                latitude: latitude,
                longitude: longitude,
                accuracyMeters: accuracy,
                timestamp: timestamp,
              ).hasFiniteGeometry &&
              (_lastTrustedFixAt == null ||
                  timestamp.isAfter(_lastTrustedFixAt!)) &&
              _verdictFor(fix, accuracy).acting == TrustSignal.trusted,
        // A sample with no measured accuracy is not a fix (decided 2026-09-14).
        PositionAvailable() => false,
        PositionUnavailable() => false,
      };

  /// Whether [fix] is a share's first fix that nothing found wrong, held only
  /// because there is nothing yet to judge it against
  /// ([GpsTrustVerdict.awaitingComparison]). Asked like [wouldTrust], with the
  /// same cache: asking feeds nothing to the controller.
  bool awaitsComparison(PositionFix fix) => switch (fix) {
        PositionAvailable(
          :final latitude,
          :final longitude,
          accuracyMeters: final double accuracy,
          :final timestamp,
        ) =>
          RawFix(
                latitude: latitude,
                longitude: longitude,
                accuracyMeters: accuracy,
                timestamp: timestamp,
              ).hasFiniteGeometry &&
              (_lastTrustedFixAt == null ||
                  timestamp.isAfter(_lastTrustedFixAt!)) &&
              _verdictFor(fix, accuracy).awaitingComparison,
        PositionAvailable() => false,
        PositionUnavailable() => false,
      };

  /// Feed one [PositionFix].
  ///
  /// - [PositionAvailable] with a measured accuracy: judged by the GPS trust
  ///   verdict ([GpsTrustAssessor]) and fed with that verdict (decided
  ///   2026-10-05). Until then every such fix was fed as
  ///   [TrustSignal.trusted], the package's default. [speedMps], if known,
  ///   floors the radius-growth rate while the dot is frozen at last-known.
  /// - [PositionUnavailable]: NOT a position (denied / revoked / error /
  ///   non-finite). We [poll] at [now] so the estimate degrades honestly toward
  ///   `lost` rather than presenting a stale confident dot.
  LocalizationEstimate onPositionFix(
    PositionFix fix,
    DateTime now, {
    double? speedMps,
  }) {
    switch (fix) {
      case PositionAvailable(
          :final latitude,
          :final longitude,
          accuracyMeters: final double accuracy,
          :final timestamp,
        ):
        final raw = RawFix(
          latitude: latitude,
          longitude: longitude,
          accuracyMeters: accuracy,
          timestamp: timestamp,
          speedMps: speedMps,
        );
        // Geometry the controller refuses (a negative accuracy) is no fix to
        // judge, and never reaches the assessor.
        final verdict = raw.hasFiniteGeometry
            ? _verdictFor(fix, accuracy)
            : const GpsTrustVerdict(
                acting: TrustSignal.failed,
                shadow: TrustSignal.suspect,
                assessed: false,
                reasons: ['not a usable fix'],
                shadowReasons: ['not evaluated: not a usable fix'],
              );
        // Fed: the same fix fed again is judged again, as a replay.
        _asked = null;
        _lastVerdict = verdict;
        final estimate = controller.onFix(raw, trust: verdict.acting);
        if (estimate.basis == EstimateBasis.trustedGpsFix) {
          _lastTrustedFixAt = timestamp;
          _assessor.anchorOn(fix, accuracy);
        }
        return estimate;
      // No measured accuracy: not a fix (decided 2026-09-14). Treated as an event
      // that carries no position, polled at the sample's own timestamp, so the
      // brain degrades from the anchor it holds. Its coordinates and its speed
      // are never taken: no radius is invented for it.
      case PositionAvailable(:final timestamp):
        return controller.poll(timestamp);
      case PositionUnavailable _:
        return controller.poll(now);
    }
  }

  /// Feed the development page's test position: a fix nobody measured, which
  /// the app labels テスト位置 wherever it shows it. It is NOT a GPS fix, so the
  /// GPS trust verdict does not judge it and it is fed as the controller's
  /// trusted fix, as before 2026-10-05. Reached only from the development
  /// page's mock control (a release build never draws that page); every fix
  /// from her position stream goes through [onPositionFix].
  LocalizationEstimate onTestPosition(PositionAvailable fix) {
    final accuracy = fix.accuracyMeters;
    _lastVerdict = const GpsTrustVerdict(
      acting: TrustSignal.trusted,
      shadow: TrustSignal.suspect,
      assessed: false,
      reasons: ['a test position from the development page: not GPS'],
      shadowReasons: ['not evaluated: a test position'],
    );
    final estimate = controller.onFix(RawFix(
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyMeters: accuracy ?? double.nan,
      timestamp: fix.timestamp,
    ));
    if (estimate.basis == EstimateBasis.trustedGpsFix) {
      _lastTrustedFixAt = fix.timestamp;
    }
    return estimate;
  }

  /// Advance during a blackout (no fix arrived this tick) so the radius keeps
  /// growing and the mode can reach `lost`.
  LocalizationEstimate poll(DateTime now) => controller.poll(now);
}

/// Whether a MEASURED condition raises caution on its own: the advisor's
/// reasons for this environment on a trusted, fresh, exact position, other
/// than a visibility it could not read, or a firing measured-weather watch.
///
/// Why (decided 2026-09-14): before a share's first trusted fix a position
/// failure does not reach the caution rung by itself, and it never takes away
/// a caution that a measured condition raises. A missing or stale visibility
/// reading is not a measurement, so it is excluded by name. Every other reason
/// counts, including one a future advisor adds: an unknown reason routes
/// toward caution, not away from it.
bool measuredConditionRaisesCaution({
  required double? visibilityMeters,
  required double? visibilityAgeSeconds,
  required AdvisoryLevel? advisorySeverity,
  required MeasuredWeatherHazard measuredHazard,
}) {
  if (measuredHazard != MeasuredWeatherHazard.none) return true;
  final advice = adviseInDrive(DriveSituation(
    positionTrust: PositionTrust.trusted,
    confidenceRadiusMeters: 0,
    secondsSinceTrustedFix: 0,
    hasPosition: true,
    visibilityMeters: visibilityMeters,
    visibilityAgeSeconds: visibilityAgeSeconds,
    advisorySeverity: advisorySeverity,
    speedMetersPerSecond: null,
  ));
  return advice.reasons.any((r) =>
      r != CautionReason.unknownVisibility &&
      r != CautionReason.staleVisibility);
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
