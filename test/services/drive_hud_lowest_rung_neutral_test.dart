/// Design-Floor Refusal #1 (Chair, 2026-07-19): the lowest-rung HUD headline is
/// CHOICE-NEUTRAL honest information — it may NOT advocate GO (継続/走行/continue/
/// proceed/go/drive-on) and may NOT reassure (安全/安心/大丈夫/clear/OK/safe/fine).
///
/// PROVE-TO-FAIL: these assertions FAIL on the old code (`走行を継続` / `Continue`)
/// and PASS on the neutral wording. The rung fires ONLY on a measured, non-
/// elevated read (advisor score 0: position trusted+fresh, visibility measured &
/// clear); unknown/stale visibility floors to `heightenedCaution` in the
/// package (`_resolveVisibility` → concern 1), so a neutral non-elevation
/// statement is honest on every path that reaches this rung — and it must never
/// imply "measured and clear" as a safety claim.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';

void main() {
  const t = DriveHudLocalizer();

  // CJK forbidden substrings (plain contains is correct for these).
  const cjkAdvocateGo = <String>['継続', '走行'];
  const cjkReassure = <String>['安全', '安心', '大丈夫'];
  // Latin forbidden WORDS — matched at word boundaries so an innocent substring
  // (e.g. the "on" inside "cauti[on]") does not false-positive.
  const latinAdvocateGo = <String>['continue', 'proceed', 'go', 'drive'];
  const latinReassure = <String>['clear', 'ok', 'safe', 'fine'];

  bool hasWord(String haystack, String word) =>
      RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false)
          .hasMatch(haystack);

  group('lowest rung (continueDriving) headline is choice-neutral', () {
    test('ja headline is NOT the old advocate-GO wording', () {
      final ja = t.actionHeadline(DriveAction.continueDriving, 'ja');
      // Fails on old code which returned 「走行を継続」.
      expect(ja, isNot('走行を継続'),
          reason: 'lowest-rung ja headline must not advocate GO');
      for (final tok in cjkAdvocateGo) {
        expect(ja.contains(tok), isFalse,
            reason: 'ja headline "$ja" contains advocate-GO token "$tok"');
      }
      for (final tok in cjkReassure) {
        expect(ja.contains(tok), isFalse,
            reason: 'ja headline "$ja" contains reassurance token "$tok"');
      }
      // A ja headline may still embed latin (it does not here) — guard anyway.
      for (final tok in [...latinAdvocateGo, ...latinReassure]) {
        expect(hasWord(ja, tok), isFalse,
            reason: 'ja headline "$ja" contains latin token "$tok"');
      }
      expect(ja.trim(), isNotEmpty);
    });

    test('en headline is NOT the old advocate-GO wording', () {
      final en = t.actionHeadline(DriveAction.continueDriving, 'en');
      // Fails on old code which returned 'Continue'.
      expect(en, isNot('Continue'),
          reason: 'lowest-rung en headline must not advocate GO');
      for (final tok in latinAdvocateGo) {
        expect(hasWord(en, tok), isFalse,
            reason: 'en headline "$en" contains advocate-GO word "$tok"');
      }
      for (final tok in latinReassure) {
        expect(hasWord(en, tok), isFalse,
            reason: 'en headline "$en" contains reassurance word "$tok"');
      }
      for (final tok in [...cjkAdvocateGo, ...cjkReassure]) {
        expect(en.contains(tok), isFalse,
            reason: 'en headline "$en" contains cjk token "$tok"');
      }
      expect(en.trim(), isNotEmpty);
    });

    test('the two RAISED rungs are unchanged (regression guard)', () {
      // The neutralisation touches ONLY the lowest rung; the caution rungs still
      // name their posture.
      expect(t.actionHeadline(DriveAction.heightenedCaution, 'ja'), '注意して走行');
      expect(t.actionHeadline(DriveAction.heightenedCaution, 'en'),
          'Heightened caution');
      expect(t.actionHeadline(DriveAction.considerStopping, 'ja'), '停車の検討');
      expect(
          t.actionHeadline(DriveAction.considerStopping, 'en'), 'Consider stopping');
    });

    test('visual headline is parity with the voice channel silence', () {
      // The voice channel says nothing on this rung; the headline is its visual
      // parity — an honest absence, present but never an instruction/all-clear.
      expect(t.spokenGuidance(DriveAction.continueDriving, 'ja'), '');
      expect(t.spokenGuidance(DriveAction.continueDriving, 'en'), '');
    });
  });
}
