/// JMA AMeDAS observation fetcher (Akita-shi station 32402).
///
/// **Article 17 boundary**: This module performs operation-class (a) only —
/// verbatim relay of JMA-published observations. No derivation, no time-shift,
/// no fused-prediction. JMA's published forecasts (when surfaced) are relayed
/// verbatim with attribution.
///
/// The 一station + verbatim-only constraint is deliberate Slice-0 scope per the
/// project's smallest-correct-first-try discipline. Future slices
/// may add additional permitted operations (b) present-tense single-point
/// arithmetic and (e) geographic aggregation when the project's safety-boundary
/// review extends to those operations.
///
/// Why: the first user this fetch is built for is an older driver in
/// Akita; station 32402 is her local AMeDAS observation point. Sakichi
/// Toyoda began with his mother at the hand loom; we begin with one
/// driver at her local weather station.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// JMA AMeDAS station ID for Akita-shi (秋田).
const String akitaStationId = '32402';

/// Curated AMeDAS station list along Akita prefecture's main inhabited
/// corridor (north coast → city → central inland → south mountain).
/// IDs + lat/lon verified against JMA's amedastable.json via Explore
/// agent 2026-04-29 (a research note kept outside this repository).
///
/// Each entry carries (stationId, name-JA, lat, lon, descriptor) so the driver
/// has geographic context per row. Slice-3 update orders by latitude
/// descending (north → south) for geographic intuition.
///
/// Descriptor is in Japanese to match the kanji station names — the
/// named first customer reads kanji natively, and a mixed-script row
/// (kanji name + English geographic context) imposes a translation
/// step she should not have to perform on a snow-zone commute.
const List<({
  String id,
  String name,
  double lat,
  double lon,
  String descriptor,
})> corridorStations = [
  (id: '32286', name: '男鹿', lat: 39.911, lon: 139.900, descriptor: '北・海沿い'),
  (id: '32402', name: '秋田', lat: 39.717, lon: 140.098, descriptor: '市街地'),
  (id: '32551', name: '大曲', lat: 39.490, lon: 140.495, descriptor: '中央内陸'),
  // 32596, not 32466: JMA's table names 32466 角館 (Kakunodate), about 31 km
  // north. Until 2026-09-19 this row fetched it and drew it as 横手. Checked by
  // test/corridor_stations_match_jma_table_test.dart.
  (id: '32596', name: '横手', lat: 39.320, lon: 140.555, descriptor: '南・内陸'),
  (id: '32691', name: '湯沢', lat: 39.187, lon: 140.463, descriptor: '南・山間'),
];

/// Verbatim JMA observation as fetched. No interpretation.
class JmaObservation {
  /// Station ID (e.g. "32402" for Akita).
  final String stationId;

  /// Station display name (Japanese-canonical from JMA).
  final String stationName;

  /// Temperature in Celsius (JMA-reported value).
  final double? temperatureCelsius;

  /// Relative humidity percentage (JMA-reported value).
  final int? humidityPercent;

  /// Wind speed in m/s (JMA-reported value).
  final double? windMetersPerSecond;

  /// Snow depth in cm (JMA-reported value, may be null when no snow).
  final double? snowDepthCm;

  /// Precipitation over the last 10 minutes in mm (JMA-reported value).
  /// `0.0` is a MEASURED "no precipitation right now"; `null` means the
  /// station did not report the field — callers must treat null as
  /// unknown, never as dry (the invisible-ice watch abstains on null).
  final double? precipitation10mMm;

  /// Visibility in meters (JMA-reported value, often null at AMeDAS stations).
  final int? visibilityMeters;

  /// Observation timestamp in JST as reported by JMA (yyyymmddHHMMSS).
  final String observedAtJstKey;

  /// Wall-clock instant when this observation was fetched from JMA.
  final DateTime fetchedAt;

  const JmaObservation({
    required this.stationId,
    required this.stationName,
    required this.temperatureCelsius,
    required this.humidityPercent,
    required this.windMetersPerSecond,
    required this.snowDepthCm,
    required this.precipitation10mMm,
    required this.visibilityMeters,
    required this.observedAtJstKey,
    required this.fetchedAt,
  });

  /// Minutes since fetch (for staleness display).
  int minutesStale(DateTime now) => now.difference(fetchedAt).inMinutes;
}

/// Fetch result: either a verbatim observation or an explicit failure.
sealed class JmaResult {
  const JmaResult();
}

class JmaSuccess extends JmaResult {
  final JmaObservation observation;
  const JmaSuccess(this.observation);
}

class JmaFailure extends JmaResult {
  final String reason;
  const JmaFailure(this.reason);
}

/// Fetch the latest AMeDAS observation for a given JMA station.
///
/// Returns [JmaSuccess] with verbatim data on success, [JmaFailure] with
/// explicit reason on any failure (network, parse, missing fields). Never
/// returns silent fallback — staleness must be visible to the caller.
Future<JmaResult> fetchLatestObservation({
  String stationId = akitaStationId,
  String stationName = '秋田',
  http.Client? client,
  String? userAgent,
}) async {
  final c = client ?? http.Client();
  // Politeness parity with the JMA warnings provider: a contactable
  // User-Agent (when the caller supplies one) + a bounded request budget,
  // so a hung endpoint can never wedge the in-drive refresh loom.
  final headers = userAgent == null ? null : {'User-Agent': userAgent};
  const requestBudget = Duration(seconds: 30);
  try {
    // Step 1: get the latest observation timestamp JMA has published.
    final latestTimeResp = await c
        .get(
          Uri.parse('https://www.jma.go.jp/bosai/amedas/data/latest_time.txt'),
          headers: headers,
        )
        .timeout(requestBudget);
    if (latestTimeResp.statusCode != 200) {
      return JmaFailure('latest_time HTTP ${latestTimeResp.statusCode}');
    }
    final latestTime = latestTimeResp.body.trim();
    // Format: 2026-04-28T21:50:00+09:00 (ISO8601 with JST offset)
    final dt = DateTime.parse(latestTime.replaceAll('+09:00', ''));

    // Step 2: compute the 3-hour bucket file URL.
    final bucket = (dt.hour ~/ 3) * 3;
    final yyyymmdd = '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';
    final bucketStr = bucket.toString().padLeft(2, '0');
    final pointUrl = 'https://www.jma.go.jp/bosai/amedas/data/'
        'point/$stationId/${yyyymmdd}_$bucketStr.json';

    // Step 3: fetch the per-10-minute records for this station+bucket.
    final pointResp =
        await c.get(Uri.parse(pointUrl), headers: headers).timeout(requestBudget);
    if (pointResp.statusCode != 200) {
      return JmaFailure('point HTTP ${pointResp.statusCode} for $pointUrl');
    }

    final dataMap = json.decode(pointResp.body) as Map<String, dynamic>;
    if (dataMap.isEmpty) {
      return JmaFailure('point file empty for $pointUrl');
    }

    // Latest record key in this 3-hour bucket.
    final keys = dataMap.keys.toList()..sort();
    final latestKey = keys.last;
    final rec = dataMap[latestKey] as Map<String, dynamic>;

    // JMA shape: each measurement is [value, qualityFlag]. Only a
    // QC-flag-0 (normal) reading is a measurement; any other flag — or a
    // missing/malformed flag — means the station's sensor value did not
    // pass JMA's quality control, and relaying it verbatim would present a
    // rejected reading as fact. Non-0 → the field is absent (null =
    // unknown), never a value (same flag-0-only discipline as
    // pretrip_source_jma's _visibilityFor, read from its jma_visibility.dart).
    num? extractQc0(String field) {
      final v = rec[field];
      if (v is! List || v.length < 2) return null;
      final value = v[0];
      final flag = v[1];
      if (value is! num || flag is! num || flag != 0) return null;
      return value;
    }

    double? extractDouble(String field) => extractQc0(field)?.toDouble();

    int? extractInt(String field) => extractQc0(field)?.toInt();

    return JmaSuccess(JmaObservation(
      stationId: stationId,
      stationName: stationName,
      temperatureCelsius: extractDouble('temp'),
      humidityPercent: extractInt('humidity'),
      windMetersPerSecond: extractDouble('wind'),
      snowDepthCm: extractDouble('snow'),
      precipitation10mMm: extractDouble('precipitation10m'),
      visibilityMeters: extractInt('visibility'),
      observedAtJstKey: latestKey,
      fetchedAt: DateTime.now(),
    ));
  } catch (e) {
    return JmaFailure('exception: $e');
  } finally {
    if (client == null) c.close();
  }
}

/// Fetch the latest observation for every station in [corridorStations]
/// in parallel. Returns one result per station, in the same order.
///
/// Article 17 (β) classification (Japan's Meteorological Service Act, the
/// forecast-licence boundary): this is op-(e) geographic
/// aggregation (presenting N stations' verbatim observations
/// side-by-side; not combining them into a fused metric and not
/// time-shifting them). Permit-free under the project's safety boundary.
///
/// Failures are per-station: one station's network failure does not
/// invalidate the others — staleness is honest per row.
///
/// [userAgent] is passed to every station request (added 2026-09-25, on an
/// audit finding). Until then this function took none, so these five stations' requests
/// went out with dart:io's default User-Agent while the privacy policy said
/// every AMeDAS request carries the app's. [client] is for tests; when null,
/// each station request uses and closes its own client, as before.
Future<List<JmaResult>> fetchCorridorObservations({
  http.Client? client,
  String? userAgent,
}) async {
  final futures = corridorStations.map(
    (s) => fetchLatestObservation(
      stationId: s.id,
      stationName: s.name,
      client: client,
      userAgent: userAgent,
    ),
  );
  return Future.wait(futures);
}
