/// Slice 2c — HER's position, with honest uncertainty.
///
/// HER-trace: HER needs to see WHERE SHE IS, with the loom telling the
/// truth about what it knows and what it doesn't. The accuracy field IS
/// the loom's honesty. A small accuracy circle says "I'm sure"; a big
/// accuracy circle says "I'm not sure"; no dot at all says "I don't know,
/// and I will not pretend." That is V14 (silent-failure-anti-Jidoka)
/// applied to position.
///
/// What this slice does NOT yet do (deferred):
/// - Dead-reckoning fallback when GPS drops (the `kalman_dr` package in
///   the SNGNav family is the substrate; not wired yet).
/// - Cohort-respectful permission rationale UI (V96 dignity for the
///   ageingRural profile — "Allow location?" without context is a V42
///   loom failure for that cohort).
/// - Cross-trip memory of GPS-weak zones (the anti-cortisol loom from
///   the conversation that produced this slice).
///
/// All three are named here so the future-slice scope is honest.
library;

import 'dart:async';
import 'package:geolocator/geolocator.dart';

sealed class PositionFix {
  const PositionFix();
}

class PositionAvailable extends PositionFix {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
  const PositionAvailable({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });
}

class PositionUnavailable extends PositionFix {
  final String reason;
  const PositionUnavailable(this.reason);
}

/// Streams HER position with accuracy. Emits [PositionUnavailable] on
/// permission denial, service-disabled, or stream error — never silently
/// stalls on a stale fix.
Stream<PositionFix> herPositionStream() async* {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    yield const PositionUnavailable('Location services disabled');
    return;
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      yield const PositionUnavailable('Location permission denied');
      return;
    }
  }
  if (permission == LocationPermission.deniedForever) {
    yield const PositionUnavailable(
      'Location permission permanently denied — change in OS settings',
    );
    return;
  }
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).map<PositionFix>((p) => PositionAvailable(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        timestamp: p.timestamp,
      )).handleError((Object e) {
    return PositionUnavailable('GPS stream error: $e');
  });
}
