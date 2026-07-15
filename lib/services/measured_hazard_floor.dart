/// MEASURED-HAZARD FLOOR — let HER own MEASURED local weather RAISE the eyes-off
/// compound caution rung, without fabricating a measurement and without crying
/// wolf.
///
/// ── THE DEFECT THIS CLOSES (measured 2026-07-15) ─────────────────────────────
/// The app runs two measured watches over the live JMA observation — the
/// invisible-ice (radiative-frost black-ice) watch and the turmoil (strong
/// rain / strong wind) watch. Both announce on their own lane. But the
/// **compound-failure caution rung** — the one HUD banner + severity + haptic
/// HER reacts to with her eyes on the invisible road — is computed by
/// `compound_failure_advisor` from position-trust × visibility × advisory ×
/// speed ONLY. It never sees the two watches. So a MEASURED black-ice window
/// can be firing on-screen while the eyes-off rung banner still reads
/// 「走行を継続」(continue). The loudest channel contradicts the measurement, in
/// exactly the compound-failure night this whole app exists for.
///
/// ── WHAT THIS DOES, AND WHAT IT REFUSES TO DO ────────────────────────────────
/// It maps an ALREADY-FIRING measured watch onto the minimum rung that measured
/// hazard honestly justifies, and lets the app take `max(advisorRung, floor)`.
/// It is caution-add-only: it can only ever RAISE the advisor's rung, never
/// lower it.
///
/// It does NOT:
///   - fabricate a visibility number from the watch (that would be the BOD-19
///     "convert absence of data into a measurement never taken" breach; the
///     turmoil watch measures wind/rain, NOT a metres-of-visibility reading, so
///     it may never be poured into the advisor's `visibilityMeters` input);
///   - invent a fourth "turn back / abort" rung (the ladder is three by
///     construction — the worst case demotes the MAP, never the JOURNEY to her
///     mother);
///   - speak (the watch lane already speaks the specific hazard line — see the
///     announce gate in `DriveHudController`, which suppresses a duplicate
///     spoken line for a rise caused solely by this floor).
///
/// ── THE ONE NON-LINEARITY (analogous to the advisor's compounding rule) ──────
/// A firing measured watch ALONE (position locatable) justifies
/// [DriveAction.heightenedCaution] — a measured road/weather hazard asks for
/// margin, not a stop. But a measured road hazard she cannot even LOCATE —
/// firing watch AND an UNLOCATABLE position (dead-reckoning or lost) at once — is
/// precisely the stacking danger the ceiling exists for, so it compounds to
/// [DriveAction.considerStopping].
///
/// Honest bound (OPS-068): this is ANALOGOUS to, NOT identical to, the advisor's
/// own `position-concern>=2 AND visibility-concern>=2 → considerStopping` rule.
/// The measured hazard stands in for the visibility axis, and "unlocatable" (the
/// caller passes dead-reckoning/lost, position-concern>=2) stands in for the
/// position axis. It deliberately does NOT fire on a fresh, small-radius
/// SUSPECT fix (concern 1): a hazard on a still-locatable dot is heightened, not
/// a stop. The caller is responsible for passing the stricter "unlocatable"
/// condition (the app derives it from the honest localization MODE), so this
/// pure function never over-reaches to the ceiling on a locatable position.
///
/// Pure Dart: total, deterministic, synchronous. No Flutter, no IO, no clock —
/// fully testable off a device.
///
/// **Mission trace (<=4 hops).** measured black-ice/turmoil raises the eyes-off
/// caution rung → the compound-failure caution SECTION no longer shows a
/// 「走行を継続」banner over a firing hazard, and a hazard-she-cannot-locate
/// reaches "consider stopping" → she eases / pauses on real local weather she
/// cannot self-detect → HER survives the compound-failure night.
///
/// **Reach bound, honest (OPS-068).** The fusion LOGIC is built + tested and its
/// audible compound escalation reaches through the app's single actuator (audio
/// + OPS-059 haptic). Its VISIBLE banner currently renders in the alpha app's
/// WS6 "Live drive — compound-failure caution" section, NOT yet a dedicated
/// full-screen driver HUD (BETA_PLAN drive-loop; tracked-not-shipped), and the
/// on-device HEAR/FEEL is DEFERRED (no device in this env). It reaches HER's
/// phone only in the next APK build.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;

/// A measured local-weather hazard the app has ALREADY computed from live JMA
/// fields — never a synthesised or assumed hazard. Exactly one value describes
/// the current fused floor; when more than one watch fires, the caller picks the
/// stronger (see [measuredWeatherHazardFrom]).
enum MeasuredWeatherHazard {
  /// No measured watch is firing (or the fields were unknown → the watch
  /// abstained). Contributes NO floor — absence of a firing watch is never a
  /// claim of safety, it is simply the absence of a raise.
  none,

  /// The invisible-ice (radiative-frost black-ice) watch is in its `watch`
  /// state: a measured road-surface hazard.
  blackIce,

  /// The turmoil watch has at least one measured channel in caution (strong
  /// rain and/or strong wind): a measured visibility/control hazard.
  ///
  /// Deliberate choice (OPS-068): turmoil floors IDENTICALLY to [blackIce],
  /// including the compound considerStopping ceiling — even for the mildest
  /// firing channel (JMA's 10 m/s やや強い風, the first band with a driving
  /// impact). This is caution-add-only and intentional: a crosswind or a
  /// hydroplaning downpour a driver cannot even locate herself in is a stop-
  /// worthy compound. It is NOT lowered.
  turmoil,
}

/// Fuse a measured-weather [hazard] onto the advisor's rung, returning the
/// EFFECTIVE rung the HUD + severity + haptic should reflect.
///
/// - [hazard] `none` → the advisor's rung is returned unchanged.
/// - a firing hazard with [positionUnlocatable] `false` floors at
///   [DriveAction.heightenedCaution].
/// - a firing hazard with [positionUnlocatable] `true` compounds to
///   [DriveAction.considerStopping].
///
/// The result is `max(advisorAction, floor)` on the monotonic ladder, so this
/// can only ever RAISE caution (caution-add-only). [positionUnlocatable] must be
/// the STRICT condition (the honest position is dead-reckoning or lost) — NOT
/// merely `DriveAdvice.positionUncertain`, which also covers a fresh, still-
/// locatable SUSPECT fix that should stay at the heightened floor (OPS-068). The
/// app derives it from the localization MODE.
DriveAction fuseMeasuredWeather({
  required DriveAction advisorAction,
  required MeasuredWeatherHazard hazard,
  required bool positionUnlocatable,
}) {
  if (hazard == MeasuredWeatherHazard.none) return advisorAction;
  final DriveAction floor = positionUnlocatable
      ? DriveAction.considerStopping
      : DriveAction.heightenedCaution;
  return advisorAction.index >= floor.index ? advisorAction : floor;
}

/// Collapse the two measured-watch verdicts into one [MeasuredWeatherHazard].
///
/// Takes plain booleans (not the watch types) so this module stays pure of the
/// app's service layer: the caller passes
/// `blackIceFiring = _invisibleIceResult == InvisibleIceWatchResult.watch` and
/// `turmoilFiring  = _turmoilState?.anyCaution ?? false`.
///
/// Both firing floor IDENTICALLY (both to heightenedCaution alone, both to
/// considerStopping when compounded), so the precedence here is only for the
/// value's LABEL — black-ice, the harder-to-see surface hazard, is named first.
/// The ranking never lowers the floor.
MeasuredWeatherHazard measuredWeatherHazardFrom({
  required bool blackIceFiring,
  required bool turmoilFiring,
}) {
  if (blackIceFiring) return MeasuredWeatherHazard.blackIce;
  if (turmoilFiring) return MeasuredWeatherHazard.turmoil;
  return MeasuredWeatherHazard.none;
}
