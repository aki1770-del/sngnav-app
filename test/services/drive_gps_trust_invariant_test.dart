/// A GPS fix is assessed before it is shown as 「GPS 良好」 or spoken as given.
///
/// Why, written before the act (2026-10-04). The drive brain feeds every
/// finite fix to `LocalizationController.onFix` with no trust verdict
/// (`drive_safety_fusion.dart`, `DriveLocalizer.onPositionFix`), and
/// localization_fallback 0.1.4 defaults that verdict to `trusted`. Its own doc
/// says what follows: "a multipath or teleported fix is presented as a
/// confident dot, and guidance will be spoken from it". The app's only guard
/// upstream is a finite-coordinate check. So a jump no car made reads
/// 「GPS 良好」 and the next turn is read aloud as given (「そのまま読み上げます」).
/// The gap was first written down on 2026-07-14 and is still open.
///
/// What these tests hold. Every case is fed through the app's own production
/// seam, a default-constructed [DriveHudController], one fix per second. A
/// FAULT case must not end in `gpsTrusted`, must not be labelled 「GPS 良好」 or
/// "GPS good", and must not narrate the turn at `speak`; the plain turn line
/// must not reach the audio channel. A CONTROL case is the same drive without
/// the fault, and it must still end in `gpsTrusted`, 「GPS 良好」 and `speak`.
///
/// Why the controls are here. A wiring that trusted nothing (`suspect` on
/// every fix) would pass every fault case and hide the fault a different way:
/// 「GPS 良好」 would never be shown, so the label would stop telling her
/// anything, and the hedged turn would be spoken on a clean road. The controls
/// make that wiring red. They are green on `fc53fd6` and must stay green.
///
/// Why default construction. The verdict must be computed inside the seam,
/// not passed in by each caller. A verdict a caller has to remember to supply
/// is the same believes-by-default hole, one layer up: when it is forgotten,
/// the fix is trusted again and nothing says so. These tests use only the
/// constructor and the feed the app uses today, so a wiring that needs the
/// caller's help stays red.
///
/// What these tests do NOT hold, and must not be read as holding:
///  - A multipath offset that builds up slowly, or that is present from the
///    first fix of a share, is not caught by any pairwise plausibility gate and
///    is not tested here.
///  - Only the transition onto a displaced track is held (the jump fix and the
///    fix after it). A displaced track that later becomes consistent with the
///    last trusted fix is not held, because no pairwise gate can hold it.
///  - The first fix after a long blackout is not held (position_integrity
///    0.1.1 `KNOWN_LIMITATIONS.md`, section 8).
///  - No device, no real receiver. Every fix here is synthetic. The accuracy
///    figures are what each case needs, not readings from her phone.
///  - Nothing here decides what she should see or hear instead, only that it
///    is not the confident state. The wording is a separate design decision.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';

import '../support/fake_alert_actuators.dart';

// --- geometry: a straight road north out of Akita city, one fix a second ---

final _t0 = DateTime.utc(2026, 1, 15, 6, 30);
const double _lat0 = 39.72;
const double _lon0 = 140.10;

/// Metres per degree of latitude on the sphere both packages use (R = 6371 km).
const double _mPerDegLat = 6371000.0 * math.pi / 180.0;
final double _mPerDegLon = _mPerDegLat * math.cos(_lat0 * math.pi / 180.0);

/// Her cruising speed on a snowy two-lane road: 15 m/s = 54 km/h.
const double _v = 15.0;

/// One fix at [second], [northM] up the road and [eastM] across it, with the
/// platform's reported horizontal accuracy [acc]. [speed] is the platform's
/// reported ground speed, carried the way `fixFromSample` carries it; `null`
/// is a platform that reported none.
PositionAvailable _at(
  int second, {
  required double northM,
  double eastM = 0,
  double acc = 5,
  double? speed = _v,
  int? timestampSecond,
}) =>
    PositionAvailable(
      latitude: _lat0 + northM / _mPerDegLat,
      longitude: _lon0 + eastM / _mPerDegLon,
      accuracyMeters: acc,
      timestamp: _t0.add(Duration(seconds: timestampSecond ?? second)),
      speedFloorMps: speed == null ? null : speed + 0.5,
      motion: speed == null
          ? GroundMotion.unknown
          : (speed - 0.5 > kStoppedAtMostMps
              ? GroundMotion.moving
              : GroundMotion.unknown),
    );

/// A clean drive: fixes 0..n-1 at [_v] straight up the road.
List<PositionAvailable> _cleanTrack(int n) =>
    [for (var s = 0; s < n; s++) _at(s, northM: _v * s)];

// --- the seam and what she is shown ---

const _text = DriveHudLocalizer();

RouteManeuver _rightTurn() => const RouteManeuver(
      index: 1,
      instruction: 'Right onto Route 13',
      type: 'right',
      lengthKm: 0.4,
      timeSeconds: 30,
      position: LatLng(39.73, 140.10),
    );

/// The plain, as-given turn line (the `speak` text), 「この先、右折です。」.
final String _plainTurnJa = _text.maneuverInstruction('right', 'ja');

DriveHudController _controller(FakeAlertActuators fake) {
  final c = DriveHudController(actuators: fake, localeTag: 'ja');
  // Good visibility, no advisory: the caution rung stays quiet, so the only
  // thing the turn can be is the turn.
  c.updateEnvironment(
    visibilityMeters: 10000,
    visibilityAgeSeconds: 0,
    advisorySeverity: null,
    speedMetersPerSecond: null,
  );
  return c;
}

void _feed(DriveHudController c, PositionAvailable f) =>
    c.onPositionFix(f, now: f.timestamp);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// FAULT: the fix just fed must not be presented as good GPS, and the turn
/// must not be read aloud as given.
Future<void> _expectNotPresentedAsGood(
  DriveHudController c,
  FakeAlertActuators fake,
  String why,
) async {
  final mode = c.estimate!.mode;
  expect(mode, isNot(LocalizationMode.gpsTrusted), reason: why);
  expect(_text.modeLabel(mode, 'ja'), isNot('GPS 良好'), reason: why);
  expect(_text.modeLabel(mode, 'en'), isNot('GPS good'), reason: why);
  final spokenBefore = fake.spoken.length;
  final d = c.narrateNextManeuver(_rightTurn(), icyTurn: false);
  await _settle();
  expect(d.confidence, isNot(NarrationConfidence.speak), reason: why);
  expect(
    fake.spoken.skip(spokenBefore).any((s) => s.text.contains(_plainTurnJa)),
    isFalse,
    reason: '$why: the plain turn 「$_plainTurnJa」 reached the audio channel',
  );
}

/// CONTROL: the fix just fed must still be good GPS, spoken as given.
Future<void> _expectPresentedAsGood(
  DriveHudController c,
  FakeAlertActuators fake,
  String why,
) async {
  final mode = c.estimate!.mode;
  expect(mode, LocalizationMode.gpsTrusted, reason: why);
  expect(_text.modeLabel(mode, 'ja'), 'GPS 良好', reason: why);
  final spokenBefore = fake.spoken.length;
  final d = c.narrateNextManeuver(_rightTurn(), icyTurn: false);
  await _settle();
  expect(d.confidence, NarrationConfidence.speak, reason: why);
  expect(
    fake.spoken.skip(spokenBefore).any((s) => s.text.contains(_plainTurnJa)),
    isTrue,
    reason: '$why: the plain turn did not reach the audio channel',
  );
}

void main() {
  test('geometry check: the clean track really is 15 m apart a second', () {
    // If this helper were wrong, every case below would measure the wrong
    // thing. Haversine on the same sphere the packages use.
    double metres(PositionAvailable a, PositionAvailable b) {
      final p1 = a.latitude * math.pi / 180, p2 = b.latitude * math.pi / 180;
      final dp = p2 - p1, dl = (b.longitude - a.longitude) * math.pi / 180;
      final h = math.pow(math.sin(dp / 2), 2) +
          math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
      return 2 * 6371000.0 * math.asin(math.min(1.0, math.sqrt(h)));
    }

    final t = _cleanTrack(2);
    expect(metres(t[0], t[1]), closeTo(15.0, 0.01));
    expect(
      metres(_at(0, northM: 0), _at(0, northM: 0, eastM: 300)),
      closeTo(300.0, 0.05),
    );
  });

  group('CONTROLS: a clean drive is still good GPS, spoken as given', () {
    test('C1 a clean drive at 54 km/h, accuracy 5 m, ten fixes', () async {
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      final track = _cleanTrack(10);
      for (var i = 0; i < track.length; i++) {
        _feed(c, track[i]);
        // Fixes 0 and 1 are a warm-up: a verdict that wants two fixes before
        // it trusts is not excluded by this control.
        if (i >= 2) {
          expect(c.estimate!.mode, LocalizationMode.gpsTrusted,
              reason: 'C1 fix $i of a clean drive');
        }
      }
      await _expectPresentedAsGood(c, fake, 'C1 end of a clean drive');
    });

    test('C2 braking at 7 m/s² to a stop, then parked with 2 m jitter',
        () async {
      // 15 → 8 → 1 → 0 m/s: hard but legal winter braking, then stationary
      // with the small wander a parked receiver shows.
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      final track = _cleanTrack(6); // north 0..75 m
      final stop = <PositionAvailable>[
        _at(6, northM: 75 + 8, speed: 8),
        _at(7, northM: 75 + 9, speed: 1),
        _at(8, northM: 84 + 1.0, eastM: 0.5, speed: null),
        _at(9, northM: 84 - 0.5, eastM: -1.0, speed: null),
        _at(10, northM: 84 + 1.5, eastM: 1.0, speed: null),
        _at(11, northM: 84, eastM: -0.5, speed: null),
      ];
      for (final f in [...track, ...stop]) {
        _feed(c, f);
      }
      await _expectPresentedAsGood(c, fake, 'C2 parked after a legal stop');
    });

    test('C3 a 20 s tunnel, then a fix where she plausibly is', () async {
      // 15 m/s for 20 s = 300 m. The second fix after the gap must be trusted
      // again; one fix of caution on reacquisition is not excluded.
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      final track = _cleanTrack(6); // last at second 5, north 75 m
      for (final f in track) {
        _feed(c, f);
      }
      for (var s = 6; s <= 25; s++) {
        c.poll(now: _t0.add(Duration(seconds: s)));
      }
      _feed(c, _at(26, northM: 75 + _v * 21));
      _feed(c, _at(27, northM: 75 + _v * 22));
      await _expectPresentedAsGood(c, fake, 'C3 second fix after a tunnel');
    });

    test('C4 a 30 m accuracy fix on a clean drive is still good GPS',
        () async {
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      final track = _cleanTrack(8);
      for (final f in track) {
        _feed(c, f);
      }
      _feed(c, _at(8, northM: _v * 8, acc: 30));
      await _expectPresentedAsGood(c, fake, 'C4 accuracy 30 m on track');
    });

    test('C5 a fix replayed with the SAME timestamp is already not trusted',
        () async {
      // Protection that exists today (localization_fallback 0.1.4,
      // `localization_controller.dart:108-110`): a fix no newer than the last
      // trusted one is not current. It must stay that way.
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      final track = _cleanTrack(6);
      for (final f in track) {
        _feed(c, f);
      }
      _feed(c, _at(6, northM: _v * 5, timestampSecond: 5));
      await _expectNotPresentedAsGood(
          c, fake, 'C5 frozen fix replayed with its old timestamp');
    });
  });

  group('FAULTS: a fix no car could produce is not good GPS', () {
    test('JUMP 300 m across the road in 1 s at reported accuracy 5 m',
        () async {
      // Implied 300 m/s (1,080 km/h). The receiver still says ±5 m.
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      for (final f in _cleanTrack(6)) {
        _feed(c, f);
      }
      _feed(c, _at(6, northM: _v * 6, eastM: 300));
      await _expectNotPresentedAsGood(c, fake, 'JUMP the jump fix');
    });

    test('SPEED 70 m up the road in 1 s at reported accuracy 8 m', () async {
      // Along her own road, so it is not a sideways jump: implied 70 m/s
      // (252 km/h), above any road vehicle's 50 m/s.
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      for (final f in _cleanTrack(6)) {
        _feed(c, f);
      }
      _feed(c, _at(6, northM: _v * 5 + 70, acc: 8));
      await _expectNotPresentedAsGood(
          c, fake, 'SPEED the speed-implausible step');
    });

    test('HOLD a 200 m jump onto a parallel road that STAYS there', () async {
      // Multipath onto the next valley road: the fix jumps 200 m east and then
      // carries on at her speed. From the last fix that was trusted (second
      // 5), the fix after the jump is 202 m away in 2 s: 101 m/s. A gate that
      // re-baselines onto the jump fix sees an ordinary 15 m step and trusts it.
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      for (final f in _cleanTrack(6)) {
        _feed(c, f);
      }
      _feed(c, _at(6, northM: _v * 6, eastM: 200));
      await _expectNotPresentedAsGood(c, fake, 'HOLD the jump fix');
      _feed(c, _at(7, northM: _v * 7, eastM: 200));
      await _expectNotPresentedAsGood(
          c, fake, 'HOLD the fix after the jump, still 200 m off');
    });

    test('MULTIPATH 40 m sideways at reported accuracy 8 m, onset fix',
        () async {
      // A coherent multipath offset larger than the receiver's own claim: the
      // ±8 m circle excludes where she is by 32 m. At its onset the fix steps
      // 40 m across the road in 1 s at 54 km/h: implied 42.7 m/s, under the
      // 50 m/s speed gate, but a change of speed of 27.7 m/s in one second.
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      for (final f in _cleanTrack(6)) {
        _feed(c, f);
      }
      _feed(c, _at(6, northM: _v * 6, eastM: 40, acc: 8));
      await _expectNotPresentedAsGood(
          c, fake, 'MULTIPATH onset of a 40 m offset at ±8 m');
    });

    test('FROZEN the position stops while the platform says 15 m/s',
        () async {
      // The receiver keeps sending the same coordinates with NEW timestamps,
      // and the platform's own speed with each fix still says 15 m/s. In 3 s
      // she has moved 45 m; the dot has moved 0. (Replaying the same timestamp
      // is C5, already caught.)
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      for (final f in _cleanTrack(6)) {
        _feed(c, f);
      }
      for (var s = 6; s <= 8; s++) {
        _feed(c, _at(s, northM: _v * 5));
      }
      await _expectNotPresentedAsGood(
          c, fake, 'FROZEN three frozen fixes against a moving speed');
    });

    test('COARSE a 400 m accuracy fix where she plausibly is', () async {
      // A network-grade fix (no satellites in the valley). Its position is
      // plausible, but the receiver itself says ±400 m. compound_failure_advisor
      // 0.1.2 calls anything over 150 m "neighbourhood scale"
      // (`kRadiusNeighbourhoodM`), yet `trusted` raises no position concern at
      // any radius, and localization_fallback 0.1.4 trusts up to 500 m.
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      for (final f in _cleanTrack(6)) {
        _feed(c, f);
      }
      _feed(c, _at(6, northM: _v * 6, acc: 400));
      await _expectNotPresentedAsGood(
          c, fake, 'COARSE a ±400 m fix labelled GPS');
    });

    test('COARSE-FIRST the first fix of a share is ±400 m', () async {
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      _feed(c, _at(0, northM: 0, acc: 400));
      await _expectNotPresentedAsGood(
          c, fake, 'COARSE-FIRST a ±400 m first fix labelled GPS');
    });
  });
}
