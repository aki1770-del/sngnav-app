/// Back during a drive sends the app to the background and the drive runs on;
/// with no drive running, Back leaves the app exactly as it did before.
///
/// WHY, written before the act (AAE, R122 round 5a). A safety review ruled
/// that no drive may end, on anything she presses, without telling her at
/// that moment through a channel that works with her eyes off the screen, and
/// held the rule in drive_back_is_never_a_silent_end_test.dart. That test is
/// neutral between the two designs it allows. The design built is the first
/// one: Back during a drive does not end it, and the app goes to the
/// background as it does with Home (lib/services/app_task.dart says why).
///
/// This file pins WHICH design shipped, and its edges, so that neither of the
/// two ways it could quietly change goes unnoticed:
/// - Back during a drive turning into "nothing happens": the app must ASK to
///   be moved to the background, once.
/// - Back with no drive being captured too: with nothing running there is
///   nothing to protect, and Back must still leave the app, as before.
/// And when the platform cannot move the app, the drive keeps running on the
/// screen she is looking at, with 停止 on it.
///
/// BOUNDS. The platform half (Activity.moveTaskToBack in MainActivity.kt) is
/// not reached here: the channel is answered by the test. Whether the drive
/// notification and the position stream survive the move on her phone is for
/// a device to show.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/app_task.dart';

import '../support/fake_alert_actuators.dart';

const _ja = AppL10n(Locale('ja'));
final _now = DateTime.utc(2026, 1, 14, 21, 40);

Future<JmaResult> _jma() async => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: 1500,
      observedAtJstKey: '202601150630',
      fetchedAt: _now,
    ));

/// Records every SystemNavigator.pop and every request to move the task to
/// the back, in one ordered log. [moved] is what the platform answers.
void _recordPlatform(List<String> log, {bool moved = true}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') log.add('pop');
    return null;
  });
  messenger.setMockMethodCallHandler(AppTask.channel, (call) async {
    log.add('task:${call.method}');
    return moved;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(AppTask.channel, null);
  });
}

Future<StreamController<PositionFix>> _boot(WidgetTester tester) async {
  final ctrl = StreamController<PositionFix>.broadcast();
  addTearDown(ctrl.close);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    locationConsent: true,
    actuators: FakeAlertActuators(),
    locale: const Locale('ja'),
    clock: () => _now,
    jmaFetch: _jma,
    positionSource: () => ctrl.stream,
  ));
  await tester.pump();
  await tester.pump();
  return ctrl;
}

Future<void> _startDrive(
    WidgetTester tester, StreamController<PositionFix> ctrl) async {
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  expect(ctrl.hasListener, isTrue, reason: 'control: a drive is running');
  ctrl.add(PositionAvailable(
    latitude: 39.7186,
    longitude: 140.1024,
    accuracyMeters: 8,
    timestamp: _now,
  ));
  await tester.pump();
  await tester.pump();
  expect(find.widgetWithText(TextButton, _ja.stop), findsOneWidget,
      reason: 'control: the running drive offers 停止');
}

Future<List<String>> _pressBack(WidgetTester tester, List<String> log) async {
  final before = log.length;
  await tester.binding.handlePopRoute();
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  return log.sublist(before);
}

void main() {
  testWidgets('during a drive, Back asks once for the background, does not '
      'pop, and the drive runs on', (tester) async {
    final log = <String>[];
    _recordPlatform(log);
    final ctrl = await _boot(tester);
    await _startDrive(tester, ctrl);

    final after = await _pressBack(tester, log);

    expect(after, ['task:moveTaskToBack'],
        reason: 'Back during a drive sends the app to the background, as '
            'Home does, and never pops: $after');
    expect(ctrl.hasListener, isTrue,
        reason: 'the position stream is still listened to: the drive runs');
    expect(find.widgetWithText(TextButton, _ja.stop), findsOneWidget,
        reason: '停止 is still the way to end it');
  });

  testWidgets('with no drive running, Back leaves the app as it always did',
      (tester) async {
    final log = <String>[];
    _recordPlatform(log);
    final ctrl = await _boot(tester);
    expect(ctrl.hasListener, isFalse, reason: 'control: no drive');

    final after = await _pressBack(tester, log);

    expect(after, ['pop'],
        reason: 'nothing is running to protect, so Back is not captured: '
            '$after');
  });

  testWidgets('after 停止, Back leaves the app as it always did',
      (tester) async {
    final log = <String>[];
    _recordPlatform(log);
    final ctrl = await _boot(tester);
    await _startDrive(tester, ctrl);
    final stop = find.widgetWithText(TextButton, _ja.stop);
    await tester.ensureVisible(stop);
    await tester.pump();
    await tester.tap(stop);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(ctrl.hasListener, isFalse, reason: 'control: 停止 ended the drive');

    final after = await _pressBack(tester, log);

    expect(after, ['pop'], reason: 'the drive has ended: $after');
  });

  testWidgets('when the platform cannot move the app, it stays on screen with '
      'the drive running and 停止 on it', (tester) async {
    final log = <String>[];
    _recordPlatform(log, moved: false);
    final ctrl = await _boot(tester);
    await _startDrive(tester, ctrl);

    final after = await _pressBack(tester, log);

    expect(after, ['task:moveTaskToBack'],
        reason: 'asked once, refused, and never popped: $after');
    expect(ctrl.hasListener, isTrue, reason: 'the drive runs');
    expect(find.widgetWithText(TextButton, _ja.stop), findsOneWidget);
  });
}
