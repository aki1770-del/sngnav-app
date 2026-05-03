/// Slice 5d — multi-source advisory ingestion.
///
/// Wraps `condition_aggregator`'s `AdvisoryAggregator` with a thin
/// driver-facing facade. The integrator app constructs one or more
/// `AdvisoryProvider` adapters (Slice 5d ships only the NWS adapter;
/// JMA + MET Norway providers are future-Slice work) and the
/// AdvisoryService fans queries across them.
///
/// Per-provider failure handling is delegated to the underlying
/// aggregator: a transient failure of one provider does not abort the
/// fan-out; the driver receives advisories from the surviving
/// providers and the integrator can surface staleness honestly via
/// `result.providerErrors`.
///
/// Driver-facing loom: "when ANY publisher (NWS / JMA / MET Norway)
/// has issued an advisory for the driver's current point, she sees a
/// typed advisory event with severity / certainty / urgency / area /
/// effective / expires normalized across sources. Source attribution
/// is preserved verbatim — the driver always knows who published."
library;

import 'package:condition_aggregator/condition_aggregator.dart'
    show
        AdvisoryAggregateResult,
        AdvisoryAggregator,
        AdvisoryProvider;

class AdvisoryService {
  AdvisoryService({required List<AdvisoryProvider> providers})
      : _aggregator = AdvisoryAggregator(providers: providers);

  final AdvisoryAggregator _aggregator;
  bool _initCalled = false;

  /// True after [init] returns successfully at least once.
  bool get isInitialized => _aggregator.isInitialized;

  /// Initialize all underlying providers. Idempotent.
  Future<void> init() async {
    if (_initCalled && _aggregator.isInitialized) return;
    _initCalled = true;
    await _aggregator.init();
  }

  /// Fetch all active advisories at the given point. Per-provider
  /// failures are surfaced via the result's `providerErrors` field;
  /// successes from surviving providers are merged into `advisories`.
  Future<AdvisoryAggregateResult> fetchAtPoint({
    required double latitude,
    required double longitude,
  }) {
    if (!isInitialized) {
      throw StateError(
        'AdvisoryService.fetchAtPoint called before init()',
      );
    }
    return _aggregator.fetchActiveAdvisoriesAtPoint(
      latitude: latitude,
      longitude: longitude,
    );
  }
}
