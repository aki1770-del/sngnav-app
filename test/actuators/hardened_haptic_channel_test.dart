// The deaf / HoH driver's ONLY channel, under test for the first time.
//
// Founding measurement (2026-08-21, AVD sngnav_api30, API 30, vibrator HAL
// present): the app's announce dispatched Japanese TTS and registered ZERO
// vibrations in `dumpsys vibrator`, whose recording capability was proven by a
// negative control. Nothing anywhere reported it. The prior implementation had
// two silent exits — a `hasVibrator()` false branch and a bare `catch (_)` —
// and no seam through which either could be observed.
//
// Every test below asserts a REPORT, not a buzz. Whether she felt it is not
// knowable from any API; whether the cue was owed and did not land is.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/actuators/hardened_haptic_channel.dart';
import 'package:sngnav_app/services/error_log.dart';

/// A driver whose every behaviour is dictated by the test.
class _FakeDriver implements HapticDriver {
  _FakeDriver({
    this.present = true,
    this.hasVibratorThrows = false,
    this.vibrateThrows = false,
    this.hasVibratorHangs = false,
    this.vibrateHangs = false,
  });

  final bool present;
  final bool hasVibratorThrows;
  final bool vibrateThrows;
  final bool hasVibratorHangs;
  final bool vibrateHangs;

  int hasVibratorCalls = 0;
  final List<List<int>> vibrations = <List<int>>[];

  @override
  Future<bool> hasVibrator() async {
    hasVibratorCalls++;
    if (hasVibratorThrows) throw StateError('platform channel exploded');
    if (hasVibratorHangs) return Completer<bool>().future; // never completes
    return present;
  }

  @override
  Future<void> vibrate(List<int> waveformMs) async {
    if (vibrateThrows) throw StateError('vibrate rejected');
    if (vibrateHangs) return Completer<void>().future; // never completes
    vibrations.add(waveformMs);
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('haptic_report_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  LocalErrorLog makeLog() =>
      LocalErrorLog(file: File('${tmp.path}/error_log.txt'));
  String logText() {
    final f = File('${tmp.path}/error_log.txt');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  group('an owed cue that does not land is REPORTED', () {
    test(
      'no vibrator -> noVibrator, one log line, onHapticUnverified once',
      () async {
        var unverified = 0;
        var verified = 0;
        final log = makeLog();
        final channel = HardenedHapticChannel(
          driver: _FakeDriver(present: false),
          errorLog: log,
          onHapticUnverified: () => unverified++,
          onHapticVerified: () => verified++,
        );

        final outcome = await channel.fire(HapticCuePattern.critical);

        expect(outcome, HapticDelivery.noVibrator);
        expect(outcome.isUnverified, isTrue);
        expect(unverified, 1);
        expect(verified, 0);
        expect(logText(), contains('haptic unverified: noVibrator'));
        expect(logText(), contains('cue critical'));
        expect(logText(), contains('HardenedHapticChannel'));
      },
    );

    test('hasVibrator itself throws -> faulted and reported', () async {
      // The FIRST platform call is the one that threw on no device we have
      // ever measured — but it is the call that runs on EVERY cue, so an
      // unguarded throw here loses every tactile warning of the drive, not
      // one. Left untested until 2026-08-22, and the analyzer said so:
      // `unused_element_parameter` on `hasVibratorThrows` was the only
      // signal that this branch had a fixture and no test.
      var unverified = 0;
      final driver = _FakeDriver(hasVibratorThrows: true);
      final channel = HardenedHapticChannel(
        driver: driver,
        errorLog: makeLog(),
        onHapticUnverified: () => unverified++,
      );

      expect(
        await channel.fire(HapticCuePattern.critical),
        HapticDelivery.faulted,
      );
      expect(unverified, 1);
      expect(driver.vibrations, isEmpty);
      expect(logText(), contains('haptic unverified: faulted'));
    });

    test('platform throws -> faulted and reported', () async {
      var unverified = 0;
      final channel = HardenedHapticChannel(
        driver: _FakeDriver(vibrateThrows: true),
        errorLog: makeLog(),
        onHapticUnverified: () => unverified++,
      );

      expect(
        await channel.fire(HapticCuePattern.warning),
        HapticDelivery.faulted,
      );
      expect(unverified, 1);
      expect(logText(), contains('haptic unverified: faulted'));
    });

    test(
      'platform hangs -> timedOut and reported, bounded by callTimeout',
      () async {
        var unverified = 0;
        final channel = HardenedHapticChannel(
          driver: _FakeDriver(vibrateHangs: true),
          errorLog: makeLog(),
          onHapticUnverified: () => unverified++,
          callTimeout: const Duration(milliseconds: 40),
        );

        final sw = Stopwatch()..start();
        final outcome = await channel.fire(HapticCuePattern.critical);
        sw.stop();

        expect(
          outcome,
          HapticDelivery.timedOut,
          reason: 'a hang is not a throw: it is silence',
        );
        expect(unverified, 1);
        expect(
          sw.elapsedMilliseconds,
          lessThan(2000),
          reason: 'a wedged haptic must never hold the spoken warning hostage',
        );
        expect(logText(), contains('haptic unverified: timedOut'));
      },
    );

    test('hasVibrator itself hangs -> timedOut and reported', () async {
      var unverified = 0;
      final channel = HardenedHapticChannel(
        driver: _FakeDriver(hasVibratorHangs: true),
        errorLog: makeLog(),
        onHapticUnverified: () => unverified++,
        callTimeout: const Duration(milliseconds: 40),
      );
      expect(
        await channel.fire(HapticCuePattern.warning),
        HapticDelivery.timedOut,
      );
      expect(unverified, 1);
    });
  });

  group('the CONTROLS — reporting must not cry wolf', () {
    test(
      'a cue that lands -> delivered, onHapticVerified, NO log line',
      () async {
        var unverified = 0;
        var verified = 0;
        final driver = _FakeDriver();
        final channel = HardenedHapticChannel(
          driver: driver,
          errorLog: makeLog(),
          onHapticUnverified: () => unverified++,
          onHapticVerified: () => verified++,
        );

        final outcome = await channel.fire(HapticCuePattern.critical);

        expect(outcome, HapticDelivery.delivered);
        expect(outcome.isUnverified, isFalse);
        expect(verified, 1);
        expect(unverified, 0);
        expect(
          logText(),
          isEmpty,
          reason: 'a delivered cue must leave HER log clean',
        );
        expect(driver.vibrations, hasLength(1));
      },
    );

    test(
      'info-class (none) -> notOwed, driver untouched, nothing reported',
      () async {
        var unverified = 0;
        var verified = 0;
        final driver = _FakeDriver(present: false);
        final channel = HardenedHapticChannel(
          driver: driver,
          errorLog: makeLog(),
          onHapticUnverified: () => unverified++,
          onHapticVerified: () => verified++,
        );

        final outcome = await channel.fire(HapticCuePattern.none);

        expect(outcome, HapticDelivery.notOwed);
        expect(outcome.isUnverified, isFalse);
        expect(
          driver.hasVibratorCalls,
          0,
          reason: 'no sensation is owed, so no platform call is made',
        );
        expect(
          unverified,
          0,
          reason: 'reporting an info-class non-buzz would cry wolf every tick',
        );
        expect(verified, 0);
        expect(logText(), isEmpty);
      },
    );
  });

  group('reporting can never become the second fault', () {
    test('a throwing listener does not escape fire()', () async {
      final channel = HardenedHapticChannel(
        driver: _FakeDriver(present: false),
        errorLog: makeLog(),
        onHapticUnverified: () => throw StateError('listener exploded'),
      );
      expect(
        await channel.fire(HapticCuePattern.critical),
        HapticDelivery.noVibrator,
      );
    });

    test('an unwritable log does not escape fire()', () async {
      final channel = HardenedHapticChannel(
        driver: _FakeDriver(present: false),
        // A directory path where a file is expected: every write fails.
        errorLog: LocalErrorLog(file: File(tmp.path)),
      );
      expect(
        await channel.fire(HapticCuePattern.critical),
        HapticDelivery.noVibrator,
      );
    });
  });

  group(
    'the waveform grammar carries the deaf driver severity distinction',
    () {
      test('warning = 2 pulses, critical = 3, critical pulses are longer', () {
        final warning = waveformFor(HapticCuePattern.warning);
        final critical = waveformFor(HapticCuePattern.critical);

        // [0, on, gap, on] and [0, on, gap, on, gap, on]
        expect(warning.length, 4);
        expect(critical.length, 6);
        expect(warning.first, 0, reason: 'leading wait');
        expect(critical.first, 0);
        expect(warning[1], 200);
        expect(
          critical[1],
          350,
          reason:
              'a second distinguishing axis beyond count, per HapticCuePattern',
        );
        expect(critical[1], greaterThan(warning[1]));
      });

      test('none produces no pulses', () {
        expect(waveformFor(HapticCuePattern.none), <int>[0]);
      });
    },
  );
}
