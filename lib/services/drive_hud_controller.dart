/// WS6 — the live drive controller: honest position + compound caution,
/// auto-announced on the app's WS5 actuators the moment the caution rung rises.
///
/// **Why this exists.** The driver is in unexpected snow with Maps + GPS
/// failing. This controller is the live brain of her drive HUD: it feeds every
/// position sample into `localization_fallback` (honest dot), fuses the result
/// with visibility/advisory/speed via `compound_failure_advisor` (honest
/// caution rung), and — the moment the caution RISES — announces it on audio +
/// haptic through the WS5 [AlertAnnouncer]. So the caution reaches the driver even
/// when her eyes are on the invisible road and the basemap has gone blank.
///   controller (this file) → caution reaches the driver eyes-off → she eases
///   off or pauses → she gets through the whiteout.
///
/// **Reach status (honest bounds).** This controller is
/// WIRED into `SngnavApp`'s live flow (`main.dart`): the app's GPS listener
/// calls [onPositionFix] / [poll], the visibility + area-advisory it already
/// holds feed [updateEnvironment], and a rising rung fires the app's SINGLE
/// [AlertAnnouncer] (audio + haptic). The **code path reaches the driver**; the
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

/// Where the caution rung comes from before a share's first trusted fix
/// (decided 2026-09-15).
enum StartRung {
  /// The brain's own estimate sets the rung: a trusted fix came in this share,
  /// or no share is being judged by these rules.
  none,

  /// The platform stream is subscribed and no position event has come, inside
  /// 60 s of the subscription: a normal start. The rung is the road's own, what
  /// a driver with a trusted position is given in the same environment.
  road,

  /// A failure before this share's first trusted fix, or no event 60 s after
  /// the subscription: an unlocated position that compounds as one, never a
  /// concern standing alone at the ceiling.
  unlocated,
}

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

  /// BCP-47-ish tag for the driver-facing surface (defaults to `ja`).
  final String localeTag;

  // --- environment inputs the app feeds alongside position ---

  /// Visibility in metres, or `null` = no reading (a first-class unknown).
  double? visibilityMeters;

  /// Age of the visibility reading in seconds, or `null` = unknown age.
  double? visibilityAgeSeconds;

  /// Pre-selected single most-severe in-area advisory, or `null` = none.
  AdvisoryLevel? advisorySeverity;

  /// Ground speed in m/s given to the caution advisor, or `null` = unknown.
  ///
  /// The advisor's alone since 2026-09-14: her ring's growth rate comes from
  /// each fix ([PositionAvailable.speedFloorMps]), never from this field.
  double? speedMetersPerSecond;

  /// The measured local-weather hazard floor from the app's own JMA watches
  /// (invisible-ice + turmoil). Defaults to [MeasuredWeatherHazard.none]; a
  /// firing watch RAISES the compound rung (never lowers it). Set by the app
  /// alongside the other environment fields before a position event / [poll].
  MeasuredWeatherHazard measuredHazard = MeasuredWeatherHazard.none;

  /// Asked at the moment a rung line is spoken: whether the rung was raised by
  /// a value nobody measured (set by the app, which alone knows). When true the
  /// line is spoken with [DriveHudLocalizer.testValueSpokenPrefix] before it,
  /// as its own utterance, so the line itself still matches the offline audio.
  bool Function() spokenFromTestValue = _noTestValue;
  static bool _noTestValue() => false;

  LocalizationEstimate? _estimate;
  DriveAdvice? _advice;
  DriveAction? _effectiveAction;

  /// Where the rung comes from before this share's first trusted fix (decided
  /// 2026-09-15). Set by the app, which alone knows where a share begins and
  /// whether an event has come.
  StartRung _startRung = StartRung.none;

  /// The highest rung given from [_startRung] in this share. Once given, it
  /// does not fall within the share: a reading that goes stale and comes back
  /// fresh at the same band is not a rise, and is not told again.
  DriveAction? _startRungHeld;

  /// See [StartRung]. Setting [StartRung.none] drops the held rung: from a
  /// trusted fix on, the brain's own estimate sets the rung.
  StartRung get startRung => _startRung;
  set startRung(StartRung value) {
    if (value == StartRung.none) _startRungHeld = null;
    _startRung = value;
  }

  /// A share she starts herself begins with nothing told and no rung held
  /// (decided 2026-09-15). The estimate is kept: reset, a replayed fix from
  /// another place became a trusted position.
  void startShare() {
    _lastSpokenRung = null;
    _startRungHeld = null;
    _startRung = StartRung.none;
  }

  /// The highest rung told in this share, or `null`.
  DriveAction? get spokenRung => _lastSpokenRung;

  /// What a driver with a trusted, fresh, exact position is given in the
  /// environment this brain holds now: the road's own caution.
  DriveAdvice roadAdvice() => adviseInDrive(DriveSituation(
        positionTrust: PositionTrust.trusted,
        confidenceRadiusMeters: 0,
        secondsSinceTrustedFix: 0,
        hasPosition: true,
        visibilityMeters: visibilityMeters,
        visibilityAgeSeconds: visibilityAgeSeconds,
        advisorySeverity: advisorySeverity,
        speedMetersPerSecond: speedMetersPerSecond,
      ));

  /// Tell [rung] to a driver with no share running, through the one announcer:
  /// its own line once and its haptic once. Touches nothing a share has told.
  void tellWithNoShare(DriveAction rung) {
    final line = _text.spokenGuidance(rung, localeTag);
    if (line.isEmpty) return;
    unawaited(_announcer.announce(
      severity: _severityFor(rung),
      text: line,
      localeTag: localeTag,
    ));
  }

  /// The highest rung the controller has actually SPOKEN, for rise-gating the
  /// announce. Tracked SEPARATELY from the effective rung on purpose: a rung
  /// that RISES but is deliberately muted (a measured-hazard floor the watch
  /// channel already voiced, or an unknown-visibility-only heightened) must NOT
  /// advance this — otherwise it would swallow the announce slot and a LATER
  /// genuinely-grounded caution at the same rung would reach neither the voice
  /// NOR the haptic that deaf and hard-of-hearing drivers rely on (a safety
  /// regression found in review). It is
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
      // Her ring grows at least as fast as the platform measured her moving
      // at this fix (decided 2026-09-14), read from the fix itself. At a default
      // 2.0 m/s, 30 s into a blackout at 25 m/s, the map was told 70 m while
      // she could be 775 m away. [speedMetersPerSecond] stays the advisor's
      // alone, and the app gives it none.
      speedMps: fix is PositionAvailable ? fix.speedFloorMps : null,
    );
    _recompute();
  }

  /// Whether [fix] would be taken as a trusted fix if fed now
  /// ([DriveLocalizer.wouldTrust]). Asking feeds nothing.
  bool wouldTrust(PositionFix fix) => _localizer.wouldTrust(fix);

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
    // a fresh, still-locatable suspect fix that stays at the heightened
    // floor). See measured_hazard_floor.dart.
    final positionUnlocatable = estimate.mode == LocalizationMode.deadReckoning ||
        estimate.mode == LocalizationMode.lost;
    switch (_startRung) {
      case StartRung.none:
        _effectiveAction = fuseMeasuredWeather(
          advisorAction: advice.action,
          hazard: measuredHazard,
          positionUnlocatable: positionUnlocatable,
        );
        _maybeAnnounce(advice);
      case StartRung.road:
        // Ruled 2026-09-15 (the first fix never arrives, inside 60 s): the
        // road's own caution, what a driver with a trusted position is given
        // here, spoken or not as it is for her.
        final road = roadAdvice();
        _advice = road;
        _effectiveAction = _held(fuseMeasuredWeather(
          advisorAction: road.action,
          hazard: measuredHazard,
          positionUnlocatable: false,
        ));
        _maybeAnnounce(road);
      case StartRung.unlocated:
        // Ruled 2026-09-15: a failure before the share's first trusted fix
        // takes the rung the advisor gives a position that is uncertain but
        // not lost, in this same environment, fused as an unlocatable
        // position. The reasons and unknowns stay the real ones.
        _effectiveAction = _held(fuseMeasuredWeather(
          advisorAction: adviseInDrive(DriveSituation(
            positionTrust: PositionTrust.degraded,
            confidenceRadiusMeters: 0,
            secondsSinceTrustedFix: 0,
            hasPosition: true,
            visibilityMeters: visibilityMeters,
            visibilityAgeSeconds: visibilityAgeSeconds,
            advisorySeverity: advisorySeverity,
            speedMetersPerSecond: speedMetersPerSecond,
          )).action,
          hazard: measuredHazard,
          positionUnlocatable: true,
        ));
        _maybeAnnounce(advice);
    }
    notifyListeners();
  }

  DriveAction _held(DriveAction rung) {
    final held = _startRungHeld;
    final effective =
        held != null && held.index > rung.index ? held : rung;
    _startRungHeld = effective;
    return effective;
  }

  /// Fire the WS5 actuators when the EFFECTIVE caution rung RISES to a new high
  /// — once per upward transition, so a steady caution does not nag. A later
  /// re-rise re-announces (the last-announced rung tracks every change,
  /// including downgrades). info-class `continueDriving` is never announced
  /// (channel parity with the voice gate).
  ///
  /// Whether the rung's own SPOKEN guidance line fires is gated by
  /// [_shouldSpeakRise] — two kinds of rise are shown+coloured but NOT spoken
  /// here: a rise driven solely by the measured-hazard floor (the watch channel
  /// already speaks the specific hazard), and a heightened rise whose only
  /// advisor reason is unknown/stale visibility (an honest displayed state,
  /// never an alarm to blare on every sensorless drive).
  ///
  /// The speak-gate rises off [_lastSpokenRung] — the last rung actually SPOKEN
  /// — NOT off the effective rung. A muted rise therefore does not consume the
  /// announce slot: a later grounded caution at the same rung still speaks +
  /// buzzes. [_lastSpokenRung] is clamped DOWN whenever the
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
          spokenPrefix: spokenFromTestValue()
              ? _text.testValueSpokenPrefix(localeTag)
              : null,
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
  ///    watch channel already spoke the specific hazard; a second generic caution
  ///    line would be double-speak.
  ///  - a rise to `heightenedCaution` grounded by the advisor speaks ONLY when a
  ///    reason OTHER than unknown/stale visibility raised it. "We have no
  ///    visibility reading" is an honest DISPLAYED state (視程 未計測), never an
  ///    alarm to announce on every drive that lacks a visibility sensor
  ///    (cry-wolf).
  bool _shouldSpeakRise(DriveAdvice advice, DriveAction effective) {
    if (effective == DriveAction.considerStopping) return true;
    // effective == heightenedCaution here (continueDriving never reaches speak).
    // Rose solely from the measured floor → the watch channel already spoke it.
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
  /// This is what sets the app apart: a turn is spoken ONLY when the dot is
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
    bool positionIsThisShares = true,
    bool icyTurnFromTestValue = false,
  }) {
    final mode = _modeForNarration(positionIsThisShares);
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
        // The caller alone knows where [icyTurn] came from; when it is a value
        // nobody measured, the icy line is spoken as a test value.
        spokenPrefix: decision.icyCoupled && icyTurnFromTestValue
            ? _text.testValueSpokenPrefix(localeTag)
            : null,
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
    bool positionIsThisShares = true,
  }) {
    final mode = _modeForNarration(positionIsThisShares);
    return _narrator.decide(
      maneuver: maneuver,
      mode: mode,
      icyTurn: icyTurn,
      localeTag: localeTag,
    );
  }

  /// The position mode a maneuver is narrated against. When the caller says
  /// the estimate held is not this share's ([positionIsThisShares] false), it
  /// is narrated as `lost`: the controller is not reset between shares, and an
  /// earlier drive's trusted estimate says nothing about where she is now.
  LocalizationMode _modeForNarration(bool positionIsThisShares) =>
      positionIsThisShares
          ? _estimate?.mode ?? LocalizationMode.lost
          : LocalizationMode.lost;

  /// Map the advisory-only caution rung to the actuator severity gate.
  ///
  /// continueDriving → info (not announced); heightenedCaution → warning;
  /// considerStopping → critical. The announcer gates BOTH audio + haptic on
  /// `>= warning`, so a rung at or above heightened reaches the eyes-off AND
  /// the deaf / can't-hear-over-the-wind driver (accessibility floor).
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

  /// Whether the current EFFECTIVE rung is one the rung channel itself SPEAKS
  /// (vs one that is shown+coloured only while a watch channel speaks the specific
  /// hazard, or an unknown-visibility-only display). For an HONEST HUD status
  /// line: a floor-only heightened must NOT claim it auto-fired audio+haptic.
  /// `false` before any advice and for `continueDriving`.
  bool get effectiveRungIsSpokenByRung {
    final effective = _effectiveAction;
    final advice = _advice;
    if (effective == null || advice == null) return false;
    if (effective == DriveAction.continueDriving) return false;
    return _shouldSpeakRise(advice, effective);
  }
}
