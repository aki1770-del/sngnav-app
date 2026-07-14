/// The offline mouth — a [TtsEngine] that speaks from bytes already on the phone.
///
/// The problem it solves. The app's only voice path was the system TTS, which on
/// the target device is silent (no offline Japanese voice is installed) and then
/// HANGS — flutter_tts' error callback never completes the Future, so a timeout
/// is the only recovery (see HardenedTtsEngine). With no network that is not a
/// degraded voice. It is no voice, and every road-surface warning the app had
/// carefully hardened arrived at a layer that could not say them.
///
/// This engine sits IN FRONT of the TTS engine and implements the same
/// `voice_guidance` [TtsEngine] interface, so wiring it in changed no caller:
///
///   speak(text) ─┬─ text is in the finite ja safety core ──► play bundled WAV
///                └─ anything else (slotted / non-safety) ──► delegate to TTS
///
/// Bundled-first, ALWAYS — not "offline fallback". The bundled audio is preferred
/// even when the network is up and TTS is alive, for three reasons that are all
/// about the driver and none about us:
///   1. It cannot hang. TTS can, and does, on the target device.
///   2. It is identical every time — same words, same pace, same voice. A driver
///      acting on a warning at 60 km/h on ice should not be re-parsing a
///      synthesiser's fresh reading of the sentence.
///   3. It behaves on the road exactly as it did on the bench. A voice path that
///      only ever executes with no network is a voice path nobody has heard.
///
/// Known limitations — recorded, not smoothed over:
///   • Slotted phrases (e.g. 「〜時頃の観測では…」, which interpolate an hour)
///     cannot be pre-rendered and still route to TTS. Where TTS is unavailable
///     they are SILENT. That is a real hole in the mouth. Closing it means
///     splicing (stem + number + tail), which is only worth doing if the drive
///     loop shows the timestamp matters more to the driver than the warning.
///   • The rendered voice is SYNTHESISED (open_jtalk / nitech-jp). Decision of
///     2026-07-12: synthesize now, record a human voice for the safety core
///     before winter. These files are the floor, not the destination — the
///     recordings replace them at the same ids and nothing else changes.
///   • On-device listening is NOT verified (no device available when this was
///     written). This engine is proven to resolve and to select the correct
///     asset; that the driver actually HEARS it is a device claim that has not
///     been earned and is not made here.
library;

import 'package:flutter/services.dart';
import 'package:voice_guidance/voice_guidance.dart' show TtsEngine;

import 'offline_safety_voice.dart';

/// Plays a bundled asset (path relative to the `assets/` root) at [volume].
///
/// Returns TRUE only when playback actually COMPLETED (the platform resolves
/// on MediaPlayer's completion listener — see MainActivity.kt). False means
/// she was not spoken to in full, and the caller must fall back rather than
/// assume she heard it. Because the Future spans the WHOLE utterance,
/// sequential `await speak(...)` calls serialize again: the second phrase
/// starts after the first finishes, never on top of it.
typedef PlayAsset = Future<bool> Function(String assetRelPath, double volume);

/// The first-party mouth: our own Kotlin MediaPlayer, no third-party plugin.
///
/// The safety voice was briefly routed through `audioplayers`, whose Android
/// module ships a buildscript pinned to Kotlin 1.7.10 / AGP 7.3.1 and declares a
/// top-level `kotlin { }` block for a plugin it never applies. Under Flutter's
/// modern plugin-loader that cannot resolve, and it BROKE THE APK BUILD while
/// `flutter test` stayed green — because the tests never build an APK. A voice
/// that must speak on a road with no network cannot sit on a third-party Gradle
/// contract that can silently un-build the app.
const MethodChannel kBundledAudioChannel = MethodChannel('sngnav/bundled_audio');

/// A [TtsEngine] that speaks the finite ja safety core from bundled audio and
/// delegates everything else to [fallback].
class BundledAudioEngine implements TtsEngine {
  BundledAudioEngine({
    required TtsEngine fallback,
    PlayAsset? playAsset,
    void Function(String assetPath)? onBundledSpoken,
    void Function(String text)? onDelegatedToTts,
    this.playTimeout = const Duration(seconds: 25),
  })  : _fallback = fallback,
        _injectedPlay = playAsset,
        _onBundledSpoken = onBundledSpoken,
        _onDelegatedToTts = onDelegatedToTts;

  final TtsEngine _fallback;
  final PlayAsset? _injectedPlay;
  final void Function(String assetPath)? _onBundledSpoken;
  final void Function(String text)? _onDelegatedToTts;

  /// N9 — cap on the raw platform-channel await in the default [_play]. The
  /// channel resolves on playback COMPLETION (MainActivity.kt), so a wedged
  /// player — or a channel that never answers — would otherwise hang every
  /// later sequential announce behind it; a timeout is the only recovery
  /// (HardenedTtsEngine's own verified rule). 25 s: the longest bundled
  /// safety phrase is 13.5 s (measured across assets/audio/ja/*.wav), so a
  /// genuine playback always finishes well inside the cap and is never cut
  /// into a false TTS fallback; anything still pending at 25 s is a wedged
  /// channel, and the fallback mouth is better than a mouth that never
  /// speaks again. On timeout the TimeoutException takes the existing
  /// catch → TTS-fallback path.
  final Duration playTimeout;

  /// The play seam. Injectable so a test can prove the ROUTING (that a safety
  /// phrase reaches bundled bytes and never the TTS) without a platform channel
  /// — off-device the channel throws, which would send every phrase down the
  /// fallback path and let a broken mouth look perfectly healthy in CI.
  PlayAsset get _play =>
      _injectedPlay ??
      (String assetRelPath, double volume) async {
        // N9 — the ONE raw platform await on the bundled path, capped (see
        // [playTimeout]). Un-timeouted, a wedged MediaPlayer would hang this
        // Future — and with completion-resolved play (N14) that hang would
        // also queue-starve every subsequent sequential announce.
        final ok = await kBundledAudioChannel.invokeMethod<bool>(
          'play',
          <String, Object?>{'asset': assetRelPath},
        ).timeout(playTimeout);
        return ok ?? false;
      };

  double _volume = 1.0;

  /// Always true. That is the whole point: the bundled core is available with
  /// the network gone, the voice pack absent, and the TTS engine dead. It is the
  /// first speech path in this app whose availability is not a question about
  /// somebody else's infrastructure.
  @override
  Future<bool> isAvailable() async => true;

  /// The bundled audio is already Japanese. Forwarded because the fallback still
  /// needs a language for slotted text.
  @override
  Future<void> setLanguage(String languageTag) =>
      _fallback.setLanguage(languageTag);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _fallback.setVolume(volume);
  }

  /// Rate is a synthesiser concept; a recorded phrase has the pace it was
  /// recorded at. Forwarded so slotted TTS text still respects the per-profile
  /// speaking rate.
  @override
  Future<void> setSpeechRate(double rate) => _fallback.setSpeechRate(rate);

  @override
  Future<void> speak(String text) async {
    final asset = OfflineSafetyVoice.assetFor(text);
    if (asset == null) {
      _onDelegatedToTts?.call(text);
      return _fallback.speak(text);
    }
    try {
      // Asset paths are relative to the `assets/` root declared in pubspec, so
      // the leading `assets/` is stripped.
      final spoke = await _play(asset.replaceFirst('assets/', ''), _volume);
      if (!spoke) {
        // The platform did not report playback COMPLETED (never started, or
        // errored mid-phrase). She was NOT verifiably spoken to in full.
        // Never record a phrase as delivered on a channel that returned
        // false. (A mid-phrase error means the TTS fallback may partially
        // repeat what she began hearing — deliberate: a doubled warning is
        // recoverable, a swallowed one is not.)
        _onDelegatedToTts?.call(text);
        await _fallback.speak(text);
        return;
      }
      _onBundledSpoken?.call(asset);
    } catch (_) {
      // If the bundled path itself faults, TTS is still better than silence —
      // even a TTS we do not trust. Never leave the driver with nothing.
      _onDelegatedToTts?.call(text);
      await _fallback.speak(text);
    }
  }

  @override
  Future<void> stop() async {
    // A safety phrase is short and must never be cut off mid-word; the native
    // player releases itself on completion. Nothing to stop here.
    await _fallback.stop();
  }

  @override
  Future<void> dispose() async => _fallback.dispose();
}
