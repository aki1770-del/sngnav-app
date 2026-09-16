/// Which advisories are the CHANNEL reporting on itself, rather than weather.
///
/// ## Why this file exists, and why it is a SET and never one constant
///
/// `condition_aggregator_jma` emits meta-advisories that are not weather: the
/// document is old, its path may have been retired, a containing prefecture
/// could not be read, the point is outside the catalogue. Through 0.6.0 there
/// was effectively one of these — `kJmaStaleFeedEventClass`, 気象情報の更新停止 —
/// and matching that one constant was the whole job.
///
/// **0.7.0 moved the boundary.** Past `pathRetirementThreshold` the adapter
/// stops saying "the data is old" and says "this path may no longer be served",
/// under a DIFFERENT identity: `kJmaPathRetirementEventClass`. The package is
/// explicit about what that does to a consumer who did not follow:
///
/// > A consumer that matched only `kJmaStaleFeedEventClass` silently stopped
/// > seeing feed-health signals for exactly the documents most likely to be
/// > dangerous — the very oldest.
///
/// ⚑ **In THIS app it is worse than "for the oldest documents". It is for all
/// of them.** The integrator sets `staleFeedThreshold` to 7 days
/// (`jma_advisory_provider_factory.dart`) and 0.7.0's
/// `kJmaDefaultPathRetirementThreshold` is also 7 days. Every read old enough
/// to be flagged at all is therefore old enough to be diagnosed as a
/// retirement, so **`kJmaStaleFeedEventClass` is unreachable in this app's
/// configuration** and a match on it alone would see nothing, ever, while every
/// test stayed green. Measured, not reasoned about: see
/// `test/services/jma_feed_health_set_test.dart`, which is RED when the
/// single-constant match is used and green on the set.
///
/// That is the failure shape this app exists to refuse. A silence she cannot
/// see is worse than an alarm she can argue with: at ten metres' visibility she
/// cannot go and check, so a feed-health signal that stops arriving takes with
/// it the only thing telling her the road ahead is unmeasured.
library;

import 'package:condition_aggregator/condition_aggregator.dart' show Advisory;
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart'
    show kJmaFeedHealthEventClasses;

/// True when [advisory] is the feed reporting on ITSELF, not on the weather.
///
/// Keyed on the package's exported SET so a new member added by a future
/// adapter version is picked up here without an edit. The members are pinned
/// against spelled-out literals in `jma_feed_health_set_test.dart` instead, so
/// a rename cannot pass silently either.
bool isJmaFeedHealthAdvisory(Advisory advisory) =>
    kJmaFeedHealthEventClasses.contains(advisory.eventClass);

/// Every feed-health notice in [advisories]. Empty is a real answer — it means
/// the channel raised nothing, NOT that nothing was asked.
Iterable<Advisory> jmaFeedHealthNotices(Iterable<Advisory> advisories) =>
    advisories.where(isJmaFeedHealthAdvisory);

/// The advisories that are actual weather — what she would call a warning.
Iterable<Advisory> weatherAdvisoriesOnly(Iterable<Advisory> advisories) =>
    advisories.where((a) => !isJmaFeedHealthAdvisory(a));
