/// Slice 2b — driving route fetch via the OSRM public demo server.
///
/// HER-trace: HER needs to see whether a road exists from where she is to
/// where she wants to go. Snow-aware routing (avoid closed passes, prefer
/// plowed) is a later slice — that's where the condition_aggregator
/// explore-phase substrate eventually lands. Slice 2b answers the pre-snow
/// question: "is there a road at all, and roughly how far?"
///
/// OSRM demo (router.project-osrm.org) chosen because:
/// - No API key, no signup — fits the V96 "no vendor lock at first try" stance
/// - OSM-data backed — same data substrate as the map tiles in slice 1
/// - Free for low-volume demo / personal use; NOT for production traffic
///
/// V14 (silent-failure-anti-Jidoka): on any failure, surface the reason.
/// No silent fallback to a stale cached route. The driver must know when
/// the routing is unavailable.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

sealed class RouteResult {
  const RouteResult();
}

class RouteSuccess extends RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final DateTime fetchedAt;
  const RouteSuccess({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.fetchedAt,
  });
}

class RouteFailure extends RouteResult {
  final String reason;
  const RouteFailure(this.reason);
}

Future<RouteResult> fetchDrivingRoute({
  required LatLng origin,
  required LatLng destination,
}) async {
  final url = Uri.parse(
    'https://router.project-osrm.org/route/v1/driving/'
    '${origin.longitude},${origin.latitude};'
    '${destination.longitude},${destination.latitude}'
    '?overview=full&geometries=geojson',
  );
  try {
    // No custom headers: on web, a custom User-Agent triggers a CORS
    // preflight (OPTIONS). OSRM advertises only GET in
    // access-control-allow-methods, so preflight fails and the GET never
    // fires. The browser sends its own User-Agent regardless, so the
    // header was wasted on web and harmful at the same time.
    final resp = await http.get(url).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      return RouteFailure('OSRM HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = body['code'] as String?;
    if (code != 'Ok') {
      return RouteFailure('OSRM code=$code (${body['message'] ?? 'no detail'})');
    }
    final routes = body['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return const RouteFailure('OSRM returned no routes');
    }
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List<dynamic>;
    final points = coords
        .map((c) => LatLng(
              (c[1] as num).toDouble(),
              (c[0] as num).toDouble(),
            ))
        .toList();
    return RouteSuccess(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
      fetchedAt: DateTime.now(),
    );
  } catch (e) {
    return RouteFailure('network/parse error: $e');
  }
}
