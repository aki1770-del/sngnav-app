// AAE 2026-09-19 — the instrument that makes C3's "heard" and "felt"
// DECIDABLE in one short pass on a real phone.
//
// WHY IT EXISTS. C3 (seen · heard · felt) is the definition of the first
// build that reaches HER. `seen` was met on the Chair's phone 2026-09-17.
// `heard` and `felt` were met by nobody — and at 85617da (2026-09-16 00:04
// JST) the demo controls that could fire a cue moved to the development
// page, which `_developerPageOffered` gates on `!kReleaseMode` (main.dart).
// So the SIGNED 0.0.2+3 build had no release-reachable way for any person to
// make the app speak or buzz: the instrument left the shipping build 2 days
// 18 hours before that build was written (APK 2026-09-18 18:16 JST). This
// comment said "four days" until R115; the two timestamps are the measurement. Nobody skipped a step; the only surface that
// could answer the question was removed for a good reason and not replaced.
//
// WHAT THIS TEST CAN AND CANNOT DO — stated because the whole defect family
// here is a passing test being read as a met criterion:
//   CAN prove the app FIRES the real announce path (audio + haptic, real
//       severity, her locale) and that a three-valued answer is recorded
//       beside the platform's own claim.
//   CANNOT prove anyone heard or felt anything. No host can. C3 stays UNMET
//       until a person answers on a device, and this file never says
//       otherwise.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity;
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;

import 'package:sngnav_app/actuators/alert_actuators.dart'
    show hapticCueForCoreSeverity;
import 'package:sngnav_app/actuators/hardened_haptic_channel.dart'
    show waveformFor;

import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/drive_diary.dart';

import '../support/fake_alert_actuators.dart';

void main() {
  late Directory tmp;
  late DriveDiary diary;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('aae-cc-');
    diary = DriveDiary(file: File('${tmp.path}/diary.txt'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pumpApp(WidgetTester tester, FakeAlertActuators acts) async {
    await tester.pumpWidget(SngnavApp(
      locale: const Locale('ja'),
      actuators: acts,
      diary: diary,
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the check is reachable on HER page, not the developer page',
      (tester) async {
    await pumpApp(tester, FakeAlertActuators());
    await tester.scrollUntilVisible(
      find.byKey(const Key('channel-check-panel')),
      300,
    );
    expect(find.byKey(const Key('channel-check-panel')), findsOneWidget);
    // The honest bound rides the instrument, beside the button.
    expect(find.byKey(const Key('channel-check-bound')), findsOneWidget);
  });

  testWidgets('firing takes the REAL announce path — audio AND haptic',
      (tester) async {
    final acts = FakeAlertActuators();
    await pumpApp(tester, acts);
    await tester.scrollUntilVisible(
      find.byKey(const Key('channel-check-fire')),
      300,
    );
    await tester.tap(find.byKey(const Key('channel-check-fire')));
    await tester.pumpAndSettle();

    // Asserted on the LAST call, not the only one: the app may legitimately
    // announce other things while the page lives, and a `.single` here would
    // make this test fail for a reason that has nothing to do with the check.
    expect(acts.spoken, isNotEmpty, reason: 'the audio arm must fire');
    expect(acts.spoken.last.localeTag, 'ja-JP',
        reason: 'her tongue, not the build locale');
    expect(acts.spoken.last.text, contains('テスト'),
        reason: 'the cue must SAY it is a test, so a warning heard from the '
            'next room is never mistaken for a real hazard');
    expect(acts.haptics, isNotEmpty, reason: 'the tactile arm must fire');
    // The WEAKEST cue a real warning reaches her with: of every severity the
    // announcer delivers (warning and above), the one whose waveform is on
    // for the least time. Derived from the mapping and the waveforms, so it
    // follows them if either changes.
    int onMs(HapticCuePattern p) {
      final w = waveformFor(p);
      var t = 0;
      for (var i = 1; i < w.length; i += 2) {
        t += w[i];
      }
      return t;
    }

    final delivered = [
      for (final s in AlertSeverity.values)
        if (s.index >= AlertSeverity.warning.index) hapticCueForCoreSeverity(s),
    ];
    final weakest = delivered.reduce((a, b) => onMs(a) <= onMs(b) ? a : b);
    expect(acts.haptics.last, weakest,
        reason: 'the check must fire the weakest cue a real warning uses '
            '(${weakest.name}, ${onMs(weakest)} ms on). For a deaf or '
            'hard-of-hearing driver it is the only signal for most of her '
            'warnings, and a "felt it" on the strongest cue says nothing '
            'about it');
  });

  testWidgets('no answer is preselected: unanswered must never read as answered',
      (tester) async {
    await pumpApp(tester, FakeAlertActuators());
    await tester.scrollUntilVisible(
      find.byKey(const Key('channel-check-fire')),
      300,
    );
    await tester.tap(find.byKey(const Key('channel-check-fire')));
    await tester.pumpAndSettle();

    for (final p in DiaryPerception.values) {
      final chip = tester.widget<ChoiceChip>(
          find.byKey(Key('channel-check-heard-${p.token}')));
      expect(chip.selected, isFalse);
    }
    // Save stays disabled until BOTH questions are answered.
    final save =
        tester.widget<OutlinedButton>(find.byKey(const Key('channel-check-save')));
    expect(save.onPressed, isNull);
  });

  testWidgets('THE MEASUREMENT: the platform claim is recorded beside what a '
      'person perceived, so their disagreement survives', (tester) async {
    await pumpApp(tester, FakeAlertActuators());
    await tester.scrollUntilVisible(
      find.byKey(const Key('channel-check-fire')),
      300,
    );
    await tester.tap(find.byKey(const Key('channel-check-fire')));
    await tester.pumpAndSettle();

    // Heard yes, FELT NO — the Chair's own 2026-08-31 report ("buzz does not
    // work so far") while the app's fault chip stayed clear.
    await tester.tap(find.byKey(const Key('channel-check-heard-yes')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('channel-check-felt-no')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('channel-check-save')));
    await tester.pumpAndSettle();

    final text = diary.readAll();
    expect(text, contains('種別: 警報チャンネル確認'));
    expect(text, contains('heard=yes'));
    expect(text, contains('felt=no'));
    expect(text, contains('端末の申告:'));
    expect(text, contains('haptic-pattern=warning 2x200ms'),
        reason: 'the record names the cue the "felt" answer is about');
    expect(text, contains('haptic=accepted-by-platform'),
        reason: 'THE POINT. The platform said it delivered the cue and the '
            'person felt nothing. That contradiction is the finding, and it '
            'is now one shareable line instead of a lost conversation.');
  });

  testWidgets('わからない survives into the record and is not a pass',
      (tester) async {
    await pumpApp(tester, FakeAlertActuators());
    await tester.scrollUntilVisible(
      find.byKey(const Key('channel-check-fire')),
      300,
    );
    await tester.tap(find.byKey(const Key('channel-check-fire')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('channel-check-heard-unsure')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('channel-check-felt-unsure')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('channel-check-save')));
    await tester.pumpAndSettle();

    expect(diary.readAll(), contains('heard=unsure'));
    expect(diary.readAll(), contains('felt=unsure'));
    // C3 is met by an explicit yes and by nothing else.
    expect(DiaryPerception.unsure.isMet, isFalse);
    expect(DiaryPerception.notPerceived.isMet, isFalse);
    expect(DiaryPerception.perceived.isMet, isTrue);
  });

  testWidgets('with no diary the panel says so and fabricates no result',
      (tester) async {
    await tester.pumpWidget(SngnavApp(
      locale: const Locale('ja'),
      actuators: FakeAlertActuators(),
      // diary deliberately absent
    ));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('channel-check-fire')),
      300,
    );
    await tester.tap(find.byKey(const Key('channel-check-fire')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('channel-check-heard-yes')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('channel-check-felt-yes')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('channel-check-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('channel-check-save-message')), findsOneWidget);
    expect(find.textContaining('日記が使えない'), findsOneWidget);
  });
}
