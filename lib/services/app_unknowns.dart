/// App-owned first-class unknowns — the ones the drive brain has no channel
/// for.
///
/// `compound_failure_advisor`'s `Unknown` enum (0.1.2) covers position,
/// visibility and speed. It has no member for "the advisory lookup could not
/// prove it was complete" and none for "the weather observation could not be
/// read", so those outages arrive at the glance as SILENCE — and silence, on a
/// safety surface, reads as calm.
///
/// These rows are the app-side countermeasure. They ride the SAME 「不明な点」
/// list as the package's own unknowns, in the same
/// `<what happened> — <what we do not know>` convention, so an outage is
/// STATED rather than inferred from an absence.
///
/// They never raise the caution rung. An outage is an unknown, not a hazard;
/// manufacturing a warning from a feed failure is the cry-wolf the Chair ruled
/// against on 2026-07-23. These rows withhold the reassurance instead.
library;

import '../l10n/app_localizations.dart';

/// Liveness of the measured-weather (JMA observation) lane.
///
/// The two failure shapes are DISTINCT facts about the world and must not
/// collapse: before this existed, a feed LOSS and a cold START both left the
/// watches non-firing, and a non-firing watch is exactly what a measured
/// all-clear looks like. Three different states, one indistinguishable floor.
enum MeasuredWatchFeed {
  /// No observation has been read yet this session. We have not looked.
  notYetRead,

  /// The latest read SUCCEEDED — the watch verdicts are measured.
  live,

  /// The latest read FAILED. The live verdicts are cleared (they must not
  /// present a stale reading as current), so the watches are non-firing for a
  /// reason that has nothing to do with the road.
  lost,
}

/// An unknown the app owns because the drive brain cannot express it.
enum AppUnknown {
  /// The advisory lookup cannot prove it was complete
  /// (`AdvisoryAggregateResult.canAssertNoAdvisory` is false, or no lookup has
  /// returned yet). Whether a warning is in force is UNKNOWN.
  advisoryLookupIncomplete,

  /// The measured-weather observation has not been read yet this session.
  measuredWatchNotYetRead,

  /// The measured-weather observation could not be read.
  measuredWatchFeedLost,
}

/// The app-owned unknowns in force right now, in the order they are shown.
///
/// Advisory first: it is the axis with a live publisher behind it, and the one
/// whose silence would otherwise be read as a publisher all-clear.
List<AppUnknown> appUnknownsFor({
  required bool advisoryCompletenessProven,
  required MeasuredWatchFeed measuredWatchFeed,
}) =>
    [
      if (!advisoryCompletenessProven) AppUnknown.advisoryLookupIncomplete,
      switch (measuredWatchFeed) {
        MeasuredWatchFeed.notYetRead => AppUnknown.measuredWatchNotYetRead,
        MeasuredWatchFeed.lost => AppUnknown.measuredWatchFeedLost,
        MeasuredWatchFeed.live => null,
      },
    ].whereType<AppUnknown>().toList(growable: false);

/// The driver-facing sentence for an app-owned unknown.
///
/// [AppUnknown.advisoryLookupIncomplete] resolves to the SAME
/// `AppL10n` string the advisory CARD renders, by construction — the card and
/// the glance must never drift into two different sentences about one state.
String appUnknownLabel(AppUnknown unknown, AppL10n l) => switch (unknown) {
      AppUnknown.advisoryLookupIncomplete => l.advisoryLookupIncomplete,
      AppUnknown.measuredWatchNotYetRead => l.measuredWatchNotYetRead,
      AppUnknown.measuredWatchFeedLost => l.measuredWatchFeedLost,
    };
