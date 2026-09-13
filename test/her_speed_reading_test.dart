/// What the app may conclude from one platform speed reading.
///
/// Why, written before the act. Route setting is to open only when the car is
/// measured as stopped, and her ring's growth rate is to come from her measured
/// speed. Both read `Position.speed`, and `Position.speed` is `0.0` both for a
/// car standing still and for a platform that measured nothing: geolocator
/// reports the difference only in `hasSpeed` / `hasSpeedAccuracy`. On Android
/// the speed key is omitted when the platform has no speed; on iOS both keys
/// are written only when both values are non-negative; geolocator_linux builds
/// every position with `hasSpeed` false. Reading `0.0` without the flag as a
/// stop would open route setting while the car moves: the dangerous direction.
///
/// The reading, from one position:
/// * moving: a reported, finite, non-negative speed whose lower bound (speed
///   minus the reported accuracy, or the speed alone when no accuracy is
///   reported) is above the stop limit.
/// * stopped: a reported speed AND a reported accuracy, both finite and
///   non-negative, whose upper bound (speed plus accuracy) is at most the stop
///   limit. Without a reported accuracy a stop is never concluded.
/// * unknown: everything else, including a reading whose bounds straddle the
///   limit.
/// * The ring's least growth rate is the upper bound (speed plus the reported
///   accuracy), or none when there is no usable speed.
///
/// A reading describes its own fix only. Whether a stop is still current, and
/// what route setting does with "unknown", belong to the route gate.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
// The only lines to edit when the app's reading moves: bind these two.
import 'package:sngnav_app/her_position.dart' as app;

String motionOf(Position p) => app.groundMotionOf(p).name;
double? ringFloorOf(Position p) => app.groundSpeedFloorMps(p);

/// The stop limit, in m/s, that the vectors below were written against.
const double stopLimit = 0.5;

Position reading({
  double speed = 0,
  bool hasSpeed = false,
  double speedAccuracy = 0,
  bool hasSpeedAccuracy = false,
}) =>
    Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: DateTime.utc(2026, 1, 15, 6, 30),
      accuracy: 10,
      hasAccuracy: true,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      hasSpeed: hasSpeed,
      speedAccuracy: speedAccuracy,
      hasSpeedAccuracy: hasSpeedAccuracy,
    );

void main() {
  test('the stop limit these vectors assume is the app\'s', () {
    expect(app.kStoppedAtMostMps, stopLimit);
  });

  group('motion', () {
    for (final (name, p, want) in <(String, Position, String)>[
      ('0.0 not reported: a placeholder, not a stop', reading(), 'unknown'),
      (
        '0.0 not reported, accuracy reported',
        reading(speedAccuracy: 0.1, hasSpeedAccuracy: true),
        'unknown'
      ),
      ('0.0 reported, no accuracy: cannot bound it', reading(hasSpeed: true),
          'unknown'),
      (
        '0.0 ±0.1',
        reading(hasSpeed: true, speedAccuracy: 0.1, hasSpeedAccuracy: true),
        'stopped'
      ),
      (
        '0.2 ±0.3, upper bound exactly the limit',
        reading(
            speed: 0.2, hasSpeed: true, speedAccuracy: 0.3, hasSpeedAccuracy: true),
        'stopped'
      ),
      (
        '0.3 ±0.3 straddles the limit',
        reading(
            speed: 0.3, hasSpeed: true, speedAccuracy: 0.3, hasSpeedAccuracy: true),
        'unknown'
      ),
      (
        '0.4 ±2.0 straddles the limit',
        reading(
            speed: 0.4, hasSpeed: true, speedAccuracy: 2.0, hasSpeedAccuracy: true),
        'unknown'
      ),
      (
        '0.9 ±0.3, lower bound above the limit',
        reading(
            speed: 0.9, hasSpeed: true, speedAccuracy: 0.3, hasSpeedAccuracy: true),
        'moving'
      ),
      ('25 reported, no accuracy', reading(speed: 25, hasSpeed: true), 'moving'),
      ('0.6 reported, no accuracy', reading(speed: 0.6, hasSpeed: true),
          'moving'),
      ('0.4 reported, no accuracy', reading(speed: 0.4, hasSpeed: true),
          'unknown'),
      ('25 not reported: never read', reading(speed: 25), 'unknown'),
      ('NaN', reading(speed: double.nan, hasSpeed: true), 'unknown'),
      ('infinity', reading(speed: double.infinity, hasSpeed: true), 'unknown'),
      ('-1', reading(speed: -1, hasSpeed: true), 'unknown'),
      (
        '0.0 with a NaN accuracy: accuracy unusable, no stop',
        reading(
            hasSpeed: true, speedAccuracy: double.nan, hasSpeedAccuracy: true),
        'unknown'
      ),
      (
        '1.0 with accuracy -1: accuracy unusable, speed alone',
        reading(
            speed: 1.0, hasSpeed: true, speedAccuracy: -1, hasSpeedAccuracy: true),
        'moving'
      ),
    ]) {
      test(name, () => expect(motionOf(p), want));
    }
  });

  group('ring floor', () {
    for (final (name, p, want) in <(String, Position, double?)>[
      ('not reported', reading(speed: 25), null),
      (
        '25 ±0.5',
        reading(
            speed: 25, hasSpeed: true, speedAccuracy: 0.5, hasSpeedAccuracy: true),
        25.5
      ),
      ('25, no accuracy', reading(speed: 25, hasSpeed: true), 25),
      ('NaN', reading(speed: double.nan, hasSpeed: true), null),
      ('infinity', reading(speed: double.infinity, hasSpeed: true), null),
      ('-1', reading(speed: -1, hasSpeed: true), null),
      (
        '25 with a NaN accuracy',
        reading(
            speed: 25,
            hasSpeed: true,
            speedAccuracy: double.nan,
            hasSpeedAccuracy: true),
        25
      ),
    ]) {
      test(name, () => expect(ringFloorOf(p), want));
    }
  });
}
