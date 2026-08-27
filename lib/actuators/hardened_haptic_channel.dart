/// The haptic twin of [HardenedTtsEngine] — a tactile channel that reports
/// whether the cue was actually accepted by the platform.
///
/// **Why this exists (mission trace, <=4 hops).** For a deaf or hard-of-hearing
/// driver — and for ANY driver inside a roaring-wind whiteout — the haptic
/// channel is not the second channel. It is the only one. Until this file, the
/// app's haptic path was:
///
/// ```dart
/// if (await Vibration.hasVibrator()) { await Vibration.vibrate(...); }
/// } catch (_) { }
/// ```
///
/// Both exits are silent. A device that reports no vibrator took the `if`
/// and did nothing; a platform fault or a wedged channel took the `catch` and
/// did nothing; and in **neither** case was anyone told — not HER, not the
/// app, not the on-device log. The audio channel had all three of the things
/// this one lacked: an injectable seam ([TtsEngine]), an error log, and
/// verified/unverified reporting ([HardenedTtsEngine.onSpeechUnverified]).
/// That asymmetry was visible in `MobileAlertActuators`'s own constructor
/// parameter list, and it meant the channel the OPS-059 accessibility floor
/// exists to protect was the one channel with no delivery verification.
///   this channel reports a silent haptic -> the app can say the tactile cue
///   did not land -> HER is not left believing a warning was felt when none
///   was -> she is not relying on a channel that is not there.
///
/// **Measured, 2026-08-21, on AVD `sngnav_api30` (API 30, vibrator HAL
/// present).** Tapping "Announce to driver (audio + haptic)" at severity
/// `critical` dispatched Japanese TTS (`ja-jp-x-jab-lstm-embedded`, audio
/// focus `req=3`) and registered **zero** vibrations in `dumpsys vibrator`,
/// whose `Previous vibrations:` block was proven capable of recording one by a
/// negative control (`cmd vibrator vibrate 800`). Record:
/// `outputs/operational-records/aae_ondevice_verification_2026_08_21.md`.
///
/// **What "verified" means here, precisely.** [HapticDelivery.delivered] means
/// *the platform accepted the waveform* — the same bound `vibrate()` itself
/// carries, since its Future resolves on acceptance and not when the buzzing
/// ends. It does **not** mean she felt it. No API on either platform reports
/// that, and this file does not pretend otherwise: the honest ceiling is
/// "dispatched and accepted", and the unverified states below are the ones
/// that are genuinely knowable.
library;

import 'dart:async';

import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern, HapticCuePatternRendering;
import 'package:vibration/vibration.dart';

import '../services/error_log.dart';

/// The injectable vibration seam.
///
/// Exists for the same reason [TtsEngine] does: `MobileAlertActuators.haptic()`
/// sits behind a platform guard that early-returns under `flutter_test`, so
/// anything reachable only through it is, by construction, untestable. The
/// audio channel was given a seam and got tests; the haptic channel was not
/// and did not.
abstract class HapticDriver {
  /// Whether this device reports a vibrator at all.
  Future<bool> hasVibrator();

  /// Fire [waveformMs] as `[waitMs, onMs, waitMs, onMs, ...]`.
  Future<void> vibrate(List<int> waveformMs);
}

/// The production driver: the `vibration` plugin, untouched.
class VibrationPluginHapticDriver implements HapticDriver {
  const VibrationPluginHapticDriver();

  @override
  Future<bool> hasVibrator() => Vibration.hasVibrator();

  @override
  Future<void> vibrate(List<int> waveformMs) =>
      Vibration.vibrate(pattern: waveformMs);
}

/// What actually happened to a tactile cue.
///
/// Only [delivered] and [notOwed] are benign. The other three are the states
/// that were previously indistinguishable from success.
enum HapticDelivery {
  /// The platform accepted the waveform. (Not: she felt it — see the library
  /// doc.)
  delivered,

  /// The cue was `HapticCuePattern.none` (info-class). No sensation is OWED,
  /// so nothing failed and nothing is reported — reporting here would be
  /// crying wolf on every info-class advisory.
  notOwed,

  /// The device reports no vibrator. The cue was owed and cannot be given.
  noVibrator,

  /// The platform channel threw.
  faulted,

  /// The platform channel did not answer inside the call timeout. A hang is
  /// not a throw: it is silence, and only the throw was previously guarded.
  timedOut,
}

/// Whether this outcome means an owed tactile cue did not land.
extension HapticDeliveryReporting on HapticDelivery {
  bool get isUnverified => switch (this) {
    HapticDelivery.delivered => false,
    HapticDelivery.notOwed => false,
    HapticDelivery.noVibrator => true,
    HapticDelivery.faulted => true,
    HapticDelivery.timedOut => true,
  };
}

/// The injectable tactile channel — the haptic mirror of `TtsEngine`.
///
/// `MobileAlertActuators` holds one of these, exactly as it holds a
/// [TtsEngine]; production resolves it to [HardenedHapticChannel] and a test
/// injects its own.
abstract class HapticChannel {
  /// Fire the cue for [pattern] and report what became of it. Never throws.
  Future<HapticDelivery> fire(HapticCuePattern pattern);
}

/// Fires tactile cues and says, every time, whether the cue landed.
///
/// Never throws — a haptic fault must not crash the drive surface, and must
/// not block the spoken warning that [AlertAnnouncer] fires immediately after
/// (haptic-first is deliberate: were speak() awaited first, a wedged TTS would
/// hold the tactile warning hostage from the very driver who cannot hear it).
class HardenedHapticChannel implements HapticChannel {
  HardenedHapticChannel({
    HapticDriver driver = const VibrationPluginHapticDriver(),
    this.errorLog,
    this.onHapticUnverified,
    this.onHapticVerified,
    this.callTimeout = const Duration(seconds: 2),
  }) : _driver = driver;

  final HapticDriver _driver;

  /// Local, on-device, no-network log (LocalErrorLog contract). One line per
  /// unverified cue.
  final LocalErrorLog? errorLog;

  /// Invoked once per cue that was OWED and did not land. The in-drive HUD
  /// raises its tactile-unverified chip on this, exactly as it does for
  /// speech.
  final void Function()? onHapticUnverified;

  /// Invoked once per cue the platform accepted — the chip clears on this, so
  /// a transient fault does not pin a warning on screen for the rest of the
  /// drive.
  final void Function()? onHapticVerified;

  /// Cap on each raw plugin await. N9's rationale, unchanged: the announcer
  /// awaits haptic BEFORE speak, so a platform channel that never answers
  /// would hold the SPOKEN warning hostage forever. 2 s is generous for a
  /// query/enqueue call and short enough that a wedged haptic delays the voice
  /// by at most ~4 s instead of silencing it for good.
  final Duration callTimeout;

  @override
  Future<HapticDelivery> fire(HapticCuePattern pattern) async {
    if (!pattern.isTactile) return HapticDelivery.notOwed;

    HapticDelivery outcome;
    try {
      final present = await _driver.hasVibrator().timeout(callTimeout);
      if (!present) {
        outcome = HapticDelivery.noVibrator;
      } else {
        await _driver.vibrate(waveformFor(pattern)).timeout(callTimeout);
        outcome = HapticDelivery.delivered;
      }
    } on TimeoutException {
      outcome = HapticDelivery.timedOut;
    } catch (_) {
      outcome = HapticDelivery.faulted;
    }

    _report(pattern, outcome);
    return outcome;
  }

  void _report(HapticCuePattern pattern, HapticDelivery outcome) {
    // Never let reporting become the second fault. Everything below is
    // best-effort; LocalErrorLog.record already never throws, and the
    // callbacks are the page's own setState-guarded notifiers.
    try {
      if (!outcome.isUnverified) {
        onHapticVerified?.call();
        return;
      }
      // The pattern NAME only. A tactile cue carries no text, but the log
      // stays free of anything context-like on principle — same discipline as
      // HardenedTtsEngine logging the length and never the spoken words.
      errorLog?.record(
        'haptic unverified: ${outcome.name} (cue ${pattern.name})',
        null,
        source: 'HardenedHapticChannel',
      );
      onHapticUnverified?.call();
    } catch (_) {
      // Swallow: a broken log or a listener that throws must not turn a
      // missing buzz into a crashed drive surface.
    }
  }
}

/// Android waveform `[initialWaitMs, vibrateMs, waitMs, vibrateMs, ...]` built
/// from the catalog grammar's [HapticCuePattern.pulseCount] (warning = 2
/// measured pulses, critical = 3 urgent pulses). The two announced tiers are
/// distinguishable by COUNT — so a deaf driver can tell "reduce speed"
/// (warning) from "consider stopping" (critical) — and by a longer per-pulse
/// duration on critical (a second distinguishing axis), per HapticCuePattern's
/// cited deaf/HoH-driver rationale.
///
/// Public (was private to `mobile_alert_actuators.dart`) so the grammar that
/// carries the deaf driver's ONLY severity distinction is directly testable.
List<int> waveformFor(HapticCuePattern pattern) {
  final onMs = pattern == HapticCuePattern.critical ? 350 : 200;
  const gapMs = 150;
  final wave = <int>[0];
  for (var i = 0; i < pattern.pulseCount; i++) {
    wave.add(onMs);
    if (i < pattern.pulseCount - 1) wave.add(gapMs);
  }
  return wave;
}
