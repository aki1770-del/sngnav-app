/// The fix-timing record (code 13 only): what a line can hold, how it yields,
/// and that nothing cuts it.
///
/// Why, written before the act (2026-10-06). The record exists to read how far
/// apart the Chair's phone delivers GPS fixes, which decides what the next
/// change tells a driver in unexpected snow. A record that a cap or a trim
/// silently cuts measures nothing; a line that could carry a coordinate or an
/// exception's text would make its disclosure false; a record that does not
/// stop when he says stop makes him part of the instrument. These pin each.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/services/fix_timing_record.dart';
import 'package:sngnav_app/services/log_share.dart' show kLogShareMaxChars;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fix_timing_'));
  tearDown(() => dir.deleteSync(recursive: true));

  FixTimingRecord open({int maxBytes = kFixTimingRecordMaxBytes}) =>
      FixTimingRecord(
        file: File('${dir.path}/$kFixTimingRecordFileName'),
        maxBytes: maxBytes,
      );

  bool fine(FixTimingRecord r, int s, {int share = 1}) => r.record(
        share: share,
        msSinceStreamStart: s * 1000,
        kind: FixEventKind.fine,
        accuracyMeters: 12.6,
        reportedSpeedMps: 16.5,
        lateMs: 340,
        appInFront: true,
      );

  group('a line', () {
    test('holds the share, the time since its stream, the kind, rounded '
        'accuracy and speed, lateness and whether the app was in front', () {
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
      expect(kFixTimingLinePattern.hasMatch(line), isTrue);
    });

    test('a missing, negative or non-finite value is written as "-", never a '
        'number nobody measured', () {
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
        expect(kFixTimingLinePattern.hasMatch(line), isTrue, reason: line);
      }
    });

    test('every kind writes a line the whitelist accepts, and nothing else', () {
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
        expect(kFixTimingLinePattern.hasMatch(line), isTrue, reason: line);
        expect(line.length, lessThanOrEqualTo(kFixTimingMaxLineBytes));
      }
    });
  });

  group('speed is truncated to 0.1 m/s, never above what the phone reported '
      '(V16: a recorded 3.0 is strictly over 2.5)', () {
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

    test('named cases', () {
      expect(v(2.5), '2.5');
      expect(v(2.96), '2.9');
      expect(v(2.999), '2.9');
      expect(v(3.0), '3.0');
      expect(v(3.04), '3.0');
      expect(v(0.0), '0', reason: 'an exact reported zero is written apart');
      expect(v(0.03), '0.0', reason: 'a creep must never read as a stop');
      expect(v(0.1), '0.1');
      expect(v(16.5), '16.5');
    });

    test('over a sweep, the recorded value is never above the reported one, and '
        'a recorded value of 3.0 or more never stands for 2.5 or less', () {
      for (var i = 0; i <= 20000; i++) {
        final reported = i / 1000.0; // 0.000 .. 20.000 m/s
        final recorded = double.parse(v(reported));
        expect(recorded, lessThanOrEqualTo(reported), reason: '$reported');
        expect(reported - recorded, lessThan(0.1 + 1e-9), reason: '$reported');
        if (recorded >= 3.0) {
          expect(reported, greaterThan(2.5), reason: '$reported');
        }
        expect(v(reported) == '0', reported == 0,
            reason: '$reported: "0" must mean an exact reported zero');
      }
    });
  });

  test('accuracy is truncated to 0.1 m, never above what was reported, so the '
      'exit-accuracy criterion can be read fail-closed', () {
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

  group('it yields to him', () {
    test('stop holds: nothing is written while stopped, and the stop survives '
        'reopening; resume writes again', () {
      final r = open();
      expect(fine(r, 1), isTrue);
      r.stop();
      expect(fine(r, 2), isFalse);
      final again = open();
      expect(again.stopped, isTrue, reason: 'the stop did not survive');
      expect(fine(again, 3), isFalse);
      again.resume();
      expect(fine(again, 4), isTrue);
      expect(again.readAll().split('\n').where((l) => l.isNotEmpty).length, 2);
    });

    test('delete removes every line and changes nothing else', () {
      final r = open();
      fine(r, 1);
      fine(r, 2);
      r.delete();
      expect(r.hasLines, isFalse);
      expect(r.readAll(), '');
      expect(fine(r, 3), isTrue, reason: 'still recording after a delete');
    });
  });

  group('nothing cuts it', () {
    test('at its cap it stops and keeps every line it wrote, the first one '
        'included; it never drops a line to make room', () {
      final r = open(maxBytes: 2048);
      var written = 0;
      for (var s = 0; s < 1000; s++) {
        if (fine(r, s)) written++;
      }
      expect(r.full, isTrue);
      final lines = r.readAll().split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.length, written);
      expect(lines.first, startsWith('s=1 t=0 '),
          reason: 'the first line was dropped');
      expect(r.lengthBytes, lessThanOrEqualTo(2048));
      for (final l in lines) {
        expect(kFixTimingLinePattern.hasMatch(l), isTrue, reason: l);
      }
    });

    test('a full record goes in one share, whole: the payload carries every '
        'line, and stays under the share size the app holds to', () {
      final r = open();
      for (var s = 0; s < 100000; s++) {
        if (!fine(r, s)) break;
      }
      expect(r.full, isTrue, reason: 'control: the record reached its cap');
      final text = r.readAll();
      final payload = composeFixTimingSharePayload(
        recordText: text,
        operatingSystem: 'android',
        exportedAt: DateTime.utc(2026, 10, 6, 8),
      );
      expect(payload.endsWith(text), isTrue, reason: 'the share cut the record');
      expect(payload, contains('exported: 2026-10-06T08:00:00.000Z'));
      expect(payload.length, lessThanOrEqualTo(kLogShareMaxChars),
          reason: 'over the share size the app holds to');
      expect(kFixTimingRecordMaxBytes + kFixTimingHeaderBudget,
          lessThanOrEqualTo(kLogShareMaxChars));
    });

    test('the error log\'s trim never touches the record: separate files',
        () {
      final r = open();
      for (var s = 0; s < 50; s++) {
        fine(r, s);
      }
      final before = r.readAll();
      final log = LocalErrorLog(
          file: File('${dir.path}/error_log.txt'), maxBytes: 1024);
      for (var i = 0; i < 200; i++) {
        log.record(StateError('e$i ${'x' * 40}'), null);
      }
      expect(r.readAll(), before);
      expect(r.file.path, isNot(log.file.path));
    });
  });

  test('the file the next build deletes is named here, and is this one', () {
    expect(kFixTimingRecordFileName, 'fix_timing_record.txt');
    expect(kFixTimingStoppedFileName, 'fix_timing_record.stopped');
    expect(open().file.path, endsWith('/fix_timing_record.txt'));
    expect(open().stoppedFile.path, endsWith('/fix_timing_record.stopped'));
  });
}
