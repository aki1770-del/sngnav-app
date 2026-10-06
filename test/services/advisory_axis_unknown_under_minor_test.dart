/// A warning whose level could not be read must not vanish behind a notice.
///
/// Why, written before the act (2026-10-05). An advisory whose severity is
/// `unknown` is in force: condition_aggregator 0.0.11 gives `unknown` only to
/// a real, constructed advisory whose level token was missing or not
/// recognised, and condition_aggregator_jma 0.7.1 gives it to any warning
/// whose name does not end in 特別警報, 危険警報, 警報 or 注意報 (a new class,
/// as 危険警報 once was). The app maps it to moderate, never to null
/// (advisory_axis.dart, the `unknown` arm), and a test pins that for an
/// `unknown` advisory on its own.
///
/// But the app picks the single most severe advisory by
/// `AdvisorySeverity.index`, and `unknown` is declared first, index 0, below
/// `minor`. condition_aggregator_jma 0.7.1 puts its own `minor` notices in the
/// same list as the warnings: a read it could not complete, a short-time tier
/// it could not open, a point it does not cover, a feed it has retired. So when
/// one of those is in force beside a warning whose level could not be read,
/// the notice wins, the axis reads `minor`, and the warning is gone from the
/// rung. driving_weather already ranks the other way, for this reason:
/// `unknown` above `minor` and `moderate`, below `severe` and `extreme`.
///
/// FAULT (red on main 989ec9d): an `unknown` warning beside a `minor` notice,
/// in either order. CONTROLS (green on main, must stay green): each alone, and
/// beside a graded moderate, severe or extreme advisory.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/advisory_axis.dart';

/// A JMA warning whose name carries none of the four graded suffixes.
Advisory _ungradable() => Advisory(
  source: AdvisorySource.jmaJapan,
  eventClass: '大雪危険情報',
  severity: AdvisorySeverity.unknown,
  certainty: AdvisoryCertainty.unknown,
  urgency: AdvisoryUrgency.unknown,
  areaDescription: '秋田中央',
  effective: DateTime.utc(2026, 1, 15, 4, 23),
  expires: null,
  headline: '秋田県では、大雪に警戒してください。',
  description: '秋田県では、大雪に警戒してください。',
);

/// A JMA notice of the kind condition_aggregator_jma 0.7.1 emits at `minor`.
Advisory _notice() => Advisory(
  source: AdvisorySource.jmaJapan,
  eventClass: '短時間情報 取得できず',
  severity: AdvisorySeverity.minor,
  certainty: AdvisoryCertainty.unknown,
  urgency: AdvisoryUrgency.unknown,
  areaDescription: '秋田中央',
  effective: DateTime.utc(2026, 1, 15, 4, 23),
  expires: null,
  headline: '短時間の情報を取得できませんでした。',
  description: '短時間の情報を取得できませんでした。',
);

Advisory _graded(AdvisorySeverity s) => Advisory(
  source: AdvisorySource.jmaJapan,
  eventClass: '大雪注意報',
  severity: s,
  certainty: AdvisoryCertainty.unknown,
  urgency: AdvisoryUrgency.unknown,
  areaDescription: '秋田中央',
  effective: DateTime.utc(2026, 1, 15, 4, 23),
  expires: null,
  headline: '大雪',
  description: '大雪',
);

AdvisoryLevel? _level(List<Advisory> advisories) => readAdvisoryAxis(
  AdvisoryAggregateResult(
    advisories: advisories,
    providerErrors: const [],
    sourcesQueried: 1,
  ),
).level;

/// The rung the drive brain gives on a trusted, exact fix with a clear,
/// measured visibility: the advisory axis alone.
DriveAction _rung(AdvisoryLevel? level) => adviseInDrive(
  DriveSituation(
    positionTrust: PositionTrust.trusted,
    confidenceRadiusMeters: 10,
    secondsSinceTrustedFix: 0,
    hasPosition: true,
    visibilityMeters: 20000,
    visibilityAgeSeconds: 10,
    advisorySeverity: level,
    speedMetersPerSecond: null,
  ),
).action;

void main() {
  group('FAULT: a warning whose level could not be read, beside a notice', () {
    for (final (name, list) in [
      ('warning first', [_ungradable(), _notice()]),
      ('notice first', [_notice(), _ungradable()]),
    ]) {
      test('$name: the axis reads moderate, not minor', () {
        expect(
          _level(list),
          AdvisoryLevel.moderate,
          reason:
              'a warning is in force; a notice beside it must not '
              'take its place',
        );
        expect(
          _rung(_level(list)),
          DriveAction.heightenedCaution,
          reason: 'the rung the warning alone gives',
        );
      });
    }
  });

  group('CONTROLS', () {
    test('each alone', () {
      expect(_level([_ungradable()]), AdvisoryLevel.moderate);
      expect(_level([_notice()]), AdvisoryLevel.minor);
      expect(
        _rung(_level([_notice()])),
        DriveAction.continueDriving,
        reason: 'a notice alone does not raise the rung',
      );
    });

    test('beside a graded advisory, the graded one decides when it is at '
        'least moderate', () {
      for (final (s, expected) in [
        (AdvisorySeverity.moderate, AdvisoryLevel.moderate),
        (AdvisorySeverity.severe, AdvisoryLevel.severe),
        (AdvisorySeverity.extreme, AdvisoryLevel.extreme),
      ]) {
        expect(_level([_ungradable(), _graded(s)]), expected, reason: '$s');
        expect(
          _level([_graded(s), _ungradable(), _notice()]),
          expected,
          reason: '$s with a notice',
        );
      }
    });
  });
}
