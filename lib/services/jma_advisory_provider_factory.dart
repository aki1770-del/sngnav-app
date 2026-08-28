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
import 'package:http/http.dart' as http;

/// Builds a `JmaAdvisoryProvider` configured for sngnav-app. Returned
/// as the interface type so callers compose it into the aggregator
/// without coupling to the concrete adapter.
///
/// [client] and [now] are injection seams and default to the real ones, so
/// production construction is unchanged. They exist because the docstring
/// above promised this factory was "testable, fakeable in widget tests" and
/// it was not: with no seam, the one condition that most needed a test —
/// a JMA document that has stopped being rewritten, which serves a months-old
/// warning as `status=発表` — could not be reached from a test at all. A
/// factory that cannot be given a frozen feed cannot be asked what HER screen
/// shows when the feed freezes.
/// ⚑ The clock parameter is named `clock` on the 0.3.x line and `now` on 0.5.x.
/// The rename is not in either CHANGELOG. This factory is the one place that has
/// to know, which is the argument for the factory existing at all.
AdvisoryProvider buildJmaAdvisoryProvider({
  required String userAgent,
  http.Client? client,
  DateTime Function()? clock,
}) {
  return JmaAdvisoryProvider(
    userAgent: userAgent,
    client: client,
    clock: clock,
  );
}
