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

/// The driver declined (or dismissed) the pre-send consent for the OSRM
/// coordinate egress. NO request was made — the tapped origin/destination
/// coordinates did not leave the device. This is an honest neutral state,
/// not an error: the router did not fail, it was never asked.
class RouteConsentDeclined extends RouteResult {
  const RouteConsentDeclined();
}

// NOTE: the original `fetchDrivingRoute` (a direct, consent-UNGATED OSRM GET)
// was REMOVED after the B27 pre-send consent gate landed. It had zero call
// sites but survived as a live-looking public function whose doc still read
// as the route path — one future import away from silently reinstating the
// pre-consent coordinate egress. The only route path is main.dart's
// `_fetchRoute`, whose consent gate precedes construction of the routing
// engine; this file keeps only the result types that panel renders on.
