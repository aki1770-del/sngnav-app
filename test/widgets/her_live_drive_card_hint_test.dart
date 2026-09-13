/// The live-drive card must not tell her to share her location while she is
/// sharing it.
///
/// Why this test exists. Rendered 2026-09-14: after a GPS stream error, while
/// she was sharing, the card read "Share a location (Akita mock or GPS) above
/// to start the drive brain." The hint was keyed on "the last event is a
/// fix", so every sharing state without one (no event yet, a stream error,
/// services off) told her to do what she had already done, beside a line
/// under the map that named the real state.
///
/// The rule tested here. The hint is an instruction to share, so it shows
/// only when she is not sharing. Run in English, where the hint's bytes are
/// the same before and after this change.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

const _hint =
    'Share a location (Akita mock or GPS) above to start the drive brain.';

Future<StreamController<PositionFix>> _boot(WidgetTester tester) async {
  final positions = StreamController<PositionFix>.broadcast();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: FakeAlertActuators(),
    locale: const Locale('en'),
    clock: () => DateTime.utc(2026, 1, 14, 21),
    jmaFetch: () async => const JmaFailure('no network in this test'),
    positionSource: () => positions.stream,
  ));
  await tester.pump();
  await tester.pump();
  return positions;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
}

final _share = find.byKey(const Key('share-location-button'));

void main() {
  testWidgets('CONTROL: not sharing, the card says to share', (tester) async {
    final p = await _boot(tester);
    expect(find.text(_hint), findsOneWidget);
    await p.close();
  });

  testWidgets('sharing, no position event yet: no instruction to share',
      (tester) async {
    final p = await _boot(tester);
    await _tap(tester, _share);
    expect(find.text(_hint), findsNothing);
    await p.close();
  });

  testWidgets('sharing, after a stream error: no instruction to share',
      (tester) async {
    final p = await _boot(tester);
    await _tap(tester, _share);
    p.addError(StateError('platform GPS stream failed'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('GPS stream error'), findsOneWidget,
        reason: 'precondition: the stream error reached the line');
    expect(find.text(_hint), findsNothing);
    await p.close();
  });

  testWidgets('after Stop, not sharing again: the hint is back',
      (tester) async {
    final p = await _boot(tester);
    await _tap(tester, _share);
    p.addError(StateError('platform GPS stream failed'));
    await tester.pump();
    await _tap(tester, find.widgetWithText(TextButton, 'Stop'));
    expect(find.text(_hint), findsOneWidget);
    await p.close();
  });
}
