/// A WARNING from a dead source is not a live warning.
///
/// `condition_aggregator` had already closed the SILENCE direction — an empty
/// read from a document that stopped being written is not an all-clear, "the
/// same gap wearing the shape of an answer" (advisory_aggregator.dart:113).
/// The MIRROR was open, and these tests pin it shut: a warning from that same
/// dead source is not a live warning — it is a corpse wearing the shape of an
/// alarm.
///
/// ## The defect, measured live rather than imagined
///
/// 2026-08-24, real feed, Akita (39.72, 140.10), through the app's own
/// `buildJmaAdvisoryProvider` + `AdvisoryAggregator`:
///
///     advisories=1 providerErrors=0 sourcesQueried=1
///     canAssertNoAdvisory=false hasStaleSource=true staleSources=1
///     STALE age=2127h (88 d) "JMA warning document for 050000 last written
///                             88 d ago; exceeds the 168 h threshold"
///     ADVISORY eventClass=雷注意報 severity=moderate expires=null
///       headline=「秋田県では、２８日昼過ぎから２８日夜のはじめ頃まで
///                 急な強い雨や落雷に注意してください。」
///     AXIS level=AdvisoryLevel.moderate  completenessProven=false
///
/// The fetch SUCCEEDED. That is why the existing retention loom
/// (`_advisoryInForce` / `retainAdvisoriesOnFailure`, main.dart:187) never
/// engaged — it bounds how long WE keep a prior advisory when a fetch FAILS,
/// and nothing failed. Nothing bounded the age of the PUBLISHER'S DOCUMENT
/// against the advisories it was still serving.
///
/// And the advisory's own headline names a validity window that closed on
/// 2026-05-28, three months before the read. `expires` is null — the JMA
/// mapper emits null as its only value — so no publisher bound could retire
/// it either.
///
/// ## Why it reaches HER EARS, which is what makes it a safety defect
///
/// Measured against `compound_failure_advisor` on 2026-08-24, trusted
/// position + clear fresh visibility (1500 m):
///
///     advisorySeverity: null      -> continueDriving,    reasons={}
///     advisorySeverity: moderate  -> heightenedCaution,  reasons={moderateAdvisory}
///     advisorySeverity: extreme   -> considerStopping,   reasons={severeAdvisory}
///
/// A RISING rung fires `_announcer.announce` — audio AND haptic
/// (main.dart:1070-1071). So the 88-day-dead 雷注意報 moves a calm drive to
/// heightened caution and SPEAKS. The eyes-off channels — the ones she has in
/// a whiteout, the ones this seat exists to protect — were being driven by a
/// document three months in its grave.
///
/// ## Why suppressing is not the OTHER error
///
/// A false all-clear is ranked worse than a false alarm, so dropping a level
/// has to be shown safe. It is, structurally: `staleSources` non-empty already
/// forces `canAssertNoAdvisory` false (advisory_aggregator.dart:137), so
/// `completenessProven` is false on this exact path and the reassurance stays
/// withheld. The state moves "fabricated alarm + unknown" -> "unknown", never
/// to "clear". Every test below asserts BOTH halves, so a future change that
/// bought silence by fabricating a clear cannot pass.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show AdvisoryLevel;
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/advisory_axis.dart';
import 'package:sngnav_app/services/app_unknowns.dart';

Advisory _adv({
  required AdvisorySource source,
  AdvisorySeverity severity = AdvisorySeverity.moderate,
  String eventClass = '雷注意報',
}) =>
    Advisory(
      source: source,
      eventClass: eventClass,
      severity: severity,
      certainty: AdvisoryCertainty.unknown,
      urgency: AdvisoryUrgency.unknown,
      areaDescription: '秋田県',
      effective: DateTime.utc(2026, 5, 27, 21, 11),
      expires: null,
      headline: '秋田県では、２８日昼過ぎから２８日夜のはじめ頃まで'
          '急な強い雨や落雷に注意してください。',
      description: '秋田県では、２８日昼過ぎから２８日夜のはじめ頃まで'
          '急な強い雨や落雷に注意してください。',
    );

AdvisoryFeedStaleness _stale(AdvisorySource source, {int days = 88}) =>
    AdvisoryFeedStaleness(
      source: source,
      documentTime: DateTime.utc(2026, 5, 27, 21, 11),
      age: Duration(days: days),
      detail: 'JMA warning document for 050000 last written $days d ago',
    );

void main() {
  group('a stale source does not raise the eyes-off rung', () {
    test('THE DEFECT: the real 88-day 雷注意報 must not set the level', () {
      final axis = readAdvisoryAxis(AdvisoryAggregateResult(
        advisories: [_adv(source: AdvisorySource.jmaJapan)],
        providerErrors: const [],
        sourcesQueried: 1,
        staleSources: [_stale(AdvisorySource.jmaJapan)],
      ));

      expect(axis.level, isNull,
          reason: 'a 3-month-dead document must not move the advisor from '
              'continueDriving to heightenedCaution and SPEAK');

      // The other half, asserted in the same breath: we did not buy the
      // silence by fabricating a clear.
      expect(axis.completenessProven, isFalse,
          reason: 'a stale source can never prove the sky is quiet');
      expect(
        appUnknownsFor(
          advisoryCompletenessProven: axis.completenessProven,
          measuredWatchFeed: MeasuredWatchFeed.live,
        ),
        contains(AppUnknown.advisoryLookupIncomplete),
        reason: 'she is still TOLD we could not assess — the reassurance is '
            'withheld, not replaced by a false all-clear',
      );
    });

    test('the EXTREME case: a stale 大雪警報 must not reach considerStopping',
        () {
      final axis = readAdvisoryAxis(AdvisoryAggregateResult(
        advisories: [
          _adv(
            source: AdvisorySource.jmaJapan,
            severity: AdvisorySeverity.extreme,
            eventClass: '大雪警報',
          ),
        ],
        providerErrors: const [],
        sourcesQueried: 1,
        staleSources: [_stale(AdvisorySource.jmaJapan)],
      ));
      expect(axis.level, isNull,
          reason: 'extreme is the severity that raises the action to '
              'considerStopping — telling her to pull over on a clear road '
              'because of a document from May is the sharpest form of this '
              'defect, and the one winter will actually produce');
      expect(axis.completenessProven, isFalse);
    });
  });

  group('NEGATIVE CONTROLS — the axis still works', () {
    test('a LIVE source with the SAME advisory DOES set the level', () {
      final axis = readAdvisoryAxis(AdvisoryAggregateResult(
        advisories: [_adv(source: AdvisorySource.jmaJapan)],
        providerErrors: const [],
        sourcesQueried: 1,
        // no staleSources — the ONLY difference from the defect case above
      ));
      expect(axis.level, AdvisoryLevel.moderate,
          reason: 'if this ever goes null the fix has stopped being a '
              'staleness rule and has silently disabled the advisory axis');
      expect(axis.completenessProven, isTrue);
    });

    test('a live SEVERE advisory still reaches the brain', () {
      final axis = readAdvisoryAxis(AdvisoryAggregateResult(
        advisories: [
          _adv(
            source: AdvisorySource.jmaJapan,
            severity: AdvisorySeverity.severe,
            eventClass: '大雪警報',
          ),
        ],
        providerErrors: const [],
        sourcesQueried: 1,
      ));
      expect(axis.level, AdvisoryLevel.severe);
    });

    test('PER-SOURCE, not blanket: a live NWS advisory survives a stale JMA',
        () {
      final axis = readAdvisoryAxis(AdvisoryAggregateResult(
        advisories: [
          _adv(source: AdvisorySource.jmaJapan), // stale -> dropped
          _adv(
            source: AdvisorySource.nwsUnitedStates,
            severity: AdvisorySeverity.severe,
          ), // live -> must survive
        ],
        providerErrors: const [],
        sourcesQueried: 2,
        staleSources: [_stale(AdvisorySource.jmaJapan)],
      ));
      expect(axis.level, AdvisoryLevel.severe,
          reason: 'suppressing every publisher because ONE went quiet would '
              'be its own false silence');
      expect(axis.completenessProven, isFalse,
          reason: 'one stale source still breaks the completeness claim');
    });

    test('the stale-source rule does not disturb the graded-unknown pin', () {
      final axis = readAdvisoryAxis(AdvisoryAggregateResult(
        advisories: [
          _adv(
            source: AdvisorySource.nwsUnitedStates,
            severity: AdvisorySeverity.unknown,
          ),
        ],
        providerErrors: const [],
        sourcesQueried: 1,
        staleSources: [_stale(AdvisorySource.jmaJapan)],
      ));
      expect(axis.level, AdvisoryLevel.moderate,
          reason: 'an ungradeable but LIVE warning is still a publisher '
              'statement that something is in force (advisory_axis.dart '
              'graded-unknown pin) — the stale filter must not eat it');
    });
  });
}
