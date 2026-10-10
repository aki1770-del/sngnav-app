/// Code 15's fix-interval record: what a line can hold, which files it writes,
/// when it says the app is alive, how it yields, what its cap holds, and what
/// its count may say.
///
/// Why, written before the act (2026-10-10). The record exists to take again
/// the one reading of how far apart his phone delivers GPS fixes, on which the
/// tunnel-exit and weak-GPS fix waits. The reading is read by bars fixed
/// before any data, so every old line must keep code 13's exact shape; the
/// record must write only the names main's keeper protects, or the next build
/// deletes it; and its count must never say more than "the minimum is reached".
/// Each is pinned here. The format tests are code 13's own (89ed430
/// test/services/fix_timing_record_test.dart), with every expected string kept.
///
/// What they do NOT hold: anything on a device, his phone's cadence, or
/// whether a Dart timer runs on his phone in the background.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/code13_record_cleanup.dart';
import 'package:sngnav_app/services/code15_fix_interval_record.dart';
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/services/fix_interval_record_keeper.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('code15_record_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Code15FixIntervalRecord open({int maxBytes = kCode15RecordMaxBytes}) =>
      Code15FixIntervalRecord(directory: dir, maxBytes: maxBytes);

  bool fine(Code15FixIntervalRecord r, int s, {int share = 1}) => r.record(
        share: share,
        msSinceStreamStart: s * 1000,
        kind: FixEventKind.fine,
        accuracyMeters: 12.6,
        reportedSpeedMps: 16.5,
        lateMs: 340,
        appInFront: true,
      );

  List<String> linesOf(Code15FixIntervalRecord r) =>
      r.readAll().split('\n').where((l) => l.isNotEmpty).toList();

  group('code 13\'s line shapes, kept exactly (89ed430 tests, same strings)', () {
    test('a position line holds the share, the time since its stream, the '
        'kind, truncated accuracy and speed, lateness and front', () {
      expect(
        formatFixTimingLine(
          share: 3,
          msSinceStreamStart: 15040,
          kind: FixEventKind.coarse,
          accuracyMeters: 304.9,
          reportedSpeedMps: 16.5,
          lateMs: 850,
          appInFront: false,
        ),
        's=3 t=15040 k=coarse a=304.9 v=16.5 late=850 fg=0',
      );
    });

    test('an unavailable event is its kind alone', () {
      final line = formatFixTimingLine(
        share: 1,
        msSinceStreamStart: 5000,
        kind: FixEventKind.unavailable,
        appInFront: true,
      );
      expect(line, 's=1 t=5000 k=unavail a=- v=- late=- fg=1');
      expect(kCode15LinePattern.hasMatch(line), isTrue);
    });

    test('a missing, negative or non-finite value is written as "-"', () {
      for (final v in [null, -1.0, double.nan, double.infinity]) {
        final line = formatFixTimingLine(
          share: 1,
          msSinceStreamStart: 0,
          kind: FixEventKind.fine,
          accuracyMeters: v,
          reportedSpeedMps: v,
          appInFront: true,
        );
        expect(line, contains('a=- v=-'), reason: '$v');
        expect(kCode15LinePattern.hasMatch(line), isTrue, reason: line);
      }
    });

    test('every kind writes a line the whitelist accepts, within the longest '
        'line the cap keeps in hand', () {
      for (final k in FixEventKind.values) {
        final line = formatFixTimingLine(
          share: 12,
          msSinceStreamStart: 10812345,
          kind: k,
          accuracyMeters: 9999,
          reportedSpeedMps: 70,
          lateMs: -1200,
          appInFront: true,
        );
        expect(kCode15LinePattern.hasMatch(line), isTrue, reason: line);
        expect(line.length, lessThanOrEqualTo(kCode15MaxLineBytes));
      }
      for (final k in Code15MarkKind.values) {
        final line = formatCode15Mark(
            share: 99, msSinceStreamStart: 999999999, kind: k);
        expect(line.length, lessThanOrEqualTo(kCode15MaxLineBytes));
      }
    });

    test('speed: truncated to 0.1 m/s, an exact zero written apart (named '
        'cases and a sweep)', () {
      String v(double reported) => RegExp(r' v=(\S+) ')
          .firstMatch(formatFixTimingLine(
            share: 1,
            msSinceStreamStart: 0,
            kind: FixEventKind.fine,
            accuracyMeters: 10,
            reportedSpeedMps: reported,
            appInFront: true,
          ))!
          .group(1)!;
      expect(v(2.5), '2.5');
      expect(v(2.96), '2.9');
      expect(v(2.999), '2.9');
      expect(v(3.0), '3.0');
      expect(v(3.04), '3.0');
      expect(v(0.0), '0');
      expect(v(0.03), '0.0');
      expect(v(0.1), '0.1');
      expect(v(16.5), '16.5');
      for (var i = 0; i <= 20000; i++) {
        final reported = i / 1000.0;
        final recorded = double.parse(v(reported));
        expect(recorded, lessThanOrEqualTo(reported), reason: '$reported');
        expect(reported - recorded, lessThan(0.1 + 1e-9), reason: '$reported');
        if (recorded >= 3.0) expect(reported, greaterThan(2.5));
        expect(v(reported) == '0', reported == 0, reason: '$reported');
      }
    });

    test('accuracy: truncated to 0.1 m, never above what was reported', () {
      String a(double reported) => RegExp(r' a=(\S+) ')
          .firstMatch(formatFixTimingLine(
            share: 1,
            msSinceStreamStart: 0,
            kind: FixEventKind.fine,
            accuracyMeters: reported,
            appInFront: true,
          ))!
          .group(1)!;
      expect(a(14.0), '14.0');
      expect(a(24.99), '24.9');
      expect(a(304.9), '304.9');
      for (var i = 0; i <= 50000; i += 7) {
        final reported = i / 100.0;
        final recorded = double.parse(a(reported));
        expect(recorded, lessThanOrEqualTo(reported), reason: '$reported');
        expect(reported - recorded, lessThan(0.1 + 1e-9), reason: '$reported');
      }
    });

    test('end, launch, pause and resume: one shape each, as code 13 wrote '
        'them', () {
      expect(formatFixTimingEnd(share: 3, msSinceStreamStart: 15040),
          's=3 t=15040 k=end');
      expect(kFixTimingLaunchLine, 's=0 t=0 k=launch');
      expect(kFixTimingPauseLine, 's=0 t=0 k=pause');
      expect(kFixTimingResumeLine, 's=0 t=0 k=resume');
    });

    test('code 13\'s whitelist is kept verbatim (89ed430 :81-86)', () {
      expect(
        kFixTimingLinePattern.pattern,
        r'^(s=\d+ t=\d+ k=(start|fine|coarse|noacc|unavail) a=(\d+\.\d|-) '
        r'v=(0|\d+\.\d|-) late=(-?\d+|-) fg=[01]'
        r'|s=\d+ t=\d+ k=end'
        r'|s=0 t=0 k=(launch|pause|resume))$',
      );
    });
  });

  group('the whitelist gains exactly four kinds: alive, leave, back, appstop',
      () {
    final code13Lines = [
      's=3 t=15040 k=coarse a=304.9 v=16.5 late=850 fg=0',
      's=1 t=5000 k=unavail a=- v=- late=- fg=1',
      's=1 t=0 k=start a=- v=- late=- fg=1',
      's=1 t=5 k=noacc a=- v=0 late=-3 fg=0',
      's=3 t=15040 k=end',
      's=0 t=0 k=launch',
      's=0 t=0 k=pause',
      's=0 t=0 k=resume',
    ];
    final notLines = [
      's=1 t=0 k=launch',
      's=0 t=5 k=launch',
      's=2 t=5 k=end a=- v=- late=- fg=1',
      's=2 t=5 k=end fg=1',
      's=2 t=5 k=stop',
      's=2 t=5 k=killed',
      's=2 t=5 k=end lat=39.7186',
      's=2 t=5 k=fine a=10.0 v=15.0 late=300 fg=1 39.7186,140.1024',
      's=2 t=5 k=unavail a=- v=- late=- fg=1 GPS stream error: x',
      '2026-10-06T08:00:00Z s=2 t=5 k=end',
      '',
      's=2 t=5 k=alive fg=1',
      's=2 t=5 k=leave a=- v=- late=- fg=0',
      's=2 t=5 k=back 2026-10-10T05:00:00Z',
      's=2 k=alive',
      's=2 t=5 k=alived',
      's=2 t=5 k=gone',
      's=2 t=5 k=appstop fg=0',
      's=0 t=0 k=appstop 2026-10-10T07:00:00Z',
      's=2 t=5 k=appstopped',
      's=2 t=5 k=app_stop',
    ];

    test('every code 13 line is read exactly as before, by both whitelists',
        () {
      for (final l in code13Lines) {
        expect(kFixTimingLinePattern.hasMatch(l), isTrue, reason: l);
        expect(kCode15LinePattern.hasMatch(l), isTrue, reason: l);
      }
      for (final l in notLines) {
        expect(kFixTimingLinePattern.hasMatch(l), isFalse, reason: l);
      }
    });

    test('the new shapes are `s=N t=N k=<kind>` for exactly these four, and '
        'code 15\'s whitelist refuses every variant', () {
      expect(Code15MarkKind.values.map((k) => k.token).toList(),
          ['alive', 'leave', 'back', 'appstop']);
      for (final k in Code15MarkKind.values) {
        final line =
            formatCode15Mark(share: 4, msSinceStreamStart: 61234, kind: k);
        expect(line, 's=4 t=61234 k=${k.token}');
        expect(kCode15LinePattern.hasMatch(line), isTrue, reason: line);
        expect(kFixTimingLinePattern.hasMatch(line), isFalse,
            reason: 'code 13\'s whitelist must not have grown: $line');
      }
      for (final l in notLines) {
        expect(kCode15LinePattern.hasMatch(l), isFalse, reason: l);
      }
    });

    test('the shape is the one the reading\'s ending classifier parses: '
        r'^s=(\d+) t=(\d+) k=(alive|leave|back|appstop)$', () {
      // Retyped from the classifier's NEW_KINDS_RE, version 2 (the 2026-10-10
      // safety ruling, evidence/classify_endings.py).
      final reader =
          RegExp(r'^s=(\d+) t=(\d+) k=(alive|leave|back|appstop)$');
      for (final k in Code15MarkKind.values) {
        final line =
            formatCode15Mark(share: 7, msSinceStreamStart: 1200, kind: k);
        final m = reader.firstMatch(line);
        expect(m, isNotNull, reason: line);
        expect(m!.group(3), k.token);
      }
    });

    test('appstop: one shape, accepted by code 15\'s whitelist and refused by '
        'code 13\'s', () {
      const line = 's=4 t=61234 k=appstop';
      expect(
          formatCode15Mark(
              share: 4, msSinceStreamStart: 61234, kind: Code15MarkKind.appstop),
          line);
      expect(kCode15LinePattern.hasMatch(line), isTrue);
      expect(kFixTimingLinePattern.hasMatch(line), isFalse);
    });

    test('appstop is written only by recordAppStop: recordLifecycle refuses it, '
        'as it refuses alive', () {
      final r = open();
      expect(
          r.recordLifecycle(
              share: 2, msSinceStreamStart: 9000, kind: Code15MarkKind.appstop),
          isFalse);
      expect(r.hasLines, isFalse);
      expect(r.recordAppStop(share: 2, msSinceStreamStart: 9000), isTrue);
      expect(linesOf(r), ['s=2 t=9000 k=appstop']);
    });

    test('a stopped or a full record writes no appstop', () {
      final r = open();
      r.stop();
      expect(r.recordAppStop(share: 1, msSinceStreamStart: 5000), isFalse);
      expect(r.readAll(), isNot(contains('appstop')));
      final small = open(maxBytes: 256);
      small.resume();
      while (fine(small, 1)) {}
      expect(small.full, isTrue);
      expect(small.recordAppStop(share: 1, msSinceStreamStart: 5000), isFalse);
      expect(small.readAll(), isNot(contains('appstop')));
    });
  });

  group('it writes exactly the keeper\'s names (no substitute)', () {
    test('the names it writes are the keeper\'s list, not retyped', () {
      expect(Code15FixIntervalRecord.fileNames, same(kCode15RecordFileNames));
      final r = open();
      expect(r.file.path, '${dir.path}/${kCode15RecordFileNames[0]}');
      expect(r.stoppedFile.path, '${dir.path}/${kCode15RecordFileNames[1]}');
    });

    test('every write and stop it can make creates only those names, and '
        'after a stop exactly those names', () async {
      final r = (await openCode15FixIntervalRecord(directory: dir))!;
      r.record(share: 1, msSinceStreamStart: 0, kind: FixEventKind.start,
          appInFront: true);
      fine(r, 5);
      r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 11000);
      r.recordLifecycle(
          share: 1, msSinceStreamStart: 12000, kind: Code15MarkKind.leave);
      r.recordLifecycle(
          share: 1, msSinceStreamStart: 13000, kind: Code15MarkKind.back);
      r.recordEnd(share: 1, msSinceStreamStart: 14000);
      r.recordAppStop(share: 2, msSinceStreamStart: 3000);
      r.stop();
      final names = dir
          .listSync()
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toSet();
      expect(names, kCode15RecordFileNames.toSet());
      r.resume();
      r.deleteRecordOnHisTap();
      expect(dir.listSync(), isEmpty,
          reason: 'resume removes the marker, delete the record');
    });

    test('its names are disjoint from code 13\'s, which main deletes on every '
        'launch', () {
      expect(
        kCode15RecordFileNames.toSet().intersection(
            kCode13RecordFileNames.toSet()),
        isEmpty,
      );
    });

    test('main\'s launch path, run three times over what it wrote, leaves it '
        'byte for byte', () async {
      final r = (await openCode15FixIntervalRecord(directory: dir))!;
      fine(r, 1);
      r.stop();
      final before = {
        for (final n in kCode15RecordFileNames)
          n: File('${dir.path}/$n').readAsBytesSync(),
      };
      for (var i = 0; i < 3; i++) {
        await launchRecordHousekeeping(directory: dir);
      }
      for (final n in kCode15RecordFileNames) {
        expect(File('${dir.path}/$n').readAsBytesSync(), before[n],
            reason: '$n changed');
      }
    });
  });

  group('alive: one line only when the share has been quiet for the '
      'threshold', () {
    test('the threshold and period are the named constants: 6 s on a 3 s '
        'tick, so the first alive line comes under 9 s after the last line',
        () {
      expect(kCode15AliveThreshold, const Duration(seconds: 6));
      expect(kCode15AliveTimerPeriod, const Duration(seconds: 3));
    });

    test('quiet under the threshold writes nothing; at it, one alive line; '
        'then one per threshold', () {
      final r = open();
      r.record(share: 1, msSinceStreamStart: 0, kind: FixEventKind.start,
          appInFront: true);
      fine(r, 5); // t = 5000
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 8000), isFalse);
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 10999),
          isFalse);
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 11000), isTrue);
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 14000),
          isFalse);
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 17000), isTrue);
      expect(linesOf(r).sublist(2), [
        's=1 t=11000 k=alive',
        's=1 t=17000 k=alive',
      ]);
    });

    test('fixes every 5 s write no alive line at all, on a 3 s tick', () {
      final r = open();
      r.record(share: 1, msSinceStreamStart: 0, kind: FixEventKind.start,
          appInFront: true);
      var nextFix = 5000;
      for (var t = 0; t <= 600000; t += 1000) {
        if (t == nextFix) {
          fine(r, t ~/ 1000);
          nextFix += 5000;
        }
        if (t % 3000 == 0) r.recordAliveIfQuiet(share: 1, msSinceStreamStart: t);
      }
      expect(r.readAll(), isNot(contains('k=alive')));
    });

    test('any line of the share resets the quiet: a leave or back counts', () {
      final r = open();
      fine(r, 0);
      r.recordLifecycle(
          share: 1, msSinceStreamStart: 5000, kind: Code15MarkKind.leave);
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 9000), isFalse);
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 11000), isTrue);
    });

    test('a new share is measured from its own start, never from the last '
        'share\'s line', () {
      final r = open();
      fine(r, 100, share: 1); // t = 100000 in share 1
      expect(r.recordAliveIfQuiet(share: 2, msSinceStreamStart: 2000), isFalse);
      expect(r.recordAliveIfQuiet(share: 2, msSinceStreamStart: 6000), isTrue);
    });

    test('alive obeys his stop and the cap, as every line does', () {
      final r = open();
      r.stop();
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 60000), isFalse);
      final small = open(maxBytes: 256);
      small.resume();
      while (fine(small, 1)) {}
      expect(small.recordAliveIfQuiet(share: 1, msSinceStreamStart: 999999),
          isFalse);
    });

    test('leave and back carry the share and its t, and the alive kind is the '
        'timer\'s alone', () {
      final r = open();
      expect(
          r.recordLifecycle(
              share: 3, msSinceStreamStart: 42000, kind: Code15MarkKind.leave),
          isTrue);
      expect(
          r.recordLifecycle(
              share: 3, msSinceStreamStart: 99000, kind: Code15MarkKind.back),
          isTrue);
      expect(
          r.recordLifecycle(
              share: 3, msSinceStreamStart: 99500, kind: Code15MarkKind.alive),
          isFalse);
      expect(linesOf(r), ['s=3 t=42000 k=leave', 's=3 t=99000 k=back']);
    });
  });

  group('a pause he makes says itself, and it yields to him (code 13\'s '
      'rules)', () {
    test('stop writes pause first and nothing after; resume writes resume',
        () {
      final r = open();
      fine(r, 1);
      r.stop();
      expect(r.stopped, isTrue);
      expect(fine(r, 2), isFalse);
      r.resume();
      expect(fine(r, 3), isTrue);
      expect(linesOf(r), [
        startsWith('s=1 t=1000 k=fine'),
        kFixTimingPauseLine,
        kFixTimingResumeLine,
        startsWith('s=1 t=3000 k=fine'),
      ]);
    });

    test('the stop holds across reopening, as at a relaunch, and no launch is '
        'written while stopped', () async {
      final first = (await openCode15FixIntervalRecord(directory: dir))!;
      first.stop();
      final before = first.readAll();
      final again = (await openCode15FixIntervalRecord(directory: dir))!;
      expect(again.stopped, isTrue);
      expect(again.readAll(), before);
    });

    test('each opening writes the launch line, as at each process start',
        () async {
      final first = (await openCode15FixIntervalRecord(directory: dir))!;
      fine(first, 1);
      final again = (await openCode15FixIntervalRecord(directory: dir))!;
      final lines = linesOf(again);
      expect(lines.first, kFixTimingLaunchLine);
      expect(lines.last, kFixTimingLaunchLine);
    });

    test('his delete removes every line and keeps whether it records: a '
        'stopped record stays stopped (code 13\'s rule)', () {
      final r = open();
      fine(r, 1);
      r.stop();
      r.deleteRecordOnHisTap();
      expect(r.hasLines, isFalse);
      expect(r.stopped, isTrue, reason: 'a delete restarted the record');
      expect(fine(r, 2), isFalse);
      r.resume();
      r.deleteRecordOnHisTap();
      expect(fine(r, 3), isTrue, reason: 'still recording after a delete');
    });
  });

  group('the cap: sized against his measured day, and it never drops a line',
      () {
    test('the nominal line is a real line of the record, and longer than a '
        'typical one', () {
      expect(kCode15LinePattern.hasMatch(kCode15NominalLine), isTrue);
      expect(kCode15NominalLine, 's=9 t=17400000 k=fine a=12.3 v=13.4 '
          'late=1234 fg=0');
      expect(kCode15NominalLineBytes, 51);
      final typical = formatFixTimingLine(
        share: 2,
        msSinceStreamStart: 1800000,
        kind: FixEventKind.fine,
        accuracyMeters: 4.5,
        reportedSpeedMps: 13.4,
        lateMs: 250,
        appInFront: false,
      );
      expect(typical.length + 1, lessThan(kCode15NominalLineBytes));
    });

    test('it holds his measured day, 4 h 50 min of sharing at 5 s, at the '
        'nominal line', () {
      final linesPerDay = kCode15HisMeasuredShareDay.inSeconds ~/
          kCode15DesignFixPeriod.inSeconds;
      expect(linesPerDay, 3480);
      expect(linesPerDay * kCode15NominalLineBytes + kCode15MaxLineBytes,
          lessThanOrEqualTo(kCode15RecordMaxBytes),
          reason: 'the cap does not hold his day');
    });

    test('the hours in the words are derived from the cap, the fix period and '
        'the nominal line, rounded down to the half hour', () {
      final hours = kCode15RecordMaxBytes /
          (kCode15NominalLineBytes *
              (3600 / kCode15DesignFixPeriod.inSeconds));
      expect(kCode15RecordHours, (hours * 2).floor() / 2);
      expect(kCode15RecordHours, lessThanOrEqualTo(hours));
      expect(kCode15RecordHours,
          greaterThanOrEqualTo(kCode15HisMeasuredShareDay.inMinutes / 60 - 0.5),
          reason: 'the words would promise less than his day');
      expect(kCode15RecordHoursText, '5');
      expect(kCode15RecordCapKbText, '192');
    });

    test('at its cap it stops and keeps every line it wrote, the first one '
        'included; it never drops a line to make room', () {
      final r = open(maxBytes: 2048);
      var written = 0;
      for (var s = 0; s < 1000; s++) {
        if (fine(r, s)) written++;
      }
      expect(r.full, isTrue);
      final lines = linesOf(r);
      expect(lines.length, written);
      expect(lines.first, startsWith('s=1 t=0 '));
      expect(r.lengthBytes, lessThanOrEqualTo(2048));
      expect(r.recordAliveIfQuiet(share: 1, msSinceStreamStart: 9999999),
          isFalse);
      expect(r.recordEnd(share: 1, msSinceStreamStart: 9999999), isFalse);
    });

    test('a full record at the real cap goes in one share, whole, under a '
        'header that says how many lines and bytes it holds', () {
      final r = open();
      for (var s = 0; s < 100000; s++) {
        if (!fine(r, s)) break;
      }
      expect(r.full, isTrue, reason: 'control: the record reached its cap');
      expect(r.lengthBytes, lessThanOrEqualTo(kCode15RecordMaxBytes));
      final text = r.readAll();
      final payload = composeCode15SharePayload(
        recordText: text,
        operatingSystem: 'android',
        exportedAt: DateTime.utc(2026, 10, 10, 8),
      );
      expect(payload.endsWith(text), isTrue, reason: 'the share cut the record');
      expect(payload, contains('exported: 2026-10-10T08:00:00.000Z'));
      expect(payload, contains('lines: ${linesOf(r).length}\n'));
      expect(payload, contains('bytes: ${r.lengthBytes}\n'));
      expect(payload.length,
          lessThanOrEqualTo(kCode15RecordMaxBytes + kCode15HeaderBudget));
    });

    test('the share text says there is no record when it holds no fix line',
        () {
      String payload(String text) => composeCode15SharePayload(
          recordText: text, operatingSystem: 'android',
          exportedAt: DateTime.utc(2026, 10, 10));
      const none = '測位間隔の記録はありません';
      const markers = '$kFixTimingLaunchLine\n$kFixTimingPauseLine\n';
      expect(payload(markers), contains(none));
      expect(payload(markers).endsWith(markers), isTrue);
      final line = formatFixTimingLine(share: 1, msSinceStreamStart: 1,
          kind: FixEventKind.coarse, accuracyMeters: 300, appInFront: true);
      expect(payload('$markers$line\n'), isNot(contains(none)));
    });

    test('the error log\'s trim never touches the record: separate files', () {
      final r = open();
      for (var s = 0; s < 50; s++) {
        fine(r, s);
      }
      final before = r.readAll();
      final log =
          LocalErrorLog(file: File('${dir.path}/error_log.txt'), maxBytes: 1024);
      for (var i = 0; i < 200; i++) {
        log.record(StateError('e$i ${'x' * 40}'), null);
      }
      expect(r.readAll(), before);
    });
  });

  group('the count: the bars\' data minimum, and nothing more', () {
    String fix(int s, int tMs, String v, {String kind = 'fine'}) =>
        's=$s t=$tMs k=$kind a=5.0 v=$v late=200 fg=0';

    /// [moving] intervals at 5 s and 13.4 m/s, then [stopped] at 5 s and 0.
    String drive({int share = 1, int moving = 360, int stopped = 61,
        int startT = 0}) {
      final b = StringBuffer('s=$share t=$startT k=start a=- v=- late=- fg=1\n');
      var t = startT;
      for (var i = 0; i <= moving; i++) {
        t += 5000;
        b.writeln(fix(share, t, '13.4'));
      }
      t += 5000;
      b.writeln(fix(share, t, '0.0'));
      for (var i = 0; i < stopped; i++) {
        t += 5000;
        b.writeln(fix(share, t, '0'));
      }
      return b.toString();
    }

    test('30 min and 300 intervals moving, plus 5 min and 30 intervals '
        'stopped in runs of 6 or more: the minimum is reached', () {
      final c = Code15MinimumCount.ofText(drive());
      expect(c.movingIntervals, 360);
      expect(c.movingMs, 360 * 5000);
      expect(c.stoppedIntervals, 61);
      expect(c.stoppedMs, 61 * 5000);
      expect(c.unclassifiedIntervals, 1, reason: 'the 13.4 to 0.0 interval');
      expect(c.minimumReached, isTrue);
    });

    test('short of any one part, it is not', () {
      expect(Code15MinimumCount.ofText(drive(moving: 359)).minimumReached,
          isFalse, reason: '29 min 55 s moving');
      expect(Code15MinimumCount.ofText(drive(stopped: 59)).minimumReached,
          isFalse, reason: '4 min 55 s stopped');
    });

    test('stopped intervals count only inside runs of 6 or more', () {
      final b = StringBuffer();
      var t = 0;
      for (var run = 0; run < 20; run++) {
        for (var i = 0; i < 6; i++) {
          t += 5000;
          b.writeln(fix(1, t, '0'));
        }
        t += 5000;
        b.writeln(fix(1, t, '4.0')); // breaks the run
      }
      // Each run of 6 fixes is 5 STOPPED intervals: under 6, so none count.
      expect(Code15MinimumCount.ofText(b.toString()).stoppedIntervals, 0);
    });

    test('crawling more than a fifth of the moving intervals keeps it short',
        () {
      final b = StringBuffer(drive());
      var t = 10000000;
      b.writeln(fix(1, t, '13.4'));
      for (var i = 0; i < 80; i++) {
        t += 5000;
        b.writeln(fix(1, t, i.isEven ? '1.5' : '2.0'));
      }
      final c = Code15MinimumCount.ofText(b.toString());
      expect(c.unclassifiedIntervals, greaterThan(0.2 * c.movingIntervals));
      expect(c.minimumReached, isFalse);
    });

    test('an interval over 12 s is never counted as moving time, and a clock '
        'step counts as unclassified', () {
      final c = Code15MinimumCount.ofText([
        fix(1, 0, '13.4'),
        fix(1, 13000, '13.4'), // over 12 s: not counted
        fix(1, 18000, '13.4'), // counted
        fix(1, 17000, '13.4'), // a step back in t
      ].join('\n'));
      expect(c.movingIntervals, 1);
      expect(c.movingMs, 5000);
      expect(c.unclassifiedIntervals, 1);
    });

    test('no interval or run crosses a launch, pause, resume, end or a change '
        'of share', () {
      for (final cut in [
        kFixTimingLaunchLine,
        kFixTimingPauseLine,
        kFixTimingResumeLine,
      ]) {
        final c = Code15MinimumCount.ofText(
            [fix(1, 0, '13.4'), cut, fix(1, 5000, '13.4')].join('\n'));
        expect(c.movingIntervals, 0, reason: cut);
      }
      final ended = Code15MinimumCount.ofText(
          [fix(1, 0, '13.4'), 's=1 t=1000 k=end', fix(1, 5000, '13.4')]
              .join('\n'));
      expect(ended.movingIntervals, 0);
      final changed = Code15MinimumCount.ofText(
          [fix(1, 0, '13.4'), fix(2, 5000, '13.4')].join('\n'));
      expect(changed.movingIntervals, 0);
    });

    test('a trailing span over 12 s counts as one unclassified interval, at '
        'an ending and while the share is still open', () {
      final open = Code15MinimumCount.ofText(
          [fix(1, 0, '0'), 's=1 t=6000 k=alive', 's=1 t=12001 k=alive']
              .join('\n'));
      expect(open.unclassifiedIntervals, 1);
      final ended = Code15MinimumCount.ofText([
        fix(1, 0, '0'),
        's=1 t=13000 k=end',
      ].join('\n'));
      expect(ended.unclassifiedIntervals, 1);
    });

    test('alive, leave and back lines never end an interval', () {
      final c = Code15MinimumCount.ofText([
        fix(1, 0, '13.4'),
        's=1 t=2000 k=leave',
        's=1 t=3000 k=back',
        fix(1, 5000, '13.4'),
      ].join('\n'));
      expect(c.movingIntervals, 1);
      expect(c.movingMs, 5000);
    });

    test('the record keeps the count as it writes, equal to a fresh count of '
        'its file', () {
      final r = open();
      r.record(share: 1, msSinceStreamStart: 0, kind: FixEventKind.start,
          appInFront: true);
      for (var i = 1; i <= 400; i++) {
        r.record(share: 1, msSinceStreamStart: i * 5000,
            kind: FixEventKind.fine, accuracyMeters: 5, reportedSpeedMps: 13.4,
            lateMs: 200, appInFront: false);
      }
      for (var i = 401; i <= 470; i++) {
        r.record(share: 1, msSinceStreamStart: i * 5000,
            kind: FixEventKind.fine, accuracyMeters: 5, reportedSpeedMps: 0,
            lateMs: 200, appInFront: false);
      }
      final fresh = Code15MinimumCount.ofText(r.readAll());
      expect(r.count.movingIntervals, fresh.movingIntervals);
      expect(r.count.stoppedIntervals, fresh.stoppedIntervals);
      expect(r.count.unclassifiedIntervals, fresh.unclassifiedIntervals);
      expect(r.count.minimumReached, isTrue);
      expect(open().count.minimumReached, isTrue, reason: 'reopened');
      r.deleteRecordOnHisTap();
      expect(r.count.minimumReached, isFalse, reason: 'a delete keeps a count');
    });
  });

  group('the count, as the 2026-10-10 safety ruling fixed it (item 2), on its '
      'own case records (test/fixtures/code15_count, copied byte for byte)',
      () {
    Code15MinimumCount fixture(String name) => Code15MinimumCount.ofText(
        File('test/fixtures/code15_count/$name').readAsStringSync());

    test('b1m: a backward clock step behind a leave line makes the last moving '
        'interval a clock step, so the minimum is NOT reached', () {
      final c = fixture('b1m_margin_record.txt');
      expect(c.movingIntervals, 299);
      expect(c.unclassifiedIntervals, 1);
      expect(c.minimumReached, isFalse,
          reason: 'the card would say "reached" where the bars do not');
    });

    test('b3: a clock step inside the trailing span counts it', () {
      expect(fixture('b3_clock_step_in_tail.txt').unclassifiedIntervals, 1);
    });

    test('b2: parked with fixes 15 s apart, every STOPPED interval stays in its '
        'run, as the bars count it', () {
      final c = fixture('b2_parked_15s.txt');
      expect(c.stoppedIntervals, 40);
      expect(c.stoppedMs, 600000);
    });

    test('three STOPPED intervals at 5 s, one at 15 s, then three at 5 s: one '
        'run of 7', () {
      final lines = <String>[];
      var t = 0;
      for (final step in [5000, 5000, 5000, 15000, 5000, 5000, 5000]) {
        lines.add('s=1 t=$t k=fine a=5.0 v=0 late=200 fg=0');
        t += step;
      }
      lines.add('s=1 t=$t k=fine a=5.0 v=0 late=200 fg=0');
      final c = Code15MinimumCount.ofText(lines.join('\n'));
      expect(c.stoppedIntervals, 7);
      expect(c.stoppedMs, 45000);
    });

    test('appstop closes the segment: no interval crosses it, and the '
        'trailing span counts at it, as at every ending', () {
      final crossed = Code15MinimumCount.ofText([
        's=1 t=0 k=fine a=5.0 v=13.4 late=200 fg=0',
        's=1 t=5000 k=appstop',
        's=1 t=10000 k=fine a=5.0 v=13.4 late=200 fg=0',
      ].join('\n'));
      expect(crossed.movingIntervals, 0,
          reason: 'an interval was formed across the app\'s own ending');
      final tail = Code15MinimumCount.ofText([
        's=1 t=0 k=fine a=5.0 v=0 late=200 fg=0',
        's=1 t=13000 k=appstop',
        's=1 t=40000 k=alive',
      ].join('\n'));
      expect(tail.unclassifiedIntervals, 1,
          reason: 'the 13 s fix-less tail ends at appstop, once');
    });
  });

  test('the count starts before the first write: a first write that is a fix '
      'is counted once, never twice (the 2026-10-10 boundary ruling, 1.2)', () {
    final r = open();
    // No launch first: the first write after construction is a fix.
    r.record(share: 1, msSinceStreamStart: 5000, kind: FixEventKind.fine,
        accuracyMeters: 5, reportedSpeedMps: 13.4, lateMs: 200,
        appInFront: false);
    r.record(share: 1, msSinceStreamStart: 10000, kind: FixEventKind.fine,
        accuracyMeters: 5, reportedSpeedMps: 13.4, lateMs: 200,
        appInFront: false);
    expect(r.count.movingIntervals, 1,
        reason: 'the file holds two fixes, so one interval');
    expect(r.count.movingIntervals,
        Code15MinimumCount.ofText(r.readAll()).movingIntervals);
  });
}
