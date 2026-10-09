/// The build after code 13 deletes code 13's fix-timing record, and nothing
/// else; and, since 2026-10-09, it no longer throws away what it deleted.
///
/// Why, written before the act (2026-10-06). Code 13's card told the man
/// driving it that its record "is deleted when the next build is installed".
/// Code 13 is never merged, so this is where that promise is kept. These hold
/// that both of its files go, that the error log and the drive diary beside
/// them stay, that a second launch finds nothing to do, and that a missing
/// directory never stops a launch.
///
/// Why, added 2026-10-09. Code 14 deleted code 13's record and main threw the
/// count away, so a lost reading left no trace (Sakichi Vision 14: silent
/// failure). These also hold WHEN the app must tell him (option L): a deleted
/// record that held a fix line, or one that could not be read; and when it
/// must not: a record of markers only, the stopped marker alone, or nothing
/// deleted. And they hold that code 15's record beside it is untouched (the
/// keeper).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/code13_record_cleanup.dart';
import 'package:sngnav_app/services/fix_interval_record_keeper.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('code13_cleanup_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const fixLine = 's=1 t=5012 k=fine a=4.0 v=13.2 late=180 fg=1\n';

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
    final first = await deleteCode13FixTimingRecord(directory: dir);
    expect(first.deletedFiles, 2);
    expect(File('${dir.path}/fix_timing_record.txt').existsSync(), isFalse);
    expect(File('${dir.path}/fix_timing_record.stopped').existsSync(), isFalse);
    expect(errorLog.readAsStringSync(), 'e\n');
    expect(diary.readAsStringSync(), 'd\n');
    final second = await deleteCode13FixTimingRecord(directory: dir);
    expect(second.deletedFiles, 0,
        reason: 'the second launch found something to delete');
    expect(second.mustTell, isFalse,
        reason: 'L is told once: the launch after deletes nothing and tells '
            'nothing');
  });

  test('a missing directory never stops a launch', () async {
    dir.deleteSync(recursive: true);
    final r = await deleteCode13FixTimingRecord(directory: dir);
    expect(r.deletedFiles, 0);
    expect(r.mustTell, isFalse);
  });

  group('L: the deletion is told when a reading may have gone', () {
    test('a record holding a fix line: deleted AND told', () async {
      File('${dir.path}/fix_timing_record.txt').writeAsStringSync(
          's=0 t=0 k=launch\ns=1 t=0 k=start a=- v=- late=- fg=1\n$fixLine');
      final r = await deleteCode13FixTimingRecord(directory: dir);
      expect(r.deletedFiles, 1);
      expect(r.recordHeldFixLines, isTrue);
      expect(r.mustTell, isTrue);
      expect(File('${dir.path}/fix_timing_record.txt').existsSync(), isFalse);
    });

    test('a coarse fix line counts as a reading too', () async {
      File('${dir.path}/fix_timing_record.txt').writeAsStringSync(
          's=2 t=900 k=coarse a=1200.0 v=- late=40 fg=0\n');
      expect((await deleteCode13FixTimingRecord(directory: dir)).mustTell,
          isTrue);
    });

    test('markers only (launch, start, pause): deleted, NOT told — no reading '
        'was held', () async {
      File('${dir.path}/fix_timing_record.txt').writeAsStringSync(
          's=0 t=0 k=launch\ns=1 t=0 k=start a=- v=- late=- fg=1\n'
          's=1 t=8000 k=noacc a=- v=- late=- fg=1\ns=0 t=0 k=pause\n');
      final r = await deleteCode13FixTimingRecord(directory: dir);
      expect(r.deletedFiles, 1);
      expect(r.mustTell, isFalse);
    });

    test('the stopped marker alone: deleted, NOT told', () async {
      File('${dir.path}/fix_timing_record.stopped')
          .writeAsStringSync('stopped\n');
      final r = await deleteCode13FixTimingRecord(directory: dir);
      expect(r.deletedFiles, 1);
      expect(r.mustTell, isFalse);
    });

    test('a record that cannot be read as text is told, never assumed empty '
        '(fail-closed)', () async {
      // Bytes that are not UTF-8: readAsStringSync throws on them.
      File('${dir.path}/fix_timing_record.txt')
          .writeAsBytesSync([0xC3, 0x28, 0xFF, 0xFE]);
      final r = await deleteCode13FixTimingRecord(directory: dir);
      expect(r.deletedFiles, 1);
      expect(r.mustTell, isTrue);
    });
  });

  test('code 15\'s record beside it is untouched, byte for byte (the keeper)',
      () async {
    File('${dir.path}/fix_timing_record.txt').writeAsStringSync(fixLine);
    final kept = File('${dir.path}/$kCode15RecordFileName')
      ..writeAsStringSync('s=0 t=0 k=launch\n$fixLine');
    final keptStopped = File('${dir.path}/$kCode15StoppedFileName')
      ..writeAsStringSync('stopped\n');
    final before = kept.readAsBytesSync();
    await deleteCode13FixTimingRecord(directory: dir);
    expect(kept.readAsBytesSync(), before);
    expect(keptStopped.readAsStringSync(), 'stopped\n');
  });
}
