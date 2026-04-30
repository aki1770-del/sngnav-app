import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:sngnav_app/services/driver_context_service.dart';

void main() {
  group('DriverContextService — defaults and getters', () {
    test('default profile is ageingRural and default state is alert', () {
      final svc = DriverContextService();
      expect(svc.profile, equals(DriverProfile.ageingRural));
      expect(svc.activeState, equals(DriverState.alert));
      expect(svc.proposedState, isNull);
      addTearDown(svc.dispose);
    });

    test('initial resolvedConfig matches forDriverContext for the defaults',
        () {
      final svc = DriverContextService();
      final expected = NavigationSafetyConfig.forDriverContext(
        DriverContext(
          profile: DriverProfile.ageingRural,
          state: DriverState.alert,
        ),
      );
      expect(svc.resolvedConfig, equals(expected));
      addTearDown(svc.dispose);
    });
  });

  group('DriverContextService — setProfile', () {
    test('setProfile updates profile and recomputes after debounce', () async {
      final svc = DriverContextService(
        debounceDuration: const Duration(milliseconds: 10),
      );
      var notifications = 0;
      svc.addListener(() => notifications++);
      svc.setProfile(DriverProfile.foreignTouristSnowZone);
      expect(svc.profile, equals(DriverProfile.foreignTouristSnowZone));
      // First notification fires immediately for the input change.
      expect(notifications, equals(1));
      // Wait for debounce + recompute notification.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifications, greaterThanOrEqualTo(2));
      final expected = NavigationSafetyConfig.forDriverContext(
        DriverContext(
          profile: DriverProfile.foreignTouristSnowZone,
          state: DriverState.alert,
        ),
      );
      expect(svc.resolvedConfig, equals(expected));
      addTearDown(svc.dispose);
    });

    test('setProfile with same value is a no-op', () {
      final svc = DriverContextService();
      var notifications = 0;
      svc.addListener(() => notifications++);
      svc.setProfile(DriverProfile.ageingRural);
      expect(notifications, equals(0));
      addTearDown(svc.dispose);
    });
  });

  group('DriverContextService — passive-propose / active-affirm', () {
    test('proposeState sets proposedState without changing activeState', () {
      final svc = DriverContextService();
      svc.proposeState(DriverState.fatigued);
      expect(svc.proposedState, equals(DriverState.fatigued));
      expect(svc.activeState, equals(DriverState.alert));
      addTearDown(svc.dispose);
    });

    test('proposeState does NOT change resolvedConfig', () {
      final svc = DriverContextService();
      final before = svc.resolvedConfig;
      svc.proposeState(DriverState.distracted);
      // No recompute should be scheduled by a proposal alone.
      expect(svc.resolvedConfig, equals(before));
      addTearDown(svc.dispose);
    });

    test('affirmState changes activeState and clears proposedState', () {
      final svc = DriverContextService(
        debounceDuration: const Duration(milliseconds: 1),
      );
      svc.proposeState(DriverState.fatigued);
      expect(svc.proposedState, equals(DriverState.fatigued));
      svc.affirmState(DriverState.fatigued);
      expect(svc.activeState, equals(DriverState.fatigued));
      expect(svc.proposedState, isNull);
      addTearDown(svc.dispose);
    });

    test('affirmState recomputes config to the new state', () {
      final svc = DriverContextService();
      svc.affirmState(DriverState.distracted);
      svc.recomputeNowForTesting();
      final expected = NavigationSafetyConfig.forDriverContext(
        DriverContext(
          profile: DriverProfile.ageingRural,
          state: DriverState.distracted,
        ),
      );
      expect(svc.resolvedConfig, equals(expected));
      addTearDown(svc.dispose);
    });

    test('affirmState with same state and no pending proposal is a no-op', () {
      final svc = DriverContextService();
      var notifications = 0;
      svc.addListener(() => notifications++);
      svc.affirmState(DriverState.alert);
      expect(notifications, equals(0));
      addTearDown(svc.dispose);
    });
  });

  group('DriverContextService — DrivingContext', () {
    test('setDrivingContext recomputes config including speed adjustment',
        () {
      final svc = DriverContextService();
      svc.setDrivingContext(const DrivingContext(speedMps: 25.0));
      svc.recomputeNowForTesting();
      final baseline = NavigationSafetyConfig.forDriverContext(
        DriverContext(
          profile: DriverProfile.ageingRural,
          state: DriverState.alert,
        ),
      );
      // Speed-adjusted visibility should be at least the per-profile
      // baseline (the core factory contract).
      expect(
        svc.resolvedConfig.warningVisibilityMeters,
        greaterThanOrEqualTo(baseline.warningVisibilityMeters),
      );
      addTearDown(svc.dispose);
    });
  });

  group('DriverContextService — debounce', () {
    test('a burst of three setProfile calls produces one recompute', () async {
      final svc = DriverContextService(
        debounceDuration: const Duration(milliseconds: 20),
      );
      var configChangeCount = 0;
      var lastConfig = svc.resolvedConfig;
      svc.addListener(() {
        if (svc.resolvedConfig != lastConfig) {
          configChangeCount++;
          lastConfig = svc.resolvedConfig;
        }
      });
      svc.setProfile(DriverProfile.snowZoneExperienced);
      svc.setProfile(DriverProfile.noviceUrban);
      svc.setProfile(DriverProfile.foreignTouristSnowZone);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(configChangeCount, equals(1));
      addTearDown(svc.dispose);
    });
  });
}
