/// Pins the two advisory→drive-brain honesty rules in main.dart:
///
/// 1. `topAdvisoryLevel` — an `unknown`-severity advisory is a LIVE warning
///    we cannot grade; it must reach the drive brain as a moderate-equivalent
///    concern, never vanish as null (same deliberate pinning as
///    drive_situation_fusion's `advisoryLevelOf`).
/// 2. `retainAdvisoriesOnFailure` — asymmetric overwrite: a failed fetch
///    retains prior in-force hazards (until the publisher's declared expires
///    passes); the clear side is never retained.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show AdvisoryLevel;
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/main.dart'
    show retainAdvisoriesOnFailure, topAdvisoryLevel;

Advisory _advisory({
  AdvisorySeverity severity = AdvisorySeverity.severe,
  DateTime? expires,
}) {
  return Advisory(
    source: AdvisorySource.jmaJapan,
    eventClass: '大雪警報',
    severity: severity,
    certainty: AdvisoryCertainty.unknown,
    urgency: AdvisoryUrgency.unknown,
    areaDescription: '秋田中央',
    effective: DateTime.utc(2026, 1, 15, 4, 23),
    expires: expires,
    headline: '秋田県では、大雪に警戒してください。',
    description: '秋田県では、大雪に警戒してください。',
  );
}

AdvisoryAggregateResult _result(
  List<Advisory> advisories, {
  List<AdvisoryProviderError> errors = const [],
}) =>
    AdvisoryAggregateResult(advisories: advisories, providerErrors: errors);

const _jmaError = AdvisoryProviderError(
  source: AdvisorySource.jmaJapan,
  message: 'HTTP 503',
);

void main() {
  group('topAdvisoryLevel', () {
    test('null result maps to null (nothing in force)', () {
      expect(topAdvisoryLevel(null), isNull);
    });

    test('empty advisory list maps to null (nothing in force)', () {
      expect(topAdvisoryLevel(_result(const [])), isNull);
    });

    test(
        'a live unknown-severity advisory maps to moderate, NOT null — '
        'a warning we cannot grade must not vanish from the drive brain', () {
      final level = topAdvisoryLevel(
        _result([_advisory(severity: AdvisorySeverity.unknown)]),
      );
      expect(level, isNotNull);
      expect(level, AdvisoryLevel.moderate);
    });

    test('graded severities map one-to-one', () {
      for (final (severity, expected) in [
        (AdvisorySeverity.minor, AdvisoryLevel.minor),
        (AdvisorySeverity.moderate, AdvisoryLevel.moderate),
        (AdvisorySeverity.severe, AdvisoryLevel.severe),
        (AdvisorySeverity.extreme, AdvisoryLevel.extreme),
      ]) {
        expect(
          topAdvisoryLevel(_result([_advisory(severity: severity)])),
          expected,
          reason: 'severity $severity',
        );
      }
    });

    test('the single MOST severe advisory wins across a mixed list', () {
      final level = topAdvisoryLevel(_result([
        _advisory(severity: AdvisorySeverity.minor),
        _advisory(severity: AdvisorySeverity.extreme),
        _advisory(severity: AdvisorySeverity.unknown),
      ]));
      expect(level, AdvisoryLevel.extreme);
    });
  });

  group('retainAdvisoriesOnFailure', () {
    final now = DateTime.utc(2026, 1, 15, 12);
    final inForce = _advisory(expires: DateTime.utc(2026, 1, 15, 18));
    final expired = _advisory(expires: DateTime.utc(2026, 1, 15, 6));

    test('failed fetch retains a prior in-force hazard, with the errors', () {
      final applied = retainAdvisoriesOnFailure(
        prior: _result([inForce]),
        fresh: _result(const [], errors: const [_jmaError]),
        now: now,
      );
      expect(applied.retained, isTrue);
      expect(applied.result.advisories, [inForce]);
      // The failure stays visible alongside the retained hazard.
      expect(applied.result.providerErrors, const [_jmaError]);
    });

    test('a retained advisory past its publisher-declared expires drops', () {
      final applied = retainAdvisoriesOnFailure(
        prior: _result([expired]),
        fresh: _result(const [], errors: const [_jmaError]),
        now: now,
      );
      expect(applied.retained, isFalse);
      expect(applied.result.advisories, isEmpty);
      expect(applied.result.providerErrors, const [_jmaError]);
    });

    test('an advisory without a declared expires is not retained '
        '(in-force cannot be verified while the publisher is unreachable)',
        () {
      final applied = retainAdvisoriesOnFailure(
        prior: _result([_advisory(expires: null)]),
        fresh: _result(const [], errors: const [_jmaError]),
        now: now,
      );
      expect(applied.retained, isFalse);
      expect(applied.result.advisories, isEmpty);
    });

    test('the clear side is never retained: a genuine clear overwrites', () {
      final applied = retainAdvisoriesOnFailure(
        prior: _result([inForce]),
        fresh: _result(const []), // fetch succeeded, nothing in force
        now: now,
      );
      expect(applied.retained, isFalse);
      expect(applied.result.advisories, isEmpty);
    });

    test('a successful fetch with advisories always wins over the prior', () {
      final freshHazard = _advisory(severity: AdvisorySeverity.extreme);
      final applied = retainAdvisoriesOnFailure(
        prior: _result([inForce]),
        fresh: _result([freshHazard]),
        now: now,
      );
      expect(applied.retained, isFalse);
      expect(applied.result.advisories, [freshHazard]);
    });

    test('failed fetch with no prior passes through (nothing to retain)', () {
      final fresh = _result(const [], errors: const [_jmaError]);
      final applied =
          retainAdvisoriesOnFailure(prior: null, fresh: fresh, now: now);
      expect(applied.retained, isFalse);
      expect(applied.result, same(fresh));
    });
  });
}
