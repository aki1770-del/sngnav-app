/// Code 15's fix-interval record through the real app.
///
/// Why, written before the act (2026-10-10). Code 15 takes again the reading
/// code 13 took, with three new kinds so that a share the phone ends while he
/// is parked can be read honestly. These run the app's own position stream and
/// clock and read back what the record holds:
/// - code 13's cadence tests, carried (89ed430
///   test/widgets/fix_timing_record_card_test.dart): one line per fix at 1 s
///   and 15 s, every kind a kind, an end line at 停止 only, nothing outside a
///   share;
/// - ONE CLOCK: alive, leave and back take t from the page's injected clock
///   minus the share's subscription time, as the fix lines do; a clock that
///   jumps while the timer ticks once shows in t;
/// - alive lines in a gap and none while fixes come every 5 s;
/// - leave and back at the app's own leave (visible to hidden) and return
///   (hidden to visible), with the share's s and t;
/// - when the APP ends a share (a share without its service, the app left),
///   no end line: the record never says "his tap" for an ending he did not
///   make;
/// - the card: its own, with 記録を止める and 記録を消す, the full state said,
///   and the left-behind card never drawn.
///
/// What they do NOT hold: anything on a device, his phone's cadence, whether
/// a Dart timer runs on his phone in the background, the share sheet itself.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/code15_fix_interval_record.dart';
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/services/notification_permission.dart';
import 'package:sngnav_app/widgets/keep_together.dart';

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
  double speed = 15,
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
  speed: speed,
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
  _App(this.dir, {int maxBytes = kCode15RecordMaxBytes})
      : record = Code15FixIntervalRecord(directory: dir, maxBytes: maxBytes),
        errorLog = LocalErrorLog(file: File('${dir.path}/error_log.txt'));
  final Directory dir;
  final Code15FixIntervalRecord record;
  final LocalErrorLog errorLog;
  final positions = StreamController<Position>();
  final shared = <String>[];

  List<String> get lines =>
      record.readAll().split('\n').where((l) => l.isNotEmpty).toList();

  /// [canPost] true: the notification read answers "can post", so the share
  /// is built with its service and leaving the app does not end it.
  Future<void> boot(WidgetTester tester,
      {Locale locale = const Locale('ja'), bool canPost = false}) async {
    if (canPost) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NotificationPermission.channel,
        (call) async => call.method == 'read'
            ? <String, dynamic>{
                'granted': true,
                'enabled': true,
                'needsRuntimeRequest': false,
              }
            : true,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NotificationPermission.channel,
          null,
        ),
      );
    }
    _clockNow = DateTime.utc(2026, 1, 14, 21);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      SngnavApp(
        locationConsent: true,
        actuators: FakeAlertActuators(),
        locale: locale,
        clock: () => _clockNow,
        jmaFetch: () async => JmaSuccess(_clear()),
        errorLog: errorLog,
        code15Record: record,
        // The sink is handed a FILE path; what it shares is that file's text,
        // read at the moment of the call (services/record_share_file.dart).
        code15RecordShareSink: (path) async =>
            shared.add(File(path).readAsStringSync()),
        code15ShareCacheDirectory: Directory('${dir.path}/cache'),
        positionSource: () => herPositionStream(
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.whileInUse,
          positionStream: () => positions.stream,
        ),
      ),
    );
    await _settle(tester);
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

  /// [n] fixes [every] apart, at [speed].
  Future<void> drive(WidgetTester tester, int n, Duration every,
      {double accuracy = 10, double speed = 15}) async {
    for (var i = 0; i < n; i++) {
      await _advance(tester, every);
      positions.add(_sample(15.0 * i * every.inSeconds,
          accuracy: accuracy, speed: speed));
      await _settle(tester);
    }
  }
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key), skipOffstage: false)).data ?? '';

int _t(String line) => int.parse(RegExp(r' t=(\d+) ').firstMatch('$line ')!.group(1)!);

/// Milliseconds between consecutive lines of [kind] in share [share].
List<int> _gaps(List<String> lines, String kind, int share) {
  final t = [
    for (final l in lines)
      if (l.startsWith('s=$share ') && l.contains(' k=$kind ')) _t(l),
  ];
  return [for (var i = 1; i < t.length; i++) t[i] - t[i - 1]];
}

Future<void> _to(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
  await _settle(tester);
}

const _leave = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const _back = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('code15_card_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('code 13\'s cadence tests, carried', () {
    testWidgets('a fix every second: one line per fix, 1000 ms apart, after the '
        'share\'s start line', (tester) async {
      final app = _App(dir);
      await app.boot(tester);
      await app.share(tester);
      await app.drive(tester, 20, const Duration(seconds: 1));
      final lines = app.lines;
      expect(lines.first, matches(RegExp(r'^s=\d+ t=0 k=start ')),
          reason: lines.join('\n'));
      final share =
          int.parse(RegExp(r'^s=(\d+)').firstMatch(lines.first)!.group(1)!);
      expect(lines.where((l) => l.contains(' k=fine ')).length, 20);
      expect(_gaps(lines, 'fine', share), everyElement(1000));
      expect(lines.where((l) => l.contains(' k=fine ')),
          everyElement(contains('a=10.0 v=15.0 late=300 fg=1')));
      expect(app.record.readAll(), isNot(contains('k=alive')),
          reason: 'alive while fixes came every second');
      for (final l in lines) {
        expect(kCode15LinePattern.hasMatch(l), isTrue, reason: l);
      }
      await app.positions.close();
    });

    testWidgets('a fix every 15 s: one line per fix, 15000 ms apart, and the '
        'gaps carry alive lines', (tester) async {
      final app = _App(dir);
      await app.boot(tester);
      await app.share(tester);
      await app.drive(tester, 8, const Duration(seconds: 15));
      final lines = app.lines;
      final share =
          int.parse(RegExp(r'^s=(\d+)').firstMatch(lines.first)!.group(1)!);
      expect(lines.where((l) => l.contains(' k=fine ')).length, 8);
      expect(_gaps(lines, 'fine', share), everyElement(15000),
          reason: lines.join('\n'));
      expect(lines.where((l) => l.endsWith(' k=alive')), isNotEmpty,
          reason: lines.join('\n'));
      await app.positions.close();
    });

    testWidgets('every kind is recorded as a kind, and a stream error\'s text '
        'never enters the record', (tester) async {
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
      expect(text, isNot(contains('39.7')));
      expect(text, isNot(contains('140.1')));
      expect(text, isNot(contains('Akita')));
      await app.positions.close();
    });

    testWidgets('停止 writes the share\'s end line, and nothing is recorded '
        'before a share or after 停止', (tester) async {
      final app = _App(dir);
      await app.boot(tester);
      await _advance(tester, const Duration(seconds: 30));
      expect(app.record.hasLines, isFalse, reason: 'recorded with no share');
      await app.share(tester);
      await app.drive(tester, 3, const Duration(seconds: 1));
      await _advance(tester, const Duration(seconds: 2));
      await app.stopSharing(tester);
      final lines = app.lines;
      final share = RegExp(r'^s=(\d+)').firstMatch(lines.first)!.group(1);
      expect(lines.last, 's=$share t=5000 k=end', reason: lines.join('\n'));
      expect(lines.where((l) => l.contains(' k=end')).length, 1);
      expect(app.record.readAll(), isNot(contains('k=appstop')),
          reason: 'his 停止 is never the app\'s ending');
      final held = lines.length;
      app.positions.add(_sample(100));
      for (var i = 0; i < 10; i++) {
        await _advance(tester, const Duration(seconds: 3));
      }
      expect(app.lines.length, held, reason: 'recorded after 停止');
      unawaited(app.positions.close());
    });
  });

  group('one clock for every kind', () {
    testWidgets('alive lines in a gap carry t from the page\'s clock: the '
        'first comes 6 to 9 s after the last line, then one every 6 s',
        (tester) async {
      final app = _App(dir);
      await app.boot(tester);
      await app.share(tester);
      await app.drive(tester, 3, const Duration(seconds: 5));
      final lastFix = _t(app.lines.last);
      for (var i = 0; i < 30; i++) {
        await _advance(tester, const Duration(seconds: 1));
      }
      final alive = app.lines.where((l) => l.endsWith(' k=alive')).toList();
      expect(alive, isNotEmpty, reason: app.lines.join('\n'));
      final first = _t(alive.first) - lastFix;
      expect(first, greaterThanOrEqualTo(6000));
      expect(first, lessThan(9000));
      final ts = alive.map(_t).toList();
      expect([for (var i = 1; i < ts.length; i++) ts[i] - ts[i - 1]],
          everyElement(6000));
      await app.positions.close();
    });

    testWidgets('a clock that jumps while the timer ticks once shows in t: '
        'the line reads the page\'s clock, not a stopwatch', (tester) async {
      final app = _App(dir);
      await app.boot(tester);
      await app.share(tester);
      await app.drive(tester, 1, const Duration(seconds: 1));
      final last = _t(app.lines.last);
      // The wall clock moves 60 s; the timer gets one 3 s tick.
      _clockNow = _clockNow.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 3));
      final alive = app.lines.last;
      expect(alive, endsWith(' k=alive'), reason: app.lines.join('\n'));
      expect(_t(alive) - last, 60000,
          reason: 'alive t is not the page clock minus the subscription');
      await app.positions.close();
    });

    testWidgets('leave and back: written at the app\'s own leave and return, '
        'with the share\'s s and t by the page clock; the share keeps going',
        (tester) async {
      final app = _App(dir);
      await app.boot(tester, canPost: true);
      await app.share(tester);
      await app.drive(tester, 2, const Duration(seconds: 5));
      final share =
          RegExp(r'^s=(\d+)').firstMatch(app.lines.first)!.group(1);
      await _advance(tester, const Duration(seconds: 1));
      await _to(tester, _leave);
      expect(app.lines.last, 's=$share t=11000 k=leave',
          reason: app.lines.join('\n'));
      await app.drive(tester, 2, const Duration(seconds: 5));
      await _advance(tester, const Duration(seconds: 2));
      await _to(tester, _back);
      expect(app.lines.last, 's=$share t=23000 k=back',
          reason: app.lines.join('\n'));
      expect(app.lines.where((l) => l.endsWith(' k=leave')).length, 1);
      expect(app.lines.where((l) => l.endsWith(' k=back')).length, 1);
      expect(app.record.readAll(), isNot(contains('k=appstop')),
          reason: 'a share with its service keeps going when the app leaves: '
              'the app did not end it');
      expect(app.lines.where((l) => l.contains(' k=fine ') && l.endsWith('fg=0')),
          hasLength(2), reason: 'the fixes while away are behind');
      await app.positions.close();
    });

    testWidgets('a dialog over the app (inactive only) is neither a leave nor '
        'a back', (tester) async {
      final app = _App(dir);
      await app.boot(tester, canPost: true);
      await app.share(tester);
      await app.drive(tester, 1, const Duration(seconds: 1));
      await _to(tester, const [AppLifecycleState.inactive]);
      await _to(tester, const [AppLifecycleState.resumed]);
      expect(app.record.readAll(), isNot(contains('k=leave')));
      expect(app.record.readAll(), isNot(contains('k=back')));
      await app.positions.close();
    });
  });

  testWidgets('when the APP ends a share (no service, the app left), the '
      'record holds the leave, then appstop, and NO end line: the ending was '
      'not his tap', (tester) async {
    final app = _App(dir);
    await app.boot(tester); // the notification read says "cannot post"
    await app.share(tester);
    await app.drive(tester, 2, const Duration(seconds: 1));
    final share =
        RegExp(r'^s=(\d+)').firstMatch(app.lines.first)!.group(1);
    await _to(tester, _leave);
    await _advance(tester, const Duration(seconds: 3));
    await _to(tester, _back);
    expect(find.byKey(const Key('share-location-button')), findsOneWidget,
        reason: 'control: the app ended the share itself');
    final lines = app.lines;
    final mine = [for (final l in lines) if (l.startsWith('s=$share ')) l];
    expect(mine.reversed.take(2).toList().reversed.toList(),
        ['s=$share t=2000 k=leave', 's=$share t=2000 k=appstop'],
        reason: lines.join('\n'));
    expect(lines.last, 's=$share t=2000 k=appstop',
        reason: 'nothing of that share follows its appstop');
    expect(app.record.readAll(), isNot(contains('k=end')),
        reason: 'an app ending was written as his tap');
    unawaited(app.positions.close());
  });

  group('the card: its own, with 記録を止める and 記録を消す', () {
    testWidgets('status, stop that holds while the share runs, resume, share '
        'of every line, and his delete', (tester) async {
      final app = _App(dir);
      await app.boot(tester);
      expect(_textOf(tester, 'code15-record-status'), '測位間隔の記録はありません。');
      expect(find.text('測位間隔の記録（テスト版）', skipOffstage: false),
          findsOneWidget);
      await app.share(tester);
      await app.drive(tester, 3, const Duration(seconds: 1));
      expect(_textOf(tester, 'code15-record-status'),
          '測位間隔の記録があります。「記録を共有」で送れます。');

      await app.tap(tester, 'code15-record-stop-button');
      expect(_textOf(tester, 'code15-record-status'),
          '記録は止めています。\n測位間隔の記録があります。「記録を共有」で送れます。');
      expect(app.lines.last, kFixTimingPauseLine);
      final held = app.lines.length;
      await app.drive(tester, 3, const Duration(seconds: 5));
      expect(app.lines.length, held, reason: 'recorded while stopped');

      await app.tap(tester, 'code15-record-stop-button');
      expect(app.lines.last, kFixTimingResumeLine);

      await app.tap(tester, 'code15-record-share-button');
      expect(app.shared, hasLength(1));
      expect(app.shared.single.endsWith(app.record.readAll()), isTrue);
      expect(app.record.hasLines, isTrue, reason: 'a share deleted lines');

      await app.tap(tester, 'code15-record-delete-button');
      expect(app.record.hasLines, isFalse);
      expect(_textOf(tester, 'code15-record-status'), '測位間隔の記録はありません。');
      expect(find.byKey(const Key('code15-record-status'), skipOffstage: false),
          findsOneWidget, reason: 'the card stays: the build still records');
      await app.positions.close();
    });

    testWidgets('at its cap the record stops and the card says so, with the '
        'cap read from source; the share still carries every line',
        (tester) async {
      final app = _App(dir, maxBytes: 1024);
      await app.boot(tester);
      await app.share(tester);
      await app.drive(tester, 40, const Duration(seconds: 1));
      expect(app.record.full, isTrue, reason: 'control: the cap was reached');
      expect(app.lines.first, matches(RegExp(r'^s=\d+ t=0 k=start ')));
      expect(_textOf(tester, 'code15-record-status'),
          '上限（約$kCode15RecordCapKbText KB）に達したため、記録を止めています。\n'
          '測位間隔の記録があります。「記録を共有」で送れます。');
      expect(find.byKey(const Key('code15-record-stop-button'),
          skipOffstage: false), findsNothing);
      expect(
          tester
              .widget<KeepTogetherText>(find.byKey(
                  const Key('code15-record-count'), skipOffstage: false))
              .data,
          '記録が上限に達しました。最低限には達していません（アプリの数え方で）。'
          '駐車中に「記録を共有」を押して送り、欠けずに届いたと知らされるまで、'
          '記録は消さずに残しておいてください。',
          reason: 'full and not reached: form F, never a reached-shaped line');
      expect(find.byKey(const Key('code15-record-delete-button'),
          skipOffstage: false), findsOneWidget);
      await app.tap(tester, 'code15-record-share-button');
      expect(app.shared.single.endsWith(app.record.readAll()), isTrue);
      await app.positions.close();
    });

    testWidgets('the card draws the disclosure and the count line from '
        'AppL10n, and no left-behind card', (tester) async {
      final app = _App(dir);
      await app.boot(tester);
      expect(_textOf(tester, 'code15-record-disclosure'),
          contains('コード13と違い、新しい版を入れても消えません。'));
      final count = tester.widget<KeepTogetherText>(
          find.byKey(const Key('code15-record-count'), skipOffstage: false));
      expect(count.data,
          'まだ最低限に達していません（アプリの数え方で）。これまでに数えたのは、'
          '走行0分（30分以上必要）、停車0分（5分以上必要）です。');
      expect(count.words,
          const AppL10n(Locale('ja'))
              .code15RecordCountKeep(movingMinutes: 0, stoppedMinutes: 0),
          reason: 'the Japanese is drawn with the keep list');
      expect(count.words, containsAll(['最低限', '（アプリの数え方で）', '30分', '5分']));
      final drawn = tester.widget<Text>(find.descendant(
          of: find.byKey(const Key('code15-record-count'), skipOffstage: false),
          matching: find.byType(Text, skipOffstage: false)));
      expect(drawn.semanticsLabel, count.data,
          reason: 'the plain words are the semantics label');
      expect(drawn.data, contains(kWordJoiner),
          reason: 'control: the drawn string carries the joiners');
      expect(
          find.ancestor(
            of: find.byKey(const Key('code15-record-count'), skipOffstage: false),
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && (w.properties.liveRegion ?? false),
                skipOffstage: false),
          ),
          findsNothing,
          reason: 'the count line is never inside a live region');
      expect(find.text('前の版の測位間隔の記録', skipOffstage: false), findsNothing);
      expect(find.textContaining('この版は記録しません', skipOffstage: false),
          findsNothing);
      for (final k in [
        'left-behind-record-status',
        'left-behind-record-share-button',
        'left-behind-record-delete-button',
      ]) {
        expect(find.byKey(Key(k), skipOffstage: false), findsNothing);
      }
    });

    testWidgets('with no record the card says it cannot be opened and offers '
        'no action', (tester) async {
      _clockNow = DateTime.utc(2026, 1, 14, 21);
      await tester.pumpWidget(SngnavApp(
        locationConsent: true,
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        clock: () => _clockNow,
        jmaFetch: () async => JmaSuccess(_clear()),
      ));
      await _settle(tester);
      expect(_textOf(tester, 'code15-record-status'),
          'この端末では測位間隔の記録を開けません。');
      final share = tester.widget<TextButton>(find.byKey(
          const Key('code15-record-share-button'), skipOffstage: false));
      expect(share.onPressed, isNull);
    });
  });
}
