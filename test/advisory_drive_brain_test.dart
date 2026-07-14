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
    show
        cullExpiredRetainedAdvisories,
        retainAdvisoriesOnFailure,
        topAdvisoryLevel;

Advisory _advisory({
  AdvisorySeverity severity = AdvisorySeverity.severe,
  DateTime? expires,
  AdvisorySource source = AdvisorySource.jmaJapan,
}) {
  return Advisory(
    source: source,
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

    test(
        'PARTIAL failure: fresh advisories from a surviving provider do NOT '
        'erase the errored provider\'s prior in-force hazard — it is retained '
        'and merged after the fresh ones', () {
      final freshNws = _advisory(
        source: AdvisorySource.nwsUnitedStates,
        severity: AdvisorySeverity.moderate,
        expires: DateTime.utc(2026, 1, 15, 20),
      );
      final applied = retainAdvisoriesOnFailure(
        prior: _result([inForce]), // jmaJapan, in force until 18:00
        fresh: _result([freshNws], errors: const [_jmaError]),
        now: now,
      );
      expect(applied.retained, isTrue);
      expect(applied.result.advisories, [freshNws, inForce]);
      expect(applied.result.providerErrors, const [_jmaError]);
    });

    test(
        'PARTIAL failure retains per provider: a provider that ANSWERED '
        '(even empty) is a genuine per-provider clear — only the errored '
        'provider\'s prior hazards are retained', () {
      final priorNws = _advisory(
        source: AdvisorySource.nwsUnitedStates,
        expires: DateTime.utc(2026, 1, 15, 20),
      );
      final freshJma = _advisory(expires: DateTime.utc(2026, 1, 15, 22));
      const nwsError = AdvisoryProviderError(
        source: AdvisorySource.nwsUnitedStates,
        message: 'HTTP 503',
      );
      final applied = retainAdvisoriesOnFailure(
        prior: _result([inForce, priorNws]),
        fresh: _result([freshJma], errors: const [nwsError]),
        now: now,
      );
      expect(applied.retained, isTrue);
      // JMA answered with a fresh hazard: its prior is NOT re-retained.
      // NWS errored: its prior in-force hazard survives.
      expect(applied.result.advisories, [freshJma, priorNws]);
    });

    test(
        'PARTIAL failure: an expired prior hazard from the errored provider '
        'is still dropped (the publisher\'s validity bound holds)', () {
      final freshNws = _advisory(
        source: AdvisorySource.nwsUnitedStates,
        expires: DateTime.utc(2026, 1, 15, 20),
      );
      final applied = retainAdvisoriesOnFailure(
        prior: _result([expired]), // jmaJapan, expired 06:00
        fresh: _result([freshNws], errors: const [_jmaError]),
        now: now,
      );
      expect(applied.retained, isFalse);
      expect(applied.result.advisories, [freshNws]);
    });
  });

  group('cullExpiredRetainedAdvisories (stationary expiry)', () {
    final expiresAt = DateTime.utc(2026, 1, 15, 18);
    final hazard = _advisory(expires: expiresAt);

    test('nothing expired → null (caller skips the rebuild)', () {
      final held = _result([hazard], errors: const [_jmaError]);
      expect(
        cullExpiredRetainedAdvisories(held, DateTime.utc(2026, 1, 15, 17)),
        isNull,
      );
    });

    test(
        'past the publisher\'s expires the retained hazard drops, leaving '
        'the empty+errors shape (renders degraded-unknown, never all-clear)',
        () {
      final held = _result([hazard], errors: const [_jmaError]);
      final culled =
          cullExpiredRetainedAdvisories(held, DateTime.utc(2026, 1, 15, 19));
      expect(culled, isNotNull);
      expect(culled!.advisories, isEmpty);
      expect(culled.providerErrors, const [_jmaError],
          reason: 'the provider errors survive the cull — the empty result '
              'must keep rendering as unverified absence, not calm');
    });

    test(
        'a null-expires advisory (fresh, from a partial retention) is NEVER '
        'culled — culling it would erase a live warning', () {
      final freshNoExpires = _advisory(
        source: AdvisorySource.nwsUnitedStates,
        expires: null,
      );
      final held = _result([freshNoExpires, hazard], errors: const [_jmaError]);
      final culled =
          cullExpiredRetainedAdvisories(held, DateTime.utc(2026, 1, 15, 19));
      expect(culled, isNotNull);
      expect(culled!.advisories, [freshNoExpires]);
    });
  });
}
