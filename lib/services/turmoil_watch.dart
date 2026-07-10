/// Measured-turmoil (downpour / strong-wind) watch over the live JMA
/// observation — the W3 turmoil surface (BETA_PLAN; Chair-ratified
/// 2026-07-09: *"we do not assume but measure the actual weather. Not our
/// historical data."*).
///
/// Design, stated honestly (same grammar as the invisible-ice watch):
/// - Every input is a MEASURED JMA field: 10-minute precipitation (mm) and
///   10-minute mean wind (m/s). A missing field makes THAT channel
///   [TurmoilChannel.unknown] (判定不能) — never "clear". The two channels
///   abstain INDEPENDENTLY: a station reporting wind but not rain can still
///   warn about wind while saying, honestly, that rain is unknown.
/// - The caution is DERIVED from the measured values against JMA's published
///   intensity vocabulary and must always be labeled as an inference, never a
///   JMA statement. No historical or seasonal assumption enters anywhere.
/// - Delivery is possibility-graded wording at warning tier, transition-gated
///   by the caller (the cry-wolf discipline the invisible-ice announce uses).
///
/// Thresholds — grounded in JMA's own published tables, both read from
/// source 2026-07-10:
/// - RAIN: JMA「雨の強さと降り方」(www.jma.go.jp/jma/kishou/know/yougo_hp/
///   amehyo.html): 20 mm/h 以上 = 強い雨 —「ワイパーを速くしても見づらい」;
///   30 mm/h 以上 adds ハイドロプレーニング現象. AMeDAS reports 10-minute
///   precipitation, so the sustained-rate hourly equivalent is
///   `precipitation10mMm × 6`. That ×6 conversion is THIS APP'S derivation
///   (label it — JMA's table speaks in hourly rates). The caution fires at
///   hourly-equivalent ≥ 20.0 mm/h — the 強い雨 lower bound, deliberately NOT
///   the やや強い雨 band below it (cry-wolf discipline: when this row speaks,
///   it must matter).
/// - WIND: JMA「風の強さと吹き方」(kazehyo.pdf, same page family): 平均風速
///   10 m/s 以上 = やや強い風 —「高速運転中では横風に流される感覚を受ける」—
///   JMA's FIRST band with an explicit driving impact. AMeDAS wind IS a
///   10-minute mean — the same unit as the table's 平均風速; no conversion.
/// - 台風-class winds (暴風警報 etc.) and 大雨警報-class rain reach the app on
///   a SEPARATE lane: the JMA warnings feed (condition_aggregator_jma),
///   relayed verbatim as advisory cards. This watch is the measured-field
///   complement, not a substitute for JMA's own warnings.
library;

import '../jma_fetch.dart';

/// One measured channel's verdict.
enum TurmoilChannel {
  /// The measured value crosses the JMA-grounded caution threshold.
  caution,

  /// The measured value is present and below the threshold.
  clear,

  /// The station did not report this field — honest unknown, never "clear".
  unknown,
}

/// JMA 強い雨 lower bound in mm/h (雨の強さと降り方, read 2026-07-10).
const double kRainCautionHourlyEquivalentMmPerHour = 20.0;

/// JMA やや強い風 lower bound in m/s 平均風速 (風の強さと吹き方, read
/// 2026-07-10) — the first band with an explicit driving impact.
const double kWindCautionMeanMs = 10.0;

/// Outcome of one turmoil-watch evaluation: two independent measured
/// channels plus the verbatim values they were judged on (so the UI can
/// show the measurement beside the inference).
class TurmoilWatchState {
  final TurmoilChannel rain;
  final TurmoilChannel wind;

  /// Verbatim measured inputs (null = station did not report the field).
  final double? precipitation10mMm;
  final double? windMetersPerSecond;

  const TurmoilWatchState({
    required this.rain,
    required this.wind,
    required this.precipitation10mMm,
    required this.windMetersPerSecond,
  });

  /// True when at least one measured channel crossed its caution threshold.
  bool get anyCaution =>
      rain == TurmoilChannel.caution || wind == TurmoilChannel.caution;

  /// True when neither channel had a measurement to judge.
  bool get allUnknown =>
      rain == TurmoilChannel.unknown && wind == TurmoilChannel.unknown;
}

/// Evaluate the measured-turmoil watch from a verbatim JMA observation.
///
/// Pure and synchronous, like [evaluateInvisibleIceWatch] — the caller owns
/// fetch, state, and the transition-gated announce.
TurmoilWatchState evaluateTurmoilWatch(JmaObservation obs) {
  final precip = obs.precipitation10mMm;
  final wind = obs.windMetersPerSecond;

  final TurmoilChannel rainChannel;
  if (precip == null) {
    rainChannel = TurmoilChannel.unknown;
  } else if (precip * 6.0 >= kRainCautionHourlyEquivalentMmPerHour) {
    rainChannel = TurmoilChannel.caution;
  } else {
    rainChannel = TurmoilChannel.clear;
  }

  final TurmoilChannel windChannel;
  if (wind == null) {
    windChannel = TurmoilChannel.unknown;
  } else if (wind >= kWindCautionMeanMs) {
    windChannel = TurmoilChannel.caution;
  } else {
    windChannel = TurmoilChannel.clear;
  }

  return TurmoilWatchState(
    rain: rainChannel,
    wind: windChannel,
    precipitation10mMm: precip,
    windMetersPerSecond: wind,
  );
}

/// The 荒天ウォッチ row text — ja, verdict + honest per-channel bounds.
///
/// Wording notes (domain faithfulness):
/// - 「強い雨」 is used only when the hourly-equivalent crosses JMA's 強い雨
///   bound (that is exactly the threshold above).
/// - 「強めの風」 deliberately does NOT borrow JMA's 強い風 class name —
///   10 m/s is JMA's やや強い風 band; claiming 強い風 (15 m/s+) would
///   overstate the measurement.
/// - A channel with no measurement is named 判定不能, even when the other
///   channel is clear — absence of data is never displayed as safety.
String turmoilRowText(TurmoilWatchState s) {
  final rainCaution = s.rain == TurmoilChannel.caution;
  final windCaution = s.wind == TurmoilChannel.caution;
  if (rainCaution && windCaution) return '⚠ 強い雨・強めの風を観測中';
  if (rainCaution) {
    return s.wind == TurmoilChannel.unknown
        ? '⚠ 強い雨を観測中（風は判定不能）'
        : '⚠ 強い雨を観測中';
  }
  if (windCaution) {
    return s.rain == TurmoilChannel.unknown
        ? '⚠ 強めの風を観測中（降水は判定不能）'
        : '⚠ 強めの風を観測中';
  }
  if (s.allUnknown) return '判定不能（降水・風の観測値が不足）';
  if (s.rain == TurmoilChannel.unknown) return '該当なし（降水は判定不能）';
  if (s.wind == TurmoilChannel.unknown) return '該当なし（風は判定不能）';
  return '該当なし';
}

/// Spoken caution line for a turmoil transition — possibility-graded and
/// action-coupled, in the resolved spoken locale.
///
/// App-authored strings (no catalog announcement exists yet for measured
/// downpour/wind — registered as a §B catalog follow-on). Consequences are
/// stated as おそれ/may (possibility-graded), and every line couples to a
/// concrete driver action, mirroring the catalog announcement grammar.
///
/// Returns null when no channel is in caution (nothing to announce).
String? turmoilSpokenText(TurmoilWatchState s, {required bool ja}) {
  final rainCaution = s.rain == TurmoilChannel.caution;
  final windCaution = s.wind == TurmoilChannel.caution;
  if (rainCaution && windCaution) {
    return ja
        ? '強い雨と強めの風を観測しています。視界の悪化と横風のおそれがあります。'
            '速度を落とし、車間距離をとって慎重に運転してください。'
        : 'Heavy rain and strong wind observed. Visibility may drop and '
            'crosswind may push the vehicle. Reduce speed, keep extra '
            'distance, and drive with caution.';
  }
  if (rainCaution) {
    return ja
        ? '強い雨を観測しています。視界の悪化や、水たまりによるスリップの'
            'おそれがあります。速度を落とし、車間距離をとってください。'
        : 'Heavy rain observed. Visibility may drop and standing water may '
            'cause slipping. Reduce speed and keep extra distance.';
  }
  if (windCaution) {
    return ja
        ? '強めの風を観測しています。横風に流されるおそれがあります。'
            'ハンドルをしっかり握り、速度を落としてください。'
        : 'Strong wind observed. Crosswind may push the vehicle. Grip the '
            'wheel firmly and reduce speed.';
  }
  return null;
}
