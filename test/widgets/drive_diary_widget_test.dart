// Ring-2 運転日記 — the diary card wired end-to-end in the widget tree.
//
// A recording fake DiaryShareSink is injected (SngnavApp.diaryShareSink), so
// the platform share channel is NEVER touched in the test binding: the test
// drives the real form (chips + fields + save), then taps the real share
// button and asserts the REAL payload the production composer produced.
//
// HONESTY (OPS-066 / AAE env-bound): this verifies the WIDGET TREE and the
// payload handed to the sink. It does NOT verify the OS share sheet — there
// is no Android device/emulator in this env. On-device observation is
// DEFERRED (docs/on_device_verify_checklist.md lane).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/build_info.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/drive_diary.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sngnav_drive_diary_widget');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  DriveDiary makeDiary() =>
      DriveDiary(file: File('${tmp.path}/drive_diary.txt'));

  Future<void> pumpAndReveal(
    WidgetTester tester, {
    DriveDiary? diary,
    DiaryShareSink? sink,
    Locale locale = const Locale('ja'),
  }) async {
    await tester.pumpWidget(SngnavApp(
      locale: locale,
      diary: diary,
      diaryShareSink: sink,
    ));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('diary-write-button')));
    await tester.pump();
  }

  testWidgets('write flow: chips + her words -> saved to the local file; '
      'the ja saved line names where the entry went', (tester) async {
    final diary = makeDiary();
    await pumpAndReveal(tester, diary: diary, sink: (_) async {});

    await tester.tap(find.byKey(const Key('diary-write-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('diary-road-ice')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('diary-advisory-fired-helpful')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('diary-area-field')), '横手市郊外');
    await tester.enterText(
        find.byKey(const Key('diary-note-field')), '橋の上で警告が鳴った。');
    await tester.tap(find.byKey(const Key('diary-save-button')));
    await tester.pumpAndSettle();

    // The entry persisted with the chosen chips + her words verbatim.
    final text = diary.readAll();
    expect(text, contains('路面: 凍結・アイスバーン (ice)'));
    expect(text, contains('警告: 警告あり・役立った (fired-helpful)'));
    expect(text, contains('地域: 横手市郊外'));
    expect(text, contains('メモ: 橋の上で警告が鳴った。'));

    // The confirmation names WHERE the entry went (consent transparency).
    expect(find.text('保存しました（この端末の中だけに記録されます）'), findsOneWidget);
  });

  testWidgets('cancel records NOTHING — the diary is hers to withhold',
      (tester) async {
    final diary = makeDiary();
    await pumpAndReveal(tester, diary: diary, sink: (_) async {});

    await tester.tap(find.byKey(const Key('diary-write-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('diary-note-field')), '書きかけ');
    await tester.tap(find.byKey(const Key('diary-cancel-button')));
    await tester.pumpAndSettle();

    expect(diary.readAll(), isEmpty);
    expect(diary.hasEntries(), isFalse);
  });

  testWidgets('double-tap save: exactly ONE entry recorded, exactly one pop '
      '(the home route survives — no black screen)', (tester) async {
    final diary = makeDiary();
    await pumpAndReveal(tester, diary: diary, sink: (_) async {});

    await tester.tap(find.byKey(const Key('diary-write-button')));
    await tester.pumpAndSettle();

    // Two taps land before any frame is pumped — the near-simultaneous
    // double-pointer case the _popped guard exists for.
    await tester.tap(find.byKey(const Key('diary-save-button')));
    await tester.tap(find.byKey(const Key('diary-save-button')));
    await tester.pumpAndSettle();

    expect(diary.entryCount(), 1,
        reason: 'a double tap must not forge a second entry');
    expect(find.byKey(const Key('diary-write-button')), findsOneWidget,
        reason: 'the HomePage route must survive (no double pop)');
  });

  testWidgets('tap 日記を共有 -> the sink receives header + the saved entry, '
      'and NO position state', (tester) async {
    final diary = makeDiary();
    diary.record(
      road: DiaryRoadCondition.whiteout,
      advisory: DiaryAdvisoryExperience.firedNotHelpful,
      area: '湯沢',
    );

    final captured = <String>[];
    await pumpAndReveal(tester, diary: diary, sink: (payload) async {
      captured.add(payload);
    });

    await tester.tap(find.byKey(const Key('diary-share-button')));
    await tester.pump();

    expect(captured, hasLength(1),
        reason: 'one tap must fire exactly one share');
    final payload = captured.single;
    expect(payload, contains('sngnav-app $appVersion'));
    expect(payload, contains(kDiaryEntryMarker));
    expect(payload, contains('(whiteout)'));
    expect(payload, contains('地域: 湯沢'));
    // Consent floor: the akitaStation mock coordinates (akita_map.dart)
    // must never ride along — the payload is strictly header + diary.
    expect(payload, isNot(contains('39.7167')));
    expect(payload, isNot(contains('140.0983')));
  });

  testWidgets('empty diary: share sends the honest empty line, never '
      'fabricated content', (tester) async {
    final diary = makeDiary();
    final captured = <String>[];
    await pumpAndReveal(tester, diary: diary, sink: (payload) async {
      captured.add(payload);
    });

    await tester.tap(find.byKey(const Key('diary-share-button')));
    await tester.pump();

    expect(captured.single, contains(kDiaryShareEmptyLine));
    expect(captured.single, isNot(contains(kDiaryEntryMarker)));
  });

  testWidgets('null diary (documents dir unresolvable): actions honestly '
      'disabled; the unavailable line renders', (tester) async {
    await pumpAndReveal(tester, diary: null, sink: (_) async {
      fail('the sink must never fire with a null diary');
    });

    final writeBtn = tester
        .widget<TextButton>(find.byKey(const Key('diary-write-button')));
    final shareBtn = tester
        .widget<TextButton>(find.byKey(const Key('diary-share-button')));
    expect(writeBtn.onPressed, isNull);
    expect(shareBtn.onPressed, isNull);
    expect(find.text('運転日記はこの環境では利用できません。'), findsOneWidget);
  });

  testWidgets('disclosure states where the data goes BEFORE any tap '
      '(consent-framing discipline)', (tester) async {
    await pumpAndReveal(tester, diary: makeDiary(), sink: (_) async {});
    await tester.ensureVisible(find.byKey(const Key('diary-disclosure')));
    final disclosure = tester
        .widget<Text>(find.byKey(const Key('diary-disclosure')))
        .data!;
    expect(disclosure, contains('この端末の中だけ'));
    expect(disclosure, contains('自動送信は一切なく'));
    expect(disclosure, contains('位置情報は記録されません'));
  });
}
