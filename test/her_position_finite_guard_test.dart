/// Regression test for the finite-coordinate ingest guard in
/// [fixFromSample] (lib/her_position.dart).
///
/// HER-trace: a degraded / NaN / Inf GPS fix must surface as the honest
/// "position unavailable" state, NEVER as a confidently-wrong dot. On the
/// pinned flutter_map 8.3.0, a non-finite `LatLng` would also crash HER
/// entire map subtree via `Crs.checkLatLng` (throws "LatLng is not finite",
/// flutter_map issue #2178). This is the #161 NaN-GPS class the sibling
/// SNGNav repo guards at its LocationBloc chokepoint (fixed 2026-06-27).
///
/// The guard is tested directly at its pure chokepoint function so no
/// platform-channel mocking of geolocator is required.
library;

import 'package:flutter_map/flutter_map.dart' show Epsg3857;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:sngnav_app/her_position.dart';

void main() {
  final ts = DateTime.utc(2026, 1, 1, 12);

  group('fixFromSample — finite-coordinate guard', () {
    test('a normal finite fix emits PositionAvailable (drops nothing)', () {
      final fix = fixFromSample(
        latitude: 35.1709, // Nagoya
        longitude: 136.8815,
        accuracyMeters: 8.0,
        timestamp: ts,
      );

      expect(fix, isA<PositionAvailable>());
      final p = fix as PositionAvailable;
      expect(p.latitude, 35.1709);
      expect(p.longitude, 136.8815);
      expect(p.accuracyMeters, 8.0);
      expect(p.timestamp, ts);
    });

    test('zero accuracy is finite — left to flow (not over-guarded)', () {
      // Zero accuracy is suspicious but isFinite; the accuracy circle tells
      // that truth. Matching the sibling pattern, only non-finite is guarded.
      final fix = fixFromSample(
        latitude: 35.0,
        longitude: 136.0,
        accuracyMeters: 0.0,
        timestamp: ts,
      );
      expect(fix, isA<PositionAvailable>());
    });

    test('NaN latitude emits PositionUnavailable (not a position)', () {
      final fix = fixFromSample(
        latitude: double.nan,
        longitude: 136.8815,
        accuracyMeters: 8.0,
        timestamp: ts,
      );
      expect(fix, isA<PositionUnavailable>());
      expect((fix as PositionUnavailable).reason, contains('non-finite'));
    });

    test('NaN longitude emits PositionUnavailable', () {
      final fix = fixFromSample(
        latitude: 35.1709,
        longitude: double.nan,
        accuracyMeters: 8.0,
        timestamp: ts,
      );
      expect(fix, isA<PositionUnavailable>());
    });

    test('Infinity latitude emits PositionUnavailable', () {
      final fix = fixFromSample(
        latitude: double.infinity,
        longitude: 136.8815,
        accuracyMeters: 8.0,
        timestamp: ts,
      );
      expect(fix, isA<PositionUnavailable>());
    });

    test('negative Infinity longitude emits PositionUnavailable', () {
      final fix = fixFromSample(
        latitude: 35.1709,
        longitude: double.negativeInfinity,
        accuracyMeters: 8.0,
        timestamp: ts,
      );
      expect(fix, isA<PositionUnavailable>());
    });

    test('NaN accuracy emits PositionUnavailable (accuracy is guarded too)',
        () {
      final fix = fixFromSample(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracyMeters: double.nan,
        timestamp: ts,
      );
      expect(fix, isA<PositionUnavailable>());
    });

    test('Infinity accuracy emits PositionUnavailable', () {
      final fix = fixFromSample(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracyMeters: double.infinity,
        timestamp: ts,
      );
      expect(fix, isA<PositionUnavailable>());
    });
  });

  group('grounding: a non-finite coord WOULD crash flutter_map 8.3.0', () {
    test('flutter_map Crs.latLngToOffset throws on a non-finite LatLng', () {
      // latlong2 constructs a non-finite LatLng without complaint...
      const bad = LatLng(double.nan, 136.8815);
      // ...and the pinned flutter_map 8.3.0 then THROWS at the throw site
      // (Crs.checkLatLng -> "LatLng is not finite"). This is the crash the
      // ingest guard exists to prevent ever reaching.
      expect(
        () => const Epsg3857().latLngToOffset(bad, 13),
        throwsA(isA<Exception>()),
      );
    });

    test(
        'a finite fix from the guard produces a LatLng flutter_map accepts',
        () {
      final fix = fixFromSample(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracyMeters: 8.0,
        timestamp: ts,
      ) as PositionAvailable;
      final latLng = LatLng(fix.latitude, fix.longitude);
      // Does not throw — the only LatLng the guard ever lets through is finite.
      expect(() => const Epsg3857().latLngToOffset(latLng, 13), returnsNormally);
    });
  });
}
