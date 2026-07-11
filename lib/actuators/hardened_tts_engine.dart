/// Tier-1 voice-lane hardening — a [TtsEngine] that READS what flutter_tts
/// already returns instead of fire-and-forgetting.
///
/// Every plugin-API fact below was verified against the REAL flutter_tts
/// 4.2.5 source (clone: /home/komada/work/flutter_tts-serve; version pinned
/// in its pubspec.yaml:3). Load-bearing citations are at the call sites.
///
/// What this raises — and what it honestly cannot:
/// - RAISES delivery *verification*: under `awaitSpeakCompletion(true)` the
///   Android plugin holds the `speak` result until the utterance actually
///   finishes and completes it with `1` (success) or `0` (discarded /
///   stopped). Reading that value is the difference between "we asked the
///   OS to speak" and "the OS reports the utterance completed".
/// - CANNOT guarantee *audibility*: the media-stream volume is not readable
///   from Dart via this plugin — a completed utterance at volume zero is
///   still silent. Closing that gap (volume read / audibility check) is
///   Tier-2, platform-channel territory. This class never claims HEARD;
///   it claims completed-or-unverified.
///
/// On-device behavior (actual audio focus ducking, engine rebind timing) is
/// OPS-066 DEFERRED — no Android device in this environment.
library;

import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:voice_guidance/voice_guidance.dart' show TtsEngine;

import '../services/error_log.dart';

/// Injectable seam over the flutter_tts plugin surface this engine consumes.
///
/// The REAL implementation ([FlutterTtsAdapter]) wraps the [FlutterTts]
/// singleton-channel plugin; tests fake this interface. Honest note on the
/// plugin's channel semantics: `FlutterTts` instances all share ONE method
/// channel + ONE Android plugin instance (flutter_tts.dart:16-17 static
/// channel; the Kotlin side is a single `FlutterTtsPlugin` with global
/// `awaitSpeakCompletion` / `speakResult` state) — so configuration set here
/// (awaitSpeakCompletion, audio attributes) applies process-wide to every
/// other `FlutterTts()` holder, and two concurrent `speak` calls share the
/// single pending-result slot. This app routes ALL speech through the one
/// engine instance MobileAlertActuators owns, which keeps that global state
/// coherent.
abstract class TtsAdapter {
  /// flutter_tts 4.2.5 lib/flutter_tts.dart:354-363 —
  /// `speak(String text, {bool focus = false})`; on Android it sends
  /// `{"text": text, "focus": focus}` over the channel. The returned Future
  /// resolves with the platform result (see [HardenedTtsEngine.speak] for
  /// the verified value semantics).
  Future<dynamic> speak(String text, {required bool focus});

  /// lib/flutter_tts.dart:345-346. Android handler: FlutterTtsPlugin.kt:
  /// 328-331 (parses the bool, replies 1).
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion);

  /// lib/flutter_tts.dart:665-667. Android: FlutterTtsPlugin.kt:785-793 —
  /// sets USAGE_ASSISTANCE_NAVIGATION_GUIDANCE + CONTENT_TYPE_SPEECH on the
  /// engine (the nav-guidance audio attributes), then replies 1 (kt:454-457).
  Future<dynamic> setAudioAttributesForNavigation();

  Future<dynamic> setLanguage(String languageTag);
  Future<dynamic> setVolume(double volume);
  Future<dynamic> setSpeechRate(double rate);
  Future<dynamic> stop();

  /// Used by [HardenedTtsEngine.isAvailable] (same probe FlutterTtsEngine
  /// uses — voice_guidance/lib/src/flutter_tts_engine.dart:30-44).
  Future<dynamic> getLanguages();
}

/// Production adapter over the real plugin.
class FlutterTtsAdapter implements TtsAdapter {
  FlutterTtsAdapter({FlutterTts? flutterTts})
      : _tts = flutterTts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<dynamic> speak(String text, {required bool focus}) =>
      _tts.speak(text, focus: focus);

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) =>
      _tts.awaitSpeakCompletion(awaitCompletion);

  @override
  Future<dynamic> setAudioAttributesForNavigation() =>
      _tts.setAudioAttributesForNavigation();

  @override
  Future<dynamic> setLanguage(String languageTag) =>
      _tts.setLanguage(languageTag);

  @override
  Future<dynamic> setVolume(double volume) => _tts.setVolume(volume);

  @override
  Future<dynamic> setSpeechRate(double rate) => _tts.setSpeechRate(rate);

  @override
  Future<dynamic> stop() => _tts.stop();

  @override
  Future<dynamic> getLanguages() => _tts.getLanguages;
}

/// Outcome of one speak attempt, from the platform's own report.
enum _SpeakOutcome { verified, failed, timedOut }

/// A [TtsEngine] (the same voice_guidance interface [FlutterTtsEngine]
/// implements) that verifies delivery instead of assuming it.
///
/// Behavior contract (announcer-facing):
/// - NEVER throws out of any method (matches MobileAlertActuators'
///   never-crash posture; the announcer already guards, this is the inner
///   belt of the belt-and-suspenders).
/// - NEVER hangs: every `speak` is wrapped in a text-length-scaled timeout.
///   Load-bearing, verified fact: under `awaitSpeakCompletion(true)` the
///   Android plugin completes the pending result ONLY in the utterance's
///   `onDone` (FlutterTtsPlugin.kt:120-121 → speakCompletion(1),
///   kt:201-207) or on an explicit stop/pause (kt:367-370, 379-382 →
///   success(0)); the utterance **onError paths set `speaking = false` but
///   never complete `speakResult`** (kt:168-183, 185-198) — i.e. on an
///   engine error the Dart Future HANGS. The timeout here is therefore not
///   paranoia; it is the only recovery from a real, reachable plugin state.
/// - On an unverified delivery (failure after one retry, or timeout):
///   writes ONE line to the app's [LocalErrorLog] and invokes
///   [onSpeechUnverified]. On a verified delivery invokes [onSpeechVerified]
///   (the HUD chip clears on the next verified speak).
class HardenedTtsEngine implements TtsEngine {
  HardenedTtsEngine({
    TtsAdapter? adapter,
    this.errorLog,
    this.onSpeechUnverified,
    this.onSpeechVerified,
    this.retryDelay = const Duration(milliseconds: 300),
    this.speakTimeoutFloor = const Duration(seconds: 10),
    this.speakTimeoutPerChar = const Duration(milliseconds: 300),
    this.speakTimeoutCeiling = const Duration(seconds: 90),
  }) : _adapter = adapter ?? FlutterTtsAdapter();

  final TtsAdapter _adapter;

  /// The app's local, no-network error log (services/error_log.dart). One
  /// line per unverified delivery; never throws (LocalErrorLog contract).
  final LocalErrorLog? errorLog;

  /// Fired when a delivery could not be verified (retry exhausted or timed
  /// out). The in-drive HUD shows its unverified chip on this.
  final void Function()? onSpeechUnverified;

  /// Fired when the platform reports an utterance completed (result == 1).
  /// Clears the HUD chip.
  final void Function()? onSpeechVerified;

  /// Wait before the single retry — the engine-rebind window. Verified
  /// fact behind the retry: when the Android TTS service connection is
  /// unusable, the plugin rebuilds the engine and returns false from its
  /// native speak (FlutterTtsPlugin.kt:682-686), which re-queues the call
  /// until init completes (kt:311-318, 280-284, 217-226) — so a `0` result
  /// (busy-discard, kt:304-309, or stopped mid-utterance, kt:379-382) is
  /// worth exactly one spaced retry, not a loop.
  final Duration retryDelay;

  /// Timeout = floor + length×perChar, capped at ceiling. Conservative:
  /// Japanese TTS speaks ~5-7 chars/s; 300 ms/char is ~2x slack, so a real
  /// long utterance is never cut short, while an onError-hung Future (see
  /// class doc) is always recovered.
  final Duration speakTimeoutFloor;
  final Duration speakTimeoutPerChar;
  final Duration speakTimeoutCeiling;

  bool _disposed = false;
  bool _pluginAvailable = true;
  bool _configured = false;

  bool get pluginAvailable => _pluginAvailable;

  Duration _timeoutFor(String text) {
    final scaled = speakTimeoutFloor +
        speakTimeoutPerChar * text.length;
    return scaled > speakTimeoutCeiling ? speakTimeoutCeiling : scaled;
  }

  /// Same MissingPluginException discipline as FlutterTtsEngine
  /// (voice_guidance flutter_tts_engine.dart:19-27): first missing-plugin
  /// marks the engine unavailable and every later call no-ops.
  Future<T?> _guard<T>(Future<T> Function() action) async {
    if (_disposed || !_pluginAvailable) return null;
    try {
      return await action();
    } on MissingPluginException {
      _pluginAvailable = false;
      return null;
    } catch (_) {
      // Any other platform-channel fault: swallow (never-throw contract).
      return null;
    }
  }

  /// One-time lazy config, on the first speak:
  /// - `awaitSpeakCompletion(true)` so the speak Future resolves on
  ///   utterance completion with the platform's own 1/0 verdict
  ///   (FlutterTtsPlugin.kt:319-325).
  /// - `setAudioAttributesForNavigation()` — Android nav-guidance audio
  ///   attributes (kt:785-793). On non-Android platforms both are guarded
  ///   no-ops here (and this engine is only ever built behind
  ///   MobileAlertActuators' mobile-platform guard anyway).
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    _configured = true;
    await _guard(() => _adapter.awaitSpeakCompletion(true));
    await _guard(() => _adapter.setAudioAttributesForNavigation());
  }

  @override
  Future<void> speak(String text) async {
    if (_disposed || !_pluginAvailable) return;
    if (text.trim().isEmpty) return;
    try {
      await _ensureConfigured();
      if (_disposed || !_pluginAvailable) return;

      final first = await _attempt(text);
      if (first == _SpeakOutcome.verified) {
        onSpeechVerified?.call();
        return;
      }
      if (first == _SpeakOutcome.timedOut) {
        // No retry after a timeout: the generous window already elapsed and
        // a second full window would hold the announcer far past the
        // hazard's moment. Recover + report instead.
        _recordUnverified(text, 'timeout (no completion report)');
        return;
      }
      // failed (platform replied but not 1): one retry after the rebind
      // window (see [retryDelay] doc for the verified plugin semantics).
      await Future<void>.delayed(retryDelay);
      if (_disposed || !_pluginAvailable) return;
      final second = await _attempt(text);
      if (second == _SpeakOutcome.verified) {
        onSpeechVerified?.call();
        return;
      }
      _recordUnverified(
        text,
        second == _SpeakOutcome.timedOut
            ? 'retry timeout (no completion report)'
            : 'platform reported failure twice',
      );
    } catch (e) {
      // Belt-and-suspenders: nothing above should throw, but the announcer
      // must never crash on a speech fault. An exception here still means
      // the delivery is unverified — say so.
      _recordUnverified(text, 'unexpected error: $e');
    }
  }

  Future<_SpeakOutcome> _attempt(String text) async {
    final timeout = _timeoutFor(text);
    try {
      // focus: true — Android requests transient-may-duck audio focus for
      // the utterance (FlutterTtsPlugin.kt:668-670 → requestAudioFocus,
      // kt:795-806 AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK; released in onDone,
      // kt:128), so HER music/radio ducks under the warning instead of
      // drowning it. Non-Android ignores the flag (flutter_tts.dart:355-362).
      final dynamic result =
          await _adapter.speak(text, focus: true).timeout(timeout);
      // Verified success/failure semantics (Android, FlutterTtsPlugin.kt):
      //   1 = utterance completed (kt:120-121 onDone → speakCompletion(1))
      //       or accepted when awaitSpeakCompletion is off (kt:324);
      //   0 = discarded while busy under QUEUE_FLUSH (kt:304-309) or
      //       stopped/paused before completion (kt:367-370, 379-382).
      // Anything that is not 1 is an UNVERIFIED delivery.
      return (result is num && result.toInt() == 1)
          ? _SpeakOutcome.verified
          : _SpeakOutcome.failed;
    } on TimeoutException {
      // The plugin's pending speakResult may still be held (the onError-hang
      // state, class doc). stop() makes the Kotlin side complete + clear it
      // (kt:373-383) and flushes the engine, so the NEXT announce starts
      // from a clean slot instead of leaking the stale one.
      await _guard(() => _adapter.stop())
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      return _SpeakOutcome.timedOut;
    } on MissingPluginException {
      _pluginAvailable = false;
      return _SpeakOutcome.failed;
    } catch (_) {
      return _SpeakOutcome.failed;
    }
  }

  void _recordUnverified(String text, String reason) {
    // One line, local-only (no network — LocalErrorLog contract). Log the
    // LENGTH, not the text: the spoken guidance can include location-ish
    // context; the log must stay free of anything position-like.
    errorLog?.record(
      'speech unverified: $reason (${text.length} chars)',
      null,
      source: 'HardenedTtsEngine',
    );
    onSpeechUnverified?.call();
  }

  // ==== Delegation parity with FlutterTtsEngine =========================
  // (voice_guidance/lib/src/flutter_tts_engine.dart — same guard, same
  // clamps, same rate mapping, so swapping engines never changes voice
  // behavior, only verification.)

  @override
  Future<bool> isAvailable() async {
    if (_disposed || !_pluginAvailable) return false;
    final dynamic langs = await _guard(() => _adapter.getLanguages());
    if (langs is List) return langs.isNotEmpty;
    return langs != null;
  }

  @override
  Future<void> setLanguage(String languageTag) async {
    await _guard(() => _adapter.setLanguage(languageTag));
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    await _guard(() => _adapter.setVolume(clamped));
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    // Identical mapping to FlutterTtsEngine (flutter_tts_engine.dart:58-66):
    // our 0.25..2.0 normalized scale → flutter_tts 0.0..1.0, base 1.0 → 0.5.
    final clamped = rate.clamp(0.25, 2.0).toDouble();
    final flutterTtsRate = (clamped / 2.0).clamp(0.0, 1.0);
    await _guard(() => _adapter.setSpeechRate(flutterTtsRate));
  }

  @override
  Future<void> stop() async {
    await _guard(() => _adapter.stop());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _guard(() => _adapter.stop());
    _disposed = true;
  }
}
