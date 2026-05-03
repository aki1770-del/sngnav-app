/// Slice 5b — fleet hazard aggregation surface.
///
/// Holds a rolling buffer of `FleetReport` records, ages them out per
/// `maxAge`, and exposes the clustered `HazardZone` list via
/// `HazardAggregator`. The driver-facing surface consumes the zones
/// and lets the `RouteForecastService` test them against route
/// segments.
///
/// Privacy / consent posture (D4 + PHIL-001 boundary): this service
/// never originates fleet reports. It only ingests reports the
/// integrator app has already explicitly opted-in to share. We do not
/// implement a crash-data-harvester here; the surface is consent-
/// aggregated and ASIL-QM (advisory only).
///
/// Driver-facing loom: "when other vehicles upstream of you have
/// reported snow or ice, you see a clustered hazard zone on your route
/// — collective intelligence presented as a typed advisory, not a raw
/// telemetry stream."
library;

import 'package:fleet_hazard/fleet_hazard.dart'
    show FleetReport, HazardAggregator, HazardZone;

class FleetHazardService {
  FleetHazardService({
    Duration maxReportAge = const Duration(minutes: 15),
    double clusterRadius = HazardAggregator.defaultClusterRadius,
  })  : _maxReportAge = maxReportAge,
        _clusterRadius = clusterRadius;

  final Duration _maxReportAge;
  final double _clusterRadius;
  final List<FleetReport> _reports = <FleetReport>[];

  /// Number of reports currently in the buffer (does not age — call
  /// [currentZones] with an explicit `now` to evict stale reports).
  int get reportCount => _reports.length;

  /// Ingest a single report. Reports are kept verbatim; aging happens
  /// lazily at [currentZones] read time using the caller's `now`.
  /// This keeps the service deterministic under test (where `now` is
  /// often a fixed past date) and avoids smearing wall-clock time
  /// across the integration boundary.
  void ingest(FleetReport report) {
    _reports.add(report);
  }

  /// Bulk-ingest helper.
  void ingestAll(Iterable<FleetReport> reports) {
    _reports.addAll(reports);
  }

  /// Returns the current set of clustered hazard zones.
  ///
  /// The aggregator filters non-hazard reports automatically (see
  /// `HazardAggregator.aggregate`) so dry / wet / unknown reports do
  /// not generate zones.
  List<HazardZone> currentZones({DateTime? now}) {
    _expire(now ?? DateTime.now());
    return HazardAggregator.aggregate(
      List<FleetReport>.unmodifiable(_reports),
      clusterRadius: _clusterRadius,
    );
  }

  /// Drop reports older than `now - maxReportAge`.
  void _expire(DateTime now) {
    final cutoff = now.subtract(_maxReportAge);
    _reports.removeWhere((r) => r.timestamp.isBefore(cutoff));
  }

  /// Reset the buffer — useful at session boundary.
  void clear() => _reports.clear();
}
