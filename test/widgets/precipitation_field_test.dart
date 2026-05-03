import 'package:driving_weather/driving_weather.dart'
    show PrecipitationIntensity, PrecipitationType, WeatherCondition;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_rendering/snow_rendering.dart' show PrecipitationConfig;
import 'package:sngnav_app/widgets/precipitation_field.dart';

void main() {
  final ts = DateTime.utc(2026, 1, 1);

  group('PrecipitationField', () {
    testWidgets('renders without throwing for clear conditions', (
      tester,
    ) async {
      final config = PrecipitationConfig.fromCondition(
        WeatherCondition.clear(timestamp: ts),
      );
      expect(config.particleCount, 0);
      await tester.pumpWidget(SizedBox(
        width: 200,
        height: 200,
        child: PrecipitationField(config: config),
      ));
      expect(tester.takeException(), isNull);
      // CustomPaint uses Size.infinite which collapses inside the SizedBox
      // — the widget still mounts even when particle count is zero.
      expect(find.byType(PrecipitationField), findsOneWidget);
    });

    testWidgets('paints heavy snow with stable seed', (tester) async {
      final heavySnow = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: -5.0,
        visibilityMeters: 400.0,
        windSpeedKmh: 20.0,
        timestamp: ts,
      );
      final config = PrecipitationConfig.fromCondition(heavySnow);
      // Heavy snow → particleCount = 500 (1.0 * 500).
      expect(config.particleCount, 500);
      await tester.pumpWidget(SizedBox(
        width: 300,
        height: 300,
        child: PrecipitationField(config: config, seed: 42),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(PrecipitationField), findsOneWidget);
    });

    testWidgets('repaints when config changes', (tester) async {
      final light = PrecipitationConfig.fromCondition(WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 0.0,
        visibilityMeters: 5000.0,
        windSpeedKmh: 5.0,
        timestamp: ts,
      ));
      final heavy = PrecipitationConfig.fromCondition(WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: -5.0,
        visibilityMeters: 400.0,
        windSpeedKmh: 20.0,
        timestamp: ts,
      ));
      await tester.pumpWidget(SizedBox(
        width: 200,
        height: 200,
        child: PrecipitationField(config: light, seed: 0),
      ));
      await tester.pumpWidget(SizedBox(
        width: 200,
        height: 200,
        child: PrecipitationField(config: heavy, seed: 0),
      ));
      expect(tester.takeException(), isNull);
      expect(light.particleCount, lessThan(heavy.particleCount));
    });
  });
}
