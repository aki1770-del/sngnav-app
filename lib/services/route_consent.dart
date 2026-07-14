/// Persisted app-local consent for the OSRM coordinate egress.
///
/// The tap-route path sends the FULL-PRECISION origin + destination
/// coordinates to the public OSRM demo server (router.project-osrm.org —
/// see route_fetch.dart / main.dart `_fetchRoute`). Those coordinates come
/// from map taps, NOT from GPS, so the location-share consent gate never
/// covered them: this store is the gate for that egress. Nothing is sent
/// until the driver has read the pre-send disclosure and agreed; her choice
/// is remembered here so she is asked once, not nagged per tap.
///
/// SCOPE NOTE (honest bound): the catalog's `driving_consent` package is the
/// eventual home for this decision, but its `ConsentPurpose` vocabulary
/// cannot yet name a coordinate-query egress (routing/geocoding class) — a
/// catalog follow-up. Until then this app-local store IS the consent gate at
/// the app's only coordinate egress that sits outside the location-share
/// disclosure (JMA receives only an on-device-derived prefecture code; the
/// NWS point query fires only behind the location-share gate).
///
/// Same on-disk idiom as TripHazardStore: plain JSON in the app documents
/// directory; absent/unreadable/malformed loads as null ("not decided"),
/// NEVER as a fabricated grant or a fabricated refusal.
library;

import 'dart:convert';
import 'dart:io';

class RouteConsentStore {
  RouteConsentStore({required this.file});

  final File file;

  static const String fileName = 'route_consent.json';

  /// Persist the driver's decision. [granted] true = she agreed to send
  /// tapped coordinates to the OSRM demo server; false = she declined.
  Future<void> save(bool granted) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      json.encode({
        'schema': 1,
        'osrmCoordinateConsent': granted,
        'decidedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  /// Load the persisted decision. Returns null when absent, unreadable, or
  /// malformed — "not decided" re-asks; it never invents a grant or a
  /// refusal she did not make.
  Future<bool?> load() async {
    try {
      if (!await file.exists()) return null;
      final decoded = json.decode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final v = decoded['osrmCoordinateConsent'];
      return v is bool ? v : null;
    } catch (_) {
      return null;
    }
  }
}
