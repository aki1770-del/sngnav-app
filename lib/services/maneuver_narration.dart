/// (e) NARROW honest confidence-gated maneuver narration — the HER differentiator.
///
/// **Why this exists (mission trace, <=4 hops).** HER — the Chair's mother in
/// Akita — is driving in unexpected snow. Maps and GPS are failing. A turn-by-
/// turn instruction spoken against a DRIFTING or LOST position dot is a
/// *confidently-wrong* command: "turn right now" when the app does not actually
/// know where she is can send her off a plowed road into a ditch. That is the
/// exact hazard `localization_fallback` + the finite-position guard exist to
/// kill. So this narrator does the one thing neither Ferrostar nor Valhalla
/// does: it GATES the spoken maneuver on the honest position confidence —
///   trusted GPS  → SPEAK the turn plainly,
///   suspect GPS  → HEDGE (soften, tell her to confirm before acting),
///   dead-reckoning / lost → SUPPRESS (say NOTHING about the turn — honest
///                            silence, never a wrong "turn now").
///   narrator (this file) → honest guidance reaches HER → she turns only when
///   the dot is trustworthy → HER survives the whiteout.
///
/// **This is NOT a nav state machine.** No route-snapping, no off-route
/// detection, no recompute-on-deviation. It takes the NEXT maneuver from the
/// already-parsed `routing_engine` list and decides, for the CURRENT honest
/// position mode, whether/how to say it. Small by design.
///
/// **The seam.** `routing_engine` emits [RouteManeuver]; the catalog's
/// `voice_guidance.ManeuverSpeechFormatter` consumes
/// `navigation_safety.NavigationManeuver`. The two types are field-identical, so
/// [toNavigationManeuver] adapts one to the other in a single copy (proven by
/// test). We do NOT, however, route HER's spoken line through
/// `ManeuverSpeechFormatter`: that formatter returns the maneuver's `instruction`
/// VERBATIM when non-empty, and `OsrmRoutingEngine` emits ENGLISH instructions
/// ("Left onto Main St") — shipping English to a Japanese-reading driver is a D4
/// breach. So the app localizes by engine-agnostic maneuver TYPE via
/// [DriveHudLocalizer] (JA for HER), and carries the adapted [NavigationManeuver]
/// alongside for any consumer that wants the catalog type. That is the honest
/// reconciliation: adapt the type, but localize the words ourselves.
///
/// **Honesty (OPS-066 / AAE-1).** The speak/hedge/suppress DECISION is pure and
/// fully provable off-device (this file's tests). Whether HER actually HEARS the
/// line, and the real-world turn-trigger TIMING, are device-observable and
/// DEFERRED — never claimed as "guidance works" from a green suite.
library;

import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity, NavigationManeuver, RoadSurfaceCondition;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;

import 'drive_hud_localizer.dart';

/// The three honest outcomes of the position-confidence gate.
enum NarrationConfidence {
  /// Position is trusted — the turn is spoken plainly.
  speak,

  /// Position is suspect — the turn is softened and HER is told to confirm.
  hedge,

  /// Position is dead-reckoned or lost — the turn is NOT announced. Honest
  /// silence, never a confidently-wrong "turn now".
  suppressed,
}

/// The decision the gate returns for one (maneuver, position-mode) pair.
///
/// Invariant enforced by construction: when [confidence] is
/// [NarrationConfidence.suppressed], [shouldAnnounce] is `false`, [text] is the
/// empty string, and [severity] is [AlertSeverity.info] (below the announcer's
/// speak gate) — a suppressed decision can carry NO turn instruction, because
/// the suppressing factory never builds one.
class ManeuverNarration {
  const ManeuverNarration._({
    required this.shouldAnnounce,
    required this.confidence,
    required this.mode,
    required this.text,
    required this.severity,
    required this.icyCoupled,
    required this.routeManeuver,
    required this.navigationManeuver,
  });

  /// A SPEAK / HEDGE decision that WILL be announced. Only ever built from the
  /// trusted/suspect branches, so it always carries a real localized line.
  factory ManeuverNarration._announce({
    required NarrationConfidence confidence,
    required LocalizationMode mode,
    required String text,
    required AlertSeverity severity,
    required bool icyCoupled,
    required RouteManeuver routeManeuver,
    required NavigationManeuver navigationManeuver,
  }) {
    assert(confidence != NarrationConfidence.suppressed);
    return ManeuverNarration._(
      shouldAnnounce: true,
      confidence: confidence,
      mode: mode,
      text: text,
      severity: severity,
      icyCoupled: icyCoupled,
      routeManeuver: routeManeuver,
      navigationManeuver: navigationManeuver,
    );
  }

  /// The SUPPRESS decision. Hard-codes: not announced, empty text, info
  /// severity. **No maneuver phrase is ever constructed on this path** — this
  /// is the structural guarantee that a lost / dead-reckoning dot cannot
  /// produce a "turn now" instruction.
  factory ManeuverNarration._suppressed({
    required LocalizationMode mode,
    required RouteManeuver routeManeuver,
    required NavigationManeuver navigationManeuver,
  }) {
    return ManeuverNarration._(
      shouldAnnounce: false,
      confidence: NarrationConfidence.suppressed,
      mode: mode,
      text: '',
      severity: AlertSeverity.info,
      icyCoupled: false,
      routeManeuver: routeManeuver,
      navigationManeuver: navigationManeuver,
    );
  }

  /// Whether the announcer should be fired for this decision.
  final bool shouldAnnounce;

  /// The honest confidence tier this maneuver was narrated at.
  final NarrationConfidence confidence;

  /// The position mode that produced [confidence].
  final LocalizationMode mode;

  /// The localized (JA for HER) line to speak. Empty iff suppressed.
  final String text;

  /// The severity to announce at (drives the audibility gate + haptic cue).
  /// `warning` for a plain/hedged turn, `critical` when icy-coupled, `info`
  /// (unspoken) when suppressed.
  final AlertSeverity severity;

  /// Whether the icy-turn advisory was coupled onto the line.
  final bool icyCoupled;

  /// The source maneuver from `routing_engine`.
  final RouteManeuver routeManeuver;

  /// The same maneuver adapted to the catalog's `navigation_safety` type (the
  /// seam), carried for any consumer that wants it.
  final NavigationManeuver navigationManeuver;
}

/// Adapt a `routing_engine` [RouteManeuver] to the catalog's
/// `navigation_safety_core` [NavigationManeuver].
///
/// The two are field-identical (index / instruction / type / lengthKm /
/// timeSeconds / position), so this is a single lossless copy — the whole seam.
NavigationManeuver toNavigationManeuver(RouteManeuver m) => NavigationManeuver(
      index: m.index,
      instruction: m.instruction,
      type: m.type,
      lengthKm: m.lengthKm,
      timeSeconds: m.timeSeconds,
      position: m.position,
    );

/// Pick the next maneuver worth narrating from a parsed route.
///
/// No progress tracking (no route-snapping — see the file doc): this simply
/// returns the first ACTIONABLE maneuver — i.e. the first that is not the
/// `depart` bookend. If the only maneuvers are `depart`/`arrive`, the `arrive`
/// is returned; if the list is empty, `null`.
RouteManeuver? nextActionableManeuver(List<RouteManeuver> maneuvers) {
  for (final m in maneuvers) {
    if (m.type != 'depart') return m;
  }
  return maneuvers.isEmpty ? null : maneuvers.last;
}

/// THE CORE: the position-confidence gate over maneuver narration.
///
/// Pure + injectable. Given a maneuver and the CURRENT honest position [mode],
/// [decide] returns a [ManeuverNarration] whose [NarrationConfidence] is fixed
/// solely by the mode (see [_confidenceFor]).
class ManeuverNarrator {
  const ManeuverNarrator({this.text = const DriveHudLocalizer()});

  /// The driver-facing string localizer (JA for HER). Reused for the maneuver
  /// phrasing AND the icy-turn coupling.
  final DriveHudLocalizer text;

  /// Decide whether/how to narrate [maneuver] at the current honest [mode].
  ///
  /// [icyTurn] couples the icy-turn advisory ("...the turn may be icy") when a
  /// maneuver coincides with an ice / low-visibility hazard — but ONLY on a
  /// spoken/hedged path; a suppressed maneuver stays silent (the position
  /// caution is surfaced separately by `DriveHudController`).
  ManeuverNarration decide({
    required RouteManeuver maneuver,
    required LocalizationMode mode,
    required bool icyTurn,
    String localeTag = 'ja',
  }) {
    final navigationManeuver = toNavigationManeuver(maneuver);
    final confidence = _confidenceFor(mode);

    switch (confidence) {
      case NarrationConfidence.suppressed:
        // STRUCTURAL SUPPRESS: return WITHOUT building any maneuver phrase.
        // There is no code path here that can emit a directional instruction,
        // so a `lost` / `deadReckoning` dot can never produce "turn now".
        return ManeuverNarration._suppressed(
          mode: mode,
          routeManeuver: maneuver,
          navigationManeuver: navigationManeuver,
        );

      case NarrationConfidence.speak:
        var line = text.maneuverInstruction(maneuver.type, localeTag);
        if (icyTurn) line = text.icyManeuverCoupling(line, localeTag);
        return ManeuverNarration._announce(
          confidence: confidence,
          mode: mode,
          text: line,
          severity: icyTurn ? AlertSeverity.critical : AlertSeverity.warning,
          icyCoupled: icyTurn,
          routeManeuver: maneuver,
          navigationManeuver: navigationManeuver,
        );

      case NarrationConfidence.hedge:
        var line = text.hedgedManeuverInstruction(maneuver.type, localeTag);
        if (icyTurn) line = text.icyManeuverCoupling(line, localeTag);
        return ManeuverNarration._announce(
          confidence: confidence,
          mode: mode,
          text: line,
          severity: icyTurn ? AlertSeverity.critical : AlertSeverity.warning,
          icyCoupled: icyTurn,
          routeManeuver: maneuver,
          navigationManeuver: navigationManeuver,
        );
    }
  }

  /// The gate proper: honest position mode → narration confidence.
  ///
  /// This one exhaustive switch is the whole safety contract. `deadReckoning`
  /// and `lost` BOTH map to [NarrationConfidence.suppressed] — the app never
  /// speaks a turn it cannot honestly place.
  static NarrationConfidence _confidenceFor(LocalizationMode mode) =>
      switch (mode) {
        LocalizationMode.gpsTrusted => NarrationConfidence.speak,
        LocalizationMode.gpsSuspect => NarrationConfidence.hedge,
        LocalizationMode.deadReckoning => NarrationConfidence.suppressed,
        LocalizationMode.lost => NarrationConfidence.suppressed,
      };
}

/// True when the road surface is genuinely slippery — the ONLY condition under
/// which the icy-turn advisory is honestly coupled onto a maneuver (the coupling
/// text is ice-specific: "路面が凍結 / the turn may be icy"). Deliberately NOT
/// triggered by a heightened-caution state or low visibility alone (a dry road,
/// even under a suspect GPS fix, must never raise a false CRITICAL icy warning;
/// low visibility is warned separately by the drive HUD).
bool isSlipperySurface(RoadSurfaceCondition condition) =>
    condition == RoadSurfaceCondition.ice ||
    condition == RoadSurfaceCondition.wetIce ||
    condition == RoadSurfaceCondition.snow ||
    condition == RoadSurfaceCondition.slush;
