/// Code 15: 記録を共有 hands the WHOLE record to the share sheet as a FILE,
/// and every copy made for it is the record too.
///
/// Why, written before the act (2026-10-10). On the emulator, API 30 and API
/// 34, the record shared as text could not reach the share sheet at its cap:
/// the system gave up on a 593,120-byte parcel, nothing was sent, and the app
/// was told nothing while the card said the record could be sent. The record
/// now goes as a file: only a link rides the intent. These pin:
/// - the file handed on is the whole record under its header, its `lines:`
///   and `bytes:` equal to the body, at any size up to the cap;
/// - this app's staging copy is gone as soon as the call returns;
/// - share_plus's copy (`<cache>/share_plus/<name>`), the one the receiver
///   reads, is KEPT after the share: while the call runs, when it returns,
///   and after he is back in the app, so a receiver that opens the link late
///   still reads the whole record (the receiver-copy move, 2026-10-10). It
///   goes at his next 記録を共有, even if that share fails before share_plus
///   is reached;
/// - 記録を消す deletes every copy; the launch path deletes any left over;
/// - copies live only under the cache directory, which Android never backs up
///   or transfers;
/// - a share that cannot be handed on is said, in the ruled words, and the
///   line goes at his next 記録を共有 or 記録を消す.
///
/// HONEST BOUND. A test binding with a fake share sink that copies the file
/// as share_plus 13.3.0 does (Share.kt:297-305). Not the platform share sheet,
/// not a receiver, not a phone. Whether a real receiver opens the link late,
/// and what it then reads, is not shown here (an emulator read).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/code15_fix_interval_record.dart';
import 'package:sngnav_app/services/record_share_file.dart';
import 'package:sngnav_app/widgets/keep_together.dart' show plainOf;

import '../support/fake_alert_actuators.dart';
import '../support/test_record_writer.dart';

const _failedJa = '記録を端末の共有画面に渡せませんでした。何も送られていません。';

/// A share's file name since code 16 (ported from d7c5b6a): the prefix, a
/// token of 8 hex digits, `.txt`. No time of day.
final _shareName = RegExp(r'^sngnav-fix-interval-record-[0-9a-f]{8}\.txt$');
const _failedEn = 'The record could not be handed to the share screen. Nothing was sent.';

JmaObservation _clear() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 8.0,
      humidityPercent: 50,
      windMetersPerSecond: 1.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: 20000,
      observedAtJstKey: '20260115060000',
      fetchedAt: DateTime.utc(2026, 1, 14, 21),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final b = find.byKey(Key(key));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await _settle(tester);
}

/// The status's plain words: it is drawn through KeepTogetherText, so the
/// drawn Text's joiners are removed (the plain words are its label).
String _status(WidgetTester tester) => plainOf(tester
    .widget<Text>(find.descendant(
        of: find.byKey(const Key('code15-record-status'), skipOffstage: false),
        matching: find.byType(Text, skipOffstage: false),
        matchRoot: true))
    .data!);

/// A sink that does what share_plus 13.3.0 does with a file: copy it into
/// `<cache>/share_plus/<name>` before the sheet opens. It records what it was
/// handed, and can hold the call open until [release].
class _FakeSharePlus {
  _FakeSharePlus(this.cache);
  final Directory cache;
  final handed = <String>[];
  final texts = <String>[];
  Completer<void>? hold;
  Object? throwThis;

  Future<void> call(String path) async {
    handed.add(path);
    final f = File(path);
    texts.add(f.readAsStringSync());
    final copy = File('${cache.path}/$kSharePlusCacheDir/${f.uri.pathSegments.last}');
    copy.parent.createSync(recursive: true);
    f.copySync(copy.path);
    if (throwThis != null) throw throwThis!;
    if (hold != null) await hold!.future;
  }
}

void main() {
  late Directory dir;
  late Directory cache;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('code15_share_file_');
    cache = Directory('${dir.path}/cache')..createSync();
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<(Code15FixIntervalRecord, _FakeSharePlus)> boot(
    WidgetTester tester, {
    Locale locale = const Locale('ja'),
    Code15RecordShareSink? sink,
    Directory? cacheDirectory,
    int maxBytes = kCode15RecordMaxBytes,
  }) async {
    final record = Code15FixIntervalRecord(
writer: kTestRecordWriter,
directory: Directory('${dir.path}/files')..createSync(),
        maxBytes: maxBytes);
    final fake = _FakeSharePlus(cache);
    await tester.pumpWidget(SngnavApp(
      locationConsent: true,
      actuators: FakeAlertActuators(),
      locale: locale,
      clock: () => DateTime.utc(2026, 1, 14, 21),
      jmaFetch: () async => JmaSuccess(_clear()),
      code15Record: record,
      code15RecordShareSink: sink ?? fake.call,
      code15ShareCacheDirectory: cacheDirectory ?? cache,
    ));
    await _settle(tester);
    return (record, fake);
  }

  void fill(Code15FixIntervalRecord r, {int lines = 50}) {
    for (var i = 1; i <= lines; i++) {
      if (!r.record(
          share: 1,
          msSinceStreamStart: i * 5000,
          kind: FixEventKind.fine,
          accuracyMeters: 5,
          reportedSpeedMps: 13.4,
          lateMs: 200,
          appInFront: false)) {
        break;
      }
    }
  }

  testWidgets('a FULL record at the real cap goes whole, as one file, under a '
      'header whose lines: and bytes: equal the body', (tester) async {
    final (record, fake) = await boot(tester);
    fill(record, lines: 100000);
    expect(record.full, isTrue, reason: 'control: the record is at its cap');
    await _tap(tester, 'code15-record-share-button');
    expect(fake.handed, hasLength(1));
    final handed = File(fake.handed.single);
    expect(handed.parent.path, '${cache.path}/$kRecordShareStagingDir');
    expect(handed.uri.pathSegments.last, matches(_shareName));
    final text = fake.texts.single;
    final body = record.readAll();
    expect(text.endsWith('---\n$body'), isTrue, reason: 'the file cut the record');
    expect(text, contains('lines: ${'\n'.allMatches(body).length}\n'));
    expect(text, contains('bytes: ${record.lengthBytes}\n'));
    expect(text.length, greaterThan(150006),
        reason: 'control: larger than the largest text IDV saw open on API 34');
    expect(_status(tester), isNot(contains(_failedJa)));
  });

  testWidgets('the staging copy goes when the call returns; share_plus\'s copy, '
      'the one the receiver reads, is kept whole, the app being in front',
      (tester) async {
    final (record, fake) = await boot(tester);
    fill(record);
    final copies = RecordShareFile(cacheDirectory: cache);
    await _tap(tester, 'code15-record-share-button');
    expect(fake.handed, hasLength(1), reason: 'control: the sink was called');
    expect(copies.staged, isEmpty, reason: 'the staging copy outlived the call');
    expect(copies.sharePlusCopies, hasLength(1),
        reason: 'a receiver that opens the link late would read nothing');
    expect(copies.sharePlusCopies.single.readAsStringSync(), fake.texts.single,
        reason: 'the kept copy is the whole file that was handed on');
  });

  testWidgets('while the share call still runs (the app behind the share sheet), '
      'and after he is back in front, share_plus\'s copy is kept',
      (tester) async {
    final (record, fake) = await boot(tester);
    fill(record);
    final copies = RecordShareFile(cacheDirectory: cache);
    fake.hold = Completer<void>();
    final b = find.byKey(const Key('code15-record-share-button'));
    await tester.ensureVisible(b);
    await tester.pump();
    await tester.tap(b);
    await _settle(tester);
    // The sheet covers the app: inactive, hidden.
    for (final s in const [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
    }
    expect(copies.sharePlusCopies, hasLength(1),
        reason: 'the receiver may still be reading: kept while the call runs');
    // The call returns while the app is still behind.
    fake.hold!.complete();
    await _settle(tester);
    expect(copies.staged, isEmpty);
    expect(copies.sharePlusCopies, hasLength(1),
        reason: 'not deleted while the app is not in front');
    // He comes back.
    for (final s in const [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
    }
    await _settle(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _settle(tester);
    expect(copies.sharePlusCopies, hasLength(1),
        reason: 'his return deleted the copy a late receiver reads');
    expect(copies.sharePlusCopies.single.readAsStringSync(), fake.texts.single);
  });

  testWidgets('his next 記録を共有 deletes the last share\'s receiver copy, even '
      'when that share fails before share_plus is reached', (tester) async {
    final (record, fake) = await boot(tester);
    fill(record);
    final copies = RecordShareFile(cacheDirectory: cache);
    await _tap(tester, 'code15-record-share-button');
    expect(copies.sharePlusCopies, hasLength(1), reason: 'control: kept after the share');
    // The next staging write cannot be made: a regular file where the folder was.
    final staging = Directory('${cache.path}/$kRecordShareStagingDir');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    File(staging.path).writeAsStringSync('x');
    await _tap(tester, 'code15-record-share-button');
    expect(fake.handed, hasLength(1), reason: 'control: the second share reached nothing');
    expect(_status(tester).split('\n').first, _failedJa, reason: 'control: said');
    expect(copies.sharePlusCopies, isEmpty,
        reason: 'the last share\'s receiver copy outlived his next 記録を共有');
  });

  testWidgets('記録を消す deletes every copy made for sharing, with the record',
      (tester) async {
    final (record, _) = await boot(tester);
    fill(record);
    final copies = RecordShareFile(cacheDirectory: cache);
    // The receiver copy his share left, kept for a late reader.
    await _tap(tester, 'code15-record-share-button');
    expect(copies.sharePlusCopies, hasLength(1), reason: 'control: kept after the share');
    // A staging copy left on disk too (as if a share were cut short).
    copies.stage('leftover\n');
    await _tap(tester, 'code15-record-delete-button');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _settle(tester);
    expect(record.hasLines, isFalse, reason: 'control: the record is deleted');
    expect(copies.staged, isEmpty);
    expect(copies.sharePlusCopies, isEmpty);
  });

  testWidgets('a share that cannot be handed on says so, in the ruled words, in '
      'the status line, until his next 記録を共有 or 記録を消す', (tester) async {
    final (record, fake) = await boot(tester);
    fill(record);
    fake.throwThis = Exception('Share failed');
    await _tap(tester, 'code15-record-share-button');
    expect(_status(tester).split('\n').first, _failedJa);
    expect(RecordShareFile(cacheDirectory: cache).staged, isEmpty,
        reason: 'the staging copy outlived a failed call');
    fake.throwThis = null;
    await _tap(tester, 'code15-record-share-button');
    expect(_status(tester), isNot(contains(_failedJa)), reason: 'a good share clears it');
    fake.throwThis = Exception('Share failed');
    await _tap(tester, 'code15-record-share-button');
    expect(_status(tester), contains(_failedJa));
    await _tap(tester, 'code15-record-delete-button');
    expect(_status(tester), isNot(contains(_failedJa)),
        reason: 'the line is about a share of a record he has now deleted');
  });

  testWidgets('a copy that cannot be written is a share that cannot be handed '
      'on, and is said (English too)', (tester) async {
    final blocked = File('${dir.path}/not_a_dir')..writeAsStringSync('x');
    final (record, fake) = await boot(tester,
        locale: const Locale('en'), cacheDirectory: Directory(blocked.path));
    fill(record);
    await _tap(tester, 'code15-record-share-button');
    expect(fake.handed, isEmpty, reason: 'control: nothing reached the sheet');
    expect(_status(tester).split('\n').first, _failedEn);
  });

  test('the launch path deletes every copy left on disk (main() calls '
      'openRecordShareFile()?.deleteAll())', () async {
    final copies = (await openRecordShareFile(cacheDirectory: cache))!;
    copies.stage('left by a process that ended mid-share\n');
    // A receiver copy, and the one fixed name earlier builds wrote.
    for (final n in ['sngnav-fix-interval-record-0badf00d.txt', 'sngnav-fix-interval-record.txt']) {
      File('${copies.sharePlusDirectory.path}/$n')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    expect(copies.anyCopy, isTrue, reason: 'control');
    copies.deleteAll();
    expect(copies.anyCopy, isFalse);
    final src = File('lib/main.dart').readAsStringSync();
    final body = src.substring(src.indexOf('Future<void> main() async {'),
        src.indexOf('\n}\n', src.indexOf('Future<void> main() async {')));
    expect(body, contains('(await openRecordShareFile())?.deleteAll();'));
  });

  test('copies live only under the cache directory, which Android never backs '
      'up or transfers, and the record goes as a file, never as text', () {
    final src = File('lib/services/record_share_file.dart').readAsStringSync();
    expect(src, contains('getTemporaryDirectory()'));
    for (final other in [
      'getApplicationSupportDirectory',
      'getApplicationDocumentsDirectory',
      'getExternalStorageDirectory',
      'getDownloadsDirectory',
      'getLibraryDirectory',
    ]) {
      expect(src.contains(other), isFalse, reason: other);
    }
    final shareParams = RegExp(r'ShareParams\((.*?)\)\s*,?\s*\);', dotAll: true)
        .firstMatch(src)!
        .group(1)!;
    expect(shareParams, contains('files: [XFile(path'));
    expect(shareParams.contains('text:'), isFalse,
        reason: 'the record must never ride the intent as text');
    final rec = File('lib/services/code15_fix_interval_record.dart').readAsStringSync();
    expect(rec, contains('shareRecordFileViaShareSheet(path,'));
    expect(RegExp(r'ShareParams\(').hasMatch(rec), isFalse,
        reason: 'the recorder builds no share of its own');
    final c = RecordShareFile(cacheDirectory: Directory('/cache'));
    expect(c.stagingDirectory.path, '/cache/$kRecordShareStagingDir');
    expect(c.sharePlusDirectory.path, '/cache/share_plus');
    expect(c.newShareFileName(), matches(_shareName));
  });

  testWidgets('each share has a file name of its own; the last share\'s link '
      'then names a file that is gone, so a late read fails rather than '
      'reading the next share', (tester) async {
    final (record, fake) = await boot(tester);
    fill(record);
    final copies = RecordShareFile(cacheDirectory: cache);
    await _tap(tester, 'code15-record-share-button');
    final first = copies.sharePlusCopies.single;
    await _tap(tester, 'code15-record-share-button');
    final second = copies.sharePlusCopies.single;
    expect(fake.handed, hasLength(2), reason: 'control: two shares');
    for (final f in [first, second]) {
      expect(f.uri.pathSegments.last, matches(_shareName));
    }
    expect(second.path, isNot(first.path),
        reason: 'one name for two shares: a late link would read the next '
            'share\'s bytes');
    expect(() => first.readAsStringSync(), throwsA(isA<FileSystemException>()),
        reason: 'the first share\'s link must fail, not read another share');
    expect(second.readAsStringSync(), fake.texts.last);
  });

  test('every copy is deleted by the name\'s prefix, an earlier build\'s fixed '
      'name included, and nothing else in the folders is touched', () {
    final copies = RecordShareFile(cacheDirectory: cache);
    final plant = [
      File('${cache.path}/$kSharePlusCacheDir/sngnav-fix-interval-record.txt'),
      File('${cache.path}/$kSharePlusCacheDir/sngnav-fix-interval-record-0badf00d.txt'),
      File('${cache.path}/$kSharePlusCacheDir/sngnav-fix-interval-record-12345678.txt'),
      File('${cache.path}/$kRecordShareStagingDir/sngnav-fix-interval-record-cafe0001.txt'),
    ];
    final other = File('${cache.path}/$kSharePlusCacheDir/someone-else.txt');
    for (final f in [...plant, other]) {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('x');
    }
    expect(copies.sharePlusCopies, hasLength(3), reason: 'control');
    copies.deleteAll();
    for (final f in plant) {
      expect(f.existsSync(), isFalse, reason: f.path);
    }
    expect(other.existsSync(), isTrue, reason: 'not the record\'s: not touched');
  });

  test('a share\'s name is the prefix and a random token, with no field for '
      'a version code or a time of day', () {
    final c = RecordShareFile(cacheDirectory: Directory('/cache'));
    final names = {for (var i = 0; i < 50; i++) c.newShareFileName()};
    for (final n in names) {
      expect(n, matches(_shareName));
    }
    expect(names.length, greaterThan(45),
        reason: 'the token is random: 50 draws of 32 bits barely repeat');
    expect(recordShareFileName('0badf00d'), 'sngnav-fix-interval-record-0badf00d.txt');
    expect(kRecordShareFilePrefix, 'sngnav-fix-interval-record',
        reason: 'the name is a key; identity lives in the header');
  });
}
