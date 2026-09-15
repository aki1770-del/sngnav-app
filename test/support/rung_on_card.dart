/// The rung the live-drive card shows, read from the rung's own widget.
///
/// WHY (2026-09-15). Seven test files decided the rung by searching the whole
/// screen for any rung's words, so any other text that named a rung read as
/// that rung. A draft footer that quoted 停車の検討 once made ten tests in four
/// files read the top rung for a driver who had none, and a footer naming no
/// rung is only a rule for that one footer.
///
/// This reads one widget: the caution banner's headline
/// (`Key('drive-hud-rung')`, inside `Key('drive-hud-caution-banner')`), and
/// maps its words back to a [DriveAction] through the app's own
/// [DriveHudLocalizer], in either language and with every scoping the lowest
/// rung can carry. It does not guess: a headline no rung produces, a headline
/// outside the banner, or more than one headline fails the test.
///
/// With no banner, the card shows its no-position line in the rung's place
/// (`Key('drive-hud-no-position')`); [noPositionLineOnCard] reads that.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';

const Key kRungHeadlineKey = Key('drive-hud-rung');
const Key kNoPositionLineKey = Key('drive-hud-no-position');
const Key _bannerKey = Key('drive-hud-caution-banner');

/// The rung on the card, or null when the card shows no rung.
DriveAction? rungOnCard() {
  final headline = find.byKey(kRungHeadlineKey);
  final found = headline.evaluate().toList();
  if (found.isEmpty) return null;
  if (found.length > 1) {
    throw TestFailure(
        '${found.length} rung headlines on the screen; the card has one');
  }
  if (find
      .descendant(of: find.byKey(_bannerKey), matching: headline)
      .evaluate()
      .isEmpty) {
    throw TestFailure('the rung headline is not inside the caution banner');
  }
  final words = (found.single.widget as Text).data;
  const text = DriveHudLocalizer();
  for (final lang in const ['ja', 'en']) {
    for (final action in DriveAction.values) {
      for (final advisory in const [false, true]) {
        for (final measured in const [false, true]) {
          for (final calm in const [false, true]) {
            final produced = text.actionHeadline(action, lang,
                advisoryUnconfirmed: advisory,
                measuredUnconfirmed: measured,
                calmNoteInForce: calm);
            if (words == produced) return action;
          }
        }
      }
    }
  }
  throw TestFailure(
      'the rung headline 「$words」 is not a headline any rung produces');
}

/// Whether the card shows its no-position line where the rung would be.
bool noPositionLineOnCard() =>
    find.byKey(kNoPositionLineKey).evaluate().isNotEmpty;
