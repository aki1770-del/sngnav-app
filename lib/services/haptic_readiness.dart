/// Pre-drive readiness of the TACTILE channel — the probe the audio channel
/// always had and this one did not.
///
/// **Why this exists.** AAA's 2026-08-22 verdict
/// (`outputs/operational-records/aaa_verdict_eyes_off_channel_boundary_2026_08_22.md`)
/// ruled PUSHBACK, load-bearing, on a measured asymmetry: `_probeAudioCautions()`
/// fired at four triggers — app open, a 45 s ticker, real drive start, mock
/// drive start — under this app's own comment *"the drive is when a mute
/// matters"*. The tactile channel had none of them. Its only readiness call
/// lived inside `HardenedHapticChannel.fire()`, which runs when a warning is
/// already owed. So the app could tell her BEFORE the drive that speech would
/// not reach her, and could only tell her AFTER a lost warning that vibration
/// had not — on the channel that, for a deaf or hard-of-hearing driver, is not
/// the second one.
///
/// AAA named the remedy and did not build it (its bylaws forbid authoring
/// code); this file is AAE's build of it, on the same cadence as the audio
/// probe by construction — see `_probeAlertChannelReadiness` in `main.dart`
/// and the anti-drift test in `test/actuators/haptic_report_wiring_test.dart`.
library;

import 'dart:async';

import '../actuators/hardened_haptic_channel.dart'
    show HapticDriver, VibrationPluginHapticDriver;
import '../actuators/mobile_alert_actuators.dart' show isMobileActuatorPlatform;

/// Injectable probe seam, mirroring `AudioReadinessProbe`.
///
/// `true` = the platform reports a vibrator · `false` = it reports none ·
/// **`null` = it did not answer** (non-mobile, test binding, a channel that
/// threw or hung). Null is honest-unknown and renders NOTHING: a caution about
/// a device that may vibrate perfectly well is a false alarm, and this channel
/// cannot afford to cry wolf.
abstract interface class HapticReadinessProbe {
  Future<bool?> read();
}

/// The production probe: one `hasVibrator()` read, bounded and fail-soft.
final class DriverHapticReadinessProbe implements HapticReadinessProbe {
  const DriverHapticReadinessProbe({
    HapticDriver driver = const VibrationPluginHapticDriver(),
    bool? platformSupported,
    this.timeout = const Duration(seconds: 2),
  })  : _driver = driver,
        _platformSupportedOverride = platformSupported;

  final HapticDriver _driver;
  final bool? _platformSupportedOverride;

  /// Same cap and same rationale as `HardenedHapticChannel.callTimeout`: a
  /// platform channel that never answers must not wedge the surface she is
  /// about to drive with.
  final Duration timeout;

  @override
  Future<bool?> read() async {
    final supported = _platformSupportedOverride ?? isMobileActuatorPlatform;
    if (!supported) return null;
    try {
      return await _driver.hasVibrator().timeout(timeout);
    } catch (_) {
      // TimeoutException / PlatformException / MissingPluginException /
      // anything: unreadable is UNKNOWN, never "no vibrator". Reporting a
      // fault as an absence would put a caution on HER screen about a device
      // we never actually asked.
      return null;
    }
  }
}
