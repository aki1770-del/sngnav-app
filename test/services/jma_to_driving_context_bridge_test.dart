import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:sngnav_app/services/jma_to_driving_context_bridge.dart';

void main() {
  group('bridgeJmaToDrivingContext', () {
    test('all-null inputs produce an all-null DrivingContext', () {
      final ctx = bridgeJmaToDrivingContext();
      expect(ctx.speedMps, isNull);
      expect(ctx.humidityRH, isNull);
      expect(ctx.ambientTempCelsius, isNull);
      expect(ctx.timeSincePrecipitation, isNull);
    });

    test('humidityPercent 85 becomes humidityRH 0.85', () {
      final ctx = bridgeJmaToDrivingContext(humidityPercent: 85);
      expect(ctx.humidityRH, closeTo(0.85, 1e-9));
    });

    test('humidityPercent above 100 is clamped to 1.0', () {
      final ctx = bridgeJmaToDrivingContext(humidityPercent: 150);
      expect(ctx.humidityRH, equals(1.0));
    });

    test('humidityPercent below 0 is clamped to 0.0', () {
      final ctx = bridgeJmaToDrivingContext(humidityPercent: -5);
      expect(ctx.humidityRH, equals(0.0));
    });

    test('speedMps and ambientTempCelsius pass through unchanged', () {
      final ctx = bridgeJmaToDrivingContext(
        speedMps: 16.7,
        ambientTempCelsius: -1.5,
      );
      expect(ctx.speedMps, equals(16.7));
      expect(ctx.ambientTempCelsius, equals(-1.5));
    });

    test('timeSincePrecipitation passes through unchanged', () {
      const dur = Duration(minutes: 30);
      final ctx = bridgeJmaToDrivingContext(timeSincePrecipitation: dur);
      expect(ctx.timeSincePrecipitation, equals(dur));
    });

    test('result is the value-equal DrivingContext expected', () {
      final ctx = bridgeJmaToDrivingContext(
        speedMps: 10.0,
        humidityPercent: 60,
        ambientTempCelsius: 0.5,
        timeSincePrecipitation: const Duration(hours: 2),
      );
      expect(
        ctx,
        equals(const DrivingContext(
          speedMps: 10.0,
          humidityRH: 0.6,
          ambientTempCelsius: 0.5,
          timeSincePrecipitation: Duration(hours: 2),
        )),
      );
    });
  });
}
