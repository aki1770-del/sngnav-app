/// Factory for the JMA advisory provider used by `AdvisoryService`.
///
/// The condition_aggregator_jma package's `JmaAdvisoryProvider` already
/// implements `condition_aggregator`'s `AdvisoryProvider` contract — no
/// app-side adapter is needed. This factory exists so the construction
/// site is one symbol (testable, fakeable in widget tests) rather than
/// scattered across `main.dart`.
///
/// Driver-facing loom: when JMA has issued a 大雪 / 暴風雪 / 着雪
/// advisory for the driver's current point in Japan, the integrator
/// surfaces a typed `Advisory` event with the publisher's exact
/// wording — not in our paraphrase. Verbatim JA event name is
/// preserved in `Advisory.eventClass` per Article 17 (β).
library;

import 'package:condition_aggregator/condition_aggregator.dart'
    show AdvisoryProvider;
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart'
    show JmaAdvisoryProvider;

/// Builds a `JmaAdvisoryProvider` configured for sngnav-app. Returned
/// as the interface type so callers compose it into the aggregator
/// without coupling to the concrete adapter.
AdvisoryProvider buildJmaAdvisoryProvider({required String userAgent}) {
  return JmaAdvisoryProvider(userAgent: userAgent);
}
