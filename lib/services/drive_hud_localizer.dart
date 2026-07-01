/// WS6 — driver-facing localization for the in-drive caution surface.
///
/// `compound_failure_advisor` deliberately returns ENUMS, not prose, so the
/// integrator localizes for HER — the Chair's Japanese-reading mother in Akita.
/// This class is that localization: honest, calm, and faithful to the package's
/// doctrine.
///
/// Faithfulness that matters for HER safety:
///  - The ceiling rung is *consider stopping* — an INVITATION she owns, never a
///    command, and NEVER "turn back" (the package structurally has no turn-back
///    rung; the worst case demotes the MAP, never the JOURNEY to her mother).
///  - `continueDriving` is worded as *continue*, never "safe to continue" — it
///    is the ABSENCE of a raised concern, not an assertion of safety.
/// Both wordings are copied from the package's own `DriveAction` doc comments.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:localization_fallback/localization_fallback.dart';

/// Localizes the advisory-only in-drive vocabulary into HER language.
class DriveHudLocalizer {
  const DriveHudLocalizer();

  bool _isJa(String localeTag) => localeTag.toLowerCase().startsWith('ja');

  /// A short headline for the caution rung, for the on-screen HUD.
  String actionHeadline(DriveAction action, String localeTag) {
    final ja = _isJa(localeTag);
    switch (action) {
      case DriveAction.continueDriving:
        return ja ? '走行を継続' : 'Continue';
      case DriveAction.heightenedCaution:
        return ja ? '注意して走行' : 'Heightened caution';
      case DriveAction.considerStopping:
        return ja ? '停車の検討' : 'Consider stopping';
    }
  }

  /// The spoken / eyes-off guidance line handed VERBATIM to the announcer.
  ///
  /// Calm, honest, an invitation not a command — the ceiling never says "stop
  /// now" or "turn back". `continueDriving` returns an empty string because it
  /// is info-class and is not spoken (parity with the voice gate).
  String spokenGuidance(DriveAction action, String localeTag) {
    final ja = _isJa(localeTag);
    switch (action) {
      case DriveAction.continueDriving:
        return '';
      case DriveAction.heightenedCaution:
        return ja
            ? '速度を落とし、車間を広げて、前方に注意してください。'
            : 'Ease your speed, leave more room, and watch the road ahead.';
      case DriveAction.considerStopping:
        return ja
            ? '安全にできるときは、安全な場所での停車も選べます。'
            : 'If you can do so safely, pausing at a safe place is an option.';
    }
  }

  /// One-line honesty label for the position estimate's mode — the truth about
  /// how much to believe the dot.
  String modeLabel(LocalizationMode mode, String localeTag) {
    final ja = _isJa(localeTag);
    switch (mode) {
      case LocalizationMode.gpsTrusted:
        return ja ? 'GPS 良好' : 'GPS good';
      case LocalizationMode.gpsSuspect:
        return ja ? 'GPS 不確か' : 'GPS suspect';
      case LocalizationMode.deadReckoning:
        return ja ? 'GPS 途絶（推測航法）' : 'GPS lost — dead reckoning';
      case LocalizationMode.lost:
        return ja ? '現在地 不明' : 'Position unknown';
    }
  }

  /// A driver-facing statement of WHY the caution was raised.
  String reasonLabel(CautionReason reason, String localeTag) {
    final ja = _isJa(localeTag);
    switch (reason) {
      case CautionReason.positionUncertain:
        return ja ? '現在地が不確かです' : 'Position is uncertain';
      case CautionReason.lowVisibility:
        return ja ? '視界が非常に悪い' : 'Visibility is low';
      case CautionReason.reducedVisibility:
        return ja ? '視界が低下しています' : 'Visibility is reduced';
      case CautionReason.unknownVisibility:
        return ja ? '視界の情報がありません' : 'No visibility reading';
      case CautionReason.staleVisibility:
        return ja ? '視界の情報が古い' : 'Visibility reading is stale';
      case CautionReason.severeAdvisory:
        return ja ? '重大な気象警戒情報' : 'Severe weather advisory';
      case CautionReason.moderateAdvisory:
        return ja ? '気象注意情報' : 'Weather advisory';
      case CautionReason.highSpeedInDegradedConditions:
        return ja ? '悪条件での速度超過ぎみ' : 'Fast for the conditions';
    }
  }

  /// A driver-facing statement of a first-class UNKNOWN — the heart of the
  /// honesty contract, surfaced as a plain fact, never hidden.
  String unknownLabel(Unknown unknown, String localeTag) {
    final ja = _isJa(localeTag);
    switch (unknown) {
      case Unknown.positionCouldBeAnywhereInRadius:
        return ja ? '現在地は誤差円内のどこか' : 'You could be anywhere in the circle';
      case Unknown.noTrustedGpsForAWhile:
        return ja ? 'しばらく GPS が途絶しています' : 'No trusted GPS for a while';
      case Unknown.noPositionAtAll:
        return ja ? '現在地が取得できません' : 'No position at all';
      case Unknown.noVisibilityReading:
        return ja ? '視界の測定値がありません' : 'No visibility reading';
      case Unknown.visibilityReadingIsStale:
        return ja ? '視界の測定値が古い' : 'Visibility reading is stale';
      case Unknown.speedUnknown:
        return ja ? '速度が不明です' : 'Speed unknown';
    }
  }

  /// Localized "the dot could be anywhere within ~X m" line for a radius.
  String radiusLabel(double radiusMeters, String localeTag) {
    if (!radiusMeters.isFinite) {
      return _isJa(localeTag) ? '誤差 不明' : 'Uncertainty unknown';
    }
    final m = radiusMeters.round();
    return _isJa(localeTag) ? '誤差 約 $m m' : 'within ~$m m';
  }

  /// Localized sight-stopping-speed hint — "a speed at which you could stop
  /// within what you can see" (km/h, from the package's m/s).
  String sightHintLabel(double mps, String localeTag) {
    final kmh = (mps * 3.6).round();
    return _isJa(localeTag)
        ? '見える範囲で止まれる目安 約 $kmh km/h'
        : 'Stop-within-sight guide ~$kmh km/h';
  }
}
