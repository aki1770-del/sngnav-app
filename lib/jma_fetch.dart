/// JMA AMeDAS observation fetcher (Akita-shi station 32402).
///
/// **Article 17 boundary**: This module performs operation-class (a) only —
/// verbatim relay of JMA-published observations. No derivation, no time-shift,
/// no fused-prediction. JMA's published forecasts (when surfaced) are relayed
/// verbatim with attribution.
///
/// The 一station + verbatim-only constraint is deliberate Slice-0 scope per the
/// SPA Actuator unit's smallest-correct-first-try discipline. Future slices
/// may add additional permitted operations (b) present-tense single-point
/// arithmetic and (e) geographic aggregation when AAA's safety-boundary
/// review extends to those operations.
///
/// HER-trace: the named first customer for this fetch is HER's mother in
/// Akita; station 32402 is her local AMeDAS observation point. Per V21
/// substance — Sakichi began with his mother at the hand loom; we begin
/// with HER's mother at her local weather station.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// JMA AMeDAS station ID for Akita-shi (秋田).
const String akitaStationId = '32402';

/// Curated AMeDAS station list along Akita prefecture's main inhabited
/// corridor (Oga peninsula → Akita-shi → Omagari → Yokote → Yuzawa).
/// IDs verified against JMA's amedastable.json via Explore agent
/// 2026-04-29. Initial Slice-3 hardcoding used 3 wrong IDs (32441 /
/// 32486 / 32414) that 404'd in the live fetch — V14 honesty surfaced
/// the failure per row and a verify-first lookup against the canonical
/// table fixed it. Lesson saved in feedback memory.
///
/// Each entry is (stationId, stationName-JA). Coordinates are deferred
/// until route-corridor filtering becomes a real need (a future slice).
const List<({String id, String name})> corridorStations = [
  (id: '32402', name: '秋田'),       // Akita-shi
  (id: '32551', name: '大曲'),       // Omagari
  (id: '32466', name: '横手'),       // Yokote
  (id: '32691', name: '湯沢'),       // Yuzawa
  (id: '32286', name: '男鹿'),       // Oga peninsula
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
}) async {
  final c = client ?? http.Client();
  try {
    // Step 1: get the latest observation timestamp JMA has published.
    final latestTimeResp = await c.get(Uri.parse(
      'https://www.jma.go.jp/bosai/amedas/data/latest_time.txt',
    ));
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
    final pointResp = await c.get(Uri.parse(pointUrl));
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

    // JMA shape: each measurement is [value, qualityFlag].
    double? extractDouble(String field) {
      final v = rec[field];
      if (v is List && v.isNotEmpty && v[0] != null) {
        return (v[0] as num).toDouble();
      }
      return null;
    }

    int? extractInt(String field) {
      final v = rec[field];
      if (v is List && v.isNotEmpty && v[0] != null) {
        return (v[0] as num).toInt();
      }
      return null;
    }

    return JmaSuccess(JmaObservation(
      stationId: stationId,
      stationName: stationName,
      temperatureCelsius: extractDouble('temp'),
      humidityPercent: extractInt('humidity'),
      windMetersPerSecond: extractDouble('wind'),
      snowDepthCm: extractDouble('snow'),
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
/// AAA Article 17 (β) classification: this is op-(e) geographic
/// aggregation (presenting N stations' verbatim observations
/// side-by-side; not combining them into a fused metric and not
/// time-shifting them). Permit-free under the unit's safety boundary.
///
/// Failures are per-station: one station's network failure does not
/// invalidate the others — staleness is honest per row.
Future<List<JmaResult>> fetchCorridorObservations() async {
  final futures = corridorStations.map(
    (s) => fetchLatestObservation(stationId: s.id, stationName: s.name),
  );
  return Future.wait(futures);
}
