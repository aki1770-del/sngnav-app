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
/// - Two app-policy gates mirror the SNGNav status-bar alert gate:
///   measured no-precipitation (10-min rain/snow = 0.0) and ambient
///   ABOVE 0 °C. Sub-zero ambient stays out of THIS alert (the
///   sub-zero cry-wolf contract: nearly every freezing reading passes
///   the dew-point check, and alerting on all of them trains the
///   driver to dismiss the one that matters). Possibility-graded
///   wording + warning-tier delivery for the same reason.
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
  clear,

  /// A required field (temperature / humidity / precipitation) was not
  /// reported — the watch abstains. Honest unknown, not "clear".
  unknown,
}

/// Evaluate the invisible-ice window from a verbatim JMA observation.
InvisibleIceWatchResult evaluateInvisibleIceWatch(JmaObservation obs) {
  final temp = obs.temperatureCelsius;
  final humidity = obs.humidityPercent;
  final precip10m = obs.precipitation10mMm;
  if (temp == null || humidity == null || precip10m == null) {
    return InvisibleIceWatchResult.unknown;
  }

  // App-policy gates (mirror of the SNGNav status-bar alert gate).
  if (precip10m > 0) return InvisibleIceWatchResult.clear;
  if (temp <= 0) return InvisibleIceWatchResult.clear;

  // Shared-classifier determination. Only the no-precipitation branch is
  // reachable here, and it reads exactly (temperature, humidityRH); the
  // filler fields are not consulted on that branch. With ambient > 0 the
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
