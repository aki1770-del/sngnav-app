/// The test builds' records on his page, ON CODE 15: code 15's own recording
/// card (test/widgets/code15_record_card_test.dart holds it), never the
/// left-behind card, and the one line that tells him this version deleted
/// code 13's record (option L).
///
/// Why, written before the act. On main this file held the left-behind card
/// (2026-10-09). Code 15 records, so that card's 「この版は記録しません」 /
/// "This version does not record" would be false here: it is not drawn on
/// this build, even with code 15's files present, and its five tests are
/// replaced by the one below that pins its absence. L is unchanged from main:
/// a deletion that took a reading must not be silent (Sakichi Vision 14). Its
/// three tests are main's, with the left-behind card replaced by code 15's.
///
/// HONEST BOUND. A widget tree in a test binding: not a phone, not a seen
/// frame.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/code13_record_cleanup.dart';
import 'package:sngnav_app/services/code15_fix_interval_record.dart';
import 'package:sngnav_app/services/fix_interval_record_keeper.dart';

import '../support/fake_alert_actuators.dart';
import '../support/test_record_writer.dart';

// The dignity read's words (W3), verbatim. Pinned here as literals so a
// paraphrase in app_localizations.dart fails.
const _lJa =
    '前の版の測位間隔の記録を、この版が削除しました。'
    '「記録を共有」で送っていなければ、その記録はもう残っていません。'
    'あなたがすることはありません。';
const _lEn =
    'This version deleted the fix-interval record from the earlier '
    'version. If you had not sent it with Share record, it no longer exists. '
    'Nothing is asked of you.';

const _status = Key('code15-record-status');
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

  Code15FixIntervalRecord keptRecord() {
    File('${dir.path}/$kCode15RecordFileName').writeAsStringSync(lines);
    return Code15FixIntervalRecord(writer: kTestRecordWriter, directory: dir);
  }

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('ja'),
    Code15FixIntervalRecord? record,
    Code13RecordDeletion? deletion,
  }) async {
    await tester.pumpWidget(
      SngnavApp(
        locale: locale,
        code15Record: record,
        code13Deletion: deletion,
        code15RecordShareSink: (_) async {},
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

  testWidgets('with code 15\'s record on this phone, the left-behind card is '
      'not drawn: its words would be false on a build that records', (
    tester,
  ) async {
    for (final locale in const [Locale('ja'), Locale('en')]) {
      await pump(tester, locale: locale, record: keptRecord());
      await reveal(tester, _status);
      expect(find.text('前の版の測位間隔の記録'), findsNothing);
      expect(find.text('Fix-interval record from an earlier version'),
          findsNothing);
      expect(find.textContaining('この版は記録しません'), findsNothing);
      expect(find.textContaining('This version does not record'),
          findsNothing);
      for (final k in [
        'left-behind-record-status',
        'left-behind-record-share-button',
        'left-behind-record-delete-button',
      ]) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect(find.byKey(_status), findsOneWidget,
          reason: 'code 15\'s own card is drawn instead');
    }
  });

  testWidgets('L, Japanese and English: the dignity read\'s words verbatim; '
      'not drawn when nothing was told', (tester) async {
    await pump(tester, deletion: _told);
    await reveal(tester, _notice);
    expect(textOf(tester, _notice), _lJa);

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

  testWidgets('L and code 15\'s card together: both drawn, L first', (
    tester,
  ) async {
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
