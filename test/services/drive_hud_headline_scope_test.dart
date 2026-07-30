/// Pins the SCOPING of the lowest-rung reassurance headline.
///
/// 「特段の注意なし」 is a claim about the WHOLE picture. When an input could
/// not be confirmed — the advisory lookup cannot prove it was complete, or the
/// measured-weather feed could not be read — the app has not measured the
/// whole picture and must not print the unscoped global claim.
///
/// The countermeasure is to WITHHOLD THE REASSURANCE, never to manufacture a
/// warning: the rung is untouched (an outage is an unknown, not a hazard —
/// raising it is the cry-wolf the Chair ruled against on 2026-07-23). Only the
/// lowest rung is scoped, because only the lowest rung REASSURES; 注意して走行
/// and 停車の検討 assert nothing that an unknown could falsify.
///
/// The same wording contradiction is what a firing calm chip creates: the
/// sub-zero frozen-surface chip (Chair ruling 2026-07-23 — a calm glance chip
/// that deliberately does NOT raise the caution rung, under a named cry-wolf
/// contract) renders directly ABOVE this banner. A chip saying 路面凍結のおそれ
/// beside an unscoped 「特段の注意なし」 is a glance-level contradiction. The
/// code is correct and stays correct; the HEADLINE is what needed scoping.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';

void main() {
  const t = DriveHudLocalizer();

  group('the unscoped claim survives when everything WAS measured', () {
    test('ja/en lowest rung unchanged with nothing withheld', () {
      expect(t.actionHeadline(DriveAction.continueDriving, 'ja'), '特段の注意なし');
      expect(t.actionHeadline(DriveAction.continueDriving, 'en'),
          'No elevated caution');
    });

    test('explicitly-confirmed inputs render the same bare claim', () {
      expect(
        t.actionHeadline(DriveAction.continueDriving, 'ja',
            advisoryUnconfirmed: false,
            measuredUnconfirmed: false,
            calmNoteInForce: false),
        '特段の注意なし',
      );
    });
  });

  group('an unconfirmed input scopes the claim', () {
    test('advisory lookup unproven names the advisory axis', () {
      final ja = t.actionHeadline(DriveAction.continueDriving, 'ja',
          advisoryUnconfirmed: true);
      expect(ja, isNot('特段の注意なし'),
          reason: 'the unscoped global claim must not survive');
      expect(ja, contains('特段の注意なし'), reason: 'the honest STATE is kept');
      expect(ja, contains('警報・注意報'), reason: 'it names WHICH axis is unconfirmed');
      expect(ja, contains('未確認'));
      final en = t.actionHeadline(DriveAction.continueDriving, 'en',
          advisoryUnconfirmed: true);
      expect(en, isNot('No elevated caution'));
      expect(en.toLowerCase(), contains('unconfirmed'));
    });

    test('measured-weather feed unread names the observation axis', () {
      final ja = t.actionHeadline(DriveAction.continueDriving, 'ja',
          measuredUnconfirmed: true);
      expect(ja, isNot('特段の注意なし'));
      expect(ja, contains('気象観測'));
      expect(ja, contains('未確認'));
    });

    test('both unconfirmed collapses to a short honest qualifier', () {
      final ja = t.actionHeadline(DriveAction.continueDriving, 'ja',
          advisoryUnconfirmed: true, measuredUnconfirmed: true);
      expect(ja, isNot('特段の注意なし'));
      expect(ja, contains('未確認'));
    });

    test('a scoped claim never becomes a WARNING (no cry-wolf)', () {
      for (final ja in [
        t.actionHeadline(DriveAction.continueDriving, 'ja',
            advisoryUnconfirmed: true),
        t.actionHeadline(DriveAction.continueDriving, 'ja',
            measuredUnconfirmed: true),
        t.actionHeadline(DriveAction.continueDriving, 'ja',
            advisoryUnconfirmed: true, measuredUnconfirmed: true),
      ]) {
        expect(ja, isNot(contains('注意して走行')));
        expect(ja, isNot(contains('停車')));
        expect(ja, isNot(contains('危険')));
      }
    });
  });

  group('a firing calm chip must not sit beside an unscoped all-clear', () {
    test('calm note in force qualifies the headline', () {
      final ja = t.actionHeadline(DriveAction.continueDriving, 'ja',
          calmNoteInForce: true);
      expect(ja, isNot('特段の注意なし'));
      expect(ja, contains('特段の注意なし'));
      expect(ja, contains('下記'), reason: 'it points HER at the chip below');
    });

    test('an UNCONFIRMED input outranks a confirmed calm note', () {
      final ja = t.actionHeadline(DriveAction.continueDriving, 'ja',
          advisoryUnconfirmed: true, calmNoteInForce: true);
      expect(ja, contains('警報・注意報'),
          reason: 'a thing we could not look at outranks a note we DID look '
              'at and deliberately chose not to escalate — the note stays '
              'fully visible in its own chip row');
    });
  });

  group('only the reassurance is scoped', () {
    test('higher rungs are untouched by every flag', () {
      for (final action in [
        DriveAction.heightenedCaution,
        DriveAction.considerStopping,
      ]) {
        expect(
          t.actionHeadline(action, 'ja',
              advisoryUnconfirmed: true,
              measuredUnconfirmed: true,
              calmNoteInForce: true),
          t.actionHeadline(action, 'ja'),
          reason: '$action asserts nothing an unknown could falsify',
        );
      }
      expect(t.actionHeadline(DriveAction.heightenedCaution, 'ja'), '注意して走行');
      expect(t.actionHeadline(DriveAction.considerStopping, 'ja'), '停車の検討');
    });
  });

  group('glance budget', () {
    test('every scoped headline stays short enough to read at a glance', () {
      for (final ja in [
        t.actionHeadline(DriveAction.continueDriving, 'ja',
            advisoryUnconfirmed: true),
        t.actionHeadline(DriveAction.continueDriving, 'ja',
            measuredUnconfirmed: true),
        t.actionHeadline(DriveAction.continueDriving, 'ja',
            advisoryUnconfirmed: true, measuredUnconfirmed: true),
        t.actionHeadline(DriveAction.continueDriving, 'ja',
            calmNoteInForce: true),
      ]) {
        expect(ja.length, lessThanOrEqualTo(20),
            reason: 'a headline she reads in a glance, not a sentence: "$ja"');
      }
    });
  });
}
