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
///  - The lowest rung (`continueDriving`) HEADLINE is CHOICE-NEUTRAL — it states
///    the honest STATE («no elevated caution» / 「特段の注意なし」), it does NOT tell
///    her to continue/proceed/go and it does NOT reassure ("safe"/"clear"). This
///    is Design-Floor Refusal #1 (Chair, 2026-07-19): the instrument serves the
///    WHEEL — honest information so the DRIVER decides — never a confidence-to-
///    continue. The visual headline once read 「走行を継続」/"Continue", which
///    ADVOCATED GO; that breach is removed here. Firing basis: this rung fires
///    ONLY when position is trusted+fresh AND visibility is MEASURED, fresh, and
///    clear (advisor score 0). It does NOT fire on unknown/stale visibility —
///    those floor to `heightenedCaution` in the package's `_resolveVisibility`
///    (concern 1).
///
///    HONEST SCOPE — this guarantee covers the POSITION and VISIBILITY axes
///    ONLY, because those are the only axes `compound_failure_advisor` models
///    as first-class unknowns. It does NOT cover the ADVISORY axis: 0.1.2's
///    `Unknown` enum has no advisory member and `advisorySeverity: null` is
///    documented as "no advisory in force", so an advisory-feed OUTAGE is
///    indistinguishable from a quiet sky and this rung DOES fire over it. The
///    file previously claimed the headline "never displays over an unmeasured
///    or degraded read"; that was measurably false on the advisory axis, and
///    is retired. The countermeasure is [actionHeadline]'s scoping flags —
///    when an input could not be confirmed the caller qualifies the claim
///    rather than raising the rung, because an outage is an unknown and not a
///    hazard (no cry-wolf; Chair 2026-07-23). See
///    `services/advisory_axis.dart` for the measured asymmetry.
///  - The voice channel already honours this: `spokenGuidance(continueDriving)`
///    returns "" (say nothing). This headline is the visual parity of that
///    silence — an honest absence, never an all-clear.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:localization_fallback/localization_fallback.dart';

/// Localizes the advisory-only in-drive vocabulary into HER language.
class DriveHudLocalizer {
  const DriveHudLocalizer();

  bool _isJa(String localeTag) => localeTag.toLowerCase().startsWith('ja');

  /// A short headline for the caution rung, for the on-screen HUD.
  ///
  /// The lowest rung is CHOICE-NEUTRAL by Design-Floor Refusal #1: it names the
  /// honest absence of elevated caution, never the instruction "continue" and
  /// never a reassurance of safety. See the library doc for the firing basis
  /// and for the axes that basis does NOT cover.
  ///
  /// ## Scoping the reassurance
  ///
  /// 「特段の注意なし」 is a claim about the WHOLE picture, so it may only be
  /// printed unscoped when the whole picture was measured. The three flags let
  /// the caller qualify it — they NEVER raise the rung, because an outage is
  /// an unknown and not a hazard (no cry-wolf; Chair 2026-07-23). We withhold
  /// the reassurance; we never manufacture the warning.
  ///
  ///  - [advisoryUnconfirmed] — the advisory lookup could not prove it was
  ///    complete (`AdvisoryAxis.completenessUnproven`).
  ///  - [measuredUnconfirmed] — the measured-weather observation was not read
  ///    (cold start) or could not be read (feed loss).
  ///  - [calmNoteInForce] — everything WAS read, and a calm note is in force
  ///    that deliberately does not raise the rung (the sub-zero
  ///    frozen-surface chip, Chair 2026-07-23). A chip reading 路面凍結のおそれ
  ///    directly above an unscoped 「特段の注意なし」 is a glance-level
  ///    contradiction; the chip is correct, so the headline is what yields.
  ///
  /// PRECEDENCE — an unconfirmed input outranks a confirmed calm note. A thing
  /// we could not look at is the more dangerous omission; the note is a thing
  /// we DID look at and deliberately chose not to escalate, and it stays fully
  /// visible in its own chip row either way.
  ///
  /// Only this rung is scoped. 注意して走行 and 停車の検討 assert nothing an
  /// unknown could falsify — they are already the cautious reading.
  String actionHeadline(
    DriveAction action,
    String localeTag, {
    bool advisoryUnconfirmed = false,
    bool measuredUnconfirmed = false,
    bool calmNoteInForce = false,
  }) {
    final ja = _isJa(localeTag);
    switch (action) {
      case DriveAction.continueDriving:
        final base = ja ? '特段の注意なし' : 'No elevated caution';
        if (advisoryUnconfirmed && measuredUnconfirmed) {
          return ja ? '$base（一部未確認）' : '$base (some inputs unconfirmed)';
        }
        if (advisoryUnconfirmed) {
          return ja ? '$base（警報・注意報は未確認）' : '$base (advisories unconfirmed)';
        }
        if (measuredUnconfirmed) {
          return ja ? '$base（気象観測は未確認）' : '$base (observation unconfirmed)';
        }
        if (calmNoteInForce) {
          return ja ? '$base（下記に注意）' : '$base (see note below)';
        }
        return base;
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

  // --- (e) maneuver narration text — localized by engine-agnostic TYPE ---
  //
  // `OsrmRoutingEngine` emits ENGLISH instruction strings; passing those to HER
  // is a D4 breach, so the app narrates from the engine-agnostic maneuver TYPE
  // token instead, localized here (JA for HER). Kept faithful + calm: a plain
  // upcoming-turn statement, never a barked command.

  /// The short maneuver noun for [type] (e.g. `right` → 右折 / "a right turn"),
  /// used to compose both the confident and hedged sentences.
  String _maneuverNoun(String type, bool ja) => switch (type) {
        'left' => ja ? '左折' : 'a left turn',
        'slight_left' => ja ? '斜め左方向' : 'a slight left',
        'sharp_left' => ja ? '左への急カーブ' : 'a sharp left',
        'right' => ja ? '右折' : 'a right turn',
        'slight_right' => ja ? '斜め右方向' : 'a slight right',
        'sharp_right' => ja ? '右への急カーブ' : 'a sharp right',
        'straight' => ja ? '直進' : 'continuing straight',
        'u_turn_left' || 'u_turn_right' || 'uturn' => ja ? 'Uターン' : 'a U-turn',
        'roundabout_enter' ||
        'roundabout' ||
        'rotary' =>
          ja ? 'ロータリー' : 'the roundabout',
        'merge' => ja ? '合流' : 'a merge',
        'ramp_left' => ja ? '左のランプ' : 'the left ramp',
        'ramp_right' => ja ? '右のランプ' : 'the right ramp',
        _ => ja ? '次の案内' : 'the next maneuver',
      };

  /// A CONFIDENT (trusted-GPS) maneuver line for HER, localized by [type].
  ///
  /// Plain and calm — " this ahead " not "TURN NOW". `depart`/`arrive` get their
  /// own sentences; everything else composes from [_maneuverNoun].
  String maneuverInstruction(String type, String localeTag) {
    final ja = _isJa(localeTag);
    switch (type) {
      case 'depart':
        return ja ? 'ルート案内を開始します。' : 'Starting route guidance.';
      case 'arrive':
        return ja ? 'まもなく目的地です。' : 'You are arriving at your destination.';
      case 'straight':
        return ja ? 'このまま直進します。' : 'Continue straight ahead.';
      default:
        final noun = _maneuverNoun(type, ja);
        return ja ? 'この先、$noun です。' : 'Ahead, take $noun.';
    }
  }

  /// A HEDGED (suspect-GPS) maneuver line: it names the same [type] but softens
  /// it to a possibility and tells HER to confirm before acting — because the
  /// position is not trusted, the app must NOT assert the turn as fact.
  String hedgedManeuverInstruction(String type, String localeTag) {
    final ja = _isJa(localeTag);
    if (type == 'arrive') {
      return ja
          ? '現在地が不確かですが、まもなく目的地の付近です。位置をご確認ください。'
          : 'Position is uncertain, but you may be nearing your destination — '
              'please confirm.';
    }
    final noun = _maneuverNoun(type, ja);
    return ja
        ? '現在地が不確かです。この先 $noun の可能性がありますが、位置をご確認のうえご判断ください。'
        : 'Position is uncertain — $noun may be coming; please confirm before '
            'acting.';
  }

  /// Couple the icy-turn advisory onto an already-built maneuver line, when the
  /// maneuver coincides with an ice / low-visibility hazard. Reuses the calm,
  /// advisory-only register of the rest of this localizer.
  String icyManeuverCoupling(String maneuverText, String localeTag) {
    final ja = _isJa(localeTag);
    return ja
        ? '$maneuverText この曲がり角は路面が凍結している可能性があります。'
        : '$maneuverText The turn may be icy.';
  }
}
