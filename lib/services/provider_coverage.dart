/// Provider coverage — pair each advisory provider with the geographic
/// region its publisher can actually answer for.
///
/// **Why this exists (the defect this closes).** The `AdvisoryAggregator`
/// fans every point query across ALL registered providers. For HER Akita
/// point (39.7167, 140.0983) that meant the US National Weather Service
/// (NWS) endpoint was called for a Japanese coordinate it has no data for
/// — it answered HTTP 400 EVERY time, surfacing a useless error card, AND
/// it sent HER coordinate to a US service that cannot help her (a D4
/// dignity / privacy boundary). The fix is to query a provider ONLY when
/// its publisher covers the query point.
///
/// This is an INTEGRATION-LAYER concern (which publisher serves which
/// region is a deployment fact, not a package fact), so it lives in the
/// app, not in the pub.dev catalog packages.
///
/// Coverage is expressed as simple inclusive lat/lon bounding boxes. They
/// are deliberately GENEROUS (a box, not a precise coastline): the cost of
/// a slightly-too-wide box is at worst one wasted query near a border; the
/// cost of a too-tight box is missing HER own advisory. When in doubt, over-
/// cover — but never cover a point on the wrong side of the planet (the US
/// and Japan boxes are disjoint in longitude, so neither ever answers for
/// the other's driver).
library;

import 'package:condition_aggregator/condition_aggregator.dart'
    show AdvisoryProvider;

/// Predicate: true when the publisher behind a provider can answer for the
/// point `(latitude, longitude)` in WGS84 decimal degrees.
typedef CoveragePredicate = bool Function(double latitude, double longitude);

/// One advisory provider paired with the geographic region it covers.
///
/// `AdvisoryService` queries [provider] ONLY when [covers] returns true for
/// the query point — so HER coordinate is never sent to a publisher that
/// has no data for her location.
class CoveredProvider {
  const CoveredProvider({required this.provider, required this.covers});

  /// The wrapped source adapter (NWS, JMA, ...).
  final AdvisoryProvider provider;

  /// True when this provider's publisher covers the query point.
  final CoveragePredicate covers;
}

/// Simple inclusive lat/lon bounding box (WGS84 decimal degrees).
class GeoBoundingBox {
  const GeoBoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  /// True when `(lat, lon)` falls inside (or on the edge of) this box.
  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
}

/// NWS coverage = the United States + its major territories, as three
/// disjoint boxes (CONUS, Alaska, Hawaii). Longitudes are all NEGATIVE
/// (western hemisphere), which is what keeps NWS from ever answering for a
/// Japanese (positive-longitude) point.
const List<GeoBoundingBox> kNwsBoxes = <GeoBoundingBox>[
  // Continental US (CONUS).
  GeoBoundingBox(minLat: 24, maxLat: 50, minLon: -125, maxLon: -66),
  // Alaska (reaches to ~ -170 lon in the west, ~72 lat in the north).
  GeoBoundingBox(minLat: 51, maxLat: 72, minLon: -170, maxLon: -129),
  // Hawaii.
  GeoBoundingBox(minLat: 18, maxLat: 23, minLon: -161, maxLon: -154),
];

/// True when `(lat, lon)` is inside US / US-territory NWS coverage.
bool nwsCoverage(double latitude, double longitude) =>
    kNwsBoxes.any((b) => b.contains(latitude, longitude));

/// JMA coverage = Japan (its four main islands through the Nansei chain).
/// Positive longitude — disjoint from every NWS box.
const GeoBoundingBox kJmaBox =
    GeoBoundingBox(minLat: 24, maxLat: 46, minLon: 122, maxLon: 154);

/// True when `(lat, lon)` is inside JMA (Japan) coverage.
bool jmaCoverage(double latitude, double longitude) =>
    kJmaBox.contains(latitude, longitude);
