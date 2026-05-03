/// Slice 5d — NOAA / NWS advisory provider.
///
/// Implements `condition_aggregator`'s `AdvisoryProvider` contract by
/// adapting `noaa_nws_adapter`'s `WinterAlert` records (CAP-class)
/// into the source-neutral `Advisory` shape the aggregator expects.
///
/// Source attribution preserved verbatim per package boundary
/// (`AdvisorySource.nwsUnitedStates`); the publisher's `event` string
/// (e.g. `Winter Storm Warning`) is carried into `Advisory.eventClass`
/// without translation.
///
/// Driver-facing loom: "when NWS has issued a winter alert for the
/// driver's current point, the integrator surfaces the advisory in
/// the publisher's exact wording — not in our paraphrase. The driver
/// recognizes the publisher's authority and decides."
library;

import 'package:condition_aggregator/condition_aggregator.dart'
    show
        Advisory,
        AdvisoryCertainty,
        AdvisoryProvider,
        AdvisoryProviderInitException,
        AdvisorySeverity,
        AdvisorySource,
        AdvisoryUrgency;
import 'package:noaa_nws_adapter/noaa_nws_adapter.dart'
    show
        AlertCertainty,
        AlertSeverity,
        AlertUrgency,
        NoaaNwsClient,
        WinterAlert;

class NoaaAdvisoryProvider implements AdvisoryProvider {
  NoaaAdvisoryProvider({
    required NoaaNwsClient client,
    bool actualOnly = true,
  })  : _client = client,
        _actualOnly = actualOnly;

  final NoaaNwsClient _client;
  final bool _actualOnly;
  bool _initialized = false;

  @override
  AdvisorySource get source => AdvisorySource.nwsUnitedStates;

  @override
  Future<void> init() async {
    // No remote handshake needed for the NWS API; mark ready.
    if (_initialized) return;
    if (_client.userAgent.trim().isEmpty) {
      throw const AdvisoryProviderInitException(
        source: AdvisorySource.nwsUnitedStates,
        message: 'NoaaNwsClient requires a non-empty User-Agent',
      );
    }
    _initialized = true;
  }

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!_initialized) {
      throw StateError(
        'NoaaAdvisoryProvider.fetchActiveAdvisoriesAtPoint called before init()',
      );
    }
    final alerts = await _client.fetchActiveWinterAlerts(
      latitude: latitude,
      longitude: longitude,
      actualOnly: _actualOnly,
    );
    return alerts.map(toAdvisory).toList(growable: false);
  }

  /// Convert one `WinterAlert` to an `Advisory`. Visible for testing.
  static Advisory toAdvisory(WinterAlert a) {
    return Advisory(
      source: AdvisorySource.nwsUnitedStates,
      eventClass: a.event,
      severity: _severity(a.severity),
      certainty: _certainty(a.certainty),
      urgency: _urgency(a.urgency),
      areaDescription: a.areaDesc,
      effective: a.effective,
      expires: a.expires,
      headline: a.headline,
      description: a.description,
    );
  }

  static AdvisorySeverity _severity(AlertSeverity s) => switch (s) {
        AlertSeverity.unknown => AdvisorySeverity.unknown,
        AlertSeverity.minor => AdvisorySeverity.minor,
        AlertSeverity.moderate => AdvisorySeverity.moderate,
        AlertSeverity.severe => AdvisorySeverity.severe,
        AlertSeverity.extreme => AdvisorySeverity.extreme,
      };

  static AdvisoryCertainty _certainty(AlertCertainty c) => switch (c) {
        AlertCertainty.unknown => AdvisoryCertainty.unknown,
        AlertCertainty.unlikely => AdvisoryCertainty.unlikely,
        AlertCertainty.possible => AdvisoryCertainty.possible,
        AlertCertainty.likely => AdvisoryCertainty.likely,
        AlertCertainty.observed => AdvisoryCertainty.observed,
      };

  static AdvisoryUrgency _urgency(AlertUrgency u) => switch (u) {
        AlertUrgency.unknown => AdvisoryUrgency.unknown,
        AlertUrgency.past => AdvisoryUrgency.past,
        AlertUrgency.future => AdvisoryUrgency.future,
        AlertUrgency.expected => AdvisoryUrgency.expected,
        AlertUrgency.immediate => AdvisoryUrgency.immediate,
      };
}
