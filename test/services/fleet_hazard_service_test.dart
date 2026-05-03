import 'package:fleet_hazard/fleet_hazard.dart'
    show FleetReport, HazardSeverity, RoadCondition;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/services/fleet_hazard_service.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 6, 0, 0);

  group('FleetHazardService', () {
    test('empty buffer → no zones', () {
      final svc = FleetHazardService();
      expect(svc.currentZones(now: now), isEmpty);
      expect(svc.reportCount, 0);
    });

    test('clustered icy reports → one icy hazard zone', () {
      final svc = FleetHazardService();
      // Three vehicles within 1 km, all reporting icy.
      svc.ingestAll([
        FleetReport(
          vehicleId: 'V-1',
          position: const LatLng(35.300, 136.850),
          timestamp: now.subtract(const Duration(minutes: 2)),
          condition: RoadCondition.icy,
        ),
        FleetReport(
          vehicleId: 'V-2',
          position: const LatLng(35.301, 136.851),
          timestamp: now.subtract(const Duration(minutes: 3)),
          condition: RoadCondition.icy,
        ),
        FleetReport(
          vehicleId: 'V-3',
          position: const LatLng(35.302, 136.849),
          timestamp: now.subtract(const Duration(minutes: 1)),
          condition: RoadCondition.icy,
        ),
      ]);
      final zones = svc.currentZones(now: now);
      expect(zones, hasLength(1));
      expect(zones.first.severity, HazardSeverity.icy);
      expect(zones.first.vehicleCount, 3);
    });

    test('reports older than maxReportAge are aged out', () {
      final svc = FleetHazardService(
        maxReportAge: const Duration(minutes: 5),
      );
      svc.ingest(FleetReport(
        vehicleId: 'V-old',
        position: const LatLng(35.300, 136.850),
        timestamp: now.subtract(const Duration(minutes: 30)),
        condition: RoadCondition.icy,
      ));
      svc.ingest(FleetReport(
        vehicleId: 'V-new',
        position: const LatLng(35.300, 136.850),
        timestamp: now.subtract(const Duration(minutes: 1)),
        condition: RoadCondition.icy,
      ));
      final zones = svc.currentZones(now: now);
      expect(zones, hasLength(1));
      expect(zones.first.reports.map((r) => r.vehicleId), contains('V-new'));
      expect(zones.first.reports.map((r) => r.vehicleId), isNot(contains('V-old')));
    });

    test('non-hazard reports do not generate zones', () {
      final svc = FleetHazardService();
      svc.ingest(FleetReport(
        vehicleId: 'V-dry',
        position: const LatLng(35.300, 136.850),
        timestamp: now,
        condition: RoadCondition.dry,
      ));
      expect(svc.currentZones(now: now), isEmpty);
    });
  });
}
