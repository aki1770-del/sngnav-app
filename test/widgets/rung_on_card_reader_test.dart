/// The rung reader reads the rung, and nothing else on the screen moves it.
///
/// WHY, written before the act (2026-09-15). The readers this replaces searched
/// the whole screen for rung words. On a screen whose banner says
/// 特段の注意なし and whose footer happens to quote 停車の検討, they answered
/// "considerStopping". See `support/rung_on_card.dart`.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import '../support/rung_on_card.dart';

Widget _card({String? headline, bool headlineInBanner = true, String? footer}) {
  final head = headline == null
      ? null
      : Text(key: kRungHeadlineKey, headline);
  return MaterialApp(
    home: Column(children: [
      if (head != null && headlineInBanner)
        Container(key: const Key('drive-hud-caution-banner'), child: head),
      if (head != null && !headlineInBanner) head,
      if (headline == null)
        const Text(key: kNoPositionLineKey, '（まだ現在地が届いていません）'),
      if (footer != null) Text(footer),
    ]),
  );
}

void main() {
  group('on a card drawn for the reader', () {
    testWidgets('a rung named elsewhere on the screen does not read as the rung',
        (tester) async {
      await tester.pumpWidget(_card(
          headline: '特段の注意なし（一部未確認）',
          footer: '視界の値がないときは停車の検討・注意して走行を表示します。'));
      expect(rungOnCard(), DriveAction.continueDriving);
    });

    testWidgets('each rung, in each language, reads as itself', (tester) async {
      for (final (words, rung) in const [
        ('停車の検討', DriveAction.considerStopping),
        ('Consider stopping', DriveAction.considerStopping),
        ('注意して走行', DriveAction.heightenedCaution),
        ('Heightened caution', DriveAction.heightenedCaution),
        ('特段の注意なし', DriveAction.continueDriving),
        ('No elevated caution (advisories unconfirmed)',
            DriveAction.continueDriving),
      ]) {
        await tester.pumpWidget(_card(headline: words));
        expect(rungOnCard(), rung, reason: words);
      }
    });

    testWidgets('no banner: no rung, and the no-position line is read',
        (tester) async {
      await tester.pumpWidget(_card(footer: '停車の検討'));
      expect(rungOnCard(), isNull);
      expect(noPositionLineOnCard(), isTrue);
    });

    testWidgets('a headline no rung produces fails instead of guessing',
        (tester) async {
      await tester.pumpWidget(_card(headline: '停車の検討してください'));
      expect(rungOnCard, throwsA(isA<TestFailure>()));
    });

    testWidgets('a headline outside the banner fails instead of reading',
        (tester) async {
      await tester.pumpWidget(_card(headline: '停車の検討', headlineInBanner: false));
      expect(rungOnCard, throwsA(isA<TestFailure>()));
    });
  });

  testWidgets('on the app: no rung before a share, the stop rung after the GPS '
      'is lost', (tester) async {
    await tester.pumpWidget(SngnavApp(
        locale: const Locale('ja'), actuators: FakeAlertActuators()));
    await tester.pump();
    await tester.pump();
    expect(rungOnCard(), isNull, reason: 'nothing shared yet');
    expect(noPositionLineOnCard(), isTrue,
        reason: 'the card says there is no position where the rung would be');

    final mock = find.byKey(const Key('use-mock-button'));
    await tester.ensureVisible(mock);
    await tester.tap(mock);
    await tester.pump();
    await tester.pump();
    expect(noPositionLineOnCard(), isFalse);
    expect(rungOnCard(), isNotNull, reason: 'a shared position gives a rung');

    final blackout = find.byKey(const Key('drive-hud-blackout-button'));
    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(blackout);
      await tester.tap(blackout);
      await tester.pump();
      await tester.pump();
    }
    expect(rungOnCard(), DriveAction.considerStopping,
        reason: 'three minutes without GPS raise the top rung');
  });
}
