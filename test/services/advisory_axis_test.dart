/// Pins the app-side countermeasure for the ONE ROOT the 4-lens review found:
///
/// `compound_failure_advisor` has NO unknown channel for the advisory axis.
/// `DriveSituation.advisorySeverity` is an `AdvisoryLevel?` whose `null` the
/// package documents as "no advisory in force", and `Unknown` (0.1.2) has six
/// members — position x3, visibility x2, speed — and NONE for advisories. So a
/// total advisory outage and a genuinely quiet sky reach the brain as the same
/// value. Measured directly against compound_failure_advisor 0.1.2 on
/// 2026-07-31:
///
///   OUTAGE   (trusted pos, clear vis, advisorySeverity null)
///     -> continueDriving, reasons={}, unknowns=[speedUnknown]
///   VIS-UNKNOWN (visibilityMeters null)
///     -> heightenedCaution, unknowns=[noVisibilityReading, speedUnknown]
///
/// The visibility axis, on the same struct in the same package, is a
/// first-class unknown that floors to caution. The advisory axis leaves no
/// trace at all. That asymmetry is the root; the package-side fix (an advisory
/// member on `Unknown`) is a later, package-side change.
///
/// [AdvisoryAxis] is the app-side answer. It carries the completeness state
/// BESIDE the level and is the ONLY way to read the level, so no caller can
/// consume the rung input while silently dropping the fact that we may not
/// have looked.
///
/// The direction is settled and it is NOT "raise the rung": an outage is an
/// unknown, not a hazard. Manufacturing a warning from a feed failure is the
/// cry-wolf the Chair ruled against on 2026-07-23. We WITHHOLD THE
/// REASSURANCE; we never manufacture the warning.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show AdvisoryLevel;
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/advisory_axis.dart';

Advisory _advisory({AdvisorySeverity severity = AdvisorySeverity.severe}) =>
    Advisory(
      source: AdvisorySource.jmaJapan,
      eventClass: '大雪警報',
      severity: severity,
      certainty: AdvisoryCertainty.unknown,
      urgency: AdvisoryUrgency.unknown,
      areaDescription: '秋田中央',
      effective: DateTime.utc(2026, 1, 15, 4, 23),
      expires: null,
      headline: '秋田県では、大雪に警戒してください。',
      description: '秋田県では、大雪に警戒してください。',
    );

void main() {
  group('completeness is carried, not discarded', () {
    test('a COMPLETE empty lookup proves its own completeness', () {
      final axis = readAdvisoryAxis(const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 2,
      ));
      expect(axis.level, isNull, reason: 'nothing is in force');
      expect(axis.completenessProven, isTrue,
          reason: 'every source was asked and every source answered — this '
              'is the ONE shape in which silence is a real all-clear');
    });

    test('ZERO sources asked is NOT an all-clear', () {
      final axis = readAdvisoryAxis(const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 0,
      ));
      expect(axis.level, isNull, reason: 'an outage is NOT a hazard — the '
          'rung must not rise (no cry-wolf, Chair 2026-07-23)');
      expect(axis.completenessProven, isFalse,
          reason: 'nobody was asked, so we cannot claim the sky is quiet');
    });

    test('a result with NO provenance at all cannot claim completeness', () {
      final axis = readAdvisoryAxis(const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
      ));
      expect(axis.level, isNull);
      expect(axis.completenessProven, isFalse);
    });

    test('a covering publisher that ERRORED breaks the completeness claim',
        () {
      final axis = readAdvisoryAxis(const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [
          AdvisoryProviderError(
              source: AdvisorySource.jmaJapan, message: 'HTTP 503'),
        ],
        sourcesQueried: 1,
      ));
      expect(axis.level, isNull);
      expect(axis.completenessProven, isFalse);
    });

    test('NO result at all — we never looked — is not a proven clear', () {
      final axis = readAdvisoryAxis(null);
      expect(axis.level, isNull);
      expect(axis.completenessProven, isFalse,
          reason: 'before the first fetch returns we have not looked; the '
              'bootstrap state must not read as a measured all-clear');
    });
  });

  group('the level mapping is unchanged (no rung inflation)', () {
    test('an unknown-severity advisory is a LIVE warning we cannot grade', () {
      final axis = readAdvisoryAxis(AdvisoryAggregateResult(
        advisories: [_advisory(severity: AdvisorySeverity.unknown)],
        providerErrors: const [],
        sourcesQueried: 1,
      ));
      expect(axis.level, AdvisoryLevel.moderate,
          reason: 'it must not vanish from the drive brain');
    });

    test('graded severities map one-to-one', () {
      for (final (severity, expected) in [
        (AdvisorySeverity.minor, AdvisoryLevel.minor),
        (AdvisorySeverity.moderate, AdvisoryLevel.moderate),
        (AdvisorySeverity.severe, AdvisoryLevel.severe),
        (AdvisorySeverity.extreme, AdvisoryLevel.extreme),
      ]) {
        final axis = readAdvisoryAxis(AdvisoryAggregateResult(
          advisories: [_advisory(severity: severity)],
          providerErrors: const [],
          sourcesQueried: 1,
        ));
        expect(axis.level, expected, reason: 'severity $severity');
      }
    });

    test('the single MOST severe advisory wins across a mixed list', () {
      final axis = readAdvisoryAxis(AdvisoryAggregateResult(
        advisories: [
          _advisory(severity: AdvisorySeverity.minor),
          _advisory(severity: AdvisorySeverity.extreme),
          _advisory(severity: AdvisorySeverity.moderate),
        ],
        providerErrors: const [],
        sourcesQueried: 1,
      ));
      expect(axis.level, AdvisoryLevel.extreme);
    });

    test('an OUTAGE never raises the rung above a proven-clear lookup', () {
      final outage = readAdvisoryAxis(const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 0,
      ));
      final proven = readAdvisoryAxis(const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 2,
      ));
      expect(outage.level, proven.level,
          reason: 'the RUNG is identical — the countermeasure is to withhold '
              'the reassurance, never to manufacture a warning');
      expect(outage.completenessProven, isNot(proven.completenessProven),
          reason: '…and the HONESTY state is what differs');
    });
  });
}
