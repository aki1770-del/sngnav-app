/// The announcer that enforces the accessibility floor.
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

/// Which tactile cue an announcement carries.
enum AnnounceCue {
  /// The cue for its severity (the catalog's grammar): every warning.
  severity,

  /// The ended cue ([AlertActuators.hapticEnded]): the lines that are not a
  /// warning but say a share has ended. The stop confirmation at 停止
  /// (decided 2026-10-05), and, since 2026-10-10, the line told when the app
  /// ends a share without its service as it leaves the screen. Its severity
  /// only opens the gate.
  ended,
}

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
  /// action string (Article 17 β, verbatim relay); the announcer must not paraphrase.
  /// [localeTag] is normalized to a full BCP-47 TTS tag ([ttsLocaleTagFor]).
  ///
  /// **Channel independence (load-bearing, accessibility floor).** The two channels are
  /// fired INDEPENDENTLY, each in its own guard: a fault on one MUST NOT
  /// suppress the other. The haptic cue — the channel the deaf / HoH /
  /// can't-hear-over-the-wind driver depends on — is fired FIRST and is
  /// unconditional on speech success, so a TTS fault can never silence the
  /// tactile warning. (Were `speak()` awaited before `haptic()` and allowed
  /// to throw, the most-vulnerable driver would lose the one channel she can
  /// receive — the exact reduced-subset failure the floor forbids.)
  Future<void> _tail = Future<void>.value();

  ///
  /// **[deliverIf], read at DELIVERY (added 2026-10-10).** A line whose truth
  /// can lapse while it waits in the queue passes the condition under which it
  /// is still true. It is read after the wait and before either channel fires.
  /// If it is false then, NOTHING of this announcement is delivered: neither
  /// the cue nor the words, never one without the other. A condition that
  /// throws counts as false (the line plays only when its truth is
  /// established). It is read here, in the one queue body, because this is
  /// the only caller of [_deliver]: no announcement reaches a channel without
  /// passing it. Lines whose words cannot lapse pass none.
  Future<void> announce({
    required AlertSeverity severity,
    required String text,
    required String localeTag,
    String? spokenPrefix,
    AnnounceCue cue = AnnounceCue.severity,
    bool Function()? deliverIf,
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
      if (deliverIf != null && !_holds(deliverIf)) return;
      await _deliver(
        severity: severity,
        text: text,
        localeTag: localeTag,
        spokenPrefix: spokenPrefix,
        cue: cue,
      );
    }();
    _tail = next;
    return next;
  }

  /// [deliverIf] read once, at delivery. A throw counts as false.
  static bool _holds(bool Function() deliverIf) {
    try {
      return deliverIf();
    } catch (_) {
      return false;
    }
  }

  Future<void> _deliver({
    required AlertSeverity severity,
    required String text,
    required String localeTag,
    String? spokenPrefix,
    AnnounceCue cue = AnnounceCue.severity,
  }) async {
    final ttsTag = ttsLocaleTagFor(localeTag);
    // Haptic first + guarded: the tactile cue is delivered regardless of the
    // audio channel's fate.
    try {
      switch (cue) {
        case AnnounceCue.severity:
          await actuators.haptic(hapticCueForCoreSeverity(severity));
        case AnnounceCue.ended:
          await actuators.hapticEnded();
      }
    } catch (_) {
      // A haptic fault must not suppress the audio channel fired below.
    }
    // [spokenPrefix] (e.g. テスト値です。) is its own utterance,
    // spoken before [text] and guarded on its own: [text] stays the exact
    // string the offline audio is looked up by, and a fault on the prefix
    // never silences the line.
    if (spokenPrefix != null && spokenPrefix.isNotEmpty) {
      try {
        await actuators.speak(spokenPrefix, localeTag: ttsTag);
      } catch (_) {
        // The line below is still spoken.
      }
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
