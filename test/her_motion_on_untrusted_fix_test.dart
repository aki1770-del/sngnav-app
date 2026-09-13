/// A stop is concluded only on a fix the app trusts. Motion can close on less.
///
/// Why, written before the act. Route setting is to open only when the car is
/// measured as stopped, and a stop is measured only when, on a trusted fix,
/// speed and speed accuracy are both reported, both finite and not negative,
/// and their sum is at most the stop limit; everything else, straddles
/// included, measures nothing. (Corrected 2026-09-14 before landing: this
/// sentence gave the superseded rule, "zero lies inside the reported speed's
/// own accuracy", which reads 3.0 ±4.0 m/s as stopped.) The motion reading
/// (`groundMotionOf`) reads the speed's own flags. A fix whose horizontal
/// accuracy was not measured is not trusted. A stop read from it would open
/// route setting on a fix the app does not trust, which is the dangerous
/// direction. "Moving" only closes route setting, so a usable speed still reads
/// moving whatever the position's accuracy.
///
/// Needs both the motion reading (`groundMotionOf`, `kStoppedAtMostMps`) and
/// the accuracy reading (`usableAccuracyMeters`), so it lands with the first.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
// The only line to edit when the app's reading moves: bind it.
import 'package:sngnav_app/her_position.dart' as app;

String motionOf(Position p) => app.groundMotionOf(p).name;

Position reading({
  double speed = 0,
  bool hasSpeed = false,
  double speedAccuracy = 0,
  bool hasSpeedAccuracy = false,
  double accuracy = 10,
  bool hasAccuracy = true,
}) =>
    Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: DateTime.utc(2026, 1, 15, 6, 30),
      accuracy: accuracy,
      hasAccuracy: hasAccuracy,
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
    expect(app.kStoppedAtMostMps, 0.5);
  });

  for (final (name, p, want) in <(String, Position, String)>[
    (
      '0.0 ±0.1 on a measured 10 m fix: stopped',
      reading(hasSpeed: true, speedAccuracy: 0.1, hasSpeedAccuracy: true),
      'stopped'
    ),
    (
      '0.0 ±0.1, horizontal accuracy not flagged: unknown',
      reading(
          hasSpeed: true,
          speedAccuracy: 0.1,
          hasSpeedAccuracy: true,
          accuracy: 0,
          hasAccuracy: false),
      'unknown'
    ),
    (
      '0.0 ±0.1, horizontal accuracy flagged -1: unknown',
      reading(
          hasSpeed: true,
          speedAccuracy: 0.1,
          hasSpeedAccuracy: true,
          accuracy: -1),
      'unknown'
    ),
    (
      '0.0 ±0.1, horizontal accuracy flagged NaN: unknown',
      reading(
          hasSpeed: true,
          speedAccuracy: 0.1,
          hasSpeedAccuracy: true,
          accuracy: double.nan),
      'unknown'
    ),
    (
      '0.2 ±0.3 (upper bound at the limit), horizontal accuracy not flagged: '
          'unknown',
      reading(
          speed: 0.2,
          hasSpeed: true,
          speedAccuracy: 0.3,
          hasSpeedAccuracy: true,
          accuracy: 0,
          hasAccuracy: false),
      'unknown'
    ),
    (
      '25 m/s, horizontal accuracy not flagged: still moving',
      reading(speed: 25, hasSpeed: true, accuracy: 0, hasAccuracy: false),
      'moving'
    ),
    (
      '0.9 ±0.3, horizontal accuracy not flagged: still moving',
      reading(
          speed: 0.9,
          hasSpeed: true,
          speedAccuracy: 0.3,
          hasSpeedAccuracy: true,
          accuracy: 0,
          hasAccuracy: false),
      'moving'
    ),
  ]) {
    test(name, () => expect(motionOf(p), want));
  }
}
