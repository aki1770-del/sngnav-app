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
  group('frozen surface at sub-zero ambient must WARN, not all-clear', () {
    for (final rh in [40, 60, 80, 95]) {
      test('-2.4 C / RH $rh% (Chuo 2021-12-15 conditions) → subZeroFrozen', () {
        final r = evaluateInvisibleIceWatch(_obs(tempC: -2.4, rh: rh));
        // Stronger than the original isNot(clear): the Chair ruled sub-zero
        // SHOULD warn (2026-07-23), so pin the exact protective verdict — a
        // silent `unknown` or a non-coverage `outOfScope` would also have
        // passed isNot(clear) while leaving her unwarned.
        expect(
          r,
          InvisibleIceWatchResult.subZeroFrozen,
          reason: 'A frozen road surface must raise the sub-zero warning at '
              'the moment of danger, not all-clear/non-coverage/silence. '
              '89% of slip accidents occur on a frozen surface.',
        );
        expect(r, isNot(InvisibleIceWatchResult.clear));
      });
    }

    test('-2.4 C with humidity DROPPED still warns (the drop-prone leaf must '
        'not silence the Chuo case)', () {
      // The single most drop-prone JMA leaf is humidity (kuksa/JMA QC-0).
      // The sub-zero verdict does not need it; a leaf drop must not turn the
      // Chuo morning into a silent 判定不能.
      final r = evaluateInvisibleIceWatch(JmaObservation(
        stationId: 'incident',
        stationName: 'incident',
        temperatureCelsius: -2.4,
        humidityPercent: null,
        windMetersPerSecond: 0.0,
        snowDepthCm: 0.0,
        precipitation10mMm: 0.0,
        visibilityMeters: 10000,
        observedAtJstKey: '0700',
        fetchedAt: DateTime.now(),
      ));
      expect(r, InvisibleIceWatchResult.subZeroFrozen);
      expect(r, isNot(InvisibleIceWatchResult.unknown));
    });
  });
}
