/// The keeper: code 15's fix-interval record survives every launch of main,
/// and only his tap deletes it.
///
/// Why, written before the act (2026-10-09). Code 13's reading was lost
/// because a later build deleted its record and keeping it rested on him
/// remembering to share first (Sakichi Vision 9: the operator must not be the
/// last line of defence). These hold the rule the machine now keeps instead:
/// - code 15's names are their own, never code 13's (which main deletes on
///   every launch), never the error log's or the diary's;
/// - the names are pinned: a rename would orphan a record written under the
///   old name, which is a deletion by another route;
/// - the WHOLE launch path main() runs (launchRecordHousekeeping) leaves code
///   15's files byte for byte, launch after launch, while it deletes code 13's;
/// - his tap deletes both of code 15's files, and nothing else;
/// - the share payload carries every line and deletes nothing.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/build_info.dart';
import 'package:sngnav_app/services/code13_record_cleanup.dart';
import 'package:sngnav_app/services/drive_diary.dart' show kDriveDiaryFileName;
import 'package:sngnav_app/services/error_log.dart' show kErrorLogFileName;
import 'package:sngnav_app/services/fix_interval_record_keeper.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('code15_keeper_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const code15Lines =
      's=0 t=0 k=launch\n'
      's=1 t=0 k=start a=- v=- late=- fg=1\n'
      's=1 t=5004 k=fine a=3.9 v=12.0 late=210 fg=1\n'
      's=1 t=10011 k=fine a=4.2 v=0.0 late=190 fg=0\n';

  group('the names', () {
    test('code 15\'s names are pinned: a rename orphans a kept record', () {
      expect(kCode15RecordFileName, 'fix_interval_record_15.txt');
      expect(kCode15StoppedFileName, 'fix_interval_record_15.stopped');
      expect(kCode15RecordFileNames, [
        'fix_interval_record_15.txt',
        'fix_interval_record_15.stopped',
      ]);
    });

    test('code 15\'s names and code 13\'s are distinct, and neither is the '
        'error log\'s or the diary\'s', () {
      expect(
        kCode15RecordFileNames.toSet().intersection(
          kCode13RecordFileNames.toSet(),
        ),
        isEmpty,
        reason:
            'main deletes code 13\'s names on every launch: a shared '
            'name would delete code 15\'s record at its own next start',
      );
      for (final other in [kErrorLogFileName, kDriveDiaryFileName]) {
        expect(kCode15RecordFileNames, isNot(contains(other)));
        expect(kCode13RecordFileNames, isNot(contains(other)));
      }
    });
  });

  group('the launch path main() runs never deletes code 15\'s record', () {
    test('code 13\'s files go and are told; code 15\'s stay, byte for byte, '
        'over three launches', () async {
      File(
        '${dir.path}/fix_timing_record.txt',
      ).writeAsStringSync('s=1 t=5000 k=fine a=4.0 v=10.0 late=100 fg=1\n');
      File(
        '${dir.path}/fix_timing_record.stopped',
      ).writeAsStringSync('stopped\n');
      final record = File('${dir.path}/$kCode15RecordFileName')
        ..writeAsStringSync(code15Lines);
      final stopped = File('${dir.path}/$kCode15StoppedFileName')
        ..writeAsStringSync('stopped\n');
      final recordBytes = record.readAsBytesSync();
      final stoppedBytes = stopped.readAsBytesSync();

      for (var launch = 1; launch <= 3; launch++) {
        final state = await launchRecordHousekeeping(directory: dir);
        expect(
          record.readAsBytesSync(),
          recordBytes,
          reason: 'launch $launch changed code 15\'s record',
        );
        expect(
          stopped.readAsBytesSync(),
          stoppedBytes,
          reason: 'launch $launch changed code 15\'s stopped marker',
        );
        expect(state.leftBehind?.present, isTrue);
        expect(
          state.code13.mustTell,
          launch == 1,
          reason: 'L is told on the launch that deleted, and only then',
        );
      }
      for (final name in kCode13RecordFileNames) {
        expect(File('${dir.path}/$name').existsSync(), isFalse);
      }
    });

    test('a launch with no record left behind reports none', () async {
      final state = await launchRecordHousekeeping(directory: dir);
      expect(state.leftBehind?.present, isFalse);
      expect(state.code13.mustTell, isFalse);
    });
  });

  group('his tap', () {
    test(
      'Delete record deletes both of code 15\'s files and nothing else',
      () async {
        File(
          '${dir.path}/$kCode15RecordFileName',
        ).writeAsStringSync(code15Lines);
        File(
          '${dir.path}/$kCode15StoppedFileName',
        ).writeAsStringSync('stopped\n');
        final log = File('${dir.path}/$kErrorLogFileName')
          ..writeAsStringSync('e\n');
        final diary = File('${dir.path}/$kDriveDiaryFileName')
          ..writeAsStringSync('d\n');
        final view = (await openLeftBehindFixIntervalRecord(directory: dir))!;
        expect(view.present, isTrue);
        expect(view.deleteOnHisTap(), isTrue);
        expect(view.present, isFalse);
        for (final name in kCode15RecordFileNames) {
          expect(File('${dir.path}/$name').existsSync(), isFalse);
        }
        expect(log.readAsStringSync(), 'e\n');
        expect(diary.readAsStringSync(), 'd\n');
      },
    );

    test('absent: not present, nothing to read', () async {
      final view = (await openLeftBehindFixIntervalRecord(directory: dir))!;
      expect(view.present, isFalse);
      expect(view.readAll(), '');
    });
  });

  group('the share payload', () {
    test('header in code 13\'s shape, then every line as written', () {
      final p = composeLeftBehindRecordSharePayload(
        recordText: code15Lines,
        operatingSystem: 'android',
        exportedAt: DateTime.utc(2026, 11, 2, 3, 4, 5),
      );
      expect(
        p,
        'sngnav-app $appVersion fix-interval record left by an earlier test '
        'build (this build does not record)\n'
        'os: android\n'
        'exported: 2026-11-02T03:04:05.000Z\n'
        '---\n'
        '$code15Lines',
      );
    });

    test('a record with no fix line says so before its markers', () {
      final p = composeLeftBehindRecordSharePayload(
        recordText: 's=0 t=0 k=launch\n',
        operatingSystem: 'android',
        exportedAt: DateTime.utc(2026, 11, 2),
      );
      expect(
        p,
        contains(
          '---\n測位間隔の記録はありません (no fix-interval lines)\n'
          's=0 t=0 k=launch\n',
        ),
      );
    });
  });
}
