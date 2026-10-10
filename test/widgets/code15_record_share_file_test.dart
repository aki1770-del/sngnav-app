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

const _failedJa = '記録を端末の共有画面に渡せませんでした。何も送られていません。';
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
    expect(fake.handed.single, '${cache.path}/$kRecordShareStagingDir/$kRecordShareFileName');
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
    expect(copies.staged.existsSync(), isFalse, reason: 'the staging copy outlived the call');
    expect(copies.sharePlusCopy.existsSync(), isTrue,
        reason: 'a receiver that opens the link late would read nothing');
    expect(copies.sharePlusCopy.readAsStringSync(), fake.texts.single,
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
    expect(copies.sharePlusCopy.existsSync(), isTrue,
        reason: 'the receiver may still be reading: kept while the call runs');
    // The call returns while the app is still behind.
    fake.hold!.complete();
    await _settle(tester);
    expect(copies.staged.existsSync(), isFalse);
    expect(copies.sharePlusCopy.existsSync(), isTrue,
        reason: 'not deleted while the app is not in front');
    // He comes back.
    for (final s in const [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
    }
    await _settle(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _settle(tester);
    expect(copies.sharePlusCopy.existsSync(), isTrue,
        reason: 'his return deleted the copy a late receiver reads');
    expect(copies.sharePlusCopy.readAsStringSync(), fake.texts.single);
  });

  testWidgets('his next 記録を共有 deletes the last share\'s receiver copy, even '
      'when that share fails before share_plus is reached', (tester) async {
    final (record, fake) = await boot(tester);
    fill(record);
    final copies = RecordShareFile(cacheDirectory: cache);
    await _tap(tester, 'code15-record-share-button');
    expect(copies.sharePlusCopy.existsSync(), isTrue, reason: 'control: kept after the share');
    // The next staging write cannot be made: a regular file where the folder was.
    final staging = Directory('${cache.path}/$kRecordShareStagingDir');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    File(staging.path).writeAsStringSync('x');
    await _tap(tester, 'code15-record-share-button');
    expect(fake.handed, hasLength(1), reason: 'control: the second share reached nothing');
    expect(_status(tester).split('\n').first, _failedJa, reason: 'control: said');
    expect(copies.sharePlusCopy.existsSync(), isFalse,
        reason: 'the last share\'s receiver copy outlived his next 記録を共有');
  });

  testWidgets('記録を消す deletes every copy made for sharing, with the record',
      (tester) async {
    final (record, _) = await boot(tester);
    fill(record);
    final copies = RecordShareFile(cacheDirectory: cache);
    // The receiver copy his share left, kept for a late reader.
    await _tap(tester, 'code15-record-share-button');
    expect(copies.sharePlusCopy.existsSync(), isTrue, reason: 'control: kept after the share');
    // A staging copy left on disk too (as if a share were cut short).
    copies.stage('leftover\n');
    await _tap(tester, 'code15-record-delete-button');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _settle(tester);
    expect(record.hasLines, isFalse, reason: 'control: the record is deleted');
    expect(copies.staged.existsSync(), isFalse);
    expect(copies.sharePlusCopy.existsSync(), isFalse);
  });

  testWidgets('a share that cannot be handed on says so, in the ruled words, in '
      'the status line, until his next 記録を共有 or 記録を消す', (tester) async {
    final (record, fake) = await boot(tester);
    fill(record);
    fake.throwThis = Exception('Share failed');
    await _tap(tester, 'code15-record-share-button');
    expect(_status(tester).split('\n').first, _failedJa);
    expect(RecordShareFile(cacheDirectory: cache).staged.existsSync(), isFalse,
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
    copies.sharePlusCopy.parent.createSync(recursive: true);
    copies.sharePlusCopy.writeAsStringSync('x');
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
    expect(c.staged.path, '/cache/$kRecordShareStagingDir/$kRecordShareFileName');
    expect(c.sharePlusCopy.path, '/cache/share_plus/$kRecordShareFileName');
  });
}
