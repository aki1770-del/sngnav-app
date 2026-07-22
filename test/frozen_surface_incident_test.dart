/// HARM-PINNED REGRESSION — the modal frozen-road case must reach HER.
///
/// Harm basis (genba 2026-07-20 §A3): slip = 83.9% of Hokkaido winter
/// accidents; of 8,097 slip accidents over ten years, 89% occurred on a
/// FROZEN surface and 0% on dry or wet. Documented instance: nine-vehicle
/// pileup, Chuo Expressway, 2021-12-15, -2.4 C, clear morning, no visible
/// snow -- the "cannot tell what the surface is doing" failure.
///
/// This test asserts that the LIVE in-drive channel (the one wired into
/// main.dart and driving both the spoken announce and the caution floor)
/// does not return a negative verdict on that condition.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/invisible_ice_watch.dart';
import 'package:sngnav_app/jma_fetch.dart';

JmaObservation _obs({required double tempC, required int rh}) => JmaObservation(
      stationId: 'incident',
      stationName: 'incident',
      temperatureCelsius: tempC,
      humidityPercent: rh,
      windMetersPerSecond: 0.0,
      snowDepthCm: 0.0,
      precipitation10mMm: 0.0,
      visibilityMeters: 10000,
      observedAtJstKey: '0700',
      fetchedAt: DateTime.now(),
    );

void main() {
  group('frozen surface at sub-zero ambient must not render an all-clear', () {
    for (final rh in [40, 60, 80, 95]) {
      test('-2.4 C / RH $rh% (Chuo 2021-12-15 conditions)', () {
        final r = evaluateInvisibleIceWatch(_obs(tempC: -2.4, rh: rh));
        expect(
          r,
          isNot(InvisibleIceWatchResult.clear),
          reason: 'A frozen road surface rendered 該当なし under the label '
              '路面凍結ウォッチ is an affirmative all-clear at the moment of '
              'danger. 89% of slip accidents occur on frozen surface.',
        );
      });
    }
  });
}
