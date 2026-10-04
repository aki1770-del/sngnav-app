/// Asking whether a fix would be trusted gives the same answer as feeding it.
///
/// Why, written before the act (2026-09-14). Before a share's first trusted
/// fix, the app now declines to give the drive brain an event that would not
/// be that fix, so it must know the answer before it feeds. The controller
/// keeps its last trusted time private, so the localizer answers from what the
/// controller emitted and from the controller's own geometry guard. If a
/// package bump changes what the controller trusts, the question and the feed
/// part ways, and this file goes red.
///
/// Each vector: ask a fresh localizer, then feed the same event to it and read
/// back whether the controller took it as a trusted fix.
///
/// Since 2026-10-05 the answer carries a GPS trust verdict, and
/// position_integrity has no way to ask without advancing. So each vector is
/// also asked TWICE before it is fed, and both answers must agree with what
/// feeding does; and a second group shows that asking does not change the
/// answer about the fix after it. The verdict-bearing vectors (a jump, a jump
/// that stays, a coarse fix, a replay) are the ones where a wrong design would
/// part asking from feeding.
///
/// Changed on 2026-10-05, each for a stated reason:
///  - 'a first fix', and the first fix in each `before` list: a share's first
///    fix has nothing to be judged against, so it is held, never trusted. Where
///    a vector means "after a trusted fix", that fix now has a predecessor one
///    second earlier at the same place, so the premise is true again.
///  - 'a fix beyond the honesty horizon (600 m)': a reported accuracy over
///    150 m is now `suspect` and is not adopted; it was adopted, then `lost`.
///  - 'a newer fix after a trusted one' stepped 1.1 km in 1 s, which no car
///    does; re-timed to 60 s (18.5 m/s), the coordinates unchanged.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_safety_fusion.dart';

final _t0 = DateTime.utc(2026, 1, 15, 6, 30);

PositionAvailable _fix(
  DateTime t, {
  double accuracy = 10,
  double lat = 39.72,
  double lon = 140.10,
}) =>
    PositionAvailable(
      latitude: lat,
      longitude: lon,
      accuracyMeters: accuracy,
      timestamp: t,
    );

/// A fix the controller trusts at [t]: the same place one second earlier,
/// then the fix itself.
List<PositionFix> _trustedAt(DateTime t, {double lat = 39.72}) => [
      _fix(t.subtract(const Duration(seconds: 1)), lat: lat),
      _fix(t, lat: lat),
    ];

/// Metres east at latitude 39.72, as degrees of longitude.
double _east(double metres) =>
    140.10 + metres / (6371000.0 * 3.141592653589793 / 180.0 * 0.769);

/// Asks, then feeds; returns (asked, taken as trusted).
(bool, bool) _askThenFeed(DriveLocalizer l, PositionFix event, DateTime now) {
  final asked = l.wouldTrust(event);
  final estimate = l.onPositionFix(event, now);
  return (asked, estimate.basis == EstimateBasis.trustedGpsFix);
}

void main() {
  test('control: a fix the controller trusts is anchored, with its basis', () {
    final l = DriveLocalizer();
    l.onPositionFix(_fix(_t0.subtract(const Duration(seconds: 1))), _t0);
    final e = l.onPositionFix(_fix(_t0), _t0);
    expect(e.basis, EstimateBasis.trustedGpsFix);
    expect(e.mode, LocalizationMode.gpsTrusted);
  });

  group('asked before feeding, the answer is what feeding it does', () {
    // (name, events fed first, the event asked about, the answer it must give)
    final vectors = <(String, List<PositionFix>, PositionFix, bool)>[
      ('a first fix: held, nothing to judge it against', [], _fix(_t0), false),
      (
        'a second fix, one second on, at the same place',
        [_fix(_t0.subtract(const Duration(seconds: 1)))],
        _fix(_t0),
        true
      ),
      (
        'a fix with accuracy 0 after a first fix',
        [_fix(_t0.subtract(const Duration(seconds: 1)), accuracy: 0)],
        _fix(_t0, accuracy: 0),
        true
      ),
      (
        'a fix beyond the honesty horizon (600 m): suspect, not adopted',
        [_fix(_t0.subtract(const Duration(seconds: 1)))],
        _fix(_t0, accuracy: 600),
        false
      ),
      ('a first fix with accuracy -1', [], _fix(_t0, accuracy: -1), false),
      (
        'a newer fix after a trusted one',
        _trustedAt(_t0),
        _fix(_t0.add(const Duration(seconds: 60)), lat: 39.73),
        true
      ),
      (
        'a fix with the same timestamp as the trusted one, elsewhere',
        _trustedAt(_t0),
        _fix(_t0, lat: 39.73),
        false
      ),
      (
        'an older fix than the trusted one',
        _trustedAt(_t0),
        _fix(_t0.subtract(const Duration(minutes: 20))),
        false
      ),
      (
        'a newer fix with accuracy -1 after a trusted one',
        _trustedAt(_t0),
        _fix(_t0.add(const Duration(seconds: 5)), accuracy: -1),
        false
      ),
      (
        'after a refused sample, a newer good fix',
        [
          _fix(_t0.subtract(const Duration(seconds: 1))),
          _fix(_t0, accuracy: -1),
        ],
        _fix(_t0.add(const Duration(seconds: 1))),
        true
      ),
      (
        'after an unavailability, a fix no newer than the old anchor',
        [..._trustedAt(_t0), const PositionUnavailable('GPS stream error: x')],
        _fix(_t0),
        false
      ),
      ('an unavailability', [], const PositionUnavailable('x'), false),
      (
        'an unavailability after a trusted fix',
        _trustedAt(_t0),
        const PositionUnavailable('x'),
        false
      ),
      // The verdict-bearing vectors (decided 2026-10-05).
      (
        'a jump: 300 m across the road in 1 s at ±10 m',
        _trustedAt(_t0),
        _fix(_t0.add(const Duration(seconds: 1)), lon: _east(300)),
        false
      ),
      (
        'a jump that stays: the fix after a 200 m jump, 15 m on from it',
        [
          ..._trustedAt(_t0),
          _fix(_t0.add(const Duration(seconds: 1)), lon: _east(200)),
        ],
        _fix(_t0.add(const Duration(seconds: 2)),
            lat: 39.72 + 15 / 111194.93, lon: _east(200)),
        false
      ),
      (
        'a coarse fix: ±400 m where she plausibly is',
        _trustedAt(_t0),
        _fix(_t0.add(const Duration(seconds: 1)), accuracy: 400),
        false
      ),
      (
        'a replay: the trusted fix again, its own timestamp',
        _trustedAt(_t0),
        _fix(_t0),
        false
      ),
      (
        // position_integrity judges the fix that comes back against the jump
        // (its KNOWN_LIMITATIONS §7, a one-fix transient).
        'after a jump, the fix that comes back is not yet trusted',
        [
          ..._trustedAt(_t0),
          _fix(_t0.add(const Duration(seconds: 1)), lon: _east(300)),
        ],
        _fix(_t0.add(const Duration(seconds: 2)),
            lat: 39.72 + 30 / 111194.93),
        false
      ),
      (
        'after a jump and the fix that comes back, the next clean fix is',
        [
          ..._trustedAt(_t0),
          _fix(_t0.add(const Duration(seconds: 1)), lon: _east(300)),
          _fix(_t0.add(const Duration(seconds: 2)),
              lat: 39.72 + 30 / 111194.93),
        ],
        _fix(_t0.add(const Duration(seconds: 3)),
            lat: 39.72 + 45 / 111194.93),
        true
      ),
      (
        'a satellite fix after a coarse one 300 m off: the coarse fix is no '
            'base',
        [
          ..._trustedAt(_t0),
          _fix(_t0.add(const Duration(seconds: 1)),
              accuracy: 400, lon: _east(300)),
        ],
        _fix(_t0.add(const Duration(seconds: 2)),
            lat: 39.72 + 30 / 111194.93),
        true
      ),
    ];

    for (final (name, before, event, want) in vectors) {
      test(name, () {
        final l = DriveLocalizer();
        for (final e in before) {
          l.onPositionFix(e, _t0);
        }
        final askedFirst = l.wouldTrust(event);
        final (asked, taken) = _askThenFeed(l, event, _t0);
        expect(taken, want,
            reason: 'control: what the controller did with it (vector wrong?)');
        expect(asked, taken, reason: 'asked before feeding: $name');
        expect(askedFirst, asked, reason: 'asked twice: $name');
      });
    }
  });

  group('asking does not change the answer about the next fix', () {
    // (name, events fed first, the event asked about and then fed, the next
    // event). One localizer is asked twice before each feed; the other is
    // only fed. Both must then say the same about the next event.
    final pairs = <(String, List<PositionFix>, PositionFix, PositionFix)>[
      (
        'a clean step, then another',
        _trustedAt(_t0),
        _fix(_t0.add(const Duration(seconds: 1)), lat: 39.72 + 15 / 111194.93),
        _fix(_t0.add(const Duration(seconds: 2)), lat: 39.72 + 30 / 111194.93),
      ),
      (
        'a jump, then the fix after it',
        _trustedAt(_t0),
        _fix(_t0.add(const Duration(seconds: 1)), lon: _east(300)),
        _fix(_t0.add(const Duration(seconds: 2)), lon: _east(300)),
      ),
      (
        'a replay, then a fix one second on',
        _trustedAt(_t0),
        _fix(_t0),
        _fix(_t0.add(const Duration(seconds: 1))),
      ),
      (
        'a first fix, then the second',
        [],
        _fix(_t0),
        _fix(_t0.add(const Duration(seconds: 1))),
      ),
    ];

    for (final (name, before, event, next) in pairs) {
      test(name, () {
        final asking = DriveLocalizer();
        final feeding = DriveLocalizer();
        for (final e in before) {
          asking.wouldTrust(e);
          asking.wouldTrust(e);
          asking.onPositionFix(e, _t0);
          feeding.onPositionFix(e, _t0);
        }
        asking.wouldTrust(event);
        asking.wouldTrust(event);
        final a = asking.onPositionFix(event, _t0);
        final f = feeding.onPositionFix(event, _t0);
        expect(a.mode, f.mode, reason: '$name: the event itself');
        final an = asking.onPositionFix(next, _t0);
        final fn = feeding.onPositionFix(next, _t0);
        expect(an.mode, fn.mode, reason: '$name: the next event');
        expect(an.basis, fn.basis, reason: '$name: the next event');
        expect(asking.lastVerdict?.acting, feeding.lastVerdict?.acting,
            reason: '$name: the next verdict');
      });
    }
  });
}
