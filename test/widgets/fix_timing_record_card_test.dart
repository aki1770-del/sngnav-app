/// The fix-timing record through the real app (code 13 only).
///
/// Why, written before the act (2026-10-06). Code 13 exists to read how far
/// apart the Chair's phone delivers GPS fixes; that reading decides whether the
/// next change can reach a driver in unexpected snow and what it tells her.
/// These run the app's own position stream and clock at injected cadences of
/// 1 s and 15 s and read back what the record holds, so the instrument is shown
/// able to see both the cadence it is for and the cadence it is afraid of.
/// They also hold what the man driving it is told and can do: its own card,
/// words that say only what is so, a stop and a delete that work while his
/// share keeps running, nothing recorded outside a share, and the ログを共有
/// card's words untouched and still true.
///
/// What they do NOT hold: anything on a device (the emulator pass is the
/// independent hand's), the share sheet itself, or his phone's real cadence.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/services/fix_timing_record.dart';

import '../support/fake_alert_actuators.dart';

var _clockNow = DateTime.utc(2026, 1, 14, 21);

Future<void> _advance(WidgetTester tester, Duration d) async {
  _clockNow = _clockNow.add(d);
  await tester.pump(d);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Position _sample(
  double northM, {
  double accuracy = 10,
  bool measuredAccuracy = true,
}) => Position(
  latitude: 39.7186 + northM / 111194.93,
  longitude: 140.1024,
  timestamp: _clockNow.subtract(const Duration(milliseconds: 300)),
  accuracy: measuredAccuracy ? accuracy : 0,
  hasAccuracy: measuredAccuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 15,
  hasSpeed: true,
  speedAccuracy: 1.5,
  hasSpeedAccuracy: true,
);

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
  fetchedAt: _clockNow,
);

class _App {
  _App(this.dir, {int maxBytes = kFixTimingRecordMaxBytes})
      : record = FixTimingRecord(
            file: File('${dir.path}/$kFixTimingRecordFileName'),
            maxBytes: maxBytes),
        errorLog = LocalErrorLog(file: File('${dir.path}/error_log.txt'));
  final Directory dir;
  final FixTimingRecord record;
  final LocalErrorLog errorLog;
  final positions = StreamController<Position>();
  final shared = <String>[];
  final logShared = <String>[];

  List<String> get lines =>
      record.readAll().split('\n').where((l) => l.isNotEmpty).toList();

  Future<void> boot(WidgetTester tester) async {
    _clockNow = DateTime.utc(2026, 1, 14, 21);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      SngnavApp(
        locationConsent: true,
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        clock: () => _clockNow,
        jmaFetch: () async => JmaSuccess(_clear()),
        errorLog: errorLog,
        logShareSink: (p) async => logShared.add(p),
        fixTimingRecord: record,
        fixTimingShareSink: (p) async => shared.add(p),
        positionSource: () => herPositionStream(
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.whileInUse,
          positionStream: () => positions.stream,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> share(WidgetTester tester) async {
    final b = find.byKey(const Key('share-location-button'));
    await tester.ensureVisible(b);
    await tester.pump();
    await tester.tap(b);
    await _settle(tester);
  }

  Future<void> stopSharing(WidgetTester tester) async {
    final s = find.text('停止');
    await tester.ensureVisible(s.first);
    await tester.pump();
    await tester.tap(s.first);
    await _settle(tester);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final b = find.byKey(Key(key));
    await tester.ensureVisible(b);
    await tester.pump();
    await tester.tap(b);
    await _settle(tester);
  }

  /// [n] fixes [every] apart, moving at 15 m/s.
  Future<void> drive(WidgetTester tester, int n, Duration every,
      {double accuracy = 10}) async {
    for (var i = 0; i < n; i++) {
      await _advance(tester, every);
      positions.add(_sample(15.0 * i * every.inSeconds, accuracy: accuracy));
      await _settle(tester);
    }
  }
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key), skipOffstage: false)).data ?? '';

/// Milliseconds between consecutive lines of [kind] in share [share].
List<int> _gaps(List<String> lines, String kind, int share) {
  final t = [
    for (final l in lines)
      if (l.startsWith('s=$share ') && l.contains(' k=$kind '))
        int.parse(RegExp(r' t=(\d+) ').firstMatch(l)!.group(1)!),
  ];
  return [for (var i = 1; i < t.length; i++) t[i] - t[i - 1]];
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fix_timing_card_'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('a fix every second: one line per fix, 1000 ms apart, after the '
      'share\'s start line', (tester) async {
    final app = _App(dir);
    await app.boot(tester);
    await app.share(tester);
    await app.drive(tester, 20, const Duration(seconds: 1));
    final lines = app.lines;
    expect(lines.first, matches(RegExp(r'^s=\d+ t=0 k=start ')),
        reason: lines.join('\n'));
    final share = int.parse(RegExp(r'^s=(\d+)').firstMatch(lines.first)!.group(1)!);
    expect(lines.where((l) => l.contains(' k=fine ')).length, 20,
        reason: lines.join('\n'));
    expect(_gaps(lines, 'fine', share), everyElement(1000));
    expect(lines.where((l) => l.contains(' k=fine ')),
        everyElement(contains('a=10.0 v=15.0 late=300 fg=1')));
    for (final l in lines) {
      expect(kFixTimingLinePattern.hasMatch(l), isTrue, reason: l);
    }
    await app.positions.close();
  });

  testWidgets('two fixes the phone delivers together read the same time, and '
      'their lateness tells them apart: t is when the app received the event',
      (tester) async {
    final app = _App(dir);
    await app.boot(tester);
    await app.share(tester);
    await app.drive(tester, 2, const Duration(seconds: 1));
    await _advance(tester, const Duration(seconds: 3));
    // A batch: two fixes stamped 2 s and 1 s ago arrive in the same moment.
    Position stamped(Duration ago, double north) => Position(
          latitude: 39.7186 + north / 111194.93,
          longitude: 140.1024,
          timestamp: _clockNow.subtract(ago),
          accuracy: 10,
          hasAccuracy: true,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 15,
          hasSpeed: true,
          speedAccuracy: 1.5,
          hasSpeedAccuracy: true,
        );
    app.positions.add(stamped(const Duration(seconds: 2), 45));
    app.positions.add(stamped(const Duration(seconds: 1), 60));
    await _settle(tester);
    final last = app.lines.reversed.take(2).toList().reversed.toList();
    int field(String l, String k) =>
        int.parse(RegExp(' $k=(-?\\d+) ').firstMatch(l)!.group(1)!);
    expect(field(last[0], 't'), field(last[1], 't'),
        reason: 'not the receipt time: ${last.join(' | ')}');
    expect(field(last[0], 'late') - field(last[1], 'late'), 1000,
        reason: last.join(' | '));
    await app.positions.close();
  });

  testWidgets('a fix every 15 s: one line per fix, 15000 ms apart', (tester) async {
    final app = _App(dir);
    await app.boot(tester);
    await app.share(tester);
    await app.drive(tester, 8, const Duration(seconds: 15));
    final lines = app.lines;
    final share = int.parse(RegExp(r'^s=(\d+)').firstMatch(lines.first)!.group(1)!);
    expect(lines.where((l) => l.contains(' k=fine ')).length, 8,
        reason: lines.join('\n'));
    expect(_gaps(lines, 'fine', share), everyElement(15000),
        reason: lines.join('\n'));
    await app.positions.close();
  });

  testWidgets('every kind is recorded as a kind: a coarse fix, a sample with no '
      'accuracy, and a stream error whose text carries coordinates, which never '
      'enters the record', (tester) async {
    final app = _App(dir);
    await app.boot(tester);
    await app.share(tester);
    await app.drive(tester, 2, const Duration(seconds: 1));
    await _advance(tester, const Duration(seconds: 1));
    app.positions.add(_sample(40, accuracy: 300));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 1));
    app.positions.add(_sample(55, measuredAccuracy: false));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 1));
    app.positions.addError(StateError('fix lost at 39.71860, 140.10240 Akita'));
    await _settle(tester);
    final text = app.record.readAll();
    expect(text, contains(' k=coarse a=300.0 '));
    expect(text, contains(' k=noacc a=- '));
    expect(text, contains(' k=unavail a=- v=- late=- '));
    expect(text, isNot(contains('39.7')), reason: 'a coordinate reached it');
    expect(text, isNot(contains('140.1')), reason: 'a coordinate reached it');
    expect(text, isNot(contains('Akita')), reason: 'error text reached it');
    for (final l in app.lines) {
      expect(kFixTimingLinePattern.hasMatch(l), isTrue, reason: l);
    }
    await app.positions.close();
  });

  testWidgets('nothing is recorded before a share starts or after 停止',
      (tester) async {
    final app = _App(dir);
    await app.boot(tester);
    await _advance(tester, const Duration(seconds: 5));
    expect(app.record.hasLines, isFalse, reason: 'recorded with no share');
    await app.share(tester);
    await app.drive(tester, 3, const Duration(seconds: 1));
    final during = app.lines.length;
    expect(during, 4, reason: 'control: start and three fixes');
    await app.stopSharing(tester);
    expect(find.byKey(const Key('share-location-button')), findsOneWidget,
        reason: 'control: the share ended');
    app.positions.add(_sample(100));
    await _advance(tester, const Duration(seconds: 30));
    expect(app.lines.length, during, reason: 'recorded after 停止');
  });

  testWidgets('the card: W2 status while lines exist, a stop that holds while '
      'the share runs, a resume, a delete, and its own share of every line',
      (tester) async {
    final app = _App(dir);
    await app.boot(tester);
    expect(_textOf(tester, 'fix-timing-status'), '測位間隔の記録はまだありません。');
    await app.share(tester);
    await app.drive(tester, 3, const Duration(seconds: 1));
    expect(_textOf(tester, 'fix-timing-status'),
        '測位間隔の記録があります。共有ボタンで送れます。');

    await app.tap(tester, 'fix-timing-stop-button');
    expect(_textOf(tester, 'fix-timing-status'),
        '測位間隔の記録があります。共有ボタンで送れます。 記録は止めています。');
    final held = app.lines.length;
    await app.drive(tester, 3, const Duration(seconds: 1));
    expect(app.lines.length, held, reason: 'recorded while stopped');
    expect(find.byKey(const Key('share-location-button')), findsNothing,
        reason: 'stopping the record ended her share');

    await app.tap(tester, 'fix-timing-stop-button');
    await app.drive(tester, 2, const Duration(seconds: 1));
    expect(app.lines.length, held + 2, reason: 'resume did not record');

    await app.tap(tester, 'fix-timing-share-button');
    expect(app.shared, hasLength(1));
    expect(app.shared.single, contains('exported: '));
    expect(app.shared.single.endsWith(app.record.readAll()), isTrue,
        reason: 'the share did not carry every line');

    await app.tap(tester, 'fix-timing-delete-button');
    expect(app.record.hasLines, isFalse);
    expect(_textOf(tester, 'fix-timing-status'), '測位間隔の記録はまだありません。');
    await app.positions.close();
  });

  testWidgets('at its cap the record stops, the card says so, and the share '
      'still carries every line', (tester) async {
    // The app's own record, with a cap small enough to reach in a test.
    final app = _App(dir, maxBytes: 1024);
    await app.boot(tester);
    await app.share(tester);
    await app.drive(tester, 40, const Duration(seconds: 1));
    expect(app.record.full, isTrue, reason: 'control: the cap was reached');
    final held = app.lines;
    expect(held.length, lessThan(41), reason: 'control: lines were refused');
    expect(held.first, matches(RegExp(r'^s=\d+ t=0 k=start ')),
        reason: 'the first line was dropped to make room');
    expect(_textOf(tester, 'fix-timing-status'),
        '測位間隔の記録があります。共有ボタンで送れます。 '
        '上限（約96 KB）に達したため、記録を止めています。');
    await app.tap(tester, 'fix-timing-share-button');
    expect(app.shared.single.endsWith(app.record.readAll()), isTrue);
    await app.positions.close();
  });

  testWidgets('the ログを共有 card is untouched: its words are the ones that '
      'were true before, and its share carries no fix line', (tester) async {
    final app = _App(dir);
    await app.boot(tester);
    await app.share(tester);
    await app.drive(tester, 3, const Duration(seconds: 1));
    expect(app.record.hasLines, isTrue, reason: 'control: lines exist');
    final disclosure = tester
        .widget<Text>(find.byKey(const Key('log-share-disclosure'),
            skipOffstage: false))
        .data;
    expect(
      disclosure,
      '共有はこのボタンを押したときだけ行われます。自動送信・テレメトリはなく、'
      'アカウントも不要です。ログに含まれるのはエラーの記録のみで、'
      '位置情報の履歴は含まれません。送信先は端末の共有画面で自分で選べます。',
    );
    expect(find.textContaining('ログは空です（クラッシュ・エラーの記録はありません）。',
            skipOffstage: false),
        findsOneWidget,
        reason: 'the error log is empty, and its card says so of errors only');
    await app.tap(tester, 'share-log-button');
    expect(app.logShared, hasLength(1));
    expect(app.logShared.single, isNot(contains('k=fine')),
        reason: 'a fix line reached the error log\'s share');
    expect(app.errorLog.readAll(), isNot(contains('k=')),
        reason: 'a fix line reached the error log');
    await app.positions.close();
  });

  testWidgets('the disclosure says what is so: no coordinates or place names, '
      'the export time included, only while sharing, on the phone until he '
      'taps, how it stops and ends, and its cap', (tester) async {
    final app = _App(dir);
    await app.boot(tester);
    final d = _textOf(tester, 'fix-timing-disclosure');
    for (final clause in [
      '現在地を共有している間だけ',
      '届いた時刻の間隔と遅れ',
      '測位の種類と精度',
      '緯度経度や地名は記録しません',
      '書き出した時刻が入ります',
      'この端末に残り、押すまで送られません',
      '「記録を止める」で止まり',
      '「記録を消す」で消えます',
      '上限は約96 KB',
      '次の版を入れると消えます',
    ]) {
      expect(d, contains(clause));
    }
    expect(d, isNot(contains('位置情報の履歴は含まれません')),
        reason: 'the record is location-adjacent: that clause would not be so');
  });
}
