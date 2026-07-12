/// THE MOUTH — the finite ja SAFETY vocabulary, pre-rendered to bundled audio.
///
/// WHY THIS EXISTS (C2 RED-2, 2026-07-12). HER phone's only voice path was
/// `flutter_tts` — the system TTS — which we measured as SILENT-THEN-HUNG
/// offline on her device: there is no offline ja voice installed on it, and the
/// plugin's error callback never resolves the Future (a timeout is the only
/// recovery). So on the one night the network dies in Akita, every warning we
/// had so carefully hardened arrived at a layer WITH NO MOUTH.
///
/// W0 (commit e2cd352) made winter warnings *survive* the dead zone. They
/// survived into silence. This file gives them a voice that needs no network,
/// no voice-pack download, and no TTS engine at all: the audio is BYTES ON HER
/// PHONE, shipped in the APK.
///
/// THE SET IS FINITE AND SLOTLESS, BY CONSTRUCTION. Only phrases with NO
/// interpolation can be pre-rendered. That is not a limitation to apologise for
/// — it is the safety core. Route guidance and JMA advisory text are moot in the
/// dead zone anyway (both need a live source); what MUST still speak is the
/// road-surface warning and the honest-absence line. Slotted phrases (「$hourJst
/// 時頃の観測では…」) continue to route to TTS when TTS is alive, and are
/// silently unavailable when it is not — a known, recorded bound, not a claim.
///
/// EVERY STRING HERE IS VERBATIM FROM SHIPPING SOURCE. Not one was authored for
/// this file. `offline_safety_voice_test.dart` re-verifies that each entry is a
/// real string in the app or catalog source, so a phrase can never be invented
/// here and quietly rendered into her car.
///
/// RENDERING: `dart run tool/render_offline_voice.dart` (open_jtalk + the
/// nitech-jp HTS voice) writes `assets/audio/ja/<id>.wav`. Chair ruling
/// 2026-07-12: **synth now, human-record the safety core before winter.** The
/// synthesized voice is the floor, not the destination — when the human
/// recordings land they replace these files at the same ids, and nothing else
/// changes.
library;

/// The finite ja safety vocabulary: stable id → the EXACT spoken text.
///
/// The id is the filename stem under `assets/audio/ja/`. The text is the lookup
/// key: [OfflineSafetyVoice.assetFor] matches on the exact string an existing
/// caller already passes to `speak()`, so wiring the mouth changed no caller.
const Map<String, String> kOfflineSafetyVoiceJa = <String, String>{
  // The honest-absence line. The MOST important entry in this file: it is what
  // she hears when we know nothing, and until today she heard it silently.
  // (lib/services/staleness_policy.dart — kConditionsUnknownJaSpokenText)
  'conditions_unknown':
      '路面状況を取得できていません。見える範囲で運転してください。',

  // Road-surface warnings (snow_rendering — the winter core).
  'black_ice': 'ブラックアイスバーンに注意。路面が凍結しているおそれがあります。',
  'compacted_snow': '圧雪路面です。急のつく操作を避け、車間距離を多めにとってください。',
  'slush': 'シャーベット状の路面です。下が凍結している可能性があります。',

  // Driving-action lines (the "what do I DO" half — a hazard named without an
  // action is a fright, not a warning).
  'no_abrupt_inputs': '急ハンドル、急ブレーキは厳禁。速度を落としてください。',
  'grip_wheel_slow_down': 'ハンドルをしっかり握り、速度を落としてください。',
  'avoid_abrupt': '急のつく操作は避けましょう。',
  'stay_alert_slow_down': '油断せず、速度を落としてください。',

  // Wind (crosswind on an exposed Akita bridge is the compound-failure case).
  'strong_wind': '強めの風を観測しています。横風に流されるおそれがあります。',

  // The dignity line: stopping is allowed. She is never ordered onward.
  'stopping_is_an_option': '安全にできるときは、安全な場所での停車も選べます。',
};

/// The bundled-audio lookup: the finite mouth.
abstract final class OfflineSafetyVoice {
  /// Asset root for the rendered ja safety audio.
  static const String assetDir = 'assets/audio/ja';

  /// Reverse index: exact spoken text → asset path. Built once.
  static final Map<String, String> _byText = <String, String>{
    for (final e in kOfflineSafetyVoiceJa.entries) e.value: '$assetDir/${e.key}.wav',
  };

  /// The bundled asset that speaks [text] verbatim, or null if [text] is not in
  /// the finite safety core (slotted / non-safety text → the caller falls back
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
