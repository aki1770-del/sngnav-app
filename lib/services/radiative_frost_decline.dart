/// The radiative-frost DECLINE predicate — the app's single source of truth
/// for "did the shared classifier decline to judge, or judge and find no
/// frost?".
///
/// EXTRACTED 2026-08-06 from `invisible_ice_watch.dart`, where it was defined,
/// so that `road_surface_classifier.dart` can call the SAME predicate without
/// importing the JMA fetch path. This is a MOVE, not a copy: there is still
/// exactly one implementation. The calibration package forbids a second copy of
/// this threshold logic by name (cal:123-129), and `pubspec.yaml` repeats the
/// prohibition — "Two independently-maintained copies of this threshold logic
/// ARE that disagreement waiting to happen". `invisible_ice_watch.dart`
/// re-exports this library, so every existing import keeps working unchanged.
///
/// Pure Dart. No Flutter, no network, no fetch path.
library;

// The coverage boundary is CALLED, never re-derived — the calibration package
// forbids a second copy of this threshold logic by name (cal:123-129).
import 'package:navigation_safety_calibration/navigation_safety_calibration.dart'
    show
        computeEffectiveTemperatureCelsius,
        radiativeFrostAmbientCeilingCelsius,
        radiativeFrostSurfaceTempCelsius;

/// The JMA AMeDAS temperature reporting step, °C.
///
/// A property of the FEED, not of the calibration — so it lives here, beside
/// the fetch path that relays it. It bounds the ceiling band in
/// [radiativeFrostJudgementDeclined]: two readings one step apart are the
/// finest distinction this feed can express, and the row may not flip from a
/// hazard warning to an affirmative 該当なし across it.
const double kJmaTemperatureStepCelsius = 0.1;

/// Did the shared radiative-frost classifier DECLINE to judge this reading,
/// rather than judge it and find no frost?
///
/// `isRadiativeFrostBlackIce` returns a bare `bool`, so structurally different
/// `false`s collapse into one value (navigation_safety_calibration 0.1.3,
/// `humidity_dependent_temperature.dart`, cited below as cal:NNN):
///
///  * cal:163 — RH null / non-finite / outside `[5, 105]`: the input is
///    REJECTED and the model never looks. The package calls sub-5 % RH
///    "almost certainly a mis-wired FRACTION" (cal:146-151). DECLINE.
///  * cal:158 — a non-finite ambient is likewise a rejected input. DECLINE.
///  * cal:174 — the effective surface estimate is ABOVE 0 °C: the documented
///    non-coverage band — verbatim, "near-zero SATURATED FREEZING FOG above
///    ~ +1 °C (dew point >= 0) is therefore NOT detected by this model — a
///    genuine hazard this function does not cover" (cal:112-115). DECLINE.
///  * cal:159 — ambient above [radiativeFrostAmbientCeilingCelsius]: a
///    DETERMINATION, not a decline. cal:88-90 gives it an affirmative reason
///    ("keeps the classification inside the physics the calibration
///    documents", naming the 20 °C / 25 % RH false positive it prevents), and
///    cal:135-153's list of EVERY rejected input class does not contain it.
///    A bare 該当なし above the ceiling is EARNED — with ONE bounded exception.
///
/// THE CEILING BAND. Exactly at the ceiling the determination is the constant,
/// not the evidence. Measured 2026-08-01: at 3.0 °C / 30 % RH the model's own
/// estimate is −12.914 °C and the row WARNS; at the NEXT REPRESENTABLE DOUBLE
/// the estimate is unchanged to 15 significant figures
/// (−12.914063344967174 → −12.914063344967172; Δ 1.8e-15 °C — nothing physical
/// changed) and the row printed an affirmative 該当なし. That flip spans 76 of
/// the 96 in-domain humidities; worst cell
/// 3.1 °C / 5 % RH with the estimate at −33.05 °C. So: within
/// [kJmaTemperatureStepCelsius] of the ceiling, where the feed cannot express a
/// finer distinction, we say we did not judge — REGARDLESS of the estimate's
/// sign, because both in-band reasons are declines (see the in-band branch).
///
/// An earlier draft abstained in-band only when the estimate was at or below
/// freezing. That left 20 cells at 3.1 °C / RH 81–100 % printing a bare 該当なし
/// with the estimate ABOVE freezing — the non-coverage band cal:112-115 names
/// verbatim. The fabricated-clear survived inside its own countermeasure until
/// the 2026-08-01 review caught it.
///
/// The band is ONE step wide DELIBERATELY. Unbounded ("estimate <= 0 above the
/// ceiling") covers ~95,000 measured cells including 20 °C / 25 % RH — the
/// exact cry-wolf the ceiling exists to prevent, re-imported through the back
/// door; the estimate stays <= 0 up to 17.81 °C at 30 % RH. Banded: ~760.
///
/// HONEST BOUND: this removes the warning→all-clear ADJACENCY. It does not
/// certify the +3.0 °C ceiling, whose only provenance is the package's own
/// prose. The residual non-claim→claim step one rung higher (3.1 → 3.2) is
/// recorded, not fixed; the durable repair is a tri-state upstream so the
/// classifier can say "I declined" instead of returning a bare `bool`.
///
/// Total and non-throwing on every input, like the classifier it mirrors.
bool radiativeFrostJudgementDeclined({
  required double t,
  required double? rhPercent,
}) {
  if (!t.isFinite) return true; // cal:158 — REJECTED input
  if (t <= 0) return false; // sub-zero never reaches the above-zero branch

  final aboveCeiling = t > radiativeFrostAmbientCeilingCelsius;
  if (aboveCeiling &&
      t > radiativeFrostAmbientCeilingCelsius + kJmaTemperatureStepCelsius) {
    return false; // cal:159 — DETERMINATION, clear of the band
  }

  // IN THE BAND: every cell is a decline, regardless of the estimate's sign.
  //
  // CORRECTED 2026-08-01 (review MUST-5/MUST-8, both CONFIRMED under
  // adversarial refutation). This branch previously abstained only when
  // `dew <= 0`, which left 20 cells at t = 3.1 °C / RH 81–100 % printing a bare
  // 該当なし while the model's own estimate was ABOVE freezing (+0.155 …
  // +3.10 °C) — i.e. inside cal:112-115's documented non-coverage band,
  // verbatim "a genuine hazard this function does not cover". Those cells had
  // TWO independent decline reasons and the code honoured neither: the
  // fabricated-clear this whole change exists to end, surviving inside its own
  // countermeasure, one JMA step from cells that correctly abstain.
  //
  // Both in-band reasons are declines and neither is a determination:
  //   dew <= 0 — the CONSTANT, not the evidence, ended the warning;
  //   dew  > 0 — cal:112-115's non-coverage band.
  // The band is one feed step wide, so this abstains over at most 0.1 °C.
  if (aboveCeiling) return true;

  // At or below the ceiling from here.
  final rh = rhPercent;
  if (rh == null || !rh.isFinite || rh < 5.0 || rh > 105.0) {
    return true; // cal:163 — REJECTED input, the model never looked
  }

  // cal:165 — the >100 clamp. NOT optional: the primitive THROWS on any
  // humidityRH > 1.0 (cal:65-71), so omitting this line CRASHES across
  // (100, 105], it does not merely disagree.
  final fraction = rh > 100.0 ? 1.0 : rh / 100.0;
  final dew = computeEffectiveTemperatureCelsius(
    ambientCelsius: t,
    humidityRH: fraction,
  );

  // At/below the ceiling: cal:174 fires on `<= 0`, so the non-fire complement
  // is `>` — the documented non-coverage band (cal:112-115). The in-band case
  // returned above, so `aboveCeiling` is necessarily false here.
  return dew > radiativeFrostSurfaceTempCelsius;
}
