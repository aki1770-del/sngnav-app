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
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_safety_fusion.dart';

final _t0 = DateTime.utc(2026, 1, 15, 6, 30);

PositionAvailable _fix(DateTime t, {double accuracy = 10, double lat = 39.72}) =>
    PositionAvailable(
      latitude: lat,
      longitude: 140.10,
      accuracyMeters: accuracy,
      timestamp: t,
    );

/// Asks, then feeds; returns (asked, taken as trusted).
(bool, bool) _askThenFeed(DriveLocalizer l, PositionFix event, DateTime now) {
  final asked = l.wouldTrust(event);
  final estimate = l.onPositionFix(event, now);
  return (asked, estimate.basis == EstimateBasis.trustedGpsFix);
}

void main() {
  test('control: a fix the controller trusts is anchored, with its basis', () {
    final l = DriveLocalizer();
    final e = l.onPositionFix(_fix(_t0), _t0);
    expect(e.basis, EstimateBasis.trustedGpsFix);
    expect(e.mode, LocalizationMode.gpsTrusted);
  });

  group('asked before feeding, the answer is what feeding it does', () {
    // (name, events fed first, the event asked about, the answer it must give)
    final vectors = <(String, List<PositionFix>, PositionFix, bool)>[
      ('a first fix', [], _fix(_t0), true),
      ('a first fix with accuracy 0', [], _fix(_t0, accuracy: 0), true),
      (
        'a first fix beyond the honesty horizon (600 m): adopted, lost',
        [],
        _fix(_t0, accuracy: 600),
        true
      ),
      ('a first fix with accuracy -1', [], _fix(_t0, accuracy: -1), false),
      (
        'a newer fix after a trusted one',
        [_fix(_t0)],
        _fix(_t0.add(const Duration(seconds: 1)), lat: 39.73),
        true
      ),
      (
        'a fix with the same timestamp as the trusted one, elsewhere',
        [_fix(_t0)],
        _fix(_t0, lat: 39.73),
        false
      ),
      (
        'an older fix than the trusted one',
        [_fix(_t0)],
        _fix(_t0.subtract(const Duration(minutes: 20))),
        false
      ),
      (
        'a newer fix with accuracy -1 after a trusted one',
        [_fix(_t0)],
        _fix(_t0.add(const Duration(seconds: 5)), accuracy: -1),
        false
      ),
      (
        'after a refused sample, a newer good fix',
        [_fix(_t0, accuracy: -1)],
        _fix(_t0.add(const Duration(seconds: 1))),
        true
      ),
      (
        'after an unavailability, a fix no newer than the old anchor',
        [_fix(_t0), const PositionUnavailable('GPS stream error: x')],
        _fix(_t0),
        false
      ),
      ('an unavailability', [], const PositionUnavailable('x'), false),
      (
        'an unavailability after a trusted fix',
        [_fix(_t0)],
        const PositionUnavailable('x'),
        false
      ),
    ];

    for (final (name, before, event, want) in vectors) {
      test(name, () {
        final l = DriveLocalizer();
        for (final e in before) {
          l.onPositionFix(e, _t0);
        }
        final (asked, taken) = _askThenFeed(l, event, _t0);
        expect(taken, want,
            reason: 'control: what the controller did with it (vector wrong?)');
        expect(asked, taken, reason: 'asked before feeding: $name');
      });
    }
  });
}
