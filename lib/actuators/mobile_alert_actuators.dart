/// WS5 — the mobile (android/ios) implementation of [AlertActuators].
///
/// Every plugin call in this file is guarded twice: the factory
/// [defaultAlertActuators] only constructs this class on a mobile target, and
/// every method ALSO re-checks [_isMobilePlatform] before touching a plugin.
/// The belt-and-suspenders is deliberate — flutter_tts / vibration /
/// wakelock_plus have no linux-desktop implementation, and the desktop
/// render-SEE ceiling (`flutter run -d linux`) MUST stay intact. On any
/// non-mobile target these methods are pure no-ops.
///
/// **Honesty (OPS-066 / AAE-1).** Not verified on an Android device in this
/// environment. Code-complete; on-device HEAR / FEEL / keep-awake is DEFERRED.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:voice_guidance/voice_guidance.dart' show TtsEngine;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/error_log.dart';
import '../voice/bundled_audio_engine.dart';
import 'alert_actuators.dart';
import 'hardened_haptic_channel.dart';
import 'hardened_tts_engine.dart';

/// True only on a real android/ios target (never web, never desktop, and —
/// load-bearing — never under the flutter_test binding).
///
/// The flutter_test binary reports `TargetPlatform.android` by default yet has
/// no plugin engine, so a target-only guard would let a test build/call the
/// real flutter_tts / vibration / wakelock plugins. We therefore treat the
/// test binding (the `FLUTTER_TEST` env var the harness sets) as non-mobile:
/// the factory returns a [NoOpAlertActuators] under test, and even a direct
/// [MobileAlertActuators] construction never touches a real plugin (its
/// methods early-return here, and its TTS engine is built lazily — see below).
bool get isMobileActuatorPlatform {
  if (kIsWeb) return false;
  // `dart:io` Platform is safe here — the kIsWeb guard above already excludes
  // the one target where it is unavailable.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  // Equality form (not an exhaustive switch) so new TargetPlatform values —
  // e.g. this SDK's linux_arm64 — never silently break the guard: anything
  // that is not android/ios is treated as non-mobile (no plugin call).
  final target = defaultTargetPlatform;
  return target == TargetPlatform.android || target == TargetPlatform.iOS;
}

// Private alias kept for the file's original internal call sites; the guard
// was made public (voice_lane_readiness.dart shares it) without churning
// every method below.
bool get _isMobilePlatform => isMobileActuatorPlatform;

/// Builds the REAL mobile speech engine: the bundled-audio mouth wrapping the
/// hardened TTS. Top-level + public so the callback GLUE below is testable
/// (an injected [playAsset] proves it without a platform channel); production
/// reaches it only through [MobileAlertActuators]'s lazily-resolved `_tts`.
///
/// B31 — [onSpeechVerified] is wired to BOTH delivery paths:
/// - the hardened TTS fires it on a platform-verified utterance (as before);
/// - the bundled mouth's [BundledAudioEngine.onBundledSpoken] now ALSO fires
///   it on a successful bundled play. Before this, the
///   「音声警告を確認できませんでした」 chip could ONLY be cleared by a TTS
///   delivery — but the safety core deliberately never routes to TTS, so one
///   unverified TTS phrase left the chip stuck on screen through every later
///   bundled warning that DID reach her. A delivered warning must clear the
///   "delivery unverified" caution regardless of which mouth delivered it.
TtsEngine buildMobileTtsEngine({
  LocalErrorLog? errorLog,
  void Function()? onSpeechUnverified,
  void Function()? onSpeechVerified,
  PlayAsset? playAsset,
}) => BundledAudioEngine(
  fallback: HardenedTtsEngine(
    errorLog: errorLog,
    onSpeechUnverified: onSpeechUnverified,
    onSpeechVerified: onSpeechVerified,
  ),
  playAsset: playAsset,
  onBundledSpoken: (_) => onSpeechVerified?.call(),
);

/// Returns the actuator appropriate for the current platform: a real
/// [MobileAlertActuators] on android/ios, else a [NoOpAlertActuators].
///
/// This is the single wiring point the app calls; keeping the platform choice
/// here (not scattered at call sites) is what lets the whole app stay desktop-
/// and test-safe.
///
/// [errorLog] / [onSpeechUnverified] / [onSpeechVerified] flow into the
/// lazily-built [HardenedTtsEngine] (Tier-1 voice-lane hardening): the log
/// receives one line per unverified delivery, and the callbacks drive the
/// in-drive HUD's 「音声警告を確認できませんでした」 chip. All optional; a
/// no-op actuator ignores them (there is no voice lane to verify off-mobile).
AlertActuators defaultAlertActuators({
  LocalErrorLog? errorLog,
  void Function()? onSpeechUnverified,
  void Function()? onSpeechVerified,
  void Function()? onHapticUnverified,
  void Function()? onHapticVerified,
}) => _isMobilePlatform
    ? MobileAlertActuators(
        errorLog: errorLog,
        onSpeechUnverified: onSpeechUnverified,
        onSpeechVerified: onSpeechVerified,
        onHapticUnverified: onHapticUnverified,
        onHapticVerified: onHapticVerified,
      )
    : const NoOpAlertActuators();

/// Drives the real phone actuators. Speech goes through the app's
/// [HardenedTtsEngine] (Tier-1 voice-lane hardening: awaitSpeakCompletion +
/// nav audio attributes + focus-duck + read-the-result + retry/timeout +
/// unverified reporting), which keeps FlutterTtsEngine's guard + rate-mapping
/// parity. The `vibration` / `wakelock_plus` static APIs drive the tactile +
/// keep-awake channels.
class MobileAlertActuators implements AlertActuators {
  /// [ttsEngine] is injectable for tests; when null the hardened
  /// flutter_tts-backed engine is built LAZILY on the first real mobile
  /// `speak()` — never in the constructor, so constructing this class off a
  /// device (a test, or a mis-wire) never eagerly builds the real plugin
  /// engine. On any non-mobile / test target `speak()` early-returns before
  /// touching the engine, so it is never built there at all.
  ///
  /// [errorLog] / [onSpeechUnverified] / [onSpeechVerified] are handed to
  /// the lazily-built [HardenedTtsEngine] (ignored when [ttsEngine] is
  /// injected — the injector owns its engine's reporting).
  /// [hapticChannel] / [onHapticUnverified] / [onHapticVerified] are the
  /// tactile twins of the speech parameters above. They did not exist before
  /// 2026-08-21, and that absence WAS the defect: the audio channel had an
  /// injectable seam, an error log and delivery reporting, and the haptic
  /// channel — the only channel a deaf or hard-of-hearing driver has — had
  /// none of the three. The asymmetry was visible in this very parameter list.
  MobileAlertActuators({
    TtsEngine? ttsEngine,
    LocalErrorLog? errorLog,
    void Function()? onSpeechUnverified,
    void Function()? onSpeechVerified,
    HapticChannel? hapticChannel,
    void Function()? onHapticUnverified,
    void Function()? onHapticVerified,
  }) : _injectedTts = ttsEngine,
       _errorLog = errorLog,
       _onSpeechUnverified = onSpeechUnverified,
       _onSpeechVerified = onSpeechVerified,
       _injectedHaptics = hapticChannel,
       _onHapticUnverified = onHapticUnverified,
       _onHapticVerified = onHapticVerified;

  final TtsEngine? _injectedTts;
  final LocalErrorLog? _errorLog;
  final void Function()? _onSpeechUnverified;
  final void Function()? _onSpeechVerified;
  TtsEngine? _resolvedTts;
  final HapticChannel? _injectedHaptics;
  final void Function()? _onHapticUnverified;
  final void Function()? _onHapticVerified;
  HapticChannel? _resolvedHaptics;

  /// The TTS engine, resolved on first use. An injected engine (tests) is used
  /// as-is; otherwise the real engine is built by [buildMobileTtsEngine] —
  /// reached ONLY from `speak()` after its `_isMobilePlatform` guard has
  /// passed. The real engine is the bundled-audio mouth wrapping the hardened
  /// TTS: the finite ja safety core plays from bytes in the APK (works with no
  /// network, no voice pack, no TTS engine), and only slotted / non-safety
  /// text is delegated to TTS. Before this, the system TTS was the ONLY mouth
  /// — and with no network it is silent, then hangs.
  TtsEngine get _tts => _resolvedTts ??=
      (_injectedTts ??
      buildMobileTtsEngine(
        errorLog: _errorLog,
        onSpeechUnverified: _onSpeechUnverified,
        onSpeechVerified: _onSpeechVerified,
      ));

  @override
  Future<void> speak(String text, {required String localeTag}) async {
    if (!_isMobilePlatform) return;
    if (text.trim().isEmpty) return;
    try {
      await _tts.setLanguage(ttsLocaleTagFor(localeTag));
      await _tts.speak(text);
    } catch (_) {
      // Never let a TTS fault crash the surface a driver is relying on.
      // (HardenedTtsEngine already never-throws and swallows
      // MissingPluginException; this is the outer safety net for any other
      // platform-channel fault — e.g. an injected engine that throws.)
    }
  }

  /// The tactile channel, resolved on first use — the exact mirror of `_tts`
  /// above, and it did not exist until 2026-08-21.
  ///
  /// Before this, `haptic()` called the plugin statically and had **two silent
  /// exits**: a `hasVibrator()` false branch that did nothing, and a bare
  /// `catch (_)` that swallowed every fault. Measured on a device that day, an
  /// announce at severity `critical` dispatched Japanese TTS and registered
  /// ZERO vibrations — with nobody told, because there was nothing to tell
  /// with. [HardenedHapticChannel] carries the reporting; the guards and the
  /// never-throw contract are unchanged.
  HapticChannel get _haptics => _resolvedHaptics ??=
      (_injectedHaptics ??
      HardenedHapticChannel(
        errorLog: _errorLog,
        onHapticUnverified: _onHapticUnverified,
        onHapticVerified: _onHapticVerified,
      ));

  @override
  Future<void> haptic(HapticCuePattern pattern) async {
    // Non-mobile is not a delivery failure: desktop/test genuinely owes no
    // sensation and uses NoOpAlertActuators. Reporting here would cry wolf on
    // every surface that never had a vibrator to begin with.
    if (!_isMobilePlatform && _injectedHaptics == null) return;
    // Fire-and-report. The outcome is deliberately not rethrown or awaited by
    // the caller for anything but ordering: AlertAnnouncer awaits haptic
    // BEFORE speak (haptic-first, OPS-059), so this must always complete.
    await _haptics.fire(pattern);
  }

  @override
  Future<void> keepAwake(bool enabled) async {
    if (!_isMobilePlatform) return;
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {}
  }

}
