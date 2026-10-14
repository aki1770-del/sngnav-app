/// Code 16's boundary line: which build wrote which lines of his record is
/// carried in the record's own bytes (2026-10-14).
///
/// WHY, written before the act. Code 16 appends to code 15's file, under code
/// 15's name. A reader of the file must know which build wrote each line, and
/// what a `launch` meant when it was written, or the reading of how far apart
/// his phone delivers GPS fixes (which the tunnel-exit fix waits on) is read
/// under the wrong build. Sakichi Vision 14: a line read as another build's is
/// a success-shaped value over a wrong attribution. Vision 15: the rule is
/// decided from the file's bytes, so it cannot be done wrong by a version
/// literal. Vision 16: a build that cannot name itself writes nothing.
///
/// Each group pins one of the reading's requirements on the writer (W-1 to
/// W-10, the safety reader's ruling of 2026-10-14) or one of the identity
/// steward's mutants (1 to 6 and 8; 7 is the share header's).
///
/// HONEST BOUND. A host test of the writer's bytes. Whether a phone's update
/// writes the line as here is the emulator's read (G-1, G-2).
library;

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/build_info.dart';
import 'package:sngnav_app/services/build_identity.dart';
import 'package:sngnav_app/services/code15_fix_interval_record.dart';

import '../support/test_record_writer.dart';

String hex(String seed, int n) => (seed * n).substring(0, n);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('record_boundary_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> linesOf(Code15FixIntervalRecord r) =>
      r.readAll().split('\n').where((l) => l.isNotEmpty).toList();

  Code15FixIntervalRecord open(RecordWriter? w, {int maxBytes = kCode15RecordMaxBytes}) =>
      Code15FixIntervalRecord(directory: dir, writer: w, maxBytes: maxBytes);

  bool fine(Code15FixIntervalRecord r, int ms, {int share = 1}) => r.record(
        share: share,
        msSinceStreamStart: ms,
        kind: FixEventKind.fine,
        accuracyMeters: 8.0,
        reportedSpeedMps: 15.0,
        lateMs: 200,
        appInFront: true,
      );

  /// A file as code 15 left it: lines, and no boundary.
  void code15File() => File('${dir.path}/${kCode15RecordFileNames[0]}')
      .writeAsStringSync('s=0 t=0 k=launch\n'
          's=1 t=0 k=start a=- v=- late=- fg=1\n'
          's=1 t=5000 k=fine a=8.0 v=15.0 late=200 fg=1\n'
          's=1 t=9000 k=end\n');

  group('W-1: the line, exactly, and the whitelist gains exactly it', () {
    test('the form, the order, lowercase hex, launch=engine', () {
      expect(kTestRecordWriter.boundaryLine, kTestBoundaryLine);
      expect(kTestBoundaryLine,
          's=0 t=0 k=build vc=16 sha=c0de16a apk=16a1b2c3d4e5 launch=engine');
      expect(kRecordLaunchMeaning, 'engine');
      expect(utf8.encode('$kTestBoundaryLine\n').length, 65);
      expect(utf8.encode(RecordWriter(versionCode: 2147483647).boundaryLine).length + 1,
          lessThanOrEqualTo(kCode15MaxLineBytes));
    });

    test('both patterns accept it and refuse every near miss', () {
      expect(kRecordBuildLinePattern.hasMatch(kTestBoundaryLine), isTrue);
      expect(kCode15LinePattern.hasMatch(kTestBoundaryLine), isTrue);
      expect(
          kCode15LinePattern
              .hasMatch('s=0 t=0 k=build vc=16 sha=- apk=- launch=engine'),
          isTrue,
          reason: 'declared gaps are a valid line');
      for (final bad in [
        's=0 t=0 k=build vc=16 sha=c0de16a1234567890123456789012345678901 apk=16a1b2c3d4e5 launch=engine',
        's=0 t=0 k=build vc=16 sha=c0de16a apk=16a1b2c3d4e5f launch=engine',
        's=0 t=0 k=build vc=16 sha=c0de16a launch=engine',
        's=0 t=0 k=build sha=c0de16a vc=16 apk=16a1b2c3d4e5 launch=engine',
        's=0 t=0 k=build vc=16 sha=C0DE16A apk=16a1b2c3d4e5 launch=engine',
        's=0 t=0 k=build vc=16 sha=c0de16a apk=16a1b2c3d4e5 launch=process',
        's=0 t=0 k=build vc=0 sha=c0de16a apk=16a1b2c3d4e5 launch=engine',
        's=0 t=0 k=build vc=16  sha=c0de16a apk=16a1b2c3d4e5 launch=engine',
        's=0 t=0 k=engine',
      ]) {
        expect(kCode15LinePattern.hasMatch(bad), isFalse, reason: bad);
        expect(kRecordBuildLinePattern.hasMatch(bad), isFalse, reason: bad);
      }
    });

    test('the tokens: 7 and 12 lowercase hex, or a declared gap', () {
      final full = hex('ab12cd', 64);
      expect(RecordWriter(versionCode: 16, gitSha: 'ecfade349fcc', selfSha256: full).sha,
          'ecfade3');
      expect(RecordWriter(versionCode: 16, gitSha: 'ECFADE3').sha, 'ecfade3');
      for (final gap in [null, 'UNKNOWN', 'UNREADABLE', 'ecfade3-dirty', 'zz12345', 'ecf']) {
        expect(RecordWriter(versionCode: 16, gitSha: gap).sha, '-', reason: '$gap');
      }
      expect(RecordWriter(versionCode: 16, selfSha256: full).apk, full.substring(0, 12));
      expect(RecordWriter(versionCode: 16).apk, '-');
      for (final vc in [null, 0, -1]) {
        expect(RecordWriter(versionCode: vc).canWrite, isFalse, reason: '$vc');
      }
    });
  });

  group('BIS mutants 1 and 2: never a literal, never a constant', () {
    test('each writer writes the tokens the platform gave it, not appVersion', () {
      for (final (vc, sha, apk) in [
        (16, 'c0de16a', hex('16a1b2', 64)),
        (23, '2323abc', hex('2323ff', 64)),
        (15, 'ecfade3', '2864c49887b9f90294143bd5881b155bd348da6aead05abd77d5bb6e59e85463'),
      ]) {
        final w = RecordWriter(versionCode: vc, gitSha: sha, selfSha256: apk);
        expect(w.boundaryLine,
            's=0 t=0 k=build vc=$vc sha=$sha apk=${apk.substring(0, 12)} launch=engine');
        expect(w.boundaryLine, isNot(contains(appVersion)));
      }
    });

    test('fromIdentity takes the identity\'s own fields', () async {
      final id = await testBuildIdentity();
      expect(RecordWriter.fromIdentity(id).boundaryLine, kTestBoundaryLine);
      expect(RecordWriter.fromIdentity(const BuildIdentity.unknown()).canWrite, isFalse);
    });
  });

  group('W-2 and BIS mutant 8: the trigger, from the file\'s bytes', () {
    test('a file with no boundary gets one, at any versionCode, 15 included', () {
      for (final vc in [15, 16]) {
        code15File();
        final w = RecordWriter(versionCode: vc, gitSha: 'ecfade3', selfSha256: hex('2864c4', 64));
        final r = open(w);
        r.recordLaunch();
        final lines = linesOf(r);
        expect(lines.sublist(4), [w.boundaryLine, kFixTimingLaunchLine], reason: 'vc $vc');
        File('${dir.path}/${kCode15RecordFileNames[0]}').deleteSync();
      }
    });

    test('BIS mutant 6: a change of writer is (vc, apk), falling back to vc '
        'when either apk is -', () {
      final a = RecordWriter(versionCode: 16, gitSha: 'c0de16a', selfSha256: hex('aaaaaa', 64));
      final b = RecordWriter(versionCode: 16, gitSha: 'c0de16a', selfSha256: hex('bbbbbb', 64));
      final gap = RecordWriter(versionCode: 16, gitSha: 'c0de16a');
      final next = RecordWriter(versionCode: 17, gitSha: 'c0de17a', selfSha256: hex('aaaaaa', 64));
      int boundariesAfter(RecordWriter first, RecordWriter second) {
        final f = File('${dir.path}/${kCode15RecordFileNames[0]}');
        if (f.existsSync()) f.deleteSync();
        open(first).recordLaunch();
        open(second).recordLaunch();
        return linesOf(open(second))
            .where((l) => kRecordBuildLinePattern.hasMatch(l))
            .length;
      }

      expect(boundariesAfter(a, a), 1, reason: 'the same writer: no new boundary');
      expect(boundariesAfter(a, b), 2, reason: 'same vc, other bytes: a new writer');
      expect(boundariesAfter(a, gap), 1, reason: 'apk unknown: fall back to vc');
      expect(boundariesAfter(gap, a), 1, reason: 'apk unknown on the file side');
      expect(boundariesAfter(a, next), 2, reason: 'another vc: a new writer');
    });

    test('the last boundary decides, not an earlier one', () {
      final a = RecordWriter(versionCode: 16, gitSha: 'c0de16a', selfSha256: hex('aaaaaa', 64));
      final b = RecordWriter(versionCode: 17, gitSha: 'c0de17a', selfSha256: hex('bbbbbb', 64));
      open(a).recordLaunch();
      open(b).recordLaunch();
      open(a).recordLaunch();
      expect(
          linesOf(open(a)).where((l) => kRecordBuildLinePattern.hasMatch(l)).toList(),
          [a.boundaryLine, b.boundaryLine, a.boundaryLine]);
    });
  });

  group('W-3: the place: immediately before the build\'s first line', () {
    test('at an open that records: before launch; reopened by the same '
        'build: no second boundary, never two in a row', () async {
      final r = (await openCode15FixIntervalRecord(directory: dir, identity: testBuildIdentity))!;
      await r.named;
      fine(r, 1000);
      final again = (await openCode15FixIntervalRecord(directory: dir, identity: testBuildIdentity))!;
      await again.named;
      expect(linesOf(again), [
        kTestBoundaryLine,
        kFixTimingLaunchLine,
        startsWith('s=1 t=1000 k=fine'),
        kFixTimingLaunchLine,
      ]);
    });

    test('opened stopped: nothing; at his resume, the boundary then resume', () {
      code15File();
      final w = RecordWriter(versionCode: 16, gitSha: 'c0de16a', selfSha256: hex('16a1b2', 64));
      open(kTestRecordWriter).stop(); // he stopped it under another build
      final before = open(w).readAll();
      final r = open(w)..recordLaunch();
      expect(fine(r, 1000), isFalse);
      expect(r.readAll(), before, reason: 'nothing while stopped, boundary included');
      r.resume();
      expect(linesOf(r).sublist(linesOf(r).length - 2), [w.boundaryLine, kFixTimingResumeLine]);
    });

    test('BIS mutant 3: after his delete, the first line of the fresh file is '
        'the boundary', () {
      final r = open(kTestRecordWriter);
      r.recordLaunch();
      fine(r, 1000);
      r.deleteRecordOnHisTap();
      expect(r.hasLines, isFalse);
      fine(r, 6000);
      expect(linesOf(r), [kTestBoundaryLine, startsWith('s=1 t=6000 k=fine')]);
    });
  });

  group('W-4 and BIS mutant 4: his stop holds for every line', () {
    test('no boundary and no line while stopped', () {
      code15File();
      open(kTestRecordWriter).stop();
      final before = open(null).readAll();
      final r = open(kTestRecordWriter);
      r.recordLaunch();
      expect(fine(r, 1000), isFalse);
      expect(r.recordEnd(share: 1, msSinceStreamStart: 2000), isFalse);
      r.stop();
      expect(r.readAll(), before);
      expect(r.stopped, isTrue);
    });
  });

  group('W-5: the cap: the boundary and one more line, or no line of any kind',
      () {
    test('owed and no room for both: nothing, pause included, and full', () {
      final f = File('${dir.path}/${kCode15RecordFileNames[0]}');
      // Room for one line, not for a boundary and a line.
      f.writeAsStringSync('${'x' * 39}\n' * 23); // 920 bytes of a 1024 cap
      final r = open(kTestRecordWriter, maxBytes: 1024);
      expect(r.full, isTrue, reason: 'owed: 920 + 2 x 96 > 1024');
      r.recordLaunch();
      expect(fine(r, 1000), isFalse);
      r.stop();
      expect(r.lengthBytes, 920, reason: 'no line of any kind, pause included');
      expect(r.stopped, isTrue, reason: 'his stop is still kept');
    });

    test('not owed: the same room takes one line', () {
      final f = File('${dir.path}/${kCode15RecordFileNames[0]}');
      // The boundary already there, then filler: 65 + 800 = 865 bytes.
      f.writeAsStringSync('$kTestBoundaryLine\n${'${'x' * 39}\n' * 20}');
      final len = f.lengthSync();
      expect(len + 96, lessThanOrEqualTo(1024));
      expect(len + 192, greaterThan(1024));
      final r = open(kTestRecordWriter, maxBytes: 1024);
      expect(r.full, isFalse);
      expect(fine(r, 1000), isTrue);
    });
  });

  group('W-6 and BIS mutant 5: a build that cannot name itself writes no line '
      'of any kind', () {
    test('nothing written; his stop and his delete still work', () {
      code15File();
      final before = File('${dir.path}/${kCode15RecordFileNames[0]}').readAsStringSync();
      final r = open(RecordWriter.unreadable);
      expect(r.cannotNameItself, isTrue);
      r.recordLaunch();
      expect(r.record(share: 1, msSinceStreamStart: 0, kind: FixEventKind.start, appInFront: true), isFalse);
      expect(fine(r, 1000), isFalse);
      expect(r.recordEnd(share: 1, msSinceStreamStart: 2000), isFalse);
      r.stop();
      expect(r.readAll(), before, reason: 'no line of any kind, pause included');
      expect(r.stopped, isTrue, reason: 'the marker is a file, not a line');
      r.deleteRecordOnHisTap();
      expect(r.hasLines, isFalse, reason: 'his delete works');
    });

    test('an identity that does not answer in time names a build that cannot '
        'name itself', () async {
      final never = Completer<BuildIdentity>();
      final r = (await openCode15FixIntervalRecord(
          directory: dir,
          identity: () => never.future,
          identityTimeout: const Duration(milliseconds: 50)))!;
      await r.named;
      expect(r.cannotNameItself, isTrue);
      expect(r.hasLines, isFalse);
    });

    test('an unknown identity: the same', () async {
      final r = (await openCode15FixIntervalRecord(
          directory: dir, identity: () async => const BuildIdentity.unknown()))!;
      await r.named;
      expect(r.cannotNameItself, isTrue);
      expect(r.hasLines, isFalse, reason: 'its launch was dropped, not written');
    });
  });

  group('held lines: nothing is written until the writer is named', () {
    test('in order, after the boundary, once named', () {
      final r = open(null);
      r.recordLaunch();
      r.record(share: 1, msSinceStreamStart: 0, kind: FixEventKind.start, appInFront: true);
      fine(r, 5000);
      expect(r.hasLines, isFalse);
      r.nameWriter(kTestRecordWriter);
      expect(linesOf(r), [
        kTestBoundaryLine,
        kFixTimingLaunchLine,
        startsWith('s=1 t=0 k=start'),
        startsWith('s=1 t=5000 k=fine'),
      ]);
      expect(r.hasFixLines, isTrue);
    });

    test('his stop is read when the line is made: a launch made while '
        'recording is kept when he stops before the naming', () {
      final r = open(null);
      r.recordLaunch();
      r.stop();
      r.nameWriter(kTestRecordWriter);
      expect(linesOf(r), [kTestBoundaryLine, kFixTimingLaunchLine, kFixTimingPauseLine]);
    });

    test('past the limit nothing is kept and nothing is written', () {
      final r = open(null);
      for (var i = 0; i <= kRecordMaxHeldLines; i++) {
        fine(r, i * 1000);
      }
      r.nameWriter(kTestRecordWriter);
      expect(r.hasLines, isFalse);
      expect(r.cannotNameItself, isTrue);
    });

    test('the naming is told to the card', () {
      final r = open(null);
      var told = 0;
      r.changes.addListener(() => told++);
      r.nameWriter(kTestRecordWriter);
      expect(told, 1);
      r.nameWriter(RecordWriter.unreadable);
      expect(r.writer, kTestRecordWriter, reason: 'named once');
    });
  });

  group('W-8: no k=engine line on code 16', () {
    test('lib/ carries no k=engine at all', () {
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('k=engine'))
          .map((f) => f.path)
          .toList();
      expect(hits, isEmpty);
    });
  });

  group('W-9: the count closes its segment at the boundary', () {
    test('no interval crosses it', () {
      const a = 's=1 t=0 k=fine a=8.0 v=15.0 late=200 fg=1';
      const b = 's=1 t=5000 k=fine a=8.0 v=15.0 late=200 fg=1';
      expect(Code15MinimumCount.ofText('$a\n$b\n').movingIntervals, 1,
          reason: 'control: the same two fixes count one interval');
      expect(Code15MinimumCount.ofText('$a\n$kTestBoundaryLine\n$b\n').movingIntervals, 0);
    });
  });

  group('W-10: the boundary does not move the alive timer', () {
    test('quiet is measured from the last share line, not from the boundary', () {
      final r = open(null);
      r.record(share: 1, msSinceStreamStart: 0, kind: FixEventKind.start, appInFront: true);
      fine(r, 5000);
      r.nameWriter(kTestRecordWriter);
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 10999), isFalse);
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 11000), isTrue);
    });
  });
}
