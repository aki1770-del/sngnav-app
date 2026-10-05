/// A GPS fix is assessed before it is shown as 「GPS 良好」 or spoken as given.
///
/// Why, written before the act (2026-10-04). The drive brain feeds every
/// finite fix to `LocalizationController.onFix` with no trust verdict
/// (`drive_safety_fusion.dart`, `DriveLocalizer.onPositionFix`), and
/// localization_fallback 0.1.4 defaults that verdict to `trusted`. Its own doc
/// says what follows: "a multipath or teleported fix is presented as a
/// confident dot, and guidance will be spoken from it". The app's only guard
/// upstream is a finite-coordinate check. So a jump no car made reads
/// 「GPS 良好」, the map follows it with a small ring, the caution rung stays
/// at its lowest, and a turn read on her press is read as given
/// (「そのまま読み上げます」). The gap was first written down on 2026-07-14.
///
/// How every case is fed. Each fix starts as a geolocator `Position`, with
/// the platform's flags, its accuracy, its speed and its speed accuracy, and
/// goes through the app's own parser (`herPositionStream`) before it reaches
/// a default-constructed [DriveHudController], one fix per second. So any
/// field the parser learns to carry (a lower bound on speed, for example)
/// reaches these fixtures without editing them. The speed accuracy is an
/// explicit input, 1.5 m/s unless a case says otherwise; her phone's real
/// figure has not been read.
///
/// What these tests hold. A FAULT case must not end in `gpsTrusted`, must not
/// be labelled 「GPS 良好」 or "GPS good", and must not narrate the turn at
/// `speak`; the plain turn line must not reach the audio channel. A CONTROL
/// case is an honest drive, and it must stay `gpsTrusted`, 「GPS 良好」 and
/// `speak`.
///
/// Why the controls are here, in two kinds.
///  - Against a wiring that trusts nothing (`suspect` on every fix): no
///    trusted baseline ever forms, so every estimate is `lost`, the turn is
///    never read, and the caution rung sits at its ceiling on a clean road.
///    C1 to C4 make that wiring red. (This file said, until 2026-10-05, that
///    such a wiring makes the hedged state universal. A probe run showed it
///    makes `lost` universal; corrected here.)
///  - Against a wiring that is too tight: each fault case could also be
///    passed by a gate that fires on honest driving. N1 to N7 are honest
///    drives that such a gate would flag: fix noise, a turn and a curve, an
///    expressway speed, a crawl, a stop that repeats its coordinates, a
///    140 m fix, and a burst of fixes at a tunnel exit. Each was shown to
///    fail its too-tight gate before it was kept.
///
/// Two fault cases, MULTIPATH and FROZEN, are skipped while the gates that
/// catch them run in shadow (see [_inShadow]); the SHADOW group holds that
/// their verdict is still computed and is not "trusted".
/// One control (C5) is a fault the app already catches: it must stay caught
/// at least as strictly as it is today, so a verdict can tighten the outcome
/// but never loosen it.
///
/// Why default construction. The verdict must be computed inside the seam,
/// not passed in by each caller. A verdict a caller has to remember to supply
/// is the same believes-by-default hole, one layer up: when it is forgotten,
/// the fix is trusted again and nothing says so.
///
/// N1's noise is a MODEL (independent errors, 2 m per axis), not a reading
/// from a phone. In that model, position_integrity 0.1.1 at its default
/// acceleration limit flags about 6% of fixes suspect and 3% failed, so N1 is
/// red on that default. N1's noise model may be replaced only by one measured
/// on recorded honest fixes. It must never be relaxed to make a gate green.
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
///  - Nothing here asserts the map camera or the caution rung directly; they
///    are reached through the mode only.
///  - No device, no real receiver. Every fix here is synthetic.
///  - Nothing here decides what she should see or hear instead, only that it
///    is not the confident state. The wording is a separate design decision.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart'
    show LocationPermission, Position;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode, TrustSignal;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';

import '../support/fake_alert_actuators.dart';

// --- geometry: roads out of Akita city, one fix a second ---

final _t0 = DateTime.utc(2026, 1, 15, 6, 30);
const double _lat0 = 39.72;
const double _lon0 = 140.10;

/// Metres per degree of latitude on the sphere both packages use (R = 6371 km).
const double _mPerDegLat = 6371000.0 * math.pi / 180.0;
final double _mPerDegLon = _mPerDegLat * math.cos(_lat0 * math.pi / 180.0);

/// Her cruising speed on a snowy two-lane road: 15 m/s = 54 km/h.
const double _v = 15.0;

/// The platform's reported speed accuracy, unless a case says otherwise.
const double _speedAcc = 1.5;

/// Why MULTIPATH and FROZEN are skipped, and what still holds them.
///
/// The two gates that catch them (a change of speed between fixes, and a
/// position that stops while the platform says it moves) are sensitive to
/// ordinary fix noise, and nobody has yet measured how often they would flag
/// honest fixes on a phone. Until that is measured, they run in shadow: they
/// are computed and recorded, but they do not change what she sees or hears
/// (wiring criterion W10; measurement plan F). The SHADOW group below asserts
/// that their verdict IS computed for these same two vectors, so a skip here is
/// never an absent verdict. Remove the skip when plan F passes; do not relax
/// either case to make it pass.
const String _inShadow = 'in shadow until honest phone fixes are measured '
    '(wiring criterion W10, measurement plan F); the SHADOW group holds the '
    'computed verdict for this vector';

/// The verdict of the gates kept in shadow, read from the seam. It is a
/// contract the wiring must provide: `DriveHudController.shadowGpsTrust`, a
/// [TrustSignal] for the last fix fed. On a tree with no such verdict the
/// read fails, and says why.
TrustSignal _shadowOf(DriveHudController c) {
  try {
    final Object? v = (c as dynamic).shadowGpsTrust;
    if (v is TrustSignal) return v;
    fail('shadowGpsTrust is $v, not a TrustSignal: no shadow verdict');
  } on NoSuchMethodError {
    fail('no shadow verdict is computed: DriveHudController has no '
        'shadowGpsTrust, so the gates in shadow leave no record (an absent '
        'verdict reads as a pass)');
  }
}

/// One platform sample at [second], [northM] up the road and [eastM] across
/// it, reporting horizontal accuracy [acc] and ground speed [speed] with
/// speed accuracy [speedAcc]. A `null` [speed] is a platform that reported
/// none (Android reads a 0.0 the same way).
Position _p(
  int second, {
  required double northM,
  double eastM = 0,
  double acc = 5,
  double? speed = _v,
  double speedAcc = _speedAcc,
  int? timestampSecond,
  int? atMs,
}) =>
    Position(
      latitude: _lat0 + northM / _mPerDegLat,
      longitude: _lon0 + eastM / _mPerDegLon,
      timestamp: atMs != null
          ? _t0.add(Duration(milliseconds: atMs))
          : _t0.add(Duration(seconds: timestampSecond ?? second)),
      accuracy: acc,
      hasAccuracy: true,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed ?? 0,
      hasSpeed: speed != null,
      speedAccuracy: speed == null ? 0 : speedAcc,
      hasSpeedAccuracy: speed != null,
    );

/// The samples through the app's own parser, in order: what the drive brain
/// is given for each.
Future<List<PositionAvailable>> _parse(List<Position> samples) async {
  final out = await herPositionStream(
    isServiceEnabled: () async => true,
    checkPermission: () async => LocationPermission.whileInUse,
    positionStream: () => Stream<Position>.fromIterable(samples),
  ).take(samples.length).toList();
  return [
    for (final f in out)
      f is PositionAvailable
          ? f
          : throw StateError('the parser did not give a fix: $f'),
  ];
}

/// A clean drive: samples 0..n-1 at [_v] straight up the road.
List<Position> _cleanTrack(int n) =>
    [for (var s = 0; s < n; s++) _p(s, northM: _v * s)];

/// A small, fixed random source, so every run draws the same noise on every
/// Dart version (xorshift32, Box-Muller).
class _Noise {
  _Noise(this._s);
  int _s;
  double _u() {
    _s ^= (_s << 13) & 0xFFFFFFFF;
    _s ^= _s >> 17;
    _s ^= (_s << 5) & 0xFFFFFFFF;
    _s &= 0xFFFFFFFF;
    return (_s + 1) / 4294967297.0;
  }

  /// One draw from a normal distribution with standard deviation [sigma].
  double next(double sigma) =>
      sigma * math.sqrt(-2 * math.log(_u())) * math.cos(2 * math.pi * _u());
}

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

/// The plain, as-given turn line (the `speak` text).
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

/// Feeds an honest drive and requires every fix from [from] on to be
/// `gpsTrusted`; then the end state must be good GPS, spoken as given.
Future<void> _expectHonestDrive(
  List<Position> samples,
  String why, {
  int from = 2,
}) async {
  final fake = FakeAlertActuators();
  final c = _controller(fake);
  final fixes = await _parse(samples);
  for (var i = 0; i < fixes.length; i++) {
    _feed(c, fixes[i]);
    if (i >= from) {
      expect(c.estimate!.mode, LocalizationMode.gpsTrusted,
          reason: '$why: fix $i of an honest drive');
    }
  }
  await _expectPresentedAsGood(c, fake, '$why: end of the drive');
}

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

/// Feeds [samples] through the parser and returns the controller after the
/// last one.
Future<(DriveHudController, FakeAlertActuators)> _drive(
    List<Position> samples) async {
  final fake = FakeAlertActuators();
  final c = _controller(fake);
  for (final f in await _parse(samples)) {
    _feed(c, f);
  }
  return (c, fake);
}

/// A drive along a polyline described by headings: [legs] of (seconds,
/// heading in degrees clockwise from north, speed), sampled once a second,
/// plus constant-radius arcs given as (seconds, start heading, turn rate in
/// degrees per second, speed). Positions are integrated at 0.01 s steps.
List<Position> _path(
  List<({int seconds, double heading, double turnRate, double speed})> legs, {
  double speedAcc = _speedAcc,
}) {
  final out = <Position>[];
  var north = 0.0, east = 0.0, t = 0;
  out.add(_p(0, northM: 0, speed: legs.first.speed, speedAcc: speedAcc));
  for (final leg in legs) {
    var heading = leg.heading;
    for (var s = 0; s < leg.seconds; s++) {
      for (var k = 0; k < 100; k++) {
        final h = (heading + leg.turnRate * 0.005) * math.pi / 180;
        north += leg.speed * 0.01 * math.cos(h);
        east += leg.speed * 0.01 * math.sin(h);
        heading += leg.turnRate * 0.01;
      }
      t++;
      out.add(_p(t,
          northM: north, eastM: east, speed: leg.speed, speedAcc: speedAcc));
    }
  }
  return out;
}

void main() {
  test('geometry check: the clean track really is 15 m apart a second', () {
    // If this helper were wrong, every case below would measure the wrong
    // thing. Haversine on the same sphere the packages use.
    double metres(Position a, Position b) {
      final p1 = a.latitude * math.pi / 180, p2 = b.latitude * math.pi / 180;
      final dp = p2 - p1, dl = (b.longitude - a.longitude) * math.pi / 180;
      final h = math.pow(math.sin(dp / 2), 2) +
          math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
      return 2 * 6371000.0 * math.asin(math.min(1.0, math.sqrt(h)));
    }

    final t = _cleanTrack(2);
    expect(metres(t[0], t[1]), closeTo(15.0, 0.01));
    expect(
      metres(_p(0, northM: 0), _p(0, northM: 0, eastM: 300)),
      closeTo(300.0, 0.05),
    );
    // A quarter turn at 5 m/s, 22.5°/s for 4 s, comes out of the integrator
    // on the radius it was given: R = v / ω = 5 / 0.3927 = 12.73 m, so the
    // chord from the start of the arc to its end is R·√2 = 18.0 m.
    final turn = _path([
      (seconds: 4, heading: 0, turnRate: 0, speed: 5),
      (seconds: 4, heading: 0, turnRate: 22.5, speed: 5),
    ]);
    expect(metres(turn[4], turn[8]), closeTo(18.0, 0.1));
  });

  test('the parser gives the drive brain what the platform measured', () async {
    final f = (await _parse([_p(0, northM: 0, speed: 15, speedAcc: 1.5)]))
        .single;
    expect(f.accuracyMeters, 5);
    expect(f.speedFloorMps, closeTo(16.5, 1e-9));
    expect(f.motion, GroundMotion.moving);
  });

  group('CONTROLS: a clean drive is still good GPS, spoken as given', () {
    test('C1 a clean drive at 54 km/h, accuracy 5 m, ten fixes', () async {
      // Fixes 0 and 1 are a warm-up: a verdict that wants two fixes before
      // it trusts is not excluded by this control.
      await _expectHonestDrive(_cleanTrack(10), 'C1');
    });

    test('C2 braking at 7 m/s² to a stop, then parked with 2 m jitter',
        () async {
      // 15 → 8 → 1 → 0 m/s: hard but legal winter braking, then stationary
      // with the small wander a parked receiver shows.
      await _expectHonestDrive([
        ..._cleanTrack(6), // north 0..75 m
        _p(6, northM: 75 + 8, speed: 8),
        _p(7, northM: 75 + 9, speed: 1, speedAcc: 0.5),
        _p(8, northM: 84 + 1.0, eastM: 0.5, speed: null),
        _p(9, northM: 84 - 0.5, eastM: -1.0, speed: null),
        _p(10, northM: 84 + 1.5, eastM: 1.0, speed: null),
        _p(11, northM: 84, eastM: -0.5, speed: null),
      ], 'C2');
    });

    test('C3 a 20 s tunnel, then a fix where she plausibly is', () async {
      // 15 m/s for 20 s = 300 m. The second fix after the gap must be trusted
      // again; one fix of caution on reacquisition is not excluded.
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      final before = await _parse(_cleanTrack(6)); // last at 5 s, 75 m
      for (final f in before) {
        _feed(c, f);
      }
      for (var s = 6; s <= 25; s++) {
        c.poll(now: _t0.add(Duration(seconds: s)));
      }
      for (final f in await _parse([
        _p(26, northM: 75 + _v * 21),
        _p(27, northM: 75 + _v * 22),
      ])) {
        _feed(c, f);
      }
      await _expectPresentedAsGood(c, fake, 'C3 second fix after a tunnel');
    });

    test('C4 a 30 m accuracy fix on a clean drive is still good GPS',
        () async {
      final (c, fake) = await _drive([
        ..._cleanTrack(8),
        _p(8, northM: _v * 8, acc: 30),
      ]);
      await _expectPresentedAsGood(c, fake, 'C4 accuracy 30 m on track');
    });

    test('C5 a fix replayed with the SAME timestamp: no turn, as today',
        () async {
      // Protection that exists today (localization_fallback 0.1.4,
      // `localization_controller.dart:108-110`): a fix no newer than the last
      // trusted one is not current, so the estimate holds the last position
      // and the turn is suppressed. A verdict computed in front of the
      // controller must not LOOSEN that. The guard only runs on a fix fed
      // as `trusted`: a monitor that calls a duplicate timestamp `suspect`
      // (position_integrity 0.1.1 does: "out-of-order or duplicate timestamp
      // — skipped") and is fed straight through turns this stale fix into
      // `gpsSuspect`, and the hedged turn is spoken from a fix that is not
      // current. A replay carries no new position at all.
      final (c, fake) = await _drive([
        ..._cleanTrack(6),
        _p(6, northM: _v * 5, timestampSecond: 5),
      ]);
      const why = 'C5 frozen fix replayed with its old timestamp';
      await _expectNotPresentedAsGood(c, fake, why);
      expect(c.estimate!.mode, isNot(LocalizationMode.gpsSuspect),
          reason: '$why: a replay is not a present, doubtful fix');
      final spokenBefore = fake.spoken.length;
      final d = c.narrateNextManeuver(_rightTurn(), icyTurn: false);
      await _settle();
      expect(d.confidence, NarrationConfidence.suppressed, reason: why);
      expect(
        fake.spoken.skip(spokenBefore).any((s) => s.text.contains('右折')),
        isFalse,
        reason: '$why: a turn, plain or hedged, reached the audio channel',
      );
    });
  });

  group('CONTROLS: honest driving a too-tight gate would flag', () {
    test('N1 an honest drive with fix noise, 2 m per axis, sixty fixes',
        () async {
      // Independent errors of 2 m north and 2 m east on every fix, at
      // 54 km/h, reported accuracy 5 m. Fails an acceleration limit set from
      // vehicle physics alone: differencing positions twice turns 2 m of
      // noise into about 5 m/s² of apparent acceleration.
      final n = _Noise(0x5EED0001);
      await _expectHonestDrive([
        for (var s = 0; s < 60; s++)
          _p(s, northM: _v * s + n.next(2), eastM: n.next(2)),
      ], 'N1');
    });

    test('N2a a 90° right turn at 5 m/s (2.6 m/s² sideways)', () async {
      // Straight 6 s, a quarter turn in 3 s at an intersection (radius 9.5 m),
      // straight 6 s. Fails a gate on sideways or vector acceleration set
      // below a real turn: the turn is the moment narration exists for.
      await _expectHonestDrive(
        _path([
          (seconds: 6, heading: 0, turnRate: 0, speed: 5),
          (seconds: 3, heading: 0, turnRate: 30, speed: 5),
          (seconds: 6, heading: 90, turnRate: 0, speed: 5),
        ]),
        'N2a',
      );
    });

    test('N2b a 90° curve at 54 km/h (radius 95 m, 2.4 m/s² sideways)',
        () async {
      await _expectHonestDrive(
        _path([
          (seconds: 6, heading: 0, turnRate: 0, speed: _v),
          (seconds: 10, heading: 0, turnRate: 9.0, speed: _v),
          (seconds: 6, heading: 90, turnRate: 0, speed: _v),
        ]),
        'N2b',
      );
    });

    test('N3 33 m/s (120 km/h) on a straight expressway, thirty fixes',
        () async {
      // Fails a speed limit set at ordinary-road speeds.
      await _expectHonestDrive([
        for (var s = 0; s < 30; s++) _p(s, northM: 33.0 * s, speed: 33.0),
      ], 'N3');
    });

    test('N4 a 3 m/s crawl in a whiteout, speed accuracy 1.5 m/s, 1 m noise',
        () async {
      // The platform cannot say she is surely moving faster than 1.5 m/s.
      // Fails a frozen-position rule that reads the upper side of the speed
      // (speed plus its accuracy) or compares single pairs of fixes.
      final n = _Noise(0x5EED0004);
      await _expectHonestDrive([
        for (var s = 0; s < 40; s++)
          _p(s,
              northM: 3.0 * s + n.next(1),
              eastM: n.next(1),
              speed: 3.0,
              speedAcc: 1.5),
      ], 'N4');
    });

    test('N5a a stop that repeats its coordinates, speed not reported',
        () async {
      // Braking to a stop at a red light, then the same coordinates again and
      // again with new timestamps. Android reports a speed of 0.0 as no
      // reading. Fails a frozen-position rule on displacement alone.
      await _expectHonestDrive([
        ..._cleanTrack(4), // 0..45 m at 15 m/s
        _p(4, northM: 45 + 11, speed: 8),
        _p(5, northM: 56 + 5, speed: 3),
        _p(6, northM: 61 + 1.5, speed: 1, speedAcc: 0.5),
        for (var s = 7; s < 27; s++) _p(s, northM: 62.5, speed: null),
      ], 'N5a');
    });

    test('N5b the same stop, speed measured as 0 m/s', () async {
      await _expectHonestDrive([
        ..._cleanTrack(4),
        _p(4, northM: 45 + 11, speed: 8),
        _p(5, northM: 56 + 5, speed: 3),
        _p(6, northM: 61 + 1.5, speed: 1, speedAcc: 0.5),
        for (var s = 7; s < 27; s++)
          _p(s, northM: 62.5, speed: 0, speedAcc: 0.3),
      ], 'N5b');
    });

    test('N7 a tunnel exit at 90 km/h: three fixes 0.3 s apart, each ±20 m',
        () async {
      // After a 20 s tunnel the receiver reacquires in a burst: three fixes
      // 0.3 s apart, each reporting ±20 m, whose errors are +6, -6 and +6 m
      // along the road. Every fix is honest: each error is well inside its own
      // reported accuracy. But the last step looks like 19.5 m in 0.3 s, which
      // is 65 m/s. Fails a speed limit computed on raw distance over a
      // sub-second interval, which would reject her position at the tunnel
      // exit, where she needs the next turn.
      const v = 25.0;
      final fake = FakeAlertActuators();
      final c = _controller(fake);
      for (final f in await _parse([
        for (var s = 0; s < 6; s++) _p(s, northM: v * s, speed: v),
      ])) {
        _feed(c, f);
      }
      for (var s = 6; s <= 25; s++) {
        c.poll(now: _t0.add(Duration(seconds: s)));
      }
      final burst = await _parse([
        _p(0, northM: v * 26.0 + 6, acc: 20, speed: v, atMs: 26000),
        _p(0, northM: v * 26.3 - 6, acc: 20, speed: v, atMs: 26300),
        _p(0, northM: v * 26.6 + 6, acc: 20, speed: v, atMs: 26600),
        _p(0, northM: v * 27.6, acc: 10, speed: v, atMs: 27600),
        _p(0, northM: v * 28.6, acc: 10, speed: v, atMs: 28600),
      ]);
      for (var i = 0; i < burst.length; i++) {
        _feed(c, burst[i]);
        // The first fix after the gap may carry one fix of caution (as C3).
        if (i >= 1) {
          expect(c.estimate!.mode, LocalizationMode.gpsTrusted,
              reason: 'N7: fix $i after the tunnel');
        }
      }
      await _expectPresentedAsGood(c, fake, 'N7 after the burst');
    });

    test('N6 a 140 m accuracy fix where she plausibly is stays trusted',
        () async {
      // Under the 150 m line for "not network-grade". Fails an accuracy
      // limit set near ordinary GNSS accuracy.
      final (c, fake) = await _drive([
        ..._cleanTrack(8),
        _p(8, northM: _v * 8, acc: 140),
      ]);
      await _expectPresentedAsGood(c, fake, 'N6 accuracy 140 m on track');
    });
  });

  group('SHADOW: the gates kept in shadow are computed, and say so', () {
    test('MULTIPATH onset: the shadow verdict is not trusted', () async {
      final (c, _) = await _drive([
        ..._cleanTrack(6),
        _p(6, northM: _v * 6, eastM: 40, acc: 8),
      ]);
      expect(_shadowOf(c), isNot(TrustSignal.trusted),
          reason: 'the 40 m onset must be on the record even while it does '
              'not change what she sees');
    });

    test('FROZEN: the shadow verdict is not trusted', () async {
      final (c, _) = await _drive([
        ..._cleanTrack(6),
        for (var s = 6; s <= 8; s++) _p(s, northM: _v * 5),
      ]);
      expect(_shadowOf(c), isNot(TrustSignal.trusted),
          reason: 'the frozen position must be on the record even while it '
              'does not change what she sees');
    });

    test('control: on a clean drive the shadow verdict is trusted', () async {
      // A shadow that always says "suspect" would pass the two cases above
      // and record nothing true.
      final (c, _) = await _drive(_cleanTrack(10));
      expect(_shadowOf(c), TrustSignal.trusted);
    });
  });

  group('FAULTS: a fix no car could produce is not good GPS', () {
    test('JUMP 300 m across the road in 1 s at reported accuracy 5 m',
        () async {
      // Implied 300 m/s (1,080 km/h). The receiver still says ±5 m.
      final (c, fake) = await _drive([
        ..._cleanTrack(6),
        _p(6, northM: _v * 6, eastM: 300),
      ]);
      await _expectNotPresentedAsGood(c, fake, 'JUMP the jump fix');
    });

    test('SPEED 70 m up the road in 1 s at reported accuracy 8 m', () async {
      // Along her own road, so it is not a sideways jump: implied 70 m/s
      // (252 km/h), above any road vehicle's 50 m/s.
      final (c, fake) = await _drive([
        ..._cleanTrack(6),
        _p(6, northM: _v * 5 + 70, acc: 8),
      ]);
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
      final fixes = await _parse([
        ..._cleanTrack(6),
        _p(6, northM: _v * 6, eastM: 200),
        _p(7, northM: _v * 7, eastM: 200),
      ]);
      for (final f in fixes.take(7)) {
        _feed(c, f);
      }
      await _expectNotPresentedAsGood(c, fake, 'HOLD the jump fix');
      _feed(c, fixes[7]);
      await _expectNotPresentedAsGood(
          c, fake, 'HOLD the fix after the jump, still 200 m off');
    });

    test('MULTIPATH 40 m sideways at reported accuracy 8 m, onset fix',
        () async {
      // A coherent multipath offset larger than the receiver's own claim: the
      // ±8 m circle excludes where she is by 32 m. At its onset the fix steps
      // 40 m across the road in 1 s at 54 km/h: implied 42.7 m/s, under the
      // 50 m/s speed gate, but a change of speed of 27.7 m/s in one second.
      final (c, fake) = await _drive([
        ..._cleanTrack(6),
        _p(6, northM: _v * 6, eastM: 40, acc: 8),
      ]);
      await _expectNotPresentedAsGood(
          c, fake, 'MULTIPATH onset of a 40 m offset at ±8 m');
    }, skip: _inShadow);

    test('FROZEN the position stops while the platform says 15 m/s',
        () async {
      // The receiver keeps sending the same coordinates with NEW timestamps,
      // and the platform's own speed with each fix still says 15 m/s, give or
      // take 1.5 m/s. In 3 s she has moved at least 40 m; the dot has moved 0.
      // (Replaying the same timestamp is C5, already caught.)
      final (c, fake) = await _drive([
        ..._cleanTrack(6),
        for (var s = 6; s <= 8; s++) _p(s, northM: _v * 5),
      ]);
      await _expectNotPresentedAsGood(
          c, fake, 'FROZEN three frozen fixes against a moving speed');
    }, skip: _inShadow);

    test('COARSE a 400 m accuracy fix where she plausibly is', () async {
      // A network-grade fix (no satellites in the valley). Its position is
      // plausible, but the receiver itself says ±400 m. compound_failure_advisor
      // 0.1.2 calls anything over 150 m "neighbourhood scale"
      // (`kRadiusNeighbourhoodM`), yet `trusted` raises no position concern at
      // any radius, and localization_fallback 0.1.4 trusts up to 500 m.
      final (c, fake) = await _drive([
        ..._cleanTrack(6),
        _p(6, northM: _v * 6, acc: 400),
      ]);
      await _expectNotPresentedAsGood(
          c, fake, 'COARSE a ±400 m fix labelled GPS');
    });

    test('COARSE-FIRST the first fix of a share is ±400 m', () async {
      final (c, fake) = await _drive([_p(0, northM: 0, acc: 400)]);
      await _expectNotPresentedAsGood(
          c, fake, 'COARSE-FIRST a ±400 m first fix labelled GPS');
    });
  });
}
