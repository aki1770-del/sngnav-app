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
    this.streamMuted,
  });

  /// Current STREAM_MUSIC volume (platform index units, 0..[mediaVolumeMax]).
  final int mediaVolume;

  /// Maximum STREAM_MUSIC volume index for this device.
  final int mediaVolumeMax;

  /// Whether ANY text-to-speech service resolves on the device. A device
  /// with no TTS engine cannot speak regardless of volume.
  final bool ttsServiceVisible;

  /// Whether the platform reports STREAM_MUSIC as MUTED, independent of the
  /// index. `null` = the platform did not say (an APK predating the key) —
  /// honest-unknown, and [mediaMuted] then rests on the index alone rather
  /// than guessing.
  ///
  /// ⚑ Added 2026-08-22 after measuring the counter-example on a device: the
  /// AVD reported `STREAM_MUSIC: Muted: true` in `dumpsys audio` while
  /// `getStreamVolume` returned 5 of 15, so this app read a silent device as
  /// audible and HER media-muted caution never rendered. Index and mute are
  /// two platform facts behind two different calls; reading one and calling
  /// it the other is an absent measurement rendered as the safe value.
  final bool? streamMuted;

  /// Volume as a 0–100 percentage. A `mediaVolumeMax <= 0` reply (never
  /// observed on real devices, but the platform type allows it) is guarded
  /// to 0 rather than dividing by zero.
  int get mediaVolumePct => mediaVolumeMax <= 0
      ? 0
      : ((mediaVolume * 100) / mediaVolumeMax).round().clamp(0, 100);

  /// True when no spoken alert can be heard: the index is at zero, OR the
  /// platform reports the stream muted at any index.
  bool get mediaMuted => mediaVolume <= 0 || (streamMuted ?? false);
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
    // ABSENT and WRONG-TYPED are different answers and are treated
    // differently: an APK that predates this key says nothing (null =
    // unknown, decode continues), while a key of the wrong type is a
    // corrupt reply and the whole reading is discarded.
    final streamMuted = raw['streamMuted'];
    if (streamMuted != null && streamMuted is! bool) return null;
    return AudioReadiness(
      mediaVolume: mediaVolume,
      mediaVolumeMax: mediaVolumeMax,
      ttsServiceVisible: ttsServiceVisible,
      streamMuted: streamMuted as bool?,
    );
  }
}
