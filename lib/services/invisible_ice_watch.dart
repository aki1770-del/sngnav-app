/// Invisible-ice (radiative-frost) watch over the live JMA observation.
///
/// THE gap this closes (BETA_PLAN W1; bond #3 reach): the catalog's
/// shared classifier can detect the Akita pre-dawn black-ice window —
/// clear sky, ambient a few degrees ABOVE zero, road surface frozen,
/// road looking merely wet or dry — but this app never fed it the real
/// JMA humidity, so the detection always abstained on the phone.
///
/// Design, stated honestly:
/// - Every input is a MEASURED JMA field (temperature, humidity,
///   10-minute precipitation). Any of them missing → the watch
///   ABSTAINS ([InvisibleIceWatchResult.unknown]) — never fabricates
///   a hazard, never fabricates safety (a first-class unknown, same
///   discipline as the drive HUD's "no reading").
/// - The frozen/not-frozen determination is the catalog's SHARED
///   classifier (`RoadSurfaceState.fromCondition`, snow_rendering
///   0.2.7) — the same single source of truth the pre-trip advisor and
///   the SNGNav in-drive surface use, so this app cannot disagree with
///   them given the same inputs. In the no-precipitation branch the
///   classifier reads exactly temperature + humidity; the neutral
///   filler fields below are never consulted on that branch.
/// - Above 0 °C, no precipitation → the radiative-frost classifier (the
///   invisible-SURPRISE window, [watch]). Sub-zero ambient, no precipitation
///   → [subZeroFrozen], the EXPECTED-frozen regime, with its own honest
///   possibility-graded line — it warns, distinctly from [watch]. (Until
///   2026-07-23 sub-zero was excluded under a cry-wolf contract; the Chair's
///   calibration ruling addressed it. The anti-cry-wolf discipline survives in
///   the DELIVERY, not the exclusion: the sub-zero line is spoken ONCE on
///   entry, possibility-graded, and does not pin the eyes-off rung.)
///   Warning-tier (not critical): an ambient inference, not a surface reading.
library;

import 'package:driving_conditions/driving_conditions.dart'
    show RoadSurfaceState;
import 'package:driving_weather/driving_weather.dart';

import '../jma_fetch.dart';

/// Outcome of one watch evaluation.
enum InvisibleIceWatchResult {
  /// Radiative-frost window detected from measured fields.
  watch,

  /// Measured fields say the window is not present.
  ///
  /// This is a MEASURED negative: every required field was reported, the
  /// conditions were inside this watch's scope, and the shared classifier
  /// determined the radiative-frost window is absent. Only this value may
  /// ever be rendered as 該当なし.
  clear,

  /// The measured conditions are OUTSIDE this watch's scope, so it renders
  /// no verdict about them — neither hazard nor safety.
  ///
  /// ONE app-policy gate now lands here: measured precipitation (this watch
  /// covers the no-precipitation window only — the visible-hazard lanes own a
  /// wet/snowy road). It was previously folded into [clear], which rendered a
  /// SCOPE EXCLUSION to the driver as an affirmative all-clear — 該当なし under
  /// the label 路面凍結ウォッチ (Andon 2026-07-20T13:40Z, the fabricated-clear
  /// failure class this project corrected three times).
  ///
  /// SUB-ZERO NO LONGER LANDS HERE. Until 2026-07-23 sub-zero ambient was also
  /// routed to [outOfScope] under a cry-wolf contract; on the Chair's
  /// calibration ruling ("sub-zero warning yes do address it") it now returns
  /// [subZeroFrozen] and warns. See that value.
  outOfScope,

  /// Sub-zero ambient, no precipitation: the road surface is very likely
  /// frozen and the driver cannot judge it by eye.
  ///
  /// A DISTINCT verdict from [watch], deliberately. [watch] names the
  /// above-zero radiative-frost SURPRISE (the road looks wet/dry but is
  /// frozen); below zero the ice is EXPECTED, not a surprise, so it carries
  /// its own honest, possibility-graded line ([subZeroFrozenSpokenText]) and
  /// never the 「ブラックアイスバーン（放射冷却の窓）」 surprise wording, which
  /// would be a false claim here.
  ///
  /// Fires UNCONDITIONALLY on temp ≤ 0 with no precipitation — it does NOT
  /// gate on humidity. Two measured reasons: (1) the family's own single
  /// source of truth classifies a road frozen at temp ≤ −3 REGARDLESS of
  /// humidity (snow_rendering `road_surface_state.dart`: "Cold dry conditions
  /// can still have residual ice"), so a humidity gate would contradict the
  /// catalog's physics; (2) humidity is the most drop-prone JMA leaf, so
  /// gating on it would fail toward silence on the exact −2.4 °C Chuo morning
  /// (89% of slip accidents are on a frozen surface). Basis: Andon
  /// 2026-07-20T13:40Z + Chair calibration ruling 2026-07-23.
  subZeroFrozen,

  /// A required field (temperature / precipitation) was not reported — the
  /// watch abstains. Honest unknown, not "clear". (Humidity is required only
  /// for the above-zero radiative-frost classifier, NOT for the sub-zero
  /// verdict — see [evaluateInvisibleIceWatch].)
  unknown,
}

/// The live sub-zero frozen-surface warning — app-authored, possibility-graded,
/// and NON-slotted so open_jtalk can pre-render it into the offline mouth
/// (bundled id `sub_zero_frozen_live`; the mouth map holds this exact string so
/// the eyes-off driver HEARS it in a dead zone, and a test asserts they match).
///
/// Deliberately NOT the 「ブラックアイスバーン」 surprise line: below zero the ice
/// is EXPECTED, and the honest message is that the surface she cannot judge by
/// eye is very likely frozen — bridges and tunnel exits first (the Chuo
/// bridge-deck hazard). Leads with the MEASURED fact (気温が0°C以下です — matched
/// to the temp ≤ 0 firing predicate, NOT 「氷点下」, which would over-state a
/// reading of exactly 0.0 °C; impl-review honesty catch), possibility-graded
/// (可能性があります), then the action. Chair calibration 2026-07-23. Every
/// fragment reuses vocabulary already in the rendered mouth
/// (橋やトンネル出口 / 速度を落とし / 急ブレーキ・急ハンドル) to avoid a
/// 濡路-class open_jtalk silence trap.
String subZeroFrozenSpokenText({required bool ja}) => ja
    ? kSubZeroFrozenSpokenJa
    : 'The air temperature is at or below freezing. On bridges and at tunnel '
        'exits, the road surface may be frozen. Reduce your speed and avoid '
        'abrupt braking or steering.';

/// The exact ja string [subZeroFrozenSpokenText] speaks and the offline mouth
/// bundles under `sub_zero_frozen_live`. A top-level const so both reference one
/// literal; `offline_safety_voice_test.dart` asserts the mouth value matches.
const String kSubZeroFrozenSpokenJa =
    '気温が0°C以下です。橋の上やトンネルの出口では、路面が凍結している可能性があります。'
    '速度を落とし、急ブレーキ・急ハンドルは避けてください。';

/// Evaluate the invisible-ice window from a verbatim JMA observation.
InvisibleIceWatchResult evaluateInvisibleIceWatch(JmaObservation obs) {
  final temp = obs.temperatureCelsius;
  final humidity = obs.humidityPercent;
  final precip10m = obs.precipitation10mMm;

  // Temperature is required on every branch, and a NON-FINITE temperature is
  // never an all-clear — abstain (NaN <= 0 is false, so without this guard a
  // NaN would fall through to the above-zero classifier and return `clear` =
  // 該当なし on garbage, the fabricated-clear class; catalog-consistent with
  // isRadiativeFrostBlackIce's own !isFinite guard). (impl-review NICE,
  // 2026-07-23 — a defensive gap, unreachable via the current JSON path.)
  if (temp == null || !temp.isFinite) {
    return InvisibleIceWatchResult.unknown;
  }

  // MEASURED precipitation (> 0) is a SCOPE EXCLUSION — the visible-hazard
  // lanes own a wet/snowy road (see [outOfScope]). But a MISSING precip leaf
  // must NOT block the sub-zero warning: the frozen road is present under a
  // passing snow band or not, and the AMeDAS precip gauge is drop-prone in
  // exactly these conditions (it rimes/ices over on a clear sub-zero morning,
  // QC-flagged to null). This is the SAME leaf-drop-must-not-silence discipline
  // applied to humidity below — the impl-review caught it left open for precip:
  // a rimed gauge on the −2.4 °C Chuo morning would have returned silent
  // `unknown` (no voice, no rung) on a very likely frozen road. (impl-review
  // SHOULD, 2026-07-23.)
  if (precip10m != null && precip10m > 0) {
    return InvisibleIceWatchResult.outOfScope;
  }

  // Sub-zero ambient, no MEASURED precipitation: the road is very likely frozen
  // and she cannot tell by looking. Fires UNCONDITIONALLY (no humidity gate,
  // and robust to a dropped precip leaf) — see [subZeroFrozen]. A DISTINCT
  // verdict, never [watch]: below zero ice is EXPECTED, not the above-zero
  // radiative surprise.
  if (temp <= 0) return InvisibleIceWatchResult.subZeroFrozen;

  // Above zero: the radiative-frost window. Unlike the sub-zero branch it needs
  // the FULL measurement — no-precipitation CONFIRMED (precip measured == 0)
  // AND humidity — so abstain honestly if either is missing.
  if (precip10m == null || humidity == null) {
    return InvisibleIceWatchResult.unknown;
  }

  // Shared-classifier determination. Reads exactly (temperature, humidityRH);
  // the filler fields are not consulted on this branch. With ambient > 0 the
  // branch returns blackIce IFF the radiative-frost check fires.
  final surface = RoadSurfaceState.fromCondition(WeatherCondition(
    precipType: PrecipitationType.none,
    intensity: PrecipitationIntensity.none,
    temperatureCelsius: temp,
    visibilityMeters: 10000, // unused on the no-precip branch
    windSpeedKmh: 0, // unused on the no-precip branch
    humidityRH: humidity.toDouble(),
    timestamp: obs.fetchedAt,
  ));
  return surface == RoadSurfaceState.blackIce
      ? InvisibleIceWatchResult.watch
      : InvisibleIceWatchResult.clear;
}

/// Honest stale-framed black-ice line (W0 detection-survival). App-authored;
/// NEVER spoken as live. [hourJst] is the FLOORED hour of the retained
/// observation's observedAt (JST) — see `spokenHourJst`; floored so the spoken
/// stamp never sounds fresher than the reading. See W0_DETECTION_SURVIVAL_DESIGN.md §4.
///
/// Two load-bearing clauses that MUST NOT be dropped under length pressure:
/// - 「○時頃の観測では…おそれがあります」 — past-framed + possibility-graded; it is
///   unmistakably an observation from a PAST hour, never a live reading.
/// - 「最新の情報は取得できていません」 — the explicit not-live disclaimer; it is the
///   ONLY spoken guarantee HER is not hearing a current reading (review #1).
String staleInvisibleBlackIceSpokenText({
  required int hourJst,
  required bool ja,
}) {
  return ja
      ? '$hourJst時頃の観測では、ブラックアイスバーンのおそれがあります。'
          '最新の情報は取得できていません。'
          '急ハンドル・急ブレーキを避け、速度を落としてください。'
      : 'As observed around $hourJst o\'clock, there may be black ice — this is '
          'not a live reading. Avoid abrupt steering or braking, and reduce '
          'speed.';
}
