// Ring-2 運転日記 — the season's consented evidence instrument
// (services/drive_diary.dart).
//
// Pins the diary's contract WITHOUT a device: entry format (marker +
// LOCAL ISO8601 with UTC offset — the AMeDAS cross-check runs on JST
// wall-clock — + ja label + stable en token per choice), her-words fields
// verbatim except marker-neutralization (entry-boundary integrity), the
// honest empty-diary line, newest-tail rotation aligned to whole entries,
// never-throws, and — load-bearing for consent — the ABSENCE of any
// position state (the diary records no coordinates; the composer must add
// none).
//
// The File is injected per the error_log_test pattern — path_provider is a
// production-only concern.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/build_info.dart';
import 'package:sngnav_app/services/drive_diary.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sngnav_drive_diary_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  DriveDiary makeDiary({int maxBytes = 512 * 1024, DateTime Function()? clock}) =>
      DriveDiary(
        file: File('${tmp.path}/drive_diary.txt'),
        maxBytes: maxBytes,
        clock: clock,
      );

  group('record', () {
    test('entry: marker + local ISO8601 WITH offset + ja labels + stable '
        'tokens + her words verbatim', () {
      final diary = makeDiary();
      final ok = diary.record(
        road: DiaryRoadCondition.ice,
        advisory: DiaryAdvisoryExperience.firedHelpful,
        area: '横手市郊外',
        note: '橋の上で警告が鳴り、速度を落とした。',
      );
      expect(ok, isTrue);

      final text = diary.readAll();
      expect(text, startsWith(kDiaryEntryMarker));
      // The timestamp carries a UTC offset (+HH:MM or -HH:MM or +00:00) —
      // Dart's local toIso8601String() omits it; the diary must not.
      expect(
        RegExp(r'--- sngnav diary \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2} ---')
            .hasMatch(text),
        isTrue,
        reason: 'local timestamp must carry its UTC offset: $text',
      );
      expect(text, contains('路面: 凍結・アイスバーン (ice)'));
      expect(text, contains('警告: 警告あり・役立った (fired-helpful)'));
      expect(text, contains('地域: 横手市郊外'));
      expect(text, contains('メモ: 橋の上で警告が鳴り、速度を落とした。'));
    });

    test('injected clock: the written day is the LOCAL day, not the UTC one '
        '(a JST pre-dawn entry must not land on yesterday)', () {
      // 05:30 JST == 20:30 UTC the previous day. The entry text must show
      // the local calendar day the driver experienced.
      final local = DateTime(2026, 11, 14, 5, 30);
      final diary = makeDiary(clock: () => local);
      diary.record(
        road: DiaryRoadCondition.ice,
        advisory: DiaryAdvisoryExperience.firedHelpful,
      );
      expect(diary.readAll(), contains('2026-11-14T05:30:00'));
    });

    test('optional fields left empty are omitted, never fabricated', () {
      final diary = makeDiary();
      diary.record(
        road: DiaryRoadCondition.unknown,
        advisory: DiaryAdvisoryExperience.notSure,
      );
      final text = diary.readAll();
      expect(text, isNot(contains('地域:')));
      expect(text, isNot(contains('メモ:')));
      expect(text, contains('(unknown)'));
      expect(text, contains('(not-sure)'));
    });

    test('a note containing the entry marker is neutralized (entry-boundary '
        'integrity: count + rotation stay correct)', () {
      final diary = makeDiary();
      diary.record(
        road: DiaryRoadCondition.snow,
        advisory: DiaryAdvisoryExperience.didNotFire,
        note: 'evil $kDiaryEntryMarker fake ---',
      );
      expect(diary.entryCount(), 1,
          reason: 'her words must not forge a second entry boundary');
    });

    test('never throws: a write failure returns false, not a crash', () {
      // A directory path as the file forces the write to fail.
      final diary = DriveDiary(file: File(tmp.path));
      final ok = diary.record(
        road: DiaryRoadCondition.dry,
        advisory: DiaryAdvisoryExperience.notSure,
      );
      expect(ok, isFalse);
      expect(diary.readAll(), isEmpty);
      expect(diary.hasEntries(), isFalse);
      expect(diary.entryCount(), 0);
    });
  });

  group('rotation', () {
    test('over-cap: oldest entries dropped at an entry boundary; newest '
        'survive', () {
      final diary = makeDiary(maxBytes: 2048);
      for (var i = 0; i < 30; i++) {
        diary.record(
          road: DiaryRoadCondition.snow,
          advisory: DiaryAdvisoryExperience.didNotFire,
          note: 'entry-$i ${'x' * 120}',
        );
      }
      final text = diary.readAll();
      expect(text.length, lessThanOrEqualTo(2048));
      expect(text, startsWith(kDiaryEntryMarker),
          reason: 'rotation must keep whole entries only');
      expect(text, contains('entry-29'), reason: 'newest entry must survive');
      expect(text, isNot(contains('entry-0 ')),
          reason: 'oldest entry must be dropped');
    });

    test('cap holds in BYTES for ja text (UTF-8 is ~3 bytes per code unit; '
        'a String-length trim would keep ~1.5x the cap)', () {
      final diary = makeDiary(maxBytes: 4096);
      for (var i = 0; i < 40; i++) {
        diary.record(
          road: DiaryRoadCondition.compacted,
          advisory: DiaryAdvisoryExperience.didNotFire,
          note: '吹雪-$i ${'雪' * 100}',
        );
      }
      expect(diary.file.lengthSync(), lessThanOrEqualTo(4096),
          reason: 'the cap is a storage promise, measured in bytes');
      final text = diary.readAll();
      expect(text, startsWith(kDiaryEntryMarker),
          reason: 'byte-aligned trim must keep whole entries only');
      expect(text, contains('吹雪-39'), reason: 'newest entry must survive');
      expect(text, contains('(compacted-snow)'));
    });
  });

  group('composeDiarySharePayload', () {
    test('header (appVersion + os + UTC export) + diary verbatim, and NO '
        'position state', () {
      final diary = makeDiary();
      diary.record(
        road: DiaryRoadCondition.whiteout,
        advisory: DiaryAdvisoryExperience.firedNotHelpful,
        area: '湯沢',
      );
      final payload = composeDiarySharePayload(
        diaryText: diary.readAll(),
        operatingSystem: 'testos',
        exportedAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      );
      expect(payload, contains('sngnav-app $appVersion'));
      expect(payload, contains('os: testos'));
      expect(payload, contains('exported: 2026-11-14T12:00:00.000Z'));
      expect(payload, contains('(whiteout)'));
      expect(payload, contains('地域: 湯沢'));
      // Consent floor: no coordinates ever ride along (akitaStation mock
      // coordinates, akita_map.dart — the log_share_test discipline).
      expect(payload, isNot(contains('39.7167')));
      expect(payload, isNot(contains('140.0983')));
    });

    test('empty diary: the honest empty line, never fabricated content', () {
      final payload = composeDiarySharePayload(
        diaryText: '',
        operatingSystem: 'testos',
        exportedAt: DateTime.utc(2026, 11, 14),
      );
      expect(payload, contains(kDiaryShareEmptyLine));
      expect(payload, isNot(contains(kDiaryEntryMarker)));
    });

    test('over-cap payload: newest tail kept, aligned to a whole entry, '
        'behind the honest truncation note', () {
      final diary = makeDiary();
      for (var i = 0; i < 40; i++) {
        diary.record(
          road: DiaryRoadCondition.snow,
          advisory: DiaryAdvisoryExperience.didNotFire,
          note: 'trip-$i ${'y' * 100}',
        );
      }
      final payload = composeDiarySharePayload(
        diaryText: diary.readAll(),
        operatingSystem: 'testos',
        exportedAt: DateTime.utc(2026, 11, 14),
        maxChars: 1024,
      );
      expect(payload, contains(kDiaryShareTruncationNote));
      expect(payload, contains('trip-39'));
      expect(payload, isNot(contains('trip-0 ')));
      final body = payload.substring(payload.indexOf(kDiaryEntryMarker));
      expect(body, startsWith(kDiaryEntryMarker),
          reason: 'shared body must start at a whole entry');
    });
  });

  group('status reads', () {
    test('hasEntries: O(1) stat honest on missing file; true after a '
        'record', () {
      final diary = makeDiary();
      expect(diary.hasEntries(), isFalse);
      diary.record(
        road: DiaryRoadCondition.wet,
        advisory: DiaryAdvisoryExperience.notSure,
      );
      expect(diary.hasEntries(), isTrue);
    });

    test('entryCount counts markers', () {
      final diary = makeDiary();
      expect(diary.entryCount(), 0);
      for (var i = 0; i < 3; i++) {
        diary.record(
          road: DiaryRoadCondition.dry,
          advisory: DiaryAdvisoryExperience.notSure,
        );
      }
      expect(diary.entryCount(), 3);
    });
  });
}
