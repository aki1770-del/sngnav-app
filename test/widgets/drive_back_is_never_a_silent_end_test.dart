/// A system Back during a drive never ends the drive without telling her.
///
/// WHY, written before the act (FSE, R122 round 4b). HIE measured on an
/// Android 14 emulator that Back, pressed while a drive ran, removed the app's
/// GPS registration and withdrew the drive notification, and that nothing told
/// her. Read at source (sngnav-app 2d51bdc, Flutter 3.45.0-1.0.pre-48): the
/// page has no PopScope and no route to pop, so WidgetsBinding.handlePopRoute
/// calls SystemNavigator.pop(); FlutterActivity extends a plain Activity, so
/// PlatformPlugin.popSystemNavigator() calls activity.finish(); an activity
/// that created its own engine destroys it; dispose() cancels the position
/// subscription. No Dart code gets a turn to tell her.
///
/// What she believes afterwards is what the consent told her: the drive
/// continues when she switches to another app, and 停止 ends it. The same
/// words tell her the notification may not show on a locked screen and can be
/// swiped away while the drive continues, so its disappearance is, by our own
/// words, no sign that the drive ended. She has no cue left.
/// For a driver in unexpected snow, silence from the app after that reads
/// as "nothing to warn about": Vision 14, a success-shaped state over a
/// function that has stopped.
///
/// THE INVARIANT, neutral between the two designs AAE may choose:
///   (a) Back during a drive does not end it: SystemNavigator.pop is not
///       called, and the drive is still running; or
///   (b) Back ends it, and the app asks to speak to her before it calls
///       SystemNavigator.pop.
/// Either passes. What fails is a pop with nothing said first.
///
/// BOUNDS.
/// - The fake actuators prove the app ASKED to speak, not that she heard it,
///   and not that speech finished before the engine went away. Under (b) the
///   pop must wait for the spoken line to complete; this test cannot see that.
/// - The words of (b) are AAA's; this test does not read them.
/// - Removal from the recent-apps list, an OS or MIUI kill, and a crash end
///   the engine with no Dart code running. No test at this layer reaches
///   them; they are the residual of the same class.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

const _ja = AppL10n(Locale('ja'));

final _now = DateTime.utc(2026, 1, 14, 21, 40);

/// Records speech into the same ordered log the platform mock writes to, so
/// the order of "asked to speak" and "SystemNavigator.pop" is measured, not
/// assumed.
class _OrderedActuators extends FakeAlertActuators {
  _OrderedActuators(this.log);
  final List<String> log;

  @override
  Future<void> speak(String text, {required String localeTag}) {
    log.add('speak:$text');
    return super.speak(text, localeTag: localeTag);
  }
}

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

/// Records every SystemNavigator.pop into [log]. Returns nothing for every
/// other platform call, as the test binding does with no handler.
void _recordPops(List<String> log) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') log.add('pop');
    return null;
  });
  addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

/// Boots the app with a remembered yes and starts a drive on an injected
/// position stream, then gives it one measured fix.
Future<StreamController<PositionFix>> _startDrive(
    WidgetTester tester, List<String> log) async {
  final ctrl = StreamController<PositionFix>.broadcast();
  addTearDown(ctrl.close);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    locationConsent: true,
    actuators: _OrderedActuators(log),
    locale: const Locale('ja'),
    clock: () => _now,
    jmaFetch: _jma,
    positionSource: () => ctrl.stream,
  ));
  await tester.pump();
  await tester.pump();
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  expect(ctrl.hasListener, isTrue,
      reason: 'control: a drive is running (the position stream is listened '
          'to)');
  ctrl.add(PositionAvailable(
    latitude: 39.7186,
    longitude: 140.1024,
    accuracyMeters: 8,
    timestamp: _now,
  ));
  await tester.pump();
  await tester.pump();
  expect(find.widgetWithText(TextButton, _ja.stop), findsWidgets,
      reason: 'control: the running drive offers 停止');
  return ctrl;
}

void main() {
  testWidgets(
      'instrument control: a SystemNavigator.pop is recorded when one happens',
      (tester) async {
    final log = <String>[];
    _recordPops(log);
    await SystemNavigator.pop();
    expect(log, ['pop'],
        reason: 'the mock must see a pop, or "no pop" below means nothing');
  });

  testWidgets('Back during a drive does not end it without telling her',
      (tester) async {
    final log = <String>[];
    _recordPops(log);
    final ctrl = await _startDrive(tester, log);

    final before = log.length;
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    final after = log.sublist(before);
    final popAt = after.indexOf('pop');

    if (popAt < 0) {
      // (a) Back was not an exit. Then the drive must still be running, or
      // Back ended it by some other road, still unannounced.
      expect(ctrl.hasListener, isTrue,
          reason: 'Back did not exit, yet the position stream was dropped: '
              'the drive ended with nothing said');
      expect(find.widgetWithText(TextButton, _ja.stop), findsWidgets,
          reason: 'Back did not exit, yet 停止 is gone: the drive ended');
    } else {
      // (b) Back exits. She must have been spoken to first.
      final spokenFirst =
          after.sublist(0, popAt).where((e) => e.startsWith('speak:'));
      expect(spokenFirst, isNotEmpty,
          reason: 'Back ended the drive (SystemNavigator.pop, which finishes '
              'the activity and destroys the engine, and with it the '
              'position stream and the drive notification), and nothing was '
              'spoken to her first. The consent she read says the drive '
              'continues when she switches apps and that 停止 ends it. '
              'Log after Back: $after');
    }
  });
}
