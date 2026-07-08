import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/services/invisible_ice_watch.dart';

JmaObservation _obs({
  double? temp,
  int? humidity,
  double? precip10m,
}) {
  return JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: temp,
    humidityPercent: humidity,
    windMetersPerSecond: 2.0,
    snowDepthCm: null,
    precipitation10mMm: precip10m,
    visibilityMeters: null,
    observedAtJstKey: '20260115063000',
    fetchedAt: DateTime(2026, 1, 15, 6, 30),
  );
}

void main() {
  group('evaluateInvisibleIceWatch', () {
    test('HER founding scenario (+2°C / 70% / measured no precip) → watch',
        () {
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.watch,
      );
    });

    test('missing ANY required field → unknown (abstain, never clear)', () {
      expect(
        evaluateInvisibleIceWatch(_obs(temp: null, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.unknown,
      );
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: null, precip10m: 0)),
        InvisibleIceWatchResult.unknown,
      );
      expect(
        evaluateInvisibleIceWatch(
            _obs(temp: 2.0, humidity: 70, precip10m: null)),
        InvisibleIceWatchResult.unknown,
      );
    });

    test('sub-zero ambient stays OUT of this alert (cry-wolf contract)', () {
      // Nearly every freezing reading passes the dew-point check; alerting
      // on all of them trains the driver to dismiss the one that matters.
      expect(
        evaluateInvisibleIceWatch(
            _obs(temp: -5.0, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.clear,
      );
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 0.0, humidity: 90, precip10m: 0)),
        InvisibleIceWatchResult.clear,
      );
    });

    test('measured precipitation → clear (visible-hazard lanes own it)', () {
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: 70, precip10m: 0.5)),
        InvisibleIceWatchResult.clear,
      );
    });

    test('warm or dry-air mornings → clear', () {
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 8.0, humidity: 70, precip10m: 0)),
        InvisibleIceWatchResult.clear,
      );
      // +2°C at 90% RH: dew point is ABOVE 0 → not the radiative window
      // (matches the shared classifier's determination).
      expect(
        evaluateInvisibleIceWatch(_obs(temp: 2.0, humidity: 90, precip10m: 0)),
        InvisibleIceWatchResult.clear,
      );
    });
  });
}
