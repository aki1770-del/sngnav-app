/// Tier-2 pre-drive audio readiness probe (the unit's first first-party
/// Kotlin surface; Chair-ratified 2026-07-11, proposal §Tier-2).
///
/// Answers ONE Dart-unreachable question before HER drive: *is the media
/// stream muted?* Media-volume-zero silences every spoken safety alert and
/// no plugin in our set exposes the volume — the app would drive HER into a
/// whiteout believing its ja warning will sound while the platform plays it
/// into silence. The platform side is a ~30-line read-only MethodChannel in
/// `MainActivity.kt` (`sngnav/audio_readiness`).
///
/// READ-ONLY BY DESIGN (the Tier-3 dignity boundary the Chair holds): we
/// inform, we NEVER touch her volume. The pre-drive surface warns and asks
/// for acknowledgment — it never blocks the drive and never adjusts a
/// setting on her behalf.
///
/// Honest-null posture (matches voice_lane_readiness.dart): anything we
/// cannot read — non-mobile platform, test binding, old APK without the
/// channel (MissingPluginException), malformed reply, any platform fault —
/// is `null`, and the surface shows NOTHING for null. Honest-unknown is
/// never a guess.
library;

import 'package:flutter/services.dart';

import '../actuators/mobile_alert_actuators.dart' show isMobileActuatorPlatform;

/// One read of the platform's audio-output readiness.
final class AudioReadiness {
  const AudioReadiness({
    required this.mediaVolume,
    required this.mediaVolumeMax,
    required this.ttsServiceVisible,
  });

  /// Current STREAM_MUSIC volume (platform index units, 0..[mediaVolumeMax]).
  final int mediaVolume;

  /// Maximum STREAM_MUSIC volume index for this device.
  final int mediaVolumeMax;

  /// Whether ANY text-to-speech service resolves on the device. A device
  /// with no TTS engine cannot speak regardless of volume.
  final bool ttsServiceVisible;

  /// Volume as a 0–100 percentage. A `mediaVolumeMax <= 0` reply (never
  /// observed on real devices, but the platform type allows it) is guarded
  /// to 0 rather than dividing by zero.
  int get mediaVolumePct => mediaVolumeMax <= 0
      ? 0
      : ((mediaVolume * 100) / mediaVolumeMax).round().clamp(0, 100);

  /// True when the media stream is at zero: every spoken alert is silent.
  bool get mediaMuted => mediaVolume <= 0;
}

/// Injectable probe seam. `null` = probe unavailable (non-Android, test
/// binding, APK-skew without the channel) — honest-unknown, never a guess.
abstract interface class AudioReadinessProbe {
  Future<AudioReadiness?> read();
}

/// Production probe over the `sngnav/audio_readiness` MethodChannel.
///
/// Never throws: MissingPluginException (old APK / non-Android engine),
/// PlatformException, or a malformed reply all resolve to `null`. Guarded by
/// the shared [isMobileActuatorPlatform] so the channel is never invoked
/// off-mobile or under the flutter_test binding ([platformSupported] lets
/// the channel-path tests bypass that guard while still exercising the real
/// channel decode).
final class ChannelAudioReadinessProbe implements AudioReadinessProbe {
  const ChannelAudioReadinessProbe({bool? platformSupported})
      : _platformSupportedOverride = platformSupported;

  static const MethodChannel _channel =
      MethodChannel('sngnav/audio_readiness');

  final bool? _platformSupportedOverride;

  @override
  Future<AudioReadiness?> read() async {
    final supported = _platformSupportedOverride ?? isMobileActuatorPlatform;
    if (!supported) return null;
    Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('read');
    } catch (_) {
      // MissingPluginException / PlatformException / anything: unreadable.
      return null;
    }
    if (raw is! Map) return null;
    final mediaVolume = raw['mediaVolume'];
    final mediaVolumeMax = raw['mediaVolumeMax'];
    final ttsServiceVisible = raw['ttsServiceVisible'];
    if (mediaVolume is! int || mediaVolumeMax is! int ||
        ttsServiceVisible is! bool) {
      return null;
    }
    return AudioReadiness(
      mediaVolume: mediaVolume,
      mediaVolumeMax: mediaVolumeMax,
      ttsServiceVisible: ttsServiceVisible,
    );
  }
}
