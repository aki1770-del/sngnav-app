/// WS6 — the live drive controller: honest position + compound caution,
/// auto-announced on the app's WS5 actuators the moment the caution rung rises.
///
/// **Mission trace (<=4 hops).** HER is in unexpected snow with Maps + GPS
/// failing. This controller is the live brain of her drive HUD: it feeds every
/// position sample into `localization_fallback` (honest dot), fuses the result
/// with visibility/advisory/speed via `compound_failure_advisor` (honest
/// caution rung), and — the moment the caution RISES — announces it on audio +
/// haptic through the WS5 [AlertAnnouncer]. So the caution reaches HER even
/// when her eyes are on the invisible road and the basemap has gone blank.
///   controller (this file) → caution reaches HER eyes-off → she eases / pauses
///   → HER survives the whiteout.
///
/// **Reach status (OPS-066 / AAE-1 — honest bounds).** This controller is
/// WIRED into `SngnavApp`'s live flow (`main.dart`): the app's GPS listener
/// calls [onPositionFix] / [poll], the visibility + area-advisory it already
/// holds feed [updateEnvironment], and a rising rung fires the app's SINGLE
/// [AlertAnnouncer] (audio + haptic). The **code-path reaches HER**; the
/// on-device HEAR / FEEL is DEFERRED (no Android device in this env — see
/// `docs/DEVICE_VERIFICATION.md`). It is never claimed as "works on Android".
///
/// Pure logic + a [ChangeNotifier]: NO timers, NO IO, NO geolocator here (the
/// live feed is injected by the app), so the whole escalation + actuator-firing
/// path is testable off a device with a recording fake actuator.
library;

import 'dart:async';

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:flutter/foundation.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity;

import '../actuators/alert_actuators.dart';
import '../actuators/alert_announcer.dart';
import '../her_position.dart';
import 'drive_hud_localizer.dart';
import 'drive_safety_fusion.dart';

/// Live in-drive controller. Observe [estimate] + [advice] via [ChangeNotifier].
class DriveHudController extends ChangeNotifier {
  /// The controller NEVER resolves its own actuator layer: the app owns ONE
  /// [AlertActuators] (and one wakelock owner), and this controller announces
  /// through it. That single-owner rule is enforced by construction here —
  /// [actuators] is REQUIRED (no `?? defaultAlertActuators()` that would build
  /// a second actuator / second wakelock owner).
  ///
  /// - [actuators]: the app's single actuator layer (a recording fake in
  ///   tests; the app's `defaultAlertActuators()` — real on mobile, no-op
  ///   everywhere else — in production). The desktop render-SEE ceiling stays
  ///   intact because that resolution happens ONCE, in the app.
  /// - [announcer]: optional — pass the app's existing [AlertAnnouncer] so the
  ///   whole app shares ONE announcer; when null, one is built over
  ///   [actuators] (the test default).
  /// - [localization]: injectable so a test can seed the honest-position state
  ///   machine.
  factory DriveHudController({
    required AlertActuators actuators,
    AlertAnnouncer? announcer,
    LocalizationController? localization,
    DriveHudLocalizer text = const DriveHudLocalizer(),
    String localeTag = 'ja',
  }) {
    return DriveHudController._(
      localizer: DriveLocalizer(controller: localization),
      announcer: announcer ?? AlertAnnouncer(actuators: actuators),
      text: text,
      localeTag: localeTag,
    );
  }

  DriveHudController._({
    required DriveLocalizer localizer,
    required AlertAnnouncer announcer,
    required DriveHudLocalizer text,
    required this.localeTag,
  })  : _localizer = localizer,
        _announcer = announcer,
        _text = text;

  final DriveLocalizer _localizer;
  final AlertAnnouncer _announcer;
  final DriveHudLocalizer _text;

  /// BCP-47-ish tag for the driver-facing surface (defaults to `ja` — HER).
  final String localeTag;

  // --- environment inputs the app feeds alongside position ---

  /// Visibility in metres, or `null` = no reading (a first-class unknown).
  double? visibilityMeters;

  /// Age of the visibility reading in seconds, or `null` = unknown age.
  double? visibilityAgeSeconds;

  /// Pre-selected single most-severe in-area advisory, or `null` = none.
  AdvisoryLevel? advisorySeverity;

  /// Current ground speed in m/s, or `null` = unknown.
  double? speedMetersPerSecond;

  LocalizationEstimate? _estimate;
  DriveAdvice? _advice;
  DriveAction? _lastAnnouncedAction;

  /// The current honest position estimate (mode + growing radius + first-class
  /// `lost`), or `null` before any input.
  LocalizationEstimate? get estimate => _estimate;

  /// The current advisory-only caution read, or `null` before any input.
  DriveAdvice? get advice => _advice;

  /// The text localizer (for the HUD widget).
  DriveHudLocalizer get text => _text;

  // The screen wakelock is owned by the app (main.dart holds it for the whole
  // navigation surface, on the SAME single actuator). This controller does NOT
  // touch keepAwake — a second owner is exactly the double-wakelock bug the
  // required-injection factory above exists to prevent.

  /// Replace the environment inputs the caution fuses with. The live feed calls
  /// this each step with the full environment; a caution recompute follows on
  /// the next position event / [poll].
  void updateEnvironment({
    required double? visibilityMeters,
    required double? visibilityAgeSeconds,
    required AdvisoryLevel? advisorySeverity,
    required double? speedMetersPerSecond,
  }) {
    this.visibilityMeters = visibilityMeters;
    this.visibilityAgeSeconds = visibilityAgeSeconds;
    this.advisorySeverity = advisorySeverity;
    this.speedMetersPerSecond = speedMetersPerSecond;
    if (_estimate != null) _recompute();
  }

  /// Feed one position sample. A [PositionUnavailable] (denied / revoked
  /// mid-drive / error / non-finite) degrades honestly toward `lost` — never a
  /// stale confident dot.
  void onPositionFix(PositionFix fix, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _estimate = _localizer.onPositionFix(
      fix,
      t,
      speedMps: speedMetersPerSecond,
    );
    _recompute();
  }

  /// Advance the honest position during a blackout (no fix this tick) so the
  /// radius grows and the mode can reach `lost`.
  void poll({DateTime? now}) {
    _estimate = _localizer.poll(now ?? DateTime.now());
    _recompute();
  }

  void _recompute() {
    final estimate = _estimate;
    if (estimate == null) return;
    final advice = adviseFromEstimate(
      estimate,
      visibilityMeters: visibilityMeters,
      visibilityAgeSeconds: visibilityAgeSeconds,
      advisorySeverity: advisorySeverity,
      speedMetersPerSecond: speedMetersPerSecond,
    );
    _advice = advice;
    _maybeAnnounce(advice);
    notifyListeners();
  }

  /// Fire the WS5 actuators when the caution RUNG RISES to a new high — once
  /// per upward transition, so a steady caution does not nag. A later re-rise
  /// re-announces (the last-announced rung tracks every change, including
  /// downgrades). info-class `continueDriving` is never announced (channel
  /// parity with the voice gate).
  void _maybeAnnounce(DriveAdvice advice) {
    final action = advice.action;
    final rising = action.index > (_lastAnnouncedAction?.index ?? -1);
    if (rising && action.index >= DriveAction.heightenedCaution.index) {
      final line = _text.spokenGuidance(action, localeTag);
      unawaited(_announcer.announce(
        severity: _severityFor(action),
        text: line,
        localeTag: localeTag,
      ));
    }
    _lastAnnouncedAction = action;
  }

  /// Map the advisory-only caution rung to the actuator severity gate.
  ///
  /// continueDriving → info (not announced); heightenedCaution → warning;
  /// considerStopping → critical. The announcer gates BOTH audio + haptic on
  /// `>= warning`, so a rung at or above heightened reaches the eyes-off AND
  /// the deaf / can't-hear-over-the-wind driver (OPS-059 floor).
  static AlertSeverity _severityFor(DriveAction action) => switch (action) {
        DriveAction.continueDriving => AlertSeverity.info,
        DriveAction.heightenedCaution => AlertSeverity.warning,
        DriveAction.considerStopping => AlertSeverity.critical,
      };

  /// The severity the current advice would announce at (for the HUD's colour +
  /// tests). `null` before any advice.
  @visibleForTesting
  AlertSeverity? get currentSeverity =>
      _advice == null ? null : _severityFor(_advice!.action);
}
