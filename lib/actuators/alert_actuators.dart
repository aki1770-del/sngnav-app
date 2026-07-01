/// WS5 — the actuator layer that makes a hazard alert *reach* the driver.
///
/// **Why this exists (mission trace, <=4 hops).** HER — the Chair's mother in
/// Akita — is driving in unexpected snow. Maps and GPS have failed; she cannot
/// see where the road is. A hazard *rendered on screen* does not reach her:
/// her eyes are on the invisible road, not the phone. The alert that reaches
/// her is **audio** (she hears it) and **haptic** (she feels it). Until WS5,
/// `voice_guidance` reached her as SILENCE — the app never spoke. This layer
/// is the seam where a surfaced alert becomes something a driver can act on
/// without looking.
///   review (this file) -> alert reaches HER on audio+haptic -> she slows /
///   eases / considers stopping -> HER survives the whiteout.
///
/// (Never "turns back": the advisory ceiling is *consider stopping*; the
/// worst case demotes the MAP, never the JOURNEY to her mother — faithful to
/// the WS6 advisor doctrine in `drive_hud_localizer.dart`.)
///
/// **The accessibility floor (OPS-059).** The audio channel is not universal:
/// a deaf or hard-of-hearing driver hears nothing, and *no one* hears speech
/// inside a roaring-wind whiteout. So the haptic channel must carry the SAME
/// warning set as audio, off the SAME severity gate — never a reduced subset.
/// [AlertAnnouncer] enforces that parity; this interface is the injectable
/// seam that lets it drive real hardware on a phone and a NO-OP everywhere
/// else (desktop / tests / web), so the render-SEE ceiling stays intact.
///
/// **Honesty (OPS-066 / AAE-1).** Nothing in this file has been verified on an
/// Android device in this environment. It is code-complete; the "she HEARS /
/// FEELS it" claim is DEFERRED to on-device verification (see the checklist at
/// `docs/DEVICE_VERIFICATION.md`).
library;

import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity;
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;

/// The injectable actuator seam: the three physical channels a hazard alert
/// can reach a driver through without her looking at the screen.
///
/// Implementations:
/// - [NoOpAlertActuators] — the default on desktop / test / web. Does nothing
///   (safe; never touches a mobile-only plugin, so `flutter analyze`,
///   `flutter test`, and `flutter run -d linux` stay green).
/// - `MobileAlertActuators` (in `mobile_alert_actuators.dart`) — drives
///   flutter_tts / vibration / wakelock_plus, guarded to run ONLY on
///   android/ios.
abstract class AlertActuators {
  /// Speak [text] aloud in [localeTag] (a BCP-47 tag such as `ja-JP`).
  /// The eyes-off channel.
  Future<void> speak(String text, {required String localeTag});

  /// Fire the tactile cue for [pattern]. The deaf / HoH / can't-hear-over-the-
  /// wind channel. [HapticCuePattern.none] produces no sensation.
  Future<void> haptic(HapticCuePattern pattern);

  /// Hold ([enabled] true) or release the screen wakelock so a driver
  /// glancing at a live hazard surface never finds a dark screen.
  /// Foreground-only by contract — callers release it when the surface leaves.
  Future<void> keepAwake(bool enabled);
}

/// The default actuator on every non-mobile surface (desktop / test / web).
///
/// Records nothing, calls nothing. This is what keeps the desktop render-SEE
/// ceiling (`flutter run -d linux`) intact: no mobile-only plugin is ever
/// invoked, so there is no MissingPluginException to crash the surface.
class NoOpAlertActuators implements AlertActuators {
  const NoOpAlertActuators();

  @override
  Future<void> speak(String text, {required String localeTag}) async {}

  @override
  Future<void> haptic(HapticCuePattern pattern) async {}

  @override
  Future<void> keepAwake(bool enabled) async {}
}

/// Bridge a `navigation_safety_core` [AlertSeverity] to the catalog's tactile
/// [HapticCuePattern] grammar.
///
/// This mirrors `navigation_safety_enums.hapticCueForSeverity` one-for-one; we
/// re-declare it here only because `navigation_safety_core` ships its OWN
/// `AlertSeverity` type (it does not yet depend on / re-export the enums
/// package), so the enums-package function — which takes the *enums* package's
/// `AlertSeverity` — cannot be applied to the core type directly. The mapping
/// is identical, and the set of severities that produce a tactile cue
/// (`{warning, critical}`) is exactly the set the audio channel announces:
/// the deaf driver's cue set equals the hearing driver's warning set.
HapticCuePattern hapticCueForCoreSeverity(AlertSeverity severity) =>
    switch (severity) {
      AlertSeverity.info => HapticCuePattern.none,
      AlertSeverity.warning => HapticCuePattern.warning,
      AlertSeverity.critical => HapticCuePattern.critical,
    };

/// Normalize a locale tag to the full BCP-47 form flutter_tts expects.
///
/// The catalog's [AlertExplainer] emits short tags (`'ja'` / `'en'`);
/// flutter_tts's `setLanguage` wants a fully-qualified tag (`'ja-JP'` /
/// `'en-US'`) to select the right voice pack. Idempotent for tags that are
/// already qualified, pass-through for anything unrecognized.
String ttsLocaleTagFor(String localeTag) {
  final lower = localeTag.toLowerCase();
  if (lower == 'ja' || lower.startsWith('ja-') || lower.startsWith('ja_')) {
    return 'ja-JP';
  }
  if (lower == 'en' || lower.startsWith('en-') || lower.startsWith('en_')) {
    return 'en-US';
  }
  return localeTag;
}
