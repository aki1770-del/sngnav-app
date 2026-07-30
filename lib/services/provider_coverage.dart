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
/// Coverage is expressed EITHER as a generous lat/lon bounding box, OR by
/// delegating to the adapter's own catalog — and which one is correct
/// depends on **how the adapter behaves for a point it cannot answer.**
///
///  * **NWS** errors (HTTP 400) on a point outside its data. A too-wide box
///    therefore costs at worst one wasted query near a border, while a
///    too-tight box costs a missed advisory. Over-cover: `kNwsBoxes`.
///
///  * **JMA** returns an EMPTY LIST, silently, for a point outside the six
///    prefectures it catalogs. A too-wide box there does NOT cost a wasted
///    query — it manufactures a positive all-clear out of a question nobody
///    was asked (B04-2). Over-covering is the defect, so `jmaCoverage`
///    delegates to the adapter's own `prefectureCodesForPoint`.
///
/// The generous-box rule is therefore NOT universal: it is safe only for a
/// publisher that FAILS LOUDLY. For one that fails silently, coverage must
/// be exactly what the adapter can actually answer for. Either way the US
/// and Japan surfaces stay disjoint in longitude, so neither ever answers
/// for the other's driver.
library;

import 'package:condition_aggregator/condition_aggregator.dart'
    show AdvisoryProvider;
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart'
    show prefectureCodesForPoint;

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

/// JMA coverage — delegated to the ADAPTER'S OWN prefecture catalog, never
/// to a box we draw ourselves.
///
/// **B04-2 — why this is not a bounding box.** This predicate used to be a
/// hand-drawn all-Japan box (lat 24–46, lon 122–154). That box was wrong in
/// a way the generous-box rationale above does not cover, and it produced a
/// fabricated all-clear:
///
///  * `condition_aggregator_jma` 0.3.1 ships a SIX-PREFECTURE snow-zone
///    catalog (北海道 / 青森 / 岩手 / 秋田 / 山形 / 新潟), and for a point
///    outside it returns an EMPTY advisory list **without throwing**
///    (`jma_advisory_provider.dart:169-175`). No request is sent.
///  * The adapter's stated fallback for that case is "the aggregator's other
///    providers cover points outside the catalog" — which is FALSE under
///    region-gating: the NWS boxes are disjoint in longitude, so for a
///    Japanese point JMA is the only provider queried.
///  * So a Tokyo / Nagoya / Osaka / Naha point produced
///    `advisories: [], providerErrors: [], sourcesQueried: 1` →
///    `canAssertNoAdvisory == true` → the POSITIVE all-clear
///    「この地点に有効な警報・注意報はありません。」 shown to a driver when
///    nobody had been asked anything.
///
/// `canAssertNoAdvisory` cannot catch that: the provider lied by silence —
/// it counted as asked-and-answered while never asking. The generous-box
/// trade above assumes a too-wide box costs "one wasted query"; for a
/// provider that answers empty-without-error it costs a fabricated clear,
/// which is the one thing this app must never render.
///
/// Deriving the predicate from `prefectureCodesForPoint` (the same catalog
/// the adapter itself consults) makes over-claim structurally impossible:
/// when the catalog grows, coverage grows with it in the same release, and
/// the two can never drift apart again. A Japanese point outside the catalog
/// now renders the honest 「この地点を管轄する対応データ提供元がありません」
/// line — true, because we genuinely cannot check it.
bool jmaCoverage(double latitude, double longitude) =>
    prefectureCodesForPoint(latitude: latitude, longitude: longitude)
        .isNotEmpty;
