/// The advisory axis as the APP knows it — the rung input the drive brain
/// consumes, PLUS the completeness state the brain has no channel for.
///
/// ## The asymmetry this exists to work around
///
/// `compound_failure_advisor` models VISIBILITY as a first-class unknown and
/// ADVISORIES as a plain value. On the same struct, in the same package:
///
///  - `DriveSituation.visibilityMeters == null` -> `Unknown.noVisibilityReading`
///    is emitted and the advisor FLOORS to `heightenedCaution`.
///  - `DriveSituation.advisorySeverity == null` -> the package documents this
///    as "no advisory in force". There is no `Unknown` member for advisories
///    at all: 0.1.2's enum is position x3 (`positionCouldBeAnywhereInRadius`,
///    `noTrustedGpsForAWhile`, `noPositionAtAll`), visibility x2
///    (`noVisibilityReading`, `visibilityReadingIsStale`) and `speedUnknown`.
///
/// So every advisory-source OUTAGE is coerced to "not firing" and leaves NO
/// trace anywhere. Measured directly against compound_failure_advisor 0.1.2 on
/// 2026-07-31, trusted position + clear visibility:
///
///     advisorySeverity: null  -> continueDriving, reasons={},
///                                unknowns=[speedUnknown]
///     visibilityMeters: null  -> heightenedCaution,
///                                reasons={unknownVisibility},
///                                unknowns=[noVisibilityReading, speedUnknown]
///
/// The advisory outage contributes nothing at all — the only unknown present
/// is the unrelated `speedUnknown`. Giving `Unknown` an advisory member is the
/// real repair and it is a PACKAGE-side change; this file is the app-side
/// countermeasure until then.
///
/// ## Why this does NOT raise the rung
///
/// An outage is an UNKNOWN, not a hazard. Manufacturing a warning out of a
/// feed failure is the cry-wolf the Chair ruled against on 2026-07-23 (the
/// sub-zero frozen-surface chip was constituted as a calm glance chip that
/// deliberately does NOT raise the caution rung, under a named cry-wolf
/// contract, for exactly this reason). An instrument that warns whenever it
/// cannot see teaches HER to stop believing it — and then it is worth nothing
/// on the night it is right.
///
/// The countermeasure is the other direction: **withhold the reassurance.**
/// The rung is untouched; the positive all-clear is what we decline to print.
///
/// ## What this type guarantees — and what it does NOT
///
/// [readAdvisoryAxis] CARRIES the completeness state alongside the level, and
/// the app uses both. The three drive-brain feeds take `.level` alone —
/// `_feedDriveHud`, `_pushMeasuredHazardToDriveHud` and `_onVisibilityChanged`
/// in main.dart, because `DriveSituation` has no completeness channel to hand
/// it to — while `_appUnknowns` reads `.completenessProven` separately. That
/// second read is what puts an unproven lookup into the 「不明な点」 row and
/// scopes the lowest-rung reassurance.
///
/// That is a DISCIPLINE THE TESTS GUARD, not a structure the compiler
/// enforces. This is a plain class with a public const constructor and two
/// public final fields: a caller can construct one, destructure one, or take
/// `.level` and leave `.completenessProven` on the floor — and only a test
/// will object. What pairing the two values buys is narrower and real: it
/// removes the DEFAULT of dropping the completeness claim. The former free
/// function `topAdvisoryLevel` returned a bare `AdvisoryLevel?`, so every
/// caller inherited a completeness claim nobody had checked.
///
/// A structural guarantee looks different. `condition_aggregator`'s own 0.1.0
/// line makes the lookup a SEALED `AdvisoryLookup`, where an exhaustive
/// `switch` refuses a caller who never handled "could not look". This app
/// resolves 0.0.8, and this type is not sealed — do not read it as a proof.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show AdvisoryLevel;
import 'package:condition_aggregator/condition_aggregator.dart';

/// The advisory axis at one instant: what is in force, and whether we can
/// prove we looked everywhere.
class AdvisoryAxis {
  const AdvisoryAxis({
    required this.level,
    required this.completenessProven,
  });

  /// The single most-severe advisory level in force, or `null` for none.
  ///
  /// `null` means "nothing in force in what we saw" — it does NOT mean "the
  /// sky is quiet". Only [completenessProven] can say that.
  final AdvisoryLevel? level;

  /// `true` only when the lookup proved it was COMPLETE — every covering
  /// source was asked and every one of them answered
  /// (`AdvisoryAggregateResult.canAssertNoAdvisory`, condition_aggregator
  /// 0.0.8: no provider errors, `sourcesQueried` present and greater than 0).
  ///
  /// When this is `false`, a `null` [level] is an ABSENCE OF KNOWLEDGE, not an
  /// all-clear, and no surface may render it as a positive global claim.
  final bool completenessProven;

  /// Convenience for the surfaces that must scope or withhold a reassurance.
  bool get completenessUnproven => !completenessProven;
}

/// Reads the advisory axis out of an aggregate [result].
///
/// A `null` [result] is the bootstrap state — the lane has not returned yet,
/// so we have not looked. It is deliberately NOT a proven clear: reading the
/// moment before the first fetch as a measured all-clear is the same
/// fabricated clear in a different disguise.
AdvisoryAxis readAdvisoryAxis(AdvisoryAggregateResult? result) {
  if (result == null) {
    return const AdvisoryAxis(level: null, completenessProven: false);
  }
  return AdvisoryAxis(
    level: _topLevelOf(result),
    completenessProven: result.canAssertNoAdvisory,
  );
}

/// `unknown` maps to [AdvisoryLevel.moderate], NOT null. In
/// `condition_aggregator`, `unknown` only ever rides a REAL, constructed
/// advisory — it means "a warning IS in force, but its severity could not be
/// graded". A live warning we cannot grade must not vanish from the drive
/// brain (same deliberate pinning as drive_situation_fusion 0.1.0's
/// `advisoryLevelOf`, read from its src/fuse.dart).
///
/// This is the ONE place `unknown`-the-severity is inflated, and it is not the
/// same thing as an outage: a graded-unknown warning is a publisher STATEMENT
/// that something is in force. An outage is the absence of any statement, and
/// it is carried by [AdvisoryAxis.completenessProven] instead — never by
/// inflating this level.
AdvisoryLevel? _topLevelOf(AdvisoryAggregateResult result) {
  if (result.advisories.isEmpty) return null;
  // A source that reported its OWN document stale does not set the rung.
  //
  // `condition_aggregator` already closed the SILENCE direction: an empty read
  // from a dead document is not an all-clear — "the same gap wearing the shape
  // of an answer" (advisory_aggregator.dart:113). This is the MIRROR, and it
  // was open: a WARNING from that same dead source is not a live warning — it
  // is a corpse wearing the shape of an alarm.
  //
  // Measured live 2026-08-24 against the real feed, Akita (39.72, 140.10):
  // JMA's warning document had not been rewritten for 88 days, and the read
  // SUCCEEDED — `providerErrors: []`, `sourcesQueried: 1` — carrying one
  // advisory, 雷注意報, `severity: moderate`, `expires: null`, whose own
  // headline names a validity window that closed on 2026-05-28
  // (「２８日昼過ぎから２８日夜のはじめ頃まで」). Fed to the drive brain on a
  // clear, trusted-position drive that advisory alone moves the advisor from
  // `continueDriving` to `heightenedCaution`, and a RISING rung fires
  // `_announcer.announce` — audio AND haptic (main.dart:1070-1071).
  //
  // So the eyes-off channels were being driven by a three-month-old document.
  // That is the cry-wolf the Chair ruled against on 2026-07-23, arriving
  // through the one door this file had left open: the doctrine above says "an
  // outage is an UNKNOWN, not a hazard", and a stale read IS an outage — it
  // just arrives dressed as a successful answer instead of an error.
  //
  // WHY DROPPING THE LEVEL IS NOT A FABRICATED ALL-CLEAR, which is the worse
  // error and the one this app must never commit: `staleSources` non-empty
  // already forces `canAssertNoAdvisory` false
  // (advisory_aggregator.dart:137), so `completenessProven` is false on this
  // exact path and `_appUnknowns` still renders
  // `AppUnknown.advisoryLookupIncomplete` and still WITHHOLDS the reassurance.
  // The state moves from "fabricated alarm + unknown" to "unknown" — strictly
  // more honest in both directions, never to "clear".
  //
  // Per-SOURCE, deliberately not blanket: a live NWS advisory beside a stale
  // JMA one still sets the rung. Suppressing the whole axis because one
  // publisher went quiet would be its own false silence.
  //
  // The CARD is untouched (advisory_cards.dart still renders the advisory
  // beside its stale-source banner). That is the split AAE-7 asks for: the
  // visual surface can carry provenance in the same glance, so it keeps the
  // information; the eyes-off surface cannot say "…but this is 88 days old",
  // so it must not assert the urgency.
  final staleSources = <AdvisorySource>{
    for (final s in result.staleSources) s.source,
  };
  var sawLive = false;
  var top = AdvisorySeverity.unknown;
  for (final a in result.advisories) {
    if (staleSources.contains(a.source)) continue;
    sawLive = true;
    if (a.severity.index > top.index) top = a.severity;
  }
  if (!sawLive) return null;
  return switch (top) {
    AdvisorySeverity.unknown => AdvisoryLevel.moderate,
    AdvisorySeverity.minor => AdvisoryLevel.minor,
    AdvisorySeverity.moderate => AdvisoryLevel.moderate,
    AdvisorySeverity.severe => AdvisoryLevel.severe,
    AdvisorySeverity.extreme => AdvisoryLevel.extreme,
  };
}
