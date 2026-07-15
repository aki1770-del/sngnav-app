/// Unit tests for the pure measured-hazard floor — the safety math that lets a
/// MEASURED JMA watch raise the compound caution rung without ever lowering it,
/// fabricating a measurement, or inventing a fourth rung.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/measured_hazard_floor.dart';

void main() {
  group('fuseMeasuredWeather — caution-add-only floor', () {
    test('none never changes the advisor rung (any action)', () {
      for (final a in DriveAction.values) {
        for (final unc in [true, false]) {
          expect(
            fuseMeasuredWeather(
              advisorAction: a,
              hazard: MeasuredWeatherHazard.none,
              positionUnlocatable: unc,
            ),
            a,
            reason: 'no firing watch is never a raise (and never a lower)',
          );
        }
      }
    });

    test('a firing watch with a TRUSTED position floors at heightenedCaution',
        () {
      for (final h in [
        MeasuredWeatherHazard.blackIce,
        MeasuredWeatherHazard.turmoil,
      ]) {
        // continue → heightened (RAISED)
        expect(
          fuseMeasuredWeather(
            advisorAction: DriveAction.continueDriving,
            hazard: h,
            positionUnlocatable: false,
          ),
          DriveAction.heightenedCaution,
        );
        // heightened → heightened (unchanged)
        expect(
          fuseMeasuredWeather(
            advisorAction: DriveAction.heightenedCaution,
            hazard: h,
            positionUnlocatable: false,
          ),
          DriveAction.heightenedCaution,
        );
        // considerStopping → considerStopping (NEVER lowered to the floor)
        expect(
          fuseMeasuredWeather(
            advisorAction: DriveAction.considerStopping,
            hazard: h,
            positionUnlocatable: false,
          ),
          DriveAction.considerStopping,
        );
      }
    });

    test(
        'a firing watch with an UNLOCATABLE position compounds to '
        'considerStopping — a measured hazard you cannot even locate', () {
      for (final h in [
        MeasuredWeatherHazard.blackIce,
        MeasuredWeatherHazard.turmoil,
      ]) {
        for (final a in DriveAction.values) {
          expect(
            fuseMeasuredWeather(
              advisorAction: a,
              hazard: h,
              positionUnlocatable: true,
            ),
            DriveAction.considerStopping,
            reason: 'the compound ceiling is reached from any advisor rung',
          );
        }
      }
    });

    test('is monotonic: the result is never below the advisor action', () {
      for (final a in DriveAction.values) {
        for (final h in MeasuredWeatherHazard.values) {
          for (final unc in [true, false]) {
            final out = fuseMeasuredWeather(
              advisorAction: a,
              hazard: h,
              positionUnlocatable: unc,
            );
            expect(out.index, greaterThanOrEqualTo(a.index),
                reason: 'caution-add-only — the floor never lowers the rung');
          }
        }
      }
    });
  });

  group('measuredWeatherHazardFrom — collapse two watches', () {
    test('neither firing → none', () {
      expect(
        measuredWeatherHazardFrom(blackIceFiring: false, turmoilFiring: false),
        MeasuredWeatherHazard.none,
      );
    });
    test('ice firing → blackIce', () {
      expect(
        measuredWeatherHazardFrom(blackIceFiring: true, turmoilFiring: false),
        MeasuredWeatherHazard.blackIce,
      );
    });
    test('turmoil only → turmoil', () {
      expect(
        measuredWeatherHazardFrom(blackIceFiring: false, turmoilFiring: true),
        MeasuredWeatherHazard.turmoil,
      );
    });
    test('both firing → blackIce (label precedence; both floor identically)',
        () {
      expect(
        measuredWeatherHazardFrom(blackIceFiring: true, turmoilFiring: true),
        MeasuredWeatherHazard.blackIce,
      );
    });
  });
}
