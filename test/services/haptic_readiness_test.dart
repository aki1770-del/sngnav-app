// The tactile channel, probed BEFORE the drive — the gap AAA ruled PUSHBACK
// load-bearing on 2026-08-22.
//
// Measured that day (`outputs/operational-records/aaa_verdict_eyes_off_channel_boundary_2026_08_22.md`):
// `_probeAudioCautions()` fired at FOUR sites — app open, a 45 s ticker, real
// drive start, mock drive start — under the app's own comment *"the drive is
// when a mute matters"*. The tactile channel had NONE of the four: its only
// readiness call ran inside `fire()`, when a warning was already owed. So the
// app could tell her before the drive that speech would not reach her, and
// could only tell her after a lost warning that vibration had not.
//
// Every test below is about a PROBE, not a buzz. Whether she feels it is not
// knowable from any API; whether this device claims a vibrator is.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/actuators/hardened_haptic_channel.dart';
import 'package:sngnav_app/services/haptic_readiness.dart';

class _Driver implements HapticDriver {
  _Driver({this.present = true, this.throws = false, this.hangs = false});
  final bool present;
  final bool throws;
  final bool hangs;
  int calls = 0;

  @override
  Future<bool> hasVibrator() async {
    calls++;
    if (throws) throw StateError('platform channel exploded');
    if (hangs) return Completer<bool>().future;
    return present;
  }

  @override
  Future<void> vibrate(List<int> waveformMs) async {}
}

void main() {
  group('DriverHapticReadinessProbe', () {
    test('a device that reports a vibrator -> true', () async {
      final probe = DriverHapticReadinessProbe(
        driver: _Driver(),
        platformSupported: true,
      );
      expect(await probe.read(), isTrue);
    });

    test('a device that reports none -> false (the caution-worthy answer)',
        () async {
      final probe = DriverHapticReadinessProbe(
        driver: _Driver(present: false),
        platformSupported: true,
      );
      expect(await probe.read(), isFalse);
    });

    test('the platform THROWS -> null, never false — an unreadable channel is '
        'unknown, and unknown must not raise a caution about a device that '
        'may vibrate perfectly well', () async {
      final probe = DriverHapticReadinessProbe(
        driver: _Driver(throws: true),
        platformSupported: true,
      );
      expect(await probe.read(), isNull);
    });

    test('the platform HANGS -> null, bounded by the timeout', () async {
      final probe = DriverHapticReadinessProbe(
        driver: _Driver(hangs: true),
        platformSupported: true,
        timeout: const Duration(milliseconds: 40),
      );
      final sw = Stopwatch()..start();
      expect(await probe.read(), isNull);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'a pre-drive probe must never wedge the drive surface');
    });

    test('off-mobile / under the test binding -> null, and the platform is '
        'never touched', () async {
      final driver = _Driver(present: false);
      final probe = DriverHapticReadinessProbe(driver: driver);
      expect(await probe.read(), isNull);
      expect(driver.calls, 0);
    });
  });
}
