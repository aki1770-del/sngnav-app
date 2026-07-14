/// N8 — the real-GPS-blackout watchdog decision table.
///
/// The degradation machine's poll() was production-wired ONLY to the demo
/// blackout button: in a REAL blackout no fix events arrive, nothing polls,
/// and the honest dot stays "trusted" forever — a confidently-wrong dot in
/// exactly the compound-failure scenario the app exists for. The app now
/// polls on a periodic tick through [positionWatchdogPollTime]; this table
/// pins when it polls, when it stays quiet, and which clock it uses.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/main.dart' show positionWatchdogPollTime;

void main() {
  final now = DateTime.utc(2026, 1, 15, 6, 30);
  const cadence = Duration(seconds: 30);

  group('positionWatchdogPollTime', () {
    test('nothing ever fed → no poll (no baseline to degrade; the permission '
        'dialog may still be up)', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: null,
          demoClock: null,
        ),
        isNull,
      );
    });

    test('a fresh event within the cadence → no poll (the pipeline is alive; '
        'degrading it would cry wolf at a healthy feed)', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(const Duration(seconds: 29)),
          demoClock: null,
        ),
        isNull,
      );
    });

    test('a drought at exactly the cadence → POLL (the boundary counts as '
        'stale — absence must not get a free extra tick of calm)', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(cadence),
          demoClock: null,
        ),
        now,
      );
    });

    test('a real drought → poll with the real clock', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(const Duration(minutes: 3)),
          demoClock: null,
        ),
        now,
      );
    });

    test('demo blackout clock AHEAD of real now → poll with the demo clock '
        '(the localizer clock must never run backwards mid-degradation)', () {
      final demoClock = now.add(const Duration(seconds: 120));
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(const Duration(minutes: 3)),
          demoClock: demoClock,
        ),
        demoClock,
      );
    });

    test('demo clock BEHIND real now (stale baseline, no demo pressed lately) '
        '→ the real clock wins', () {
      expect(
        positionWatchdogPollTime(
          now: now,
          lastPositionEventAt: now.subtract(const Duration(minutes: 3)),
          demoClock: now.subtract(const Duration(minutes: 3)),
        ),
        now,
      );
    });
  });
}
