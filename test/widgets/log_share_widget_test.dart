// C6 ログを共有 — the share-log button wired end-to-end in the widget tree.
//
// A recording fake LogShareSink is injected (SngnavApp.logShareSink), so the
// platform share channel is NEVER touched in the test binding: the test taps
// the real button and asserts the REAL payload the production composer
// produced. Semantics are pinned to the same OPS-059 floor as the consent
// buttons (label + button + tap action + focusable + >=48px tap target).
//
// HONESTY (OPS-066 / AAE env-bound): this verifies the WIDGET TREE and the
// payload handed to the sink. It does NOT verify the OS share sheet — there
// is no Android device/emulator in this env. On-device observation is
// DEFERRED (docs/on_device_verify_checklist.md lane).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/build_info.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/services/log_share.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sngnav_log_share_widget');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  LocalErrorLog makeLog() =>
      LocalErrorLog(file: File('${tmp.path}/error_log.txt'));

  Future<void> pumpAndReveal(
    WidgetTester tester, {
    required LocalErrorLog log,
    required LogShareSink sink,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(SngnavApp(
      locale: locale,
      errorLog: log,
      logShareSink: sink,
    ));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('share-log-button')));
    await tester.pump();
  }

  testWidgets('tap ログを共有 -> the sink receives header + the seeded log, '
      'and NO position state', (tester) async {
    final log = makeLog();
    log.record(StateError('widget boom'), StackTrace.current,
        source: 'FlutterError');

    final captured = <String>[];
    await pumpAndReveal(tester, log: log, sink: (payload) async {
      captured.add(payload);
    });

    await tester.tap(find.byKey(const Key('share-log-button')));
    await tester.pump();

    expect(captured, hasLength(1),
        reason: 'one tap must fire exactly one share');
    final payload = captured.single;
    expect(payload, contains('sngnav-app $appVersion'));
    expect(payload, contains(kErrorLogEntryMarker));
    expect(payload, contains('widget boom'));
    // Consent floor: the akitaStation mock coordinates (akita_map.dart)
    // must never ride along — the payload is strictly header + log.
    expect(payload, isNot(contains('39.7167')));
    expect(payload, isNot(contains('140.0983')));
  });

  testWidgets('empty log: tap shares the honest empty line, never '
      'fabricated content', (tester) async {
    final log = makeLog(); // nothing recorded

    final captured = <String>[];
    await pumpAndReveal(tester, log: log, sink: (payload) async {
      captured.add(payload);
    });

    // Status line states the empty state before the tap.
    expect(
      find.text('The log is empty (no crash or error records).'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('share-log-button')));
    await tester.pump();

    expect(captured, hasLength(1));
    expect(captured.single, contains(kLogShareEmptyLine));
    expect(captured.single, isNot(contains(kErrorLogEntryMarker)));
  });

  testWidgets('share-log button exposes the assistive-tech floor '
      '(button + tap action + focusable + non-zero >=48px rect)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final log = makeLog();
    await pumpAndReveal(tester, log: log, sink: (_) async {});

    final finder = find.byKey(const Key('share-log-button'));
    final node = tester.getSemantics(finder);
    expect(
      node,
      matchesSemantics(
        label: 'Share log',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
      reason: 'share-log-button must be a real, labelled, tappable '
          'semantics target',
    );
    final paintBounds = node.rect;
    expect(paintBounds.isEmpty, isFalse,
        reason: 'semantics rect must not be zero-size when visible');
    expect(paintBounds.height, greaterThanOrEqualTo(48.0),
        reason: 'tap target must be at least 48 logical px tall (OPS-059)');
    expect(paintBounds.width, greaterThan(0));

    semantics.dispose();
  });

  testWidgets('no log handle (crash boundary unavailable): the action is '
      'honestly disabled, the sink never fires', (tester) async {
    final captured = <String>[];
    await tester.pumpWidget(SngnavApp(
      locale: const Locale('en'),
      // errorLog deliberately null.
      logShareSink: (payload) async => captured.add(payload),
    ));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('share-log-button')));
    await tester.pump();

    expect(
      find.text('The error log is unavailable in this environment.'),
      findsOneWidget,
    );
    final button = tester
        .widget<TextButton>(find.byKey(const Key('share-log-button')));
    expect(button.onPressed, isNull,
        reason: 'no log -> the share action must be disabled, not lying');
    expect(captured, isEmpty);
  });
}
