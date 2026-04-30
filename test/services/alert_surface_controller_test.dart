import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:sngnav_app/services/alert_surface_controller.dart';

void main() {
  group('AlertSurfaceController.classifyTemperature', () {
    test('above info threshold returns null (no alert)', () {
      final cfg = NavigationSafetyConfig();
      final ctrl = AlertSurfaceController(config: cfg);
      expect(ctrl.classifyTemperature(20.0), isNull);
    });

    test('at info threshold returns info severity', () {
      final cfg = NavigationSafetyConfig(infoTemperatureCelsius: 5);
      final ctrl = AlertSurfaceController(config: cfg);
      expect(ctrl.classifyTemperature(5.0)?.severity, equals(AlertSeverity.info));
    });

    test('crosses warning threshold returns warning severity', () {
      final cfg = NavigationSafetyConfig(warningTemperatureCelsius: 1);
      final ctrl = AlertSurfaceController(config: cfg);
      expect(
        ctrl.classifyTemperature(0.5)?.severity,
        equals(AlertSeverity.warning),
      );
    });

    test('crosses critical threshold returns critical severity', () {
      final cfg = NavigationSafetyConfig(criticalTemperatureCelsius: -5);
      final ctrl = AlertSurfaceController(config: cfg);
      expect(
        ctrl.classifyTemperature(-10.0)?.severity,
        equals(AlertSeverity.critical),
      );
    });
  });

  group('AlertSurfaceController.classifyVisibility', () {
    test('above info threshold returns null', () {
      final cfg = NavigationSafetyConfig(infoVisibilityMeters: 1500);
      final ctrl = AlertSurfaceController(config: cfg);
      expect(ctrl.classifyVisibility(2000), isNull);
    });

    test('crosses warning threshold returns warning severity', () {
      final cfg = NavigationSafetyConfig(warningVisibilityMeters: 250);
      final ctrl = AlertSurfaceController(config: cfg);
      expect(
        ctrl.classifyVisibility(200)?.severity,
        equals(AlertSeverity.warning),
      );
    });

    test('crosses critical threshold returns critical severity', () {
      final cfg = NavigationSafetyConfig(criticalVisibilityMeters: 80);
      final ctrl = AlertSurfaceController(config: cfg);
      expect(
        ctrl.classifyVisibility(50)?.severity,
        equals(AlertSeverity.critical),
      );
    });
  });

  test('controller does NOT depend on DriverProfile or DriverState — '
      'two configs from different (profile, state) producing the same '
      'thresholds yield byte-identical SurfacedAlerts', () {
    final cfgA = NavigationSafetyConfig.forDriverContext(
      DriverContext(
        profile: DriverProfile.snowZoneExperienced,
        state: DriverState.alert,
      ),
    );
    final cfgB = NavigationSafetyConfig.forDriverContext(
      DriverContext(
        profile: DriverProfile.professional,
        state: DriverState.alert,
      ),
    );
    // These two profile/state combos resolve to the same thresholds in
    // 0.6.0 (see navigation_safety_config.dart — both fall through to
    // the default constructor); the controller must produce identical
    // SurfacedAlert outputs for identical inputs.
    expect(cfgA, equals(cfgB));
    final ctrlA = AlertSurfaceController(config: cfgA);
    final ctrlB = AlertSurfaceController(config: cfgB);
    expect(
      ctrlA.classifyTemperature(-2.0),
      equals(ctrlB.classifyTemperature(-2.0)),
    );
    expect(
      ctrlA.classifyVisibility(150),
      equals(ctrlB.classifyVisibility(150)),
    );
  });
}
