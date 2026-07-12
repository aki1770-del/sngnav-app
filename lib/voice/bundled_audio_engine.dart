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

import 'package:audioplayers/audioplayers.dart';
import 'package:voice_guidance/voice_guidance.dart' show TtsEngine;

import 'offline_safety_voice.dart';

/// Plays a bundled asset (path relative to the `assets/` root) at [volume].
typedef PlayAsset = Future<void> Function(String assetRelPath, double volume);

/// A [TtsEngine] that speaks the finite ja safety core from bundled audio and
/// delegates everything else to [fallback].
class BundledAudioEngine implements TtsEngine {
  BundledAudioEngine({
    required TtsEngine fallback,
    PlayAsset? playAsset,
    void Function(String assetPath)? onBundledSpoken,
    void Function(String text)? onDelegatedToTts,
  })  : _fallback = fallback,
        _injectedPlay = playAsset,
        _onBundledSpoken = onBundledSpoken,
        _onDelegatedToTts = onDelegatedToTts;

  final TtsEngine _fallback;
  final PlayAsset? _injectedPlay;
  final void Function(String assetPath)? _onBundledSpoken;
  final void Function(String text)? _onDelegatedToTts;

  AudioPlayer? _resolved;
  AudioPlayer get _player => _resolved ??= AudioPlayer();

  /// The play seam. Injectable so a test can prove the ROUTING (that a safety
  /// phrase reaches bundled bytes and never the TTS) without a platform channel
  /// — the real AudioPlayer throws off-device, which would send every phrase
  /// down the fallback path and let a broken mouth look healthy in CI.
  PlayAsset get _play =>
      _injectedPlay ??
      (String assetRelPath, double volume) async {
        await _player.play(AssetSource(assetRelPath), volume: volume);
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
    try {
      // `_resolved`, not `_player` — see stop(). The volume is carried in
      // `_volume` and applied at play() time, so there is nothing to build here.
      await _resolved?.setVolume(_volume);
    } catch (_) {
      // A player fault must never crash the surface a driver is relying on.
    }
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
      // AssetSource paths are relative to the `assets/` root declared in
      // pubspec, so the leading `assets/` is stripped.
      await _play(asset.replaceFirst('assets/', ''), _volume);
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
    try {
      // `_resolved`, never `_player`: building a player in order to stop it
      // would construct a platform channel that may not exist (and, off-device,
      // throws) for no reason at all. Nothing playing means nothing to stop.
      await _resolved?.stop();
    } catch (_) {
      // Stopping a player that never started is not a fault.
    }
    await _fallback.stop();
  }

  @override
  Future<void> dispose() async {
    try {
      await _resolved?.dispose();
    } catch (_) {
      // Disposing a player that was never built is not a fault.
    }
    _resolved = null;
    await _fallback.dispose();
  }
}
