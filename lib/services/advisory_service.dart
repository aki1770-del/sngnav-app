/// Slice 5d — multi-source advisory ingestion, REGION-GATED.
///
/// Wraps `condition_aggregator`'s `AdvisoryAggregator` with a thin
/// driver-facing facade. The integrator app constructs one or more
/// `AdvisoryProvider` adapters (NWS + JMA today; MET Norway is future-
/// Slice work), each PAIRED with a geographic coverage predicate
/// ([CoveredProvider]), and the AdvisoryService queries ONLY the
/// providers whose publisher covers the query point.
///
/// **Why region-gating (the defect this closes).** The raw aggregator
/// fans a point query across EVERY provider. For HER Akita point
/// (39.7167, 140.0983) that called the US NWS endpoint — which has no
/// Japan data, answered HTTP 400 every time (a useless error card), and
/// leaked HER coordinate to a US service that cannot help her (a D4
/// dignity / privacy boundary). Coverage-gating means a Japan point is
/// sent ONLY to JMA and NWS is never contacted; a US point is sent ONLY
/// to NWS. A point covered by neither is sent to no one (honest: no
/// covering source, so an empty result — no request, no error).
///
/// Per-provider failure handling is delegated to the underlying
/// aggregator: a transient failure of one COVERING provider does not
/// abort the fan-out; the driver receives advisories from the surviving
/// covering providers and the integrator can surface staleness honestly
/// via `result.providerErrors`.
///
/// Driver-facing loom: "when a publisher THAT COVERS the driver's point
/// has issued an advisory, she sees a typed advisory event with severity
/// / certainty / urgency / area / effective / expires normalized across
/// sources. A publisher that does not cover her point is never queried,
/// so its region-mismatch error never masquerades as a real advisory
/// failure, and her coordinate never travels to a service that cannot
/// help her. Source attribution is preserved verbatim."
library;

import 'package:condition_aggregator/condition_aggregator.dart'
    show
        AdvisoryAggregateResult,
        AdvisoryAggregator,
        AdvisoryProvider;

import 'provider_coverage.dart';

class AdvisoryService {
  AdvisoryService({required List<CoveredProvider> providers})
      : _covered = List<CoveredProvider>.unmodifiable(providers);

  final List<CoveredProvider> _covered;
  bool _initialized = false;

  /// True after [init] returns successfully at least once.
  bool get isInitialized => _initialized;

  /// Initialize every underlying provider ONCE (the `AdvisoryProvider`
  /// contract: `init()` invoked exactly once before any `fetchActive…`
  /// call; provider `init()` is idempotent, so the per-fetch covering
  /// aggregator re-invoking it below is a safe no-op). Idempotent.
  Future<void> init() async {
    if (_initialized) return;
    for (final cp in _covered) {
      await cp.provider.init();
    }
    _initialized = true;
  }

  /// Fetch all active advisories at the given point, querying ONLY the
  /// providers whose coverage predicate includes `(latitude, longitude)`.
  ///
  /// Per-covering-provider failures are surfaced via the result's
  /// `providerErrors` field; successes from surviving covering providers
  /// are merged into `advisories`. A point covered by NO provider returns
  /// an empty result WITHOUT contacting anyone (no request is sent).
  Future<AdvisoryAggregateResult> fetchAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!isInitialized) {
      throw StateError(
        'AdvisoryService.fetchAtPoint called before init()',
      );
    }
    // Region-gate: select only providers whose publisher covers this point.
    final covering = <AdvisoryProvider>[
      for (final cp in _covered)
        if (cp.covers(latitude, longitude)) cp.provider,
    ];
    if (covering.isEmpty) {
      // Honest: no publisher covers this point. Nothing is queried — no
      // request leaves the device, no coordinate is sent to a service that
      // cannot help. The driver sees an honest empty state, never an error.
      return const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
      );
    }
    // Reuse the library's tested fan-out (per-provider isolation + merge)
    // over just the covering subset. Building a fresh aggregator per fetch
    // respects the AdvisoryAggregator init contract (read from
    // condition_aggregator 0.0.7 advisory_aggregator.dart): its `init()`
    // loops the covering providers calling each provider's IDEMPOTENT
    // `init()` (safe no-op — they were already inited by our own [init]),
    // then sets its own `_initialized` flag so `fetchActive…` proceeds.
    final aggregator = AdvisoryAggregator(providers: covering);
    await aggregator.init();
    return aggregator.fetchActiveAdvisoriesAtPoint(
      latitude: latitude,
      longitude: longitude,
    );
  }
}
