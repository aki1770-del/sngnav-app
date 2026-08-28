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
    // ⚑ 7 DAYS, NOT THE ADAPTER'S 6-HOUR DEFAULT — set by the integrator,
    // which is the route the adapter's own dartdoc names for an integrator
    // that has measured its region.
    //
    // The 6-hour default assumes "JMA rewrites a prefecture's warning document
    // many times a day", which is true of the sibling FORECAST path
    // (schedule-driven) and false of the WARNING path (event-driven). A quiet
    // prefecture is simply not rewritten for days, and that is healthy.
    //
    // Measured live 2026-08-24 across all 58 offices in JMA's own area
    // catalogue, age taken from the NEWEST document per office: 16/58 = 27.6%
    // exceeded 6 h, and 13 of those 16 were SIMULTANEOUSLY serving a warning
    // the same document declared in force — so the notice would fire beside a
    // live warning and contradict it. An hour earlier the same measurement gave
    // 20/58 and 17 of 20: the count MOVES, the shape does not.
    //
    // This is not a cosmetic knob. `feedStaleness` non-null puts the source in
    // `staleSources`, and `canAssertNoAdvisory` is false whenever that list is
    // non-empty — so the threshold is the switch that turns the honest
    // all-clear OFF. At 6 h it was off about a third of the time, on healthy
    // data, in HER own prefecture.
    //
    // 7 d clears the observed healthy maximum with margin, still catches the
    // 2026-05-29 path retirement on day 8 instead of day 88, and matches the
    // value NDI staged for 0.5.1/0.3.3 so the app and the adapter family will
    // agree when those publish.
    staleFeedThreshold: const Duration(days: 7),
  );
}
