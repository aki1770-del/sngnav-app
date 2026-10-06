/// The build after code 13 deletes code 13's fix-timing record, and nothing
/// else.
///
/// Why, written before the act (2026-10-06). Code 13's card told the man
/// driving it that its record "is deleted when the next build is installed".
/// Code 13 is never merged, so this is where that promise is kept. These hold
/// that both of its files go, that the error log and the drive diary beside
/// them stay, that a second launch finds nothing to do, and that a missing
/// directory never stops a launch.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/code13_record_cleanup.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('code13_cleanup_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('the names are code 13\'s own', () {
    // As written by code 13 (branch code13-fix-timing-record,
    // services/fix_timing_record.dart: kFixTimingRecordFileName and
    // kFixTimingStoppedFileName).
    expect(kCode13RecordFileNames,
        ['fix_timing_record.txt', 'fix_timing_record.stopped']);
  });

  test('both files go; the error log and the diary beside them stay', () async {
    File('${dir.path}/fix_timing_record.txt').writeAsStringSync('s=1 t=0 k=start a=- v=- late=- fg=1\n');
    File('${dir.path}/fix_timing_record.stopped').writeAsStringSync('stopped\n');
    final errorLog = File('${dir.path}/error_log.txt')..writeAsStringSync('e\n');
    final diary = File('${dir.path}/drive_diary.txt')..writeAsStringSync('d\n');
    expect(await deleteCode13FixTimingRecord(directory: dir), 2);
    expect(File('${dir.path}/fix_timing_record.txt').existsSync(), isFalse);
    expect(File('${dir.path}/fix_timing_record.stopped').existsSync(), isFalse);
    expect(errorLog.readAsStringSync(), 'e\n');
    expect(diary.readAsStringSync(), 'd\n');
    expect(await deleteCode13FixTimingRecord(directory: dir), 0,
        reason: 'the second launch found something to delete');
  });

  test('a missing directory never stops a launch', () async {
    dir.deleteSync(recursive: true);
    expect(await deleteCode13FixTimingRecord(directory: dir), 0);
  });
}
