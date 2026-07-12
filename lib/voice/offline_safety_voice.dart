/// THE MOUTH — the finite ja SAFETY vocabulary, pre-rendered to bundled audio.
///
/// WHY THIS EXISTS (C2 RED-2). HER phone's only voice path was `flutter_tts` —
/// the system TTS — measured SILENT-THEN-HUNG offline on her device: no offline
/// ja voice is installed on it, and the plugin's error callback never resolves
/// the Future. So on the one night the network dies in Akita, every warning we
/// had hardened arrived at a layer WITH NO MOUTH.
///
/// HOW THIS SET WAS DERIVED — AND HOW THE FIRST VERSION WAS WRONG (2026-07-12).
/// The first catalog (10 phrases) was authored by GREPPING SOURCE FILES,
/// including catalog packages this app never calls. Measured against what the
/// app can ACTUALLY pass to `AlertActuators.speak()`:
///   SAFETY-class static emittable strings : 37
///   covered by that first mouth           : 2
///   bundled WAVs matching NO emittable string : 8 of 10
/// It could not say one single hazard line the app actually emits. A mouth that
/// cannot say "black ice" the way the app says it is not a mouth.
///
/// THIS SET IS DERIVED FROM THE RUNTIME EMISSIONS — every announce() call site,
/// enumerated by CALLING the production builders (not grepping):
///   main.dart:1419  AlertExplainer.forConditionAndProfile(c, p).action  (30)
///                   = 6 warning/critical conditions x 5 ja driver profiles;
///                     both selectable by the driver in the app's dropdowns
///   drive_hud_controller.dart:189  DriveHudLocalizer.spokenGuidance()    (2)
///   main.dart:1161  invisibleBlackIceAnnouncement.jaSpokenText           (1)
///   main.dart:1172  turmoilSpokenText(...)                               (3)
///   main.dart:1218  kConditionsUnknownJaSpokenText                       (1)
/// `test/voice/runtime_voice_coverage_test.dart` RE-DERIVES that list on every
/// run and FAILS if any emittable safety line is not in this map — so the mouth
/// can never again drift from what the app says.
///
/// THE HONEST REMAINDER (measured, not hand-waved):
///  - SLOTTED lines cannot be pre-rendered. One exists:
///    `staleInvisibleBlackIceSpokenText(hourJst:)` (main.dart:1240) — it
///    interpolates the observation hour. It routes to TTS; offline it is
///    SILENT. Recorded bound, not a claim.
///  - NAV-class lines (58 static maneuver strings, ManeuverNarrator) are NOT
///    bundled. They exist ONLY when a live OSRM route was fetched over the
///    network (lib/route_fetch.dart:50) — in the dead zone this mouth exists
///    for, there is no route, so there is no maneuver to speak. If routing ever
///    goes offline, these 58 must be rendered too.
///
/// RENDERING: `bash tool/render_offline_voice.sh` (open_jtalk + nitech-jp HTS,
/// 16 kHz mono) writes `assets/audio/ja/<id>.wav`. Chair ruling 2026-07-12:
/// synth now, human-record the safety core before winter — when the human
/// recordings land they replace these files at the SAME ids and nothing else
/// changes.
library;

/// The finite ja safety vocabulary: stable id -> the EXACT spoken text.
///
/// The text is the lookup key: [OfflineSafetyVoice.assetFor] matches the exact
/// string an existing caller already passes to `speak()`, so wiring the mouth
/// changed no caller.
// ignore_for_file: lines_longer_than_80_chars
const Map<String, String> kOfflineSafetyVoiceJa = <String, String>{
  // --- Road-surface alerts, spoken VERBATIM from the catalog explainer
  // (main.dart:1419). 6 conditions x 5 ja profiles. These are the lines HER
  // actually hears about the road she cannot see.
  'alert_wet_ageing_rural':
      '路面が濡れています。ブラックアイスが形成される可能性があるため、橋やトンネル出口で速度を落としてください',
  'alert_wet_snow_zone_experienced':
      '濡れた路面、橋やトンネル出口で注意',
  'alert_wet_novice_urban':
      '濡れた路面、危険。スピードを落としてください',
  'alert_wet_professional':
      '濡路、注意',
  'alert_wet_agricultural_forestry':
      '濡れた路面、未舗装路では泥濘に注意',
  'alert_snow_ageing_rural':
      '圧雪路面です。雪は固く凍結に近い状態です。低速ギアを保ち、急ブレーキ・急ハンドルを避けてください',
  'alert_snow_snow_zone_experienced':
      '圧雪、低速ギア、急操作回避',
  'alert_snow_novice_urban':
      '圧雪路面、滑ります。スピードを大きく落とし、ゆっくり運転してください',
  'alert_snow_professional':
      '圧雪、低速ギア',
  'alert_snow_agricultural_forestry':
      '圧雪路面、トラクションタイヤ・チェーン推奨',
  'alert_ice_ageing_rural':
      '凍結路面です。気温0°C以下で薄氷ができています。時速30km以下に減速し、急ブレーキは避けてください',
  'alert_ice_snow_zone_experienced':
      '凍結路面。30km/h以下に減速',
  'alert_ice_novice_urban':
      '凍結、危険です。時速30kmまで減速し、車間距離を倍に',
  'alert_ice_professional':
      '凍結、30km/h',
  'alert_ice_agricultural_forestry':
      '凍結路面、未舗装路ではグリップ大幅低下',
  'alert_slush_ageing_rural':
      'シャーベット状の路面です。タイヤが横に滑る危険があるため、車線変更を避け、道路中央寄りを走行してください',
  'alert_slush_snow_zone_experienced':
      'シャーベット、車線変更回避、中央走行',
  'alert_slush_novice_urban':
      'シャーベット路面、ハンドルを取られやすい状態。車線変更せず、ゆっくり走行してください',
  'alert_slush_professional':
      'シャーベット、中央走行',
  'alert_slush_agricultural_forestry':
      'シャーベット、轍（わだち）に注意',
  'alert_wet_ice_ageing_rural':
      'アイスバーンです。最も滑りやすい路面状態です。可能であれば停車できる安全な場所を探してください。走行中は時速20km以下を目安に',
  'alert_wet_ice_snow_zone_experienced':
      'アイスバーン、最危険、20km/h以下',
  'alert_wet_ice_novice_urban':
      'アイスバーン、極めて危険。可能なら安全な場所で停車してください。走行時は時速20km以下に',
  'alert_wet_ice_professional':
      'アイスバーン、20km/h',
  'alert_wet_ice_agricultural_forestry':
      'アイスバーン、停車できる場所まで最低速で',
  'alert_loose_gravel_ageing_rural':
      '砂利が浮いています。急ブレーキで滑る可能性があるため、十分な車間距離をとってください',
  'alert_loose_gravel_snow_zone_experienced':
      '砂利、車間距離注意',
  'alert_loose_gravel_novice_urban':
      '砂利路面、ブレーキ距離が伸びます。車間を空けてください',
  'alert_loose_gravel_professional':
      '砂利、車間注意',
  'alert_loose_gravel_agricultural_forestry':
      '砂利路面（通常運用範囲）、後続車に小石注意',

  // --- Caution-rung guidance (drive_hud_controller.dart:189).
  'guidance_heightened_caution':
      '速度を落とし、車間を広げて、前方に注意してください。',
  'guidance_consider_stopping':
      '安全にできるときは、安全な場所での停車も選べます。',

  // --- The live invisible-black-ice announcement (main.dart:1161).
  'black_ice_live':
      'ブラックアイスバーンに注意。路面は濡れて見えても、凍結しているおそれがあります。急ハンドル、急ブレーキは厳禁。速度を落としてください。',

  // --- Measured-turmoil cautions: rain / wind / both (main.dart:1172).
  'turmoil_rain_and_wind':
      '強い雨と強めの風を観測しています。視界の悪化と横風のおそれがあります。速度を落とし、車間距離をとって慎重に運転してください。',
  'turmoil_rain':
      '強い雨を観測しています。視界の悪化や、水たまりによるスリップのおそれがあります。速度を落とし、車間距離をとってください。',
  'turmoil_wind':
      '強めの風を観測しています。横風に流されるおそれがあります。ハンドルをしっかり握り、速度を落としてください。',

  // --- The honest-absence line (main.dart:1218). The MOST important entry:
  // it is what she hears when we know nothing.
  'conditions_unknown':
      '路面状況を取得できていません。見える範囲で運転してください。',

  // --- THE MEMORY (trip_hazard_memory.dart → main.dart dead-zone path).
  // A snow hazard JMA declared VALID FOR THIS TIME BAND, learned before she
  // left, spoken at T+90 with the centre gone. It names itself a FORECAST out
  // loud (これは観測ではなく予報です) so she can never mistake it for a reading we
  // just took. This is the line no other product in Japan can say in a dead
  // zone — every predictive competitor is server-side.
  'forecast_snow_valid':
      '出発前に取得した気象庁の予報では、この時間帯は雪の予報です。これは観測ではなく予報です。速度を落とし、車間距離をとってください。',
};

/// The bundled-audio lookup: the finite mouth.
abstract final class OfflineSafetyVoice {
  /// Asset root for the rendered ja safety audio.
  static const String assetDir = 'assets/audio/ja';

  /// Reverse index: exact spoken text -> asset path. Built once.
  static final Map<String, String> _byText = <String, String>{
    for (final e in kOfflineSafetyVoiceJa.entries)
      e.value: '$assetDir/${e.key}.wav',
  };

  /// The bundled asset that speaks [text] verbatim, or null if [text] is not in
  /// the finite safety core (slotted / nav-class text -> the caller falls back
  /// to TTS, which may itself be unavailable offline — a recorded bound).
  ///
  /// Exact match, deliberately. A fuzzy match would let a phrase we never
  /// rendered be spoken by an audio file that says something ELSE — which, on a
  /// road she cannot see, is worse than silence.
  static String? assetFor(String text) => _byText[text.trim()];

  /// Every rendered asset path — used by the manifest test and the renderer.
  static Iterable<String> get allAssets => _byText.values;

  /// True if [text] is in the finite safety core.
  static bool covers(String text) => _byText.containsKey(text.trim());
}
