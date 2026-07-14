/// TRIP HAZARD MEMORY — a condition source that needs no source.
///
/// This is the organ the app did not have. At PLAN time, while she still has a
/// network, we fetch JMA's forward forecast and persist the hazards it declares
/// for the trip window — each with its OWN publisher-declared validity window.
/// In the dead zone, at T+90, with no network and no GPS, this layer answers a
/// question that needs neither: **is a hazard VALID RIGHT NOW?**
///
/// ── WHY THIS IS NOT AN `AdvisoryProvider` (the seam decision) ────────────────
/// `condition_aggregator`'s contract is
/// `AdvisoryProvider.fetchActiveAdvisoriesAtPoint({lat, lon})`. It cannot admit
/// this source, for two independent reasons, and BOTH are the point:
///
///   1. NO FETCH, NO POINT-QUERY. This source performs neither. Its entire value
///      is that it works when fetching is impossible. Bending it to a
///      fetch-and-point-query shape would require re-cutting a PUBLISHED package
///      interface (5 adapters depend on it) to accommodate a source defined by
///      not needing it.
///
///   2. IT WOULD LAUNDER THE PROVENANCE. `Advisory.expires` carries three
///      incompatible meanings at once (MEASURED — see forecast_validity.dart):
///      publisher-declared in NWS/Digitraffic, ADAPTER-SYNTHESISED (`effective +
///      1h`) in MET Norway, null in JMA and OWM. To express our
///      publisher-declared validity as an `Advisory.expires`, we would pour a
///      guarantee into the same field that carries a fabrication, and no
///      consumer downstream could ever tell them apart again. That is NDI's
///      Andon, walked straight into.
///
/// So the smaller honest change is the one taken: this source lives in the APP,
/// keeps its own typed [ValidityWindow] with an explicit [ValidityProvenance],
/// and never touches `Advisory`. The published package interface is UNCHANGED.
/// NDI's Andon on `Advisory.expires` remains OPEN and is not claimed as fixed.
///
/// ── WHAT THIS IS NOT ────────────────────────────────────────────────────────
/// It is NOT "announce a stale observation". Honest-absence and the cry-wolf
/// discipline stand VERBATIM. A JMA forecast issued at 07:00 for 12:00–18:00 is
/// not "stale" at 13:30 — it is VALID, and saying so is the truth. The spoken
/// line names itself as a FORECAST, names its publisher, and is uttered ONLY
/// while the publisher's own declared window covers the clock. Outside that
/// window this layer says NOTHING and the honest-absence line stands.
library;

import 'dart:convert';
import 'dart:io';

import 'forecast_validity.dart';
import '../voice/offline_safety_voice.dart';

/// The spoken line for a snow hazard that a publisher declared VALID FOR NOW,
/// learned before she left.
///
/// Every clause is load-bearing, and the honesty is IN THE SENTENCE, not in a
/// comment above it:
///   出発前に取得した気象庁の予報では — names the publisher (JMA) and says WHEN we
///     got it (before departure). She is never told we just heard this.
///   この時間帯は雪の予報です — it is valid FOR THIS TIME BAND. Not "it is snowing".
///   これは観測ではなく予報です — it says, out loud, THIS IS A FORECAST, NOT AN
///     OBSERVATION. The distinction the whole layer exists to preserve is spoken
///     to the person it protects.
///
/// Slotless by construction, so it can be pre-rendered to bundled audio and
/// sound with the network and the TTS engine both gone.
const String kForecastSnowValidJa =
    '出発前に取得した気象庁の予報では、この時間帯は雪の予報です。これは観測ではなく予報です。速度を落とし、車間距離をとってください。';

/// The VISIBLE en counterpart of [kForecastSnowValidJa]. NOT spoken: the
/// bundled offline mouth is ja-only, and an en forecast voice is a recorded,
/// unclaimed bound — but the SCREEN has no mouth constraint, and a
/// publisher-declared-valid hazard must not be deleted from the visible
/// channel by locale. Same clause-for-clause honesty as the ja line.
const String kForecastSnowValidEn =
    'The JMA forecast fetched before departure calls for snow during this '
    'time band. This is a forecast, not an observation. Slow down and keep '
    'extra following distance.';

/// The persisted, trip-window-valid hazard bundle.
class TripHazardMemory {
  const TripHazardMemory({
    required this.hazards,
    required this.capturedAt,
  });

  /// Publisher-declared hazards, each carrying its own validity window.
  final List<ForecastHazard> hazards;

  /// When WE captured this bundle (distinct from the publisher's `issuedAt`).
  final DateTime capturedAt;

  /// Every hazard whose PUBLISHER-DECLARED validity window covers [now].
  ///
  /// The provenance filter is not decoration. A window whose end WE invented is
  /// refused here — it may be stored, it may be inspected, it may never be
  /// spoken to a driver as though a meteorological service had promised it.
  List<ForecastHazard> activeAt(DateTime now) => [
        for (final h in hazards)
          if (h.window.provenance == ValidityProvenance.publisherDeclared &&
              h.window.covers(now))
            h,
      ];

  /// The ja line to SPEAK at [now], or null for silence.
  ///
  /// Returns only text that is in the bundled offline mouth
  /// ([OfflineSafetyVoice]) — a warning that needs TTS is a warning she does not
  /// hear, because system TTS was measured 2026-07-12 as silent-then-hung
  /// offline on her phone. If the mouth cannot say it, we return null rather
  /// than pretend: silence we know about beats a warning that never sounds.
  String? speakableJaAt(DateTime now) {
    final active = activeAt(now);
    if (active.isEmpty) return null;
    if (active.any((h) => h.kind == ForecastHazardKind.snow)) {
      const line = kForecastSnowValidJa;
      // The mouth is the arbiter. If the bytes are not on the phone, this is
      // not speakable, and we say so by saying nothing.
      return OfflineSafetyVoice.covers(line) ? line : null;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'hazards': [for (final h in hazards) h.toJson()],
      };

  static TripHazardMemory? fromJson(Map<String, dynamic> j) {
    final cap = DateTime.tryParse(j['capturedAt']?.toString() ?? '');
    if (cap == null) return null;
    final raw = j['hazards'];
    if (raw is! List) return null;
    final hazards = <ForecastHazard>[];
    for (final h in raw) {
      if (h is! Map<String, dynamic>) continue;
      final parsed = ForecastHazard.fromJson(h);
      // A hazard we cannot fully reconstruct is DROPPED, not half-built. A
      // half-built hazard is a hazard with an invented field.
      if (parsed != null) hazards.add(parsed);
    }
    return TripHazardMemory(hazards: hazards, capturedAt: cap.toUtc());
  }
}

/// The on-disk memory. Plain JSON in the app's documents directory: it must be
/// readable with the network gone, the process cold-started, and the phone
/// rebooted on a roadside.
class TripHazardStore {
  TripHazardStore({required this.file});

  final File file;

  static const String fileName = 'trip_hazard_memory.json';

  Future<void> save(TripHazardMemory memory) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(memory.toJson()), flush: true);
  }

  /// Load the memory. Returns null when absent or unreadable — NEVER a
  /// fabricated empty-but-valid memory, because "we have no memory" and "the
  /// forecast says nothing is wrong" are different sentences and only one of
  /// them is safe to act on.
  Future<TripHazardMemory?> load() async {
    try {
      if (!await file.exists()) return null;
      final decoded = json.decode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return TripHazardMemory.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
