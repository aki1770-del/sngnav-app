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
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;

import '../actuators/alert_actuators.dart';
import '../actuators/alert_announcer.dart';
import '../her_position.dart';
import 'drive_hud_localizer.dart';
import 'drive_safety_fusion.dart';
import 'maneuver_narration.dart';
import 'measured_hazard_floor.dart';

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
      narrator: ManeuverNarrator(text: text),
      localeTag: localeTag,
    );
  }

  DriveHudController._({
    required DriveLocalizer localizer,
    required AlertAnnouncer announcer,
    required DriveHudLocalizer text,
    required ManeuverNarrator narrator,
    required this.localeTag,
  })  : _localizer = localizer,
        _announcer = announcer,
        _text = text,
        _narrator = narrator;

  final DriveLocalizer _localizer;
  final AlertAnnouncer _announcer;
  final DriveHudLocalizer _text;
  final ManeuverNarrator _narrator;

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

  /// The measured local-weather hazard floor from the app's own JMA watches
  /// (invisible-ice + turmoil). Defaults to [MeasuredWeatherHazard.none]; a
  /// firing watch RAISES the compound rung (never lowers it). Set by the app
  /// alongside the other environment fields before a position event / [poll].
  MeasuredWeatherHazard measuredHazard = MeasuredWeatherHazard.none;

  LocalizationEstimate? _estimate;
  DriveAdvice? _advice;
  DriveAction? _effectiveAction;

  /// The highest rung the controller has actually SPOKEN, for rise-gating the
  /// announce. Tracked SEPARATELY from the effective rung on purpose: a rung
  /// that RISES but is deliberately muted (a measured-hazard floor the watch
  /// lane already voiced, or an unknown-visibility-only heightened) must NOT
  /// advance this — otherwise it would swallow the announce slot and a LATER
  /// genuinely-grounded caution at the same rung would reach neither the voice
  /// NOR the OPS-059 haptic (the safety regression OPS-068 caught). It is
  /// clamped DOWN on a genuine downgrade so a drop-then-re-rise re-announces.
  DriveAction? _lastSpokenRung;

  /// The current honest position estimate (mode + growing radius + first-class
  /// `lost`), or `null` before any input.
  LocalizationEstimate? get estimate => _estimate;

  /// True when the honest estimate is dead-reckoning or lost — the position is
  /// no longer a trustworthy LOCATION. The map dot + status line must NOT keep
  /// presenting a confident "you are here" here; they degrade to a stale/last-
  /// known rendering (the exact silent-GPS-blackout case where the raw fix
  /// stream goes quiet and `_herFix` still holds the last confident point).
  /// Mirrors the maneuver-suppression contract (`positionUnlocatable` in
  /// `_recompute`); a `null` estimate (no fix yet) is NOT unlocatable — the
  /// surface simply shows no dot.
  bool get positionUnlocatable {
    final mode = _estimate?.mode;
    return mode == LocalizationMode.deadReckoning ||
        mode == LocalizationMode.lost;
  }

  /// The current advisory-only caution read FROM THE ADVISOR (position ×
  /// visibility × advisory × speed), or `null` before any input. This is the
  /// honest per-axis record; [effectiveAction] is what the surface reflects
  /// after the measured-weather floor is fused in.
  DriveAdvice? get advice => _advice;

  /// The EFFECTIVE caution rung the HUD banner + severity + haptic reflect:
  /// `max([advice].action, measured-weather floor)`. Equals [advice]'s action
  /// unless a firing measured watch raised it. `null` before any input.
  DriveAction? get effectiveAction => _effectiveAction;

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
    MeasuredWeatherHazard? measuredHazard,
  }) {
    this.visibilityMeters = visibilityMeters;
    this.visibilityAgeSeconds = visibilityAgeSeconds;
    this.advisorySeverity = advisorySeverity;
    this.speedMetersPerSecond = speedMetersPerSecond;
    // null = leave the current measured-hazard floor unchanged (this setter is
    // used by the visibility-band control, which does not re-evaluate the JMA
    // watches); the app passes the live value when it has one.
    if (measuredHazard != null) this.measuredHazard = measuredHazard;
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
    // Fuse the measured-weather floor: a firing JMA watch RAISES the rung the
    // driver reacts to (caution-add-only), and compounds to the ceiling when the
    // hazard cannot even be LOCATED. "Unlocatable" is the STRICT honest condition
    // — dead-reckoning or lost — NOT advice.positionUncertain (which also covers
    // a fresh, still-locatable suspect fix that stays at the heightened floor;
    // OPS-068). See measured_hazard_floor.dart.
    final positionUnlocatable = estimate.mode == LocalizationMode.deadReckoning ||
        estimate.mode == LocalizationMode.lost;
    _effectiveAction = fuseMeasuredWeather(
      advisorAction: advice.action,
      hazard: measuredHazard,
      positionUnlocatable: positionUnlocatable,
    );
    _maybeAnnounce(advice);
    notifyListeners();
  }

  /// Fire the WS5 actuators when the EFFECTIVE caution rung RISES to a new high
  /// — once per upward transition, so a steady caution does not nag. A later
  /// re-rise re-announces (the last-announced rung tracks every change,
  /// including downgrades). info-class `continueDriving` is never announced
  /// (channel parity with the voice gate).
  ///
  /// Whether the rung's own SPOKEN guidance line fires is gated by
  /// [_shouldSpeakRise] — two kinds of rise are shown+coloured but NOT spoken
  /// here: a rise driven solely by the measured-hazard floor (the watch lane
  /// already speaks the specific hazard), and a heightened rise whose only
  /// advisor reason is unknown/stale visibility (an honest displayed state,
  /// never an alarm to blare on every sensorless drive).
  ///
  /// The speak-gate rises off [_lastSpokenRung] — the last rung actually SPOKEN
  /// — NOT off the effective rung. A muted rise therefore does not consume the
  /// announce slot: a later grounded caution at the same rung still speaks +
  /// buzzes (OPS-068 fix). [_lastSpokenRung] is clamped DOWN whenever the
  /// effective rung genuinely downgrades, so a drop-then-re-rise re-announces
  /// (the documented behaviour).
  void _maybeAnnounce(DriveAdvice advice) {
    final effective = _effectiveAction ?? advice.action;

    // Downgrade clamp: never let the spoken tracker sit ABOVE the current rung,
    // so a real re-rise back up to it re-announces.
    if (_lastSpokenRung != null && effective.index < _lastSpokenRung!.index) {
      _lastSpokenRung = effective;
    }

    final risesAboveSpoken = effective.index > (_lastSpokenRung?.index ?? -1);
    if (risesAboveSpoken &&
        effective.index >= DriveAction.heightenedCaution.index &&
        _shouldSpeakRise(advice, effective)) {
      final line = _text.spokenGuidance(effective, localeTag);
      if (line.isNotEmpty) {
        unawaited(_announcer.announce(
          severity: _severityFor(effective),
          text: line,
          localeTag: localeTag,
        ));
        // Advance the SPOKEN tracker ONLY when a line actually fired.
        _lastSpokenRung = effective;
      }
    }
  }

  /// Whether a RISING effective rung should also SPEAK the compound-rung's own
  /// guidance line, as opposed to being shown + coloured + (via a co-firing
  /// watch) buzzed only.
  ///
  ///  - `considerStopping` ALWAYS speaks: its calm invitation
  ///    (「安全な場所での停車も選べます」) is additive, never a duplicate of any watch
  ///    line, and the compound "a measured hazard you cannot even locate" must
  ///    reach her eyes-off.
  ///  - a rise to `heightenedCaution` caused SOLELY by the measured-hazard floor
  ///    (the advisor itself is still below heightened) does NOT speak — the
  ///    watch lane already spoke the specific hazard; a second generic caution
  ///    line would be double-speak.
  ///  - a rise to `heightenedCaution` grounded by the advisor speaks ONLY when a
  ///    reason OTHER than unknown/stale visibility raised it. "We have no
  ///    visibility reading" is an honest DISPLAYED state (視程 未計測), never an
  ///    alarm to announce on every drive that lacks a visibility sensor
  ///    (cry-wolf).
  bool _shouldSpeakRise(DriveAdvice advice, DriveAction effective) {
    if (effective == DriveAction.considerStopping) return true;
    // effective == heightenedCaution here (continueDriving never reaches speak).
    // Rose solely from the measured floor → the watch lane already spoke it.
    if (advice.action.index < DriveAction.heightenedCaution.index) return false;
    // Advisor grounded it: speak only if something other than unknown/stale
    // visibility raised it.
    return advice.reasons.any((r) =>
        r != CautionReason.unknownVisibility &&
        r != CautionReason.staleVisibility);
  }

  // --- (e) honest confidence-gated maneuver narration ---

  /// Narrate the NEXT [maneuver] through the SAME announcer as the caution,
  /// GATED on the live honest position mode.
  ///
  /// This is the HER differentiator: a turn is spoken ONLY when the dot is
  /// trustworthy.
  ///  - `gpsTrusted` → SPEAK the JA turn plainly.
  ///  - `gpsSuspect` → HEDGE (softened, "please confirm").
  ///  - `deadReckoning` / `lost` → SUPPRESS — the announcer is NOT fired, so no
  ///    "turn now" is ever spoken against a drifting/lost position.
  ///
  /// **Fail-safe:** if no position has been fed yet ([estimate] is null) the
  /// mode is treated as [LocalizationMode.lost] → SUPPRESS. The app never
  /// speaks a turn before it knows where she is.
  ///
  /// [icyTurn] couples the icy-turn advisory when the maneuver coincides with an
  /// ice / low-visibility hazard (reuses the localizer's advisory register).
  ///
  /// Returns the [ManeuverNarration] decision (for the HUD + tests). Announcing
  /// is fire-and-forget through the app's single [AlertAnnouncer] — whose own
  /// `>= warning` gate is a second backstop: a suppressed decision carries
  /// `info` severity and empty text, so even a mis-wired call could not speak.
  ManeuverNarration narrateNextManeuver(
    RouteManeuver maneuver, {
    required bool icyTurn,
  }) {
    final mode = _estimate?.mode ?? LocalizationMode.lost;
    final decision = _narrator.decide(
      maneuver: maneuver,
      mode: mode,
      icyTurn: icyTurn,
      localeTag: localeTag,
    );
    if (decision.shouldAnnounce) {
      unawaited(_announcer.announce(
        severity: decision.severity,
        text: decision.text,
        localeTag: localeTag,
      ));
    }
    return decision;
  }

  /// A side-effect-FREE preview of what [narrateNextManeuver] would decide right
  /// now, for the on-screen HUD (which must reflect the gate honestly — showing
  /// "turn right" on-screen against a lost dot is the same confidently-wrong
  /// hazard, just visual). Does NOT fire the announcer.
  ManeuverNarration previewNextManeuver(
    RouteManeuver maneuver, {
    required bool icyTurn,
  }) {
    final mode = _estimate?.mode ?? LocalizationMode.lost;
    return _narrator.decide(
      maneuver: maneuver,
      mode: mode,
      icyTurn: icyTurn,
      localeTag: localeTag,
    );
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

  /// The severity the current EFFECTIVE rung announces at (for the HUD's colour +
  /// tests) — after the measured-weather floor is fused in. `null` before any
  /// advice.
  @visibleForTesting
  AlertSeverity? get currentSeverity =>
      _effectiveAction == null ? null : _severityFor(_effectiveAction!);

  /// Whether the current EFFECTIVE rung is one the rung lane itself SPEAKS (vs
  /// one that is shown+coloured only while a watch lane speaks the specific
  /// hazard, or an unknown-visibility-only display). For an HONEST HUD status
  /// line: a floor-only heightened must NOT claim it auto-fired audio+haptic
  /// (OPS-068). `false` before any advice and for `continueDriving`.
  bool get effectiveRungIsSpokenByRung {
    final effective = _effectiveAction;
    final advice = _advice;
    if (effective == null || advice == null) return false;
    if (effective == DriveAction.continueDriving) return false;
    return _shouldSpeakRise(advice, effective);
  }
}
