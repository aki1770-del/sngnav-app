// Added 2026-09-02, re-landed on `0bc7351` 2026-09-19 — RECORD, NEVER GATE.
//
// `hasVibrator()` DOES NOT ASK THE VIBRATOR. Read from source this turn at the
// version this app resolves (pubspec.lock -> vibration 3.2.0):
//   vibration_platform_interface-0.1.2/lib/src/method_channel_vibration.dart
//     :21-30  `if (!deviceData.isPhysicalDevice) return false;  return true;`
// and its catch falls through to `false` on any PlatformException and on any
// non-Android/iOS platform. It is a heuristic that CANNOT FAIL OPEN.
//
// Gating the vibration on it means every device the heuristic misreads gets NO
// TACTILE WARNING. For a deaf or hard-of-hearing driver that is the only
// channel there is (the accessibility rule — an accessibility channel is never gated),
// and at ten metres' visibility the screen is not a substitute.
//
// The honest REPORT must not change: the outcome stays `noVibrator` and stays
// unverified, so her "tactile cue unverified" chip still raises. What changes
// is that the buzz is ATTEMPTED anyway.
//
// This test FAILS on 0bc7351 (the signed 0.0.2+3 build): there, `!present`
// assigned the outcome and returned without ever calling vibrate().

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/actuators/hardened_haptic_channel.dart';

/// The heuristic says "not a phone" — the case a misread real device hits.
class _ProbeSaysNoDriver implements HapticDriver {
  _ProbeSaysNoDriver({this.vibrateThrows = false});

  final bool vibrateThrows;
  final List<List<int>> vibrations = <List<int>>[];

  @override
  Future<bool> hasVibrator() async => false;

  @override
  Future<void> vibrate(List<int> waveformMs) async {
    vibrations.add(waveformMs);
    if (vibrateThrows) throw StateError('platform refused');
  }
}

void main() {
  test('a false hasVibrator() probe must NOT withhold the cue', () async {
    final driver = _ProbeSaysNoDriver();
    var unverified = 0;
    var verified = 0;
    final channel = HardenedHapticChannel(
      driver: driver,
      onHapticUnverified: () => unverified++,
      onHapticVerified: () => verified++,
    );

    final outcome = await channel.fire(HapticCuePattern.critical);

    // THE POINT: she gets the buzz her hardware can produce.
    expect(driver.vibrations, isNotEmpty,
        reason: 'hasVibrator() answers "am I a real phone?", never "can I '
            'vibrate?". Skipping vibrate() on it denies the tactile warning '
            'to the driver who has no other channel.');
    expect(driver.vibrations.single, waveformFor(HapticCuePattern.critical),
        reason: 'the attempted waveform is the real cue, not a token buzz — '
            'pulse COUNT is the deaf driver\'s only severity distinction');

    // The honesty is UNCHANGED — we still do not claim she felt it.
    expect(outcome, HapticDelivery.noVibrator);
    expect(outcome.isUnverified, isTrue);
    expect(unverified, 1);
    expect(verified, 0,
        reason: 'attempting more must never be reported as verifying more');
  });

  test('a throwing attempt does not downgrade the honest noVibrator report',
      () async {
    final driver = _ProbeSaysNoDriver(vibrateThrows: true);
    var unverified = 0;
    final channel = HardenedHapticChannel(
      driver: driver,
      onHapticUnverified: () => unverified++,
    );

    final outcome = await channel.fire(HapticCuePattern.warning);

    expect(driver.vibrations, isNotEmpty, reason: 'it was still attempted');
    expect(outcome, HapticDelivery.noVibrator,
        reason: 'the probe already said unverified; a failed best-effort '
            'attempt must not replace that with the less informative '
            '`faulted`');
    expect(unverified, 1);
  });

  test('info-class cues are still not owed a sensation', () async {
    final driver = _ProbeSaysNoDriver();
    final channel = HardenedHapticChannel(driver: driver);

    final outcome = await channel.fire(HapticCuePattern.none);

    expect(outcome, HapticDelivery.notOwed);
    expect(driver.vibrations, isEmpty,
        reason: 'never-gate applies to an OWED cue; it is not a licence to '
            'buzz on every info advisory (cry-wolf)');
  });
}
