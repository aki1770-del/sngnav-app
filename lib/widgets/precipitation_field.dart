/// Slice 5c — precipitation rendering primitive.
///
/// Wraps `snow_rendering`'s pure-Dart `PrecipitationConfig` into a
/// CustomPainter widget. The widget paints a deterministic random
/// distribution of particles sized + tinted per the config; we do NOT
/// animate (animation is post-MVP per Slice 6+ smallest-slice
/// boundary). The driver sees an at-a-glance "precipitation density"
/// overlay for the active condition without the perceptual cost of a
/// continuously-animated field.
///
/// Driver-facing loom: "the windshield-on-windshield overlay shows
/// the driver, at a glance, how heavy the precipitation along the
/// route is — no animation, no chrome — the same particle-count the
/// underlying assessment computed from the WeatherCondition."
///
/// Severity-not-profile invariant: the widget renders the
/// PrecipitationConfig substrate; per-profile gating (suppress for
/// experienced-snow-zone driver, surface for novice-urban driver) is
/// the surface controller's job.
library;

import 'dart:math' as math;
import 'dart:ui' show PointMode;
import 'package:flutter/widgets.dart';
import 'package:snow_rendering/snow_rendering.dart' show PrecipitationConfig;

class PrecipitationField extends StatelessWidget {
  const PrecipitationField({
    super.key,
    required this.config,
    this.tint = const Color(0xCCFFFFFF), // white-on-translucent default
    this.seed = 0,
  });

  /// Particle configuration derived from current weather.
  final PrecipitationConfig config;

  /// Particle tint. Default is translucent white.
  final Color tint;

  /// Deterministic seed for particle placement. Use the same seed
  /// across rebuilds to keep the field stable; vary it to refresh.
  final int seed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PrecipitationPainter(
        config: config,
        tint: tint,
        seed: seed,
      ),
      size: Size.infinite,
    );
  }
}

class _PrecipitationPainter extends CustomPainter {
  _PrecipitationPainter({
    required this.config,
    required this.tint,
    required this.seed,
  });

  final PrecipitationConfig config;
  final Color tint;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (config.particleCount == 0 || size.isEmpty) return;
    final rng = math.Random(seed);
    final paint = Paint()
      ..color = tint
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    // Single canvas.drawPoints batched for perf — one stroke draw per
    // size tier (rounded to two tiers for the smallest-slice render).
    final sizeRange = config.maxSize - config.minSize;
    final tier1Points = <Offset>[];
    final tier2Points = <Offset>[];
    for (var i = 0; i < config.particleCount; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final t = rng.nextDouble();
      if (t < 0.5) {
        tier1Points.add(Offset(dx, dy));
      } else {
        tier2Points.add(Offset(dx, dy));
      }
    }
    paint.strokeWidth =
        config.minSize + sizeRange * 0.25; // smaller tier
    canvas.drawPoints(PointMode.points, tier1Points, paint);
    paint.strokeWidth =
        config.minSize + sizeRange * 0.75; // larger tier
    canvas.drawPoints(PointMode.points, tier2Points, paint);
  }

  @override
  bool shouldRepaint(covariant _PrecipitationPainter old) =>
      old.config != config || old.tint != tint || old.seed != seed;
}
