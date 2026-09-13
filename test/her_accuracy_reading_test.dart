/// What the app may take from one platform position's horizontal accuracy.
///
/// Why, written before the act. `Position.accuracy` is `0.0` both for a
/// measurement of zero and for no measurement; geolocator says which in
/// `hasAccuracy` (geolocator_platform_interface 4.3.0, position.dart:112-117).
/// Android omits the value when it has none (LocationMapper.java:25), and
/// `Position.fromMap` then reads `0.0` with the flag false. A placeholder read
/// as a measurement becomes a 0 m ring: "exactly here", which nothing measured.
///
/// The reading, from one position:
/// * usable: `hasAccuracy` is true and the value is finite and not negative.
/// * otherwise: no accuracy. A value the platform did not flag is never read,
///   whatever the field holds.
/// * A platform that flags `0.0` is believed. Whether a flagged value is
///   plausible is not this reading's question.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
// The only line to edit when the app's reading moves: bind it.
import 'package:sngnav_app/her_position.dart' as app;

double? usableAccuracyOf(Position p) => app.usableAccuracyMeters(p);

final _t = DateTime.utc(2026, 1, 15, 6, 30);

Position reading({double accuracy = 0, bool hasAccuracy = false}) => Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: _t,
      accuracy: accuracy,
      hasAccuracy: hasAccuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('from a Position', () {
    for (final (name, p, want) in <(String, Position, double?)>[
      ('10 m, flagged', reading(accuracy: 10, hasAccuracy: true), 10),
      (
        '0.0, flagged: a platform that says it measured zero is believed',
        reading(accuracy: 0, hasAccuracy: true),
        0
      ),
      ('0.0, not flagged: a placeholder, never 0 m', reading(), null),
      (
        '12 m in the field, not flagged: never read',
        reading(accuracy: 12),
        null
      ),
      ('NaN, flagged', reading(accuracy: double.nan, hasAccuracy: true), null),
      (
        'infinity, flagged',
        reading(accuracy: double.infinity, hasAccuracy: true),
        null
      ),
      ('-1, flagged', reading(accuracy: -1, hasAccuracy: true), null),
      ('NaN, not flagged', reading(accuracy: double.nan), null),
    ]) {
      test(name, () => expect(usableAccuracyOf(p), want));
    }
  });

  group('from the platform channel map, parsed by geolocator itself', () {
    final ms = _t.millisecondsSinceEpoch;
    for (final (name, p, want) in <(String, Position, double?)>[
      (
        'Android with no accuracy: the key is omitted',
        Position.fromMap(<String, dynamic>{
          'latitude': 39.7186,
          'longitude': 140.1024,
          'timestamp': ms,
        }),
        null
      ),
      (
        'Android with an accuracy',
        Position.fromMap(<String, dynamic>{
          'latitude': 39.7186,
          'longitude': 140.1024,
          'timestamp': ms,
          'accuracy': 8.5,
        }),
        8.5
      ),
      (
        'a map that writes accuracy -1 (the key present, so flagged)',
        Position.fromMap(<String, dynamic>{
          'latitude': 39.7186,
          'longitude': 140.1024,
          'timestamp': ms,
          'accuracy': -1.0,
        }),
        null
      ),
      (
        'a toJson round trip keeps "not measured"',
        Position.fromMap(reading().toJson()),
        null
      ),
      (
        'a toJson round trip keeps a measurement',
        Position.fromMap(reading(accuracy: 10, hasAccuracy: true).toJson()),
        10
      ),
    ]) {
      test(name, () => expect(usableAccuracyOf(p), want));
    }
  });
}
