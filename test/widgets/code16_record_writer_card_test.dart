/// His record's card says when this build cannot name itself, and so is not
/// recording (code 16, 2026-10-14).
///
/// WHY, written before the act. A build that cannot read its own version
/// number writes no line of any kind into his record: a line it wrote would be
/// read as an earlier build's. A card that still read as recording would then
/// be a success-shaped value over a record that is not being written (Sakichi
/// Vision 14). The build names itself after the page is up (the platform's
/// answer takes about a second), so the card must also redraw when that
/// answer comes, without a tap.
///
/// HONEST BOUND. A test binding, not a phone; the words are drafted with the
/// code and read by the screen and dignity reviews before they reach a phone.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/code15_fix_interval_record.dart';
import 'package:sngnav_app/widgets/keep_together.dart';

import '../support/fake_alert_actuators.dart';
import '../support/test_record_writer.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('code16_writer_card');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  const l = AppL10n(Locale('ja'));

  Future<void> boot(WidgetTester tester, Code15FixIntervalRecord record) async {
    final positions = StreamController<PositionFix>.broadcast();
    addTearDown(positions.close);
    await tester.pumpWidget(SngnavApp(
      locale: const Locale('ja'),
      actuators: FakeAlertActuators(),
      clock: () => DateTime.utc(2026, 1, 14, 21),
      jmaFetch: () async => const JmaFailure('test: no observation'),
      positionSource: () => positions.stream,
      code15Record: record,
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  String status(WidgetTester tester) => tester
      .widget<KeepTogetherText>(find.byKey(const Key('code15-record-status'),
          skipOffstage: false))
      .data;

  testWidgets('control: a build that names itself draws no such note',
      (tester) async {
    final r = Code15FixIntervalRecord(
        directory: Directory('${tmp.path}/a')..createSync(),
        writer: kTestRecordWriter);
    await boot(tester, r);
    expect(status(tester), isNot(contains(l.code15RecordCannotNameBuildNote)));
  });

  testWidgets('a build that cannot name itself says so first on the card',
      (tester) async {
    final r = Code15FixIntervalRecord(
        directory: Directory('${tmp.path}/b')..createSync(),
        writer: RecordWriter.unreadable);
    await boot(tester, r);
    expect(status(tester), startsWith(l.code15RecordCannotNameBuildNote));
  });

  testWidgets('the naming arrives after the page is up: the card redraws with '
      'no tap', (tester) async {
    final r = Code15FixIntervalRecord(
        directory: Directory('${tmp.path}/c')..createSync(), writer: null);
    await boot(tester, r);
    expect(status(tester), isNot(contains(l.code15RecordCannotNameBuildNote)),
        reason: 'control: not named yet');
    r.nameWriter(RecordWriter.unreadable);
    await tester.pump();
    expect(status(tester), startsWith(l.code15RecordCannotNameBuildNote));
  });
}
