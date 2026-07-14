/// WS5 — the announcer that enforces the OPS-059 accessibility floor.
///
/// A surfaced hazard has a severity and a driver-facing guidance string (the
/// catalog's action-coupled [AlertExplainer] text). This class delivers it on
/// BOTH channels — audio for the eyes-off driver, haptic for the deaf / HoH /
/// can't-hear-over-the-wind driver — gated on the SAME severity threshold the
/// voice channel uses, so the two channels carry an identical warning set.
///
/// The gate mirrors `voice_guidance`'s exactly: a hazard is announced iff
/// `severity.index >= AlertSeverity.warning.index`. info-class alerts are not
/// announced on either channel (set parity). This is the floor's substance:
/// never a reduced haptic subset that silently drops the most serious warning
/// for the driver who can least afford to miss it.
library;

import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity;

import 'alert_actuators.dart';

/// Delivers a hazard to the driver on the audio + haptic channels.
class AlertAnnouncer {
  AlertAnnouncer({required this.actuators});

  final AlertActuators actuators;

  /// Cross-call delivery queue. Several call sites fire [announce] unawaited
  /// from INDEPENDENT timers (JMA feed-loss re-warn ticker; rung-rise from a
  /// fix event or the blackout-watchdog poll), so two announces can start in
  /// the same window and speak on top of each other — two overlapping
  /// utterances are BOTH unintelligible, the worst outcome for a warning.
  /// Chaining each announce behind the previous one's completion serializes
  /// delivery through this single shared announcer. The queue cannot wedge:
  /// every speak path inside is timeout-bounded (Dart 25 s cap + native 30 s
  /// backstop) and every failure arm is caught below.

  /// Announce [text] at [severity] in [localeTag].
  ///
  /// - Below `warning` (i.e. `info`): no-op on BOTH channels (parity with the
  ///   voice gate — info is not spoken, so it is not buzzed either).
  /// - `warning` / `critical`: speak the guidance aloud AND fire the tactile
  ///   cue for that severity. The eyes-off driver hears it; the deaf driver
  ///   feels it; a driver in a roaring whiteout gets the haptic her ears
  ///   cannot receive.
  ///
  /// [text] is passed through VERBATIM — it is the catalog's publisher-owned
  /// action string (AAA Article 17 β); the announcer must not paraphrase.
  /// [localeTag] is normalized to a full BCP-47 TTS tag ([ttsLocaleTagFor]).
  ///
  /// **OPS-059 channel independence (load-bearing).** The two channels are
  /// fired INDEPENDENTLY, each in its own guard: a fault on one MUST NOT
  /// suppress the other. The haptic cue — the channel the deaf / HoH /
  /// can't-hear-over-the-wind driver depends on — is fired FIRST and is
  /// unconditional on speech success, so a TTS fault can never silence the
  /// tactile warning. (Were `speak()` awaited before `haptic()` and allowed
  /// to throw, the most-vulnerable driver would lose the one channel she can
  /// receive — the exact reduced-subset failure the floor forbids.)
  Future<void> _tail = Future<void>.value();

  Future<void> announce({
    required AlertSeverity severity,
    required String text,
    required String localeTag,
  }) {
    if (severity.index < AlertSeverity.warning.index) {
      return Future<void>.value();
    }
    // Serialize behind the previous announce (see [_tail]). The gate check
    // above stays OUTSIDE the queue: an info-class no-op never occupies a
    // queue slot. _deliver never throws (both channel arms are guarded), so
    // the chain cannot break.
    final prev = _tail;
    final next = () async {
      await prev;
      await _deliver(severity: severity, text: text, localeTag: localeTag);
    }();
    _tail = next;
    return next;
  }

  Future<void> _deliver({
    required AlertSeverity severity,
    required String text,
    required String localeTag,
  }) async {
    final ttsTag = ttsLocaleTagFor(localeTag);
    // Haptic first + guarded: the tactile cue is delivered regardless of the
    // audio channel's fate.
    try {
      await actuators.haptic(hapticCueForCoreSeverity(severity));
    } catch (_) {
      // A haptic fault must not suppress the audio channel fired below.
    }
    // Audio second + guarded: a TTS throw is swallowed here, never propagating
    // back to short-circuit the haptic already fired above.
    try {
      await actuators.speak(text, localeTag: ttsTag);
    } catch (_) {
      // The eyes-off driver loses audio on a TTS fault, but the haptic (above)
      // still reached the deaf / HoH driver — parity preserved.
    }
  }
}
