/// Pins the app-owned unknowns — the first-class rows the drive brain has no
/// channel for.
///
/// `compound_failure_advisor`'s `Unknown` enum covers position, visibility and
/// speed. It has NO member for "we could not read the advisory feed" and none
/// for "we could not read the weather observation", so those outages reach the
/// glance as silence. These app-owned rows are the countermeasure: the app
/// appends them to the same 「不明な点」 list, in the same
/// `<what happened> — <what we do not know>` convention, so the unknown is
/// stated rather than inferred from an absence.
///
/// An outage is an unknown, NOT a hazard: these rows never raise the caution
/// rung (Chair 2026-07-23, no cry-wolf). They withhold the reassurance.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/app_unknowns.dart';
import 'package:flutter/widgets.dart' show Locale;

void main() {
  group('which unknowns are in force', () {
    test('everything read and proven complete → no app-owned unknowns', () {
      expect(
        appUnknownsFor(
          advisoryCompletenessProven: true,
          measuredWatchFeed: MeasuredWatchFeed.live,
        ),
        isEmpty,
      );
    });

    test('an unproven advisory lookup raises its own row', () {
      expect(
        appUnknownsFor(
          advisoryCompletenessProven: false,
          measuredWatchFeed: MeasuredWatchFeed.live,
        ),
        [AppUnknown.advisoryLookupIncomplete],
      );
    });

    test('a LOST measured-weather feed is distinct from NEVER-READ', () {
      final lost = appUnknownsFor(
        advisoryCompletenessProven: true,
        measuredWatchFeed: MeasuredWatchFeed.lost,
      );
      final never = appUnknownsFor(
        advisoryCompletenessProven: true,
        measuredWatchFeed: MeasuredWatchFeed.notYetRead,
      );
      expect(lost, [AppUnknown.measuredWatchFeedLost]);
      expect(never, [AppUnknown.measuredWatchNotYetRead]);
      expect(lost, isNot(never),
          reason: 'a feed that FAILED and a feed not yet asked are different '
              'facts about the world; collapsing them is what let an outage '
              'reach the brain as "no hazard"');
    });

    test('both axes unknown raises both rows', () {
      expect(
        appUnknownsFor(
          advisoryCompletenessProven: false,
          measuredWatchFeed: MeasuredWatchFeed.lost,
        ),
        [
          AppUnknown.advisoryLookupIncomplete,
          AppUnknown.measuredWatchFeedLost,
        ],
      );
    });
  });

  group('the glance and the card say the SAME sentence', () {
    const ja = AppL10n(Locale('ja'));
    const en = AppL10n(Locale('en'));

    test('advisory row reuses the card string verbatim (ja + en)', () {
      expect(
        appUnknownLabel(AppUnknown.advisoryLookupIncomplete, ja),
        ja.advisoryLookupIncomplete,
        reason: 'the card at advisory_cards.dart and the glance row must not '
            'be allowed to drift into two different sentences about the same '
            'state',
      );
      expect(
        appUnknownLabel(AppUnknown.advisoryLookupIncomplete, en),
        en.advisoryLookupIncomplete,
      );
    });

    test('every app-owned row is localized and non-empty', () {
      for (final u in AppUnknown.values) {
        expect(appUnknownLabel(u, ja), isNotEmpty);
        expect(appUnknownLabel(u, en), isNotEmpty);
        expect(appUnknownLabel(u, ja), isNot(appUnknownLabel(u, en)),
            reason: '$u must actually be translated, not passed through');
      }
    });

    test('every row states what we do not know, and claims no hazard', () {
      for (final u in AppUnknown.values) {
        final line = appUnknownLabel(u, ja);
        expect(line, contains('不明'),
            reason: '$u must name the unknown: "$line"');
        for (final cryWolf in ['警戒', '危険です', '停車してください']) {
          expect(line, isNot(contains(cryWolf)),
              reason: '$u must not manufacture a warning from an outage');
        }
      }
    });
  });
}
