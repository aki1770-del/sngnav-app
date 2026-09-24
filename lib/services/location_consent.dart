/// Persisted app-local consent for STARTING the location share.
///
/// WHY THIS EXISTS (2026-09-23). Until today this app had no affirmative
/// in-app consent act attached to the location disclosure at all. The share
/// control was a bare button: the next thing after her tap was the operating
/// system's own permission prompt, and the disclosure was prose sitting near
/// the button. Adjacency was doing work adjacency cannot do — a consent she is
/// presumed to have given because some text was once on the same screen is not
/// a consent she gave.
///
/// The app already shipped exactly the right pattern, and it was bolted to the
/// SMALLER egress: [RouteConsentStore] gates a one-shot coordinate send to the
/// OSRM demo server behind an accept/decline act, while the larger, repeating
/// location share had none. This is that pattern, applied to the larger one.
///
/// Same on-disk idiom as [RouteConsentStore] and TripHazardStore: plain JSON in
/// the app documents directory; absent, unreadable or malformed loads as null
/// ("not decided"), NEVER as a fabricated grant or a fabricated refusal.
///
/// SCOPE BOUND, stated so it is not over-read: this is the app's own consent
/// act. It is NOT the operating system's location permission, which still runs
/// afterwards and which she can still refuse there; and it is not a compliance
/// certification. AAA ruled the absence a material pre-ship risk and said in as
/// many words that it has no authority to certify compliance. Neither has this
/// seat.
library;

import 'dart:convert';
import 'dart:io';

class LocationConsentStore {
  LocationConsentStore({required this.file});

  final File file;

  static const String fileName = 'location_consent.json';

  /// Persist her decision. [granted] true = she agreed to start the share;
  /// false = she declined.
  Future<void> save(bool granted) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      json.encode({
        'schema': 1,
        'locationShareConsent': granted,
        'decidedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  /// Load the persisted decision. Returns null when absent, unreadable, or
  /// malformed — "not decided" re-asks; it never invents a grant or a refusal
  /// she did not make.
  Future<bool?> load() async {
    try {
      if (!await file.exists()) return null;
      final decoded = json.decode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final v = decoded['locationShareConsent'];
      return v is bool ? v : null;
    } catch (_) {
      return null;
    }
  }
}
