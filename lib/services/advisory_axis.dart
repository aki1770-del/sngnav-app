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
  var top = AdvisorySeverity.unknown;
  for (final a in result.advisories) {
    if (a.severity.index > top.index) top = a.severity;
  }
  return switch (top) {
    AdvisorySeverity.unknown => AdvisoryLevel.moderate,
    AdvisorySeverity.minor => AdvisoryLevel.minor,
    AdvisorySeverity.moderate => AdvisoryLevel.moderate,
    AdvisorySeverity.severe => AdvisoryLevel.severe,
    AdvisorySeverity.extreme => AdvisoryLevel.extreme,
  };
}
