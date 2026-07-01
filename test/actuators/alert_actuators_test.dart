/// WS5 — pure helper + NoOp + set-parity tests for the actuator layer.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern, HapticCuePatternRendering;
import 'package:sngnav_app/actuators/alert_actuators.dart';
import 'package:sngnav_app/actuators/mobile_alert_actuators.dart';
import 'package:sngnav_app/main.dart' show severityForCondition;

void main() {
  group('hapticCueForCoreSeverity', () {
    test('mirrors the audio gate: info=none, warning=warning, critical=critical',
        () {
      expect(hapticCueForCoreSeverity(AlertSeverity.info), HapticCuePattern.none);
      expect(
        hapticCueForCoreSeverity(AlertSeverity.warning),
        HapticCuePattern.warning,
      );
      expect(
        hapticCueForCoreSeverity(AlertSeverity.critical),
        HapticCuePattern.critical,
      );
    });

    test(
      'OPS-059 set parity: the tactile-cue severity set == the announced '
      '(>= warning) severity set — no reduced haptic subset',
      () {
        for (final severity in AlertSeverity.values) {
          final announced = severity.index >= AlertSeverity.warning.index;
          final tactile = hapticCueForCoreSeverity(severity).isTactile;
          expect(
            tactile,
            announced,
            reason: 'severity $severity: haptic tactile ($tactile) must equal '
                'audio-announced ($announced)',
          );
        }
      },
    );
  });

  group('ttsLocaleTagFor', () {
    test('short catalog tags normalize to full BCP-47 voice tags', () {
      expect(ttsLocaleTagFor('ja'), 'ja-JP');
      expect(ttsLocaleTagFor('en'), 'en-US');
    });

    test('already-qualified + case-insensitive', () {
      expect(ttsLocaleTagFor('ja-JP'), 'ja-JP');
      expect(ttsLocaleTagFor('JA'), 'ja-JP');
      expect(ttsLocaleTagFor('en-GB'), 'en-US');
    });

    test('unknown tags pass through unchanged', () {
      expect(ttsLocaleTagFor('fr'), 'fr');
    });
  });

  group('severityForCondition', () {
    test('ice / wet-ice are critical (HER whiteout worst-case)', () {
      expect(
        severityForCondition(RoadSurfaceCondition.ice),
        AlertSeverity.critical,
      );
      expect(
        severityForCondition(RoadSurfaceCondition.wetIce),
        AlertSeverity.critical,
      );
    });

    test('snow / slush / wet are warning', () {
      expect(
        severityForCondition(RoadSurfaceCondition.snow),
        AlertSeverity.warning,
      );
      expect(
        severityForCondition(RoadSurfaceCondition.slush),
        AlertSeverity.warning,
      );
      expect(
        severityForCondition(RoadSurfaceCondition.wet),
        AlertSeverity.warning,
      );
    });

    test('dry / unknown are info', () {
      expect(
        severityForCondition(RoadSurfaceCondition.dry),
        AlertSeverity.info,
      );
      expect(
        severityForCondition(RoadSurfaceCondition.unknown),
        AlertSeverity.info,
      );
    });

    test('every condition is mapped (no throw)', () {
      for (final c in RoadSurfaceCondition.values) {
        expect(() => severityForCondition(c), returnsNormally);
      }
    });
  });

  group('NoOpAlertActuators', () {
    test('does nothing, throws nothing (the desktop/test default)', () async {
      const noop = NoOpAlertActuators();
      await expectLater(
        noop.speak('x', localeTag: 'ja-JP'),
        completes,
      );
      await expectLater(noop.haptic(HapticCuePattern.critical), completes);
      await expectLater(noop.keepAwake(true), completes);
    });
  });

  group('test-binding safety (no real plugin engine under flutter_test)', () {
    test(
      'defaultAlertActuators() returns a NoOp under the test binding — the '
      'FLUTTER_TEST guard beats the default TargetPlatform.android',
      () {
        // Without the FLUTTER_TEST guard this would return a real
        // MobileAlertActuators (defaultTargetPlatform is android in tests),
        // eagerly building the flutter_tts plugin engine.
        expect(defaultAlertActuators(), isA<NoOpAlertActuators>());
      },
    );

    test(
      'even a direct MobileAlertActuators() is plugin-safe under test: no '
      'eager engine build, every method a guarded no-op that never throws',
      () async {
        // Constructs WITHOUT an injected engine — proves construction no longer
        // eagerly builds FlutterTtsEngine (it is lazy + reached only past the
        // _isMobilePlatform guard, which is false under FLUTTER_TEST).
        final actuators = MobileAlertActuators();
        await expectLater(
          actuators.speak('x', localeTag: 'ja'),
          completes,
        );
        await expectLater(
          actuators.haptic(HapticCuePattern.critical),
          completes,
        );
        await expectLater(actuators.keepAwake(true), completes);
      },
    );
  });
}
