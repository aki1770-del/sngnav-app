/// FORECAST VALIDITY — the concept the app did not have.
///
/// The app models observation AGE (`kSlowHazardRetainWindow`, 60 min) and had NO
/// concept of forecast VALIDITY. A JMA forecast fetched at 07:00 and covering
/// 12:00–18:00 is not "stale" at 13:30. It is VALID. Age and validity are
/// different questions, and answering the second with the first is why, at T+90
/// in the dead zone, HER phone had a map and silence.
///
/// ── NDI's ANDON (SC-26), HONOURED HERE ───────────────────────────────────────
/// `condition_aggregator`'s `Advisory.expires` has NO PROVENANCE CONTRACT. This
/// was MEASURED at the source on 2026-07-12, not assumed:
///
///   condition_aggregator_nws/lib/src/nws_advisory_provider.dart:94
///       expires: a.expires                              → PUBLISHER-DECLARED (CAP)
///   condition_aggregator_digitraffic/.../digitraffic_advisory_provider.dart:475
///       expires = _parseIsoOrNull(time['endTime'])      → PUBLISHER-DECLARED
///   condition_aggregator_met_norway/.../met_norway_advisory_provider.dart:375
///       expires: effective?.add(const Duration(hours: 1))
///                                                       → ADAPTER-SYNTHESISED
///   condition_aggregator_jma/lib/src/jma_advisory_mapper.dart:532, :605
///       expires: null                                   → ABSENT
///   condition_aggregator_owm_road_risk/lib/src/owm_road_risk_mapper.dart:50
///       expires: null                                   → ABSENT
///
/// Three incompatible meanings in one nullable field, and `Advisory.isExpired()`
/// cannot tell a publisher's guarantee from a literal `+1h` an adapter invented.
/// Building HER dead-zone memory on that field would let a synthesised expiry be
/// spoken to her as though a meteorological service had promised it.
///
/// SO WE DID NOT. Per the ratified precondition, option (b): this layer carries
/// ONLY publisher-declared validity, in its own type, with the provenance made
/// EXPLICIT AND UNFORGEABLE — [ValidityProvenance] is required at every
/// construction site, and [TripHazardMemory] refuses to speak anything that is
/// not [ValidityProvenance.publisherDeclared].
///
/// The synthesised case is not merely excluded — it is REPRESENTABLE, because a
/// value we cannot name is a value we cannot refuse. That is the entire point of
/// giving it a name.
///
/// LIMITATION, RECORDED (not narrated away): we do not fix `Advisory.expires`.
/// The published `condition_aggregator` interface is unchanged and its provenance
/// hole is still open for every consumer of it. This layer simply does not walk
/// through that hole. Closing it properly is a package-level change (NDI's Andon
/// remains OPEN) and is not claimed here.
library;

/// WHERE a validity window's end came from. Required, never defaulted.
enum ValidityProvenance {
  /// The publisher itself declared this boundary. For JMA's forecast payload
  /// these are the verbatim `timeDefines` instants — the meteorological
  /// service's own interval boundaries, relayed, not derived.
  publisherDeclared,

  /// WE made this boundary up (e.g. `effective + 1h`). It is a guess wearing a
  /// timestamp. Nameable so that it can be REFUSED — see
  /// [TripHazardMemory.speakableAt], which will not utter it.
  adapterSynthesised,
}

/// A window of time for which a forecast is VALID — as distinct from the age of
/// an observation.
class ValidityWindow {
  const ValidityWindow({
    required this.start,
    required this.end,
    required this.provenance,
  });

  /// Inclusive start instant (UTC).
  final DateTime start;

  /// Exclusive end instant (UTC).
  final DateTime end;

  /// Where [end] came from. There is no default. A caller must SAY.
  final ValidityProvenance provenance;

  /// True when [now] falls inside `[start, end)`.
  ///
  /// This is the question the app could not previously ask. Not "how old is
  /// this?" but "is this TRUE RIGHT NOW?".
  bool covers(DateTime now) {
    final t = now.toUtc();
    return !t.isBefore(start) && t.isBefore(end);
  }

  Map<String, dynamic> toJson() => {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'provenance': provenance.name,
      };

  static ValidityWindow? fromJson(Map<String, dynamic> j) {
    final s = DateTime.tryParse(j['start']?.toString() ?? '');
    final e = DateTime.tryParse(j['end']?.toString() ?? '');
    if (s == null || e == null) return null;
    final p = ValidityProvenance.values
        .where((v) => v.name == j['provenance']?.toString())
        .firstOrNull;
    // An unrecognised provenance is NOT silently upgraded to publisherDeclared.
    // Unknown origin is the synthesised case: refusable.
    if (p == null) return null;
    return ValidityWindow(start: s.toUtc(), end: e.toUtc(), provenance: p);
  }
}

/// The classes of winter hazard this memory can carry.
///
/// Deliberately small. Each member must correspond to something a publisher
/// DECLARES for a bounded interval — not something we infer.
enum ForecastHazardKind {
  /// The publisher's own forecast text for this interval contains 雪 (snow).
  snow,
}

/// A hazard that a publisher declared for a bounded, publisher-declared interval.
class ForecastHazard {
  const ForecastHazard({
    required this.kind,
    required this.window,
    required this.publisherText,
    required this.source,
    required this.issuedAt,
    required this.areaName,
  });

  final ForecastHazardKind kind;

  /// The interval this hazard is valid FOR.
  final ValidityWindow window;

  /// The publisher's own words, VERBATIM. Never our paraphrase.
  /// (Article 17 (a): verbatim relay of a published forecast.)
  final String publisherText;

  /// e.g. `JMA 秋田地方気象台`.
  final String source;

  /// The publisher's own `reportDatetime` — when THEY issued it.
  final DateTime issuedAt;

  /// The publisher's own area name, verbatim (e.g. 沿岸).
  final String areaName;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'window': window.toJson(),
        'publisherText': publisherText,
        'source': source,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'areaName': areaName,
      };

  static ForecastHazard? fromJson(Map<String, dynamic> j) {
    final w = j['window'];
    if (w is! Map<String, dynamic>) return null;
    final window = ValidityWindow.fromJson(w);
    if (window == null) return null;
    final kind = ForecastHazardKind.values
        .where((v) => v.name == j['kind']?.toString())
        .firstOrNull;
    if (kind == null) return null;
    final issued = DateTime.tryParse(j['issuedAt']?.toString() ?? '');
    if (issued == null) return null;
    return ForecastHazard(
      kind: kind,
      window: window,
      publisherText: j['publisherText']?.toString() ?? '',
      source: j['source']?.toString() ?? '',
      issuedAt: issued.toUtc(),
      areaName: j['areaName']?.toString() ?? '',
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
