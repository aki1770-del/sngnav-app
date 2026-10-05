/// A recording [AlertActuators] for WS5 tests.
///
/// This is the max honest in-env verification: it proves the app FIRES the
/// right channel with the right payload (audio + haptic, correct JA text +
/// locale). It does NOT — and cannot — prove the driver HEARS or FEELS
/// anything; that is on-device verification, DEFERRED.
library;

import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/actuators/alert_actuators.dart';

/// One recorded speak() call.
class SpokenLine {
  const SpokenLine(this.text, this.localeTag);
  final String text;
  final String localeTag;

  @override
  String toString() => 'SpokenLine("$text", $localeTag)';
}

/// Records every actuator call so a test can assert what the app fired.
class FakeAlertActuators implements AlertActuators {
  final List<SpokenLine> spoken = <SpokenLine>[];
  final List<HapticCuePattern> haptics = <HapticCuePattern>[];
  final List<bool> keepAwakeCalls = <bool>[];

  /// Every tactile cue in the order it was fired, by name: `warning`,
  /// `critical`, or `ended` (the cue that says a share has ended, which is no
  /// [HapticCuePattern] and so never appears in [haptics]). Added 2026-10-05:
  /// a test that reads only [haptics] cannot see the ended cue, so "nothing
  /// was felt" is asserted on this list.
  final List<String> felt = <String>[];

  @override
  Future<void> speak(String text, {required String localeTag}) async {
    spoken.add(SpokenLine(text, localeTag));
  }

  @override
  Future<void> haptic(HapticCuePattern pattern) async {
    haptics.add(pattern);
    if (pattern != HapticCuePattern.none) felt.add(pattern.name);
  }

  /// The ended cue ([AlertActuators.hapticEnded]).
  @override
  Future<void> hapticEnded() async {
    felt.add('ended');
  }

  @override
  Future<void> keepAwake(bool enabled) async {
    keepAwakeCalls.add(enabled);
  }
}
