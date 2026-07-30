/// Pins the PROVENANCE of the thrown advisory path.
///
/// When `AdvisoryService.fetchAtPoint` throws, the app synthesizes a failed
/// aggregate result so retained hazards keep rendering under the honest
/// degraded banner. That synthetic result must state `sourcesQueried: 0` — the
/// throw fired before any provider answered, so ZERO sources were successfully
/// asked. Without it the result is read as a partial one and
/// `canAssertNoAdvisory` is left resting on the synthetic error entry alone.
///
/// This was UNPINNED: a mutant that dropped `sourcesQueried: 0` survived the
/// suite. The shape is now a named function so the call site carries no
/// untested literal.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/main.dart' show advisoryResultForThrownFetch;

void main() {
  test('a thrown fetch declares that ZERO sources were asked', () {
    final r = advisoryResultForThrownFetch(
      StateError('AdvisoryService.fetchAtPoint called before init()'),
    );

    expect(r.sourcesQueried, 0,
        reason: 'the throw fired before any provider answered');
    expect(r.isUnavailable, isTrue,
        reason: 'we did not look — she must be told the feed is down, not '
            'left to read silence as calm');
    expect(r.canAssertNoAdvisory, isFalse,
        reason: 'and the all-clear must be impossible on this path');
    expect(r.advisories, isEmpty);
  });

  test('the thrown result carries the error so the banner can name it', () {
    final r = advisoryResultForThrownFetch(Exception('boom'));
    expect(r.providerErrors, hasLength(1));
    expect(r.providerErrors.single.source, AdvisorySource.other);
    expect(r.providerErrors.single.message, contains('boom'));
  });

  test('provenance holds independently of the error entry', () {
    // The arithmetic must stand on its own: even if the synthetic error entry
    // were ever dropped, zero-sources-asked alone keeps the clear off screen.
    final r = advisoryResultForThrownFetch(Exception('x'));
    final withoutTheError = AdvisoryAggregateResult(
      advisories: r.advisories,
      providerErrors: const [],
      sourcesQueried: r.sourcesQueried,
    );
    expect(withoutTheError.canAssertNoAdvisory, isFalse);
    expect(withoutTheError.isUnavailable, isTrue);
  });
}
