/// The test builds' records on his page: the left-behind card for code 15's
/// kept record, and the one line that tells him this version deleted code
/// 13's record (option L).
///
/// Why, written before the act (2026-10-09). If a later build kept the record
/// but removed his way to see and delete it, his data would stay with no way
/// out short of clearing all the app's data, his diary included (Sakichi
/// Vision 24: the machine yields to the person). And a deletion that took a
/// reading must not be silent (Sakichi Vision 14). These hold, on the real
/// app tree:
/// - the card's words are the 2026-10-09 dignity read's (WDA W3), verbatim,
///   in Japanese and English, with 記録を共有 and 記録を消す;
/// - 記録を共有 hands every line to the sink and deletes nothing;
/// - 記録を消す deletes both files and the section goes;
/// - with nothing to show, the section is not drawn at all;
/// - L's line is the dignity read's words, verbatim; it is not shown while a
///   share runs, and comes back after 停止.
///
/// HONEST BOUND. A widget tree in a test binding, with an injected share sink:
/// not the OS share sheet, not a phone, not a seen frame.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/code13_record_cleanup.dart';
import 'package:sngnav_app/services/fix_interval_record_keeper.dart';

import '../support/fake_alert_actuators.dart';

// The dignity read's words (WDA W3), verbatim. Pinned here as literals so a
// paraphrase in app_localizations.dart fails.
const _cardJa =
    '前の版の測位間隔の記録が残っています。この版は記録しません。'
    '記録は「記録を消す」を押すまで、この端末に残ります'
    '（Google のバックアップや、新しい端末へのデータ移行には含まれません）。';
const _cardEn =
    'A fix-interval record from the earlier version is still on '
    'this phone. This version does not record. It stays here until you tap '
    "Delete record (it is not included in Google's backup or in a transfer to "
    'a new phone).';
const _lJa =
    '前の版の測位間隔の記録を、この版が削除しました。'
    '「記録を共有」で送っていなければ、その記録はもう残っていません。'
    'あなたがすることはありません。';
const _lEn =
    'This version deleted the fix-interval record from the earlier '
    'version. If you had not sent it with Share record, it no longer exists. '
    'Nothing is asked of you.';

const _status = Key('left-behind-record-status');
const _share = Key('left-behind-record-share-button');
const _delete = Key('left-behind-record-delete-button');
const _notice = Key('code13-record-deleted-notice');

const _told = Code13RecordDeletion(deletedFiles: 2, recordHeldFixLines: true);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('test_build_records_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const lines =
      's=0 t=0 k=launch\n'
      's=1 t=0 k=start a=- v=- late=- fg=1\n'
      's=1 t=5004 k=fine a=3.9 v=12.0 late=210 fg=1\n';

  LeftBehindFixIntervalRecord keptRecord() {
    File('${dir.path}/$kCode15RecordFileName').writeAsStringSync(lines);
    File('${dir.path}/$kCode15StoppedFileName').writeAsStringSync('stopped\n');
    return LeftBehindFixIntervalRecord(directory: dir);
  }

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('ja'),
    LeftBehindFixIntervalRecord? record,
    Code13RecordDeletion? deletion,
    LeftBehindRecordShareSink? sink,
  }) async {
    await tester.pumpWidget(
      SngnavApp(
        locale: locale,
        leftBehindRecord: record,
        code13Deletion: deletion,
        leftBehindRecordShareSink: sink ?? (_) async {},
      ),
    );
    await tester.pump();
  }

  Future<void> reveal(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
  }

  String textOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  testWidgets('nothing to show: no section, no words, no buttons', (
    tester,
  ) async {
    await pump(
      tester,
      record: LeftBehindFixIntervalRecord(directory: dir),
      deletion: Code13RecordDeletion.none,
    );
    expect(find.text('前の版の測位間隔の記録'), findsNothing);
    for (final k in [_status, _share, _delete, _notice]) {
      expect(find.byKey(k), findsNothing);
    }
  });

  testWidgets('the left-behind card, Japanese: the dignity read\'s words '
      'verbatim, with 記録を共有 and 記録を消す', (tester) async {
    await pump(tester, record: keptRecord());
    await reveal(tester, _status);
    expect(find.text('前の版の測位間隔の記録'), findsOneWidget);
    expect(textOf(tester, _status), _cardJa);
    expect(
      find.descendant(of: find.byKey(_share), matching: find.text('記録を共有')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(_delete), matching: find.text('記録を消す')),
      findsOneWidget,
    );
    expect(find.byKey(_notice), findsNothing);
  });

  testWidgets('the left-behind card, English: verbatim', (tester) async {
    await pump(tester, locale: const Locale('en'), record: keptRecord());
    await reveal(tester, _status);
    expect(
      find.text('Fix-interval record from an earlier version'),
      findsOneWidget,
    );
    expect(textOf(tester, _status), _cardEn);
    expect(find.text('Share record'), findsOneWidget);
    expect(find.text('Delete record'), findsOneWidget);
  });

  testWidgets('記録を共有 hands every line to the sink and deletes nothing', (
    tester,
  ) async {
    final shared = <String>[];
    await pump(tester, record: keptRecord(), sink: (p) async => shared.add(p));
    await reveal(tester, _share);
    await tester.tap(find.byKey(_share));
    await tester.pump();
    expect(shared, hasLength(1));
    expect(shared.single, contains('---\n$lines'));
    expect(
      File('${dir.path}/$kCode15RecordFileName').readAsStringSync(),
      lines,
    );
    expect(
      find.byKey(_status),
      findsOneWidget,
      reason: 'the card stays: a share result cannot say the text arrived',
    );
  });

  testWidgets('記録を消す deletes both files, and the section goes', (tester) async {
    await pump(tester, record: keptRecord());
    await reveal(tester, _delete);
    await tester.tap(find.byKey(_delete));
    await tester.pump();
    for (final name in kCode15RecordFileNames) {
      expect(File('${dir.path}/$name').existsSync(), isFalse);
    }
    expect(find.byKey(_status), findsNothing);
    expect(find.text('前の版の測位間隔の記録'), findsNothing);
  });

  testWidgets('L, Japanese and English: the dignity read\'s words verbatim; '
      'not drawn when nothing was told', (tester) async {
    await pump(tester, deletion: _told);
    await reveal(tester, _notice);
    expect(textOf(tester, _notice), _lJa);
    expect(
      find.byKey(_status),
      findsNothing,
      reason: 'no record left behind: L alone',
    );

    await pump(tester, locale: const Locale('en'), deletion: _told);
    await reveal(tester, _notice);
    expect(textOf(tester, _notice), _lEn);

    await pump(
      tester,
      deletion: const Code13RecordDeletion(
        deletedFiles: 1,
        recordHeldFixLines: false,
      ),
    );
    expect(find.byKey(_notice), findsNothing);
  });

  testWidgets('L and the card together: both drawn, L first', (tester) async {
    await pump(tester, record: keptRecord(), deletion: _told);
    await reveal(tester, _status);
    expect(find.byKey(_notice), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(_notice)).dy,
      lessThan(tester.getTopLeft(find.byKey(_status)).dy),
    );
  });

  testWidgets('L is not shown while a share runs, and comes back after 停止', (
    tester,
  ) async {
    var clock = DateTime.utc(2026, 1, 14, 21);
    final positions = StreamController<PositionFix>.broadcast();
    addTearDown(positions.close);
    await tester.pumpWidget(
      SngnavApp(
        locationConsent: true,
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        clock: () => clock,
        jmaFetch: () async => const JmaFailure('no network in this test'),
        positionSource: () => positions.stream,
        code13Deletion: _told,
      ),
    );
    await tester.pump();
    await reveal(tester, _notice);
    expect(find.byKey(_notice), findsOneWidget);

    final share = find.byKey(const Key('share-location-button'));
    await tester.ensureVisible(share);
    await tester.pump();
    await tester.tap(share);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(_notice),
      findsNothing,
      reason: 'the line is for a parked glance, never while she shares',
    );

    final stop = find.widgetWithText(TextButton, '停止');
    await tester.ensureVisible(stop.first);
    await tester.pump();
    await tester.tap(stop.first);
    await tester.pump();
    clock = clock.add(const Duration(seconds: 1));
    await tester.pump();
    expect(
      find.byKey(_notice),
      findsOneWidget,
      reason: 'the same launch: told after the share ends',
    );
  });
}
