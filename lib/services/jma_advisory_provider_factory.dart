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
    // This is not a cosmetic knob. `feedStaleness` non-null puts the source in
    // `staleSources`; `canAssertNoAdvisory` is false whenever that list is
    // non-empty — so the threshold is the switch that turns the honest
    // all-clear OFF. Since 2026-08-24 it also gates the CAUTION RUNG: a source
    // in `staleSources` no longer sets `AdvisoryAxis.level`
    // (advisory_axis.dart `_topLevelOf`), because a warning from a document
    // that stopped being written is not a live warning — it is a corpse
    // wearing the shape of an alarm, and a rising rung SPEAKS to her.
    // ⚑ Restored 2026-08-24: the mechanism paragraph above was true and was
    // deleted by the same edit that removed the false measurement wrapped
    // around it. Only its closing sentence — "at 6 h it was off about a third
    // of the time, on healthy data" — was refuted; see below.
    //
    // ⚑ CORRECTED 2026-08-24 BY RE-MEASUREMENT (AAE). The rationale that
    // stood here was refuted by the genba it cited. It read: "Measured live
    // 2026-08-24 across all 58 offices ... 16/58 = 27.6% exceeded 6 h", and
    // concluded "7 d clears the observed healthy maximum with margin".
    //
    // RE-MEASURED the same day, all 58 offices from JMA's own
    // `bosai/common/const/area.json`, age taken from the document-level
    // `reportDatetime` — the EXACT field this adapter uses
    // (`jmaFeedReportDatetime`, jma_advisory_mapper.dart:445):
    //
    //     >= 6 h : 58/58 = 100%
    //     >= 7 d : 58/58 = 100%
    //     median 88.7 d   max 95.1 d (鳥取県)   min 88.4 d (福岡県)
    //
    // There is no "healthy maximum" to clear. The WHOLE warning tree is
    // frozen — every per-office document AND the aggregate `map.json` carry
    // `last-modified: Thu, 28 May 2026`. Confirmed out-of-band by the HTTP
    // header, not just the JSON body.
    //
    // CONTROL, because "everything is stale" is exactly what a broken clock
    // or a broken parser reports: the same method pointed at JMA's FORECAST
    // path returned Akita at 4.55 h — FRESH — and `bosai/amedas/latest_time`
    // was 17 s old. The instrument can produce a counter-example; there is
    // none on this path.
    //
    // So the 2026-05-29 path retirement this comment once hoped to "catch on
    // day 8" ALREADY HAPPENED, 88 days ago, and every read is stale today.
    //
    // THE VALUE IS UNCHANGED AT 7 d, deliberately, and that is not inertia:
    //   * Behaviour is identical at any threshold below ~88 d — the feed is
    //     dead, so 6 h and 7 d both flag 100%. Lowering it buys nothing now.
    //   * There is no healthy-cadence data to fit a threshold TO, because
    //     there is no healthy data on this path at all. Fitting a number to
    //     a corpse would be inventing a measurement.
    //   * 7 d stays the value NDI staged for 0.5.1/0.3.3, so the app and the
    //     adapter family still agree when those publish.
    // HONEST BOUND: this number is currently UNFALSIFIABLE against live data
    // and must be re-derived from real cadence if JMA ever resumes writing
    // this path. It is a placeholder that fails safe, not a fitted bound.
    staleFeedThreshold: const Duration(days: 7),
  );
}
