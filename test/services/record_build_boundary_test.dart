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

  group('W-7 and BIS mutant 7: the share header names the exporting build',
      () {
    // The reading's own header rule, written out (classify_endings_v5.py,
    // HEADER_BUILD_RE).
    final headerRe = RegExp(r'^build: ([1-9]\d*|-) ([0-9a-f]{7}|-) ([0-9a-f]{12}|-)$');
    String payload(RecordWriter? w, String text) => composeCode15SharePayload(
        recordText: text,
        exportingBuild: w,
        operatingSystem: 'android',
        exportedAt: DateTime.utc(2026, 10, 14, 12));

    test('exactly one build: line, right after exported:, with all three '
        'tokens', () {
      const text = '$kTestBoundaryLine\n$kFixTimingLaunchLine\n';
      final head = payload(kTestRecordWriter, text).split('---\n').first.split('\n');
      expect(head.where((l) => l.startsWith('build:')).toList(),
          ['build: 16 c0de16a 16a1b2c3d4e5']);
      expect(head[head.indexWhere((l) => l.startsWith('exported:')) + 1],
          'build: 16 c0de16a 16a1b2c3d4e5');
      expect(headerRe.hasMatch('build: 16 c0de16a 16a1b2c3d4e5'), isTrue);
    });

    test('the title line, lines: and bytes: are as before', () {
      const text = '$kTestBoundaryLine\n$kFixTimingLaunchLine\n';
      final p = payload(kTestRecordWriter, text);
      expect(p.split('\n').first, 'sngnav-app $appVersion fix-timing record (test build)');
      expect(p, contains('lines: 2\n'));
      expect(p, contains('bytes: ${utf8.encode(text).length}\n'));
      expect(p.endsWith(text), isTrue, reason: 'the record whole, after ---');
    });

    test('declared gaps: an unnamed build, and one that cannot name itself',
        () {
      for (final w in [null, RecordWriter.unreadable]) {
        final head = payload(w, '').split('---\n').first;
        expect(head, contains('\n$kRecordUnnamedBuildHeader\n'), reason: '$w');
        expect(headerRe.hasMatch(kRecordUnnamedBuildHeader), isTrue);
      }
      final noApk = RecordWriter(versionCode: 16, gitSha: 'c0de16a');
      expect(payload(noApk, '').split('\n')[3], 'build: 16 c0de16a -',
          reason: 'BIS 7: the apk slot is never dropped, only declared a gap');
    });

    test('sharing writes no byte of the record', () {
      final r = open(kTestRecordWriter);
      r.recordLaunch();
      final before = r.readAll();
      payload(r.writer, r.readAll());
      expect(r.readAll(), before);
    });
  });

  group('W-11: his delete deletes every line made before his tap, the lines '
      'still waiting for the naming included', () {
    // The safety reader's T-A (2026-10-14), as offered. On 55bad2e8 his delete
    // left the waiting lines to be written into the fresh file at the naming:
    // lines from before his tap, after it. Code 15 had every such line on disk
    // at his tap, and it went with the file.
    test('T-A his delete before the naming deletes the lines waiting for it',
        () async {
      File('${dir.path}/${kCode15RecordFileNames[0]}').writeAsStringSync(
          's=0 t=0 k=launch\n'
          's=1 t=0 k=start a=- v=- late=- fg=1\n'
          's=1 t=5000 k=fine a=4.0 v=13.4 late=900 fg=1\n');
      final c = Completer<BuildIdentity>();
      final r = (await openCode15FixIntervalRecord(
          directory: dir, identity: () => c.future))!;
      fine(r, 1000); // made before his tap, still waiting
      fine(r, 2000);
      r.deleteRecordOnHisTap();
      fine(r, 3000); // made after his tap
      c.complete(await testBuildIdentity());
      await r.named;
      expect(linesOf(r), [kTestBoundaryLine, startsWith('s=1 t=3000 k=fine')]);
    });
  });

  group('W-2 as amended: the boundary is decided from the file\'s bytes at '
      'the write', () {
    // The safety reader's T-B (2026-10-14), as offered. Two writers of one
    // build in one process (a second page's engine): on 55bad2e8 each kept
    // its own decision from the naming, so the first page wrote a second
    // boundary after the second page's resume, and the reader refuses the
    // whole file (order, C11).
    test('T-B two writers of one build in one process: exactly one boundary',
        () async {
      File('${dir.path}/${kCode15RecordFileNames[0]}').writeAsStringSync(
          's=0 t=0 k=launch\n'
          's=1 t=0 k=start a=- v=- late=- fg=1\n'
          's=1 t=5000 k=fine a=4.0 v=13.4 late=900 fg=1\n');
      File('${dir.path}/${kCode15RecordFileNames[1]}').writeAsStringSync('stopped\n');
      final a = (await openCode15FixIntervalRecord(
          directory: dir, identity: testBuildIdentity))!;
      await a.named;
      final b = (await openCode15FixIntervalRecord(
          directory: dir, identity: testBuildIdentity))!;
      await b.named;
      b.resume(); // his resume, on the second page
      fine(a, 4000); // the first page's share goes on writing
      final boundaries =
          linesOf(a).where((l) => kRecordBuildLinePattern.hasMatch(l)).length;
      expect(boundaries, 1);
      expect(linesOf(a).sublist(3),
          [kTestBoundaryLine, kFixTimingResumeLine, startsWith('s=1 t=4000 k=fine')]);
    });

    test('T-B2 the other direction: his delete on the second page leaves the '
        'first page owing a boundary for the fresh file', () async {
      final a = (await openCode15FixIntervalRecord(
          directory: dir, identity: testBuildIdentity))!;
      await a.named;
      final b = (await openCode15FixIntervalRecord(
          directory: dir, identity: testBuildIdentity))!;
      await b.named;
      expect(linesOf(a), [kTestBoundaryLine, kFixTimingLaunchLine, kFixTimingLaunchLine],
          reason: 'control: one boundary for two opens by one build');
      b.deleteRecordOnHisTap(); // his delete, on the second page
      fine(a, 7000); // the first page's share writes next
      expect(linesOf(a), [kTestBoundaryLine, startsWith('s=1 t=7000 k=fine')],
          reason: 'a fresh file with no boundary would be read as code 15\'s');
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
    // The safety reader's T-C (2026-10-14), as offered: the LIVE path. The
    // rule's own test below reads text; this one reads the record object's
    // count as it writes, over a code 15 share left open, so the card and
    // the reading of the file cannot come apart. Red on the W9 mutant
    // (the boundary not fed to the live count), green on the writer.
    test('T-C the live count is the count of the file\'s own text', () {
      File('${dir.path}/${kCode15RecordFileNames[0]}').writeAsStringSync(
          's=0 t=0 k=launch\n'
          's=1 t=0 k=start a=- v=- late=- fg=1\n'
          's=1 t=5000 k=fine a=4.0 v=13.4 late=900 fg=1\n'
          's=1 t=10000 k=fine a=4.0 v=13.4 late=900 fg=1\n'
          's=1 t=500000 k=fine a=4.0 v=0 late=900 fg=0\n');
      final r = open(kTestRecordWriter);
      r.count;
      fine(r, 1000);
      fine(r, 2000);
      final live = r.count;
      final ofFile = Code15MinimumCount.ofText(r.readAll());
      expect(
          [live.movingMs, live.movingIntervals, live.unclassifiedIntervals,
           live.stoppedMs, live.stoppedIntervals],
          [ofFile.movingMs, ofFile.movingIntervals, ofFile.unclassifiedIntervals,
           ofFile.stoppedMs, ofFile.stoppedIntervals]);
    });

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
