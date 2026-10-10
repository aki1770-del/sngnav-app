/// A share WITHOUT its foreground service ends when the app is no longer in
/// front, and she is told once. It is never left running on a silence the
/// platform made.
///
/// WHY (ruled 2026-10-06 by a safety review, and audited). Without the service,
/// her fixes stop as soon as the app is not in front, for the platform's
/// reason. The app read that as a GPS loss and told her the stop line.
/// her_share_without_service_test.dart holds that no GPS-loss caution is told.
/// These tests hold what the audit added:
///   - at the moment she leaves: exactly ONE line handed to the announcer, with
///     a haptic, and no repeat while she stays away. A silent halt would leave
///     her believing her warnings still run;
///   - on her return: the page shows the share as not running;
///   - the boundary (amended the same day): the app no longer VISIBLE, hidden
///     or paused. `inactive` (a dialog, the shade, a call's heads-up) ends
///     nothing and tells nothing, and the GPS-loss reading runs there exactly
///     as in front;
///   - the service is a positive reading: a service-mode share whose stream
///     fails before its first fix is read as having no service;
///   - while a share runs without its service, the running row says it runs
///     only while the app is on screen.
///
/// The told line is the HMI review's, pinned here byte for byte: it is also the
/// offline voice catalog's lookup key. No new symbol is imported, so these
/// tests also run on a build without the rule, and fail there by behaviour.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/notification_permission.dart';

import '../support/fake_alert_actuators.dart';

const String _slowDown = '速度を落とし、車間を広げて、前方に注意してください。';
const String _stopLine = '安全にできるときは、安全な場所での停車も選べます。';
const String _notShared = '位置情報は共有されていません。';
const String _n1 = 'アプリが画面から離れたため、現在地の警告は止まりました。';
const double _v = 15;

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

Position _fix(double northM) => Position(
  latitude: 39.7186 + northM / 111194.93,
  longitude: 140.1024,
  timestamp: _clockNow,
  accuracy: 10,
  hasAccuracy: true,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: _v,
  hasSpeed: true,
  speedAccuracy: 1.5,
  hasSpeedAccuracy: true,
);

JmaObservation _clearObs() => JmaObservation(
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

/// [canPost] true: the app's notification read answers "can post", so the share
/// is built with its service. False: the channel as the test binding has it,
/// which the app reads as "cannot post".
Future<(FakeAlertActuators, StreamController<Position>)> _bootAndShare(
  WidgetTester tester, {
  required bool canPost,
  bool broadcast = false,
}) async {
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
  final a = FakeAlertActuators();
  // Broadcast when a test starts a second share on the same source.
  final positions = broadcast
      ? StreamController<Position>.broadcast()
      : StreamController<Position>();
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    SngnavApp(
      locationConsent: true,
      actuators: a,
      locale: const Locale('ja'),
      clock: () => _clockNow,
      jmaFetch: () async => JmaSuccess(_clearObs()),
      positionSource: () => herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        positionStream: () => positions.stream,
      ),
    ),
  );
  await _settle(tester);
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  await _settle(tester);
  return (a, positions);
}

Future<void> _drive(
  WidgetTester tester,
  StreamController<Position> positions,
) async {
  var north = 0.0;
  for (var i = 0; i < 4; i++) {
    if (i > 0) {
      await _advance(tester, const Duration(seconds: 5));
      north += _v * 5;
    }
    positions.add(_fix(north));
    await _settle(tester);
  }
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

/// What was told since [sb] spoken lines and [fb] cues felt. Every cue is
/// read from `felt`, which records the ended cue too: since 2026-10-10 the
/// line told here carries the ended cue (one long pulse), which `haptics`,
/// the warning grammar alone, never records. Read from `haptics`, a repeat of
/// this line while she is away would have been invisible.
(List<String>, List<String>) _toldSince(FakeAlertActuators a, int sb, int fb) =>
    (a.spoken.skip(sb).map((x) => x.text).toList(), a.felt.skip(fb).toList());

bool _running(WidgetTester tester) => find
    .widgetWithText(TextButton, '停止', skipOffstage: false)
    .evaluate()
    .isNotEmpty;

bool _shownNotShared(WidgetTester tester) =>
    find.text(_notShared, skipOffstage: false).evaluate().isNotEmpty &&
    find
        .byKey(const Key('share-location-button'), skipOffstage: false)
        .evaluate()
        .isNotEmpty;

Future<void> _silence(WidgetTester tester, int seconds) async {
  for (var s = 0; s < seconds; s++) {
    await _advance(tester, const Duration(seconds: 1));
  }
  await _settle(tester);
}

void main() {
  testWidgets(
    'N1: no service, she leaves: ONE line and a haptic at that moment, none '
    'more while she is away, and on return the share reads not running',
    (tester) async {
      final (a, positions) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, positions);
      expect(_running(tester), isTrue, reason: 'control: the share runs');

      var sb = a.spoken.length, hb = a.felt.length;
      await _to(tester, _leave);
      final (atLeave, hapticsAtLeave) = _toldSince(a, sb, hb);
      expect(
        atLeave,
        hasLength(1),
        reason:
            'THE DEFECT: a silent halt leaves her believing her warnings '
            'still run; she is told once, at the moment she leaves: $atLeave',
      );
      expect(atLeave.single, _n1,
          reason: 'what she is told is that the share stopped, not a GPS loss');
      expect(hapticsAtLeave, ['ended'],
          reason: 'the line comes with one cue, for the driver who cannot '
              'hear it: the ended cue, one long pulse, never the warning '
              'pattern, which tells her to slow down (2026-10-10)');

      sb = a.spoken.length;
      hb = a.felt.length;
      await _silence(tester, 75);
      final (whileAway, hapticsAway) = _toldSince(a, sb, hb);
      expect(whileAway, isEmpty, reason: 'no repeat while away: $whileAway');
      expect(hapticsAway, isEmpty);

      await _to(tester, _back);
      expect(_running(tester), isFalse,
          reason: 'on her return nothing claims the share runs');
      expect(_shownNotShared(tester), isTrue,
          reason: 'on her return the page shows it as not running');
      unawaited(positions.close());
      await _settle(tester);
    },
  );

  testWidgets(
    'N1 boundary: inactive alone (a dialog, the shade, a heads-up) ends '
    'nothing and tells no N1 line, and a real gap there is still told',
    (tester) async {
      final (a, positions) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, positions);
      final sb = a.spoken.length, hb = a.felt.length;
      await _to(tester, const [AppLifecycleState.inactive]);
      expect(a.spoken.length - sb, 0,
          reason: 'the app is on screen: 「画面から離れた」 would be false');
      await _silence(tester, 75);
      final (told, haptics) = _toldSince(a, sb, hb);
      expect(told, isNot(contains(_n1)));
      expect(
        told.contains(_slowDown) || told.contains(_stopLine),
        isTrue,
        reason: 'the GPS-loss reading runs in inactive as in front; '
            'suppressing it would withdraw a real warning untold: $told',
      );
      expect(haptics, isNotEmpty);
      await _to(tester, const [AppLifecycleState.resumed]);
      expect(_running(tester), isTrue, reason: 'inactive did not end it');
      unawaited(positions.close());
      await _settle(tester);
    },
  );

  testWidgets(
    'control: WITH its service, leaving neither ends the share nor tells a '
    'line at that moment',
    (tester) async {
      final (a, positions) = await _bootAndShare(tester, canPost: true);
      await _drive(tester, positions);
      final sb = a.spoken.length;
      await _to(tester, _leave);
      expect(a.spoken.length - sb, 0,
          reason: 'with the service her fixes still come: nothing to tell');
      await _to(tester, _back);
      expect(_running(tester), isTrue, reason: 'the share still runs');
      unawaited(positions.close());
      await _settle(tester);
    },
  );

  testWidgets(
    'N2: a service-mode share whose stream fails before its first fix is read '
    'as having no service: the row says so, and leaving ends it with the line',
    (tester) async {
      final (a, positions) = await _bootAndShare(tester, canPost: true);
      expect(
        find.byKey(const Key('share-runs-only-on-screen')),
        findsNothing,
        reason: 'control: built with its service, nothing says otherwise yet',
      );
      positions.addError(StateError('test: the service did not start'));
      await _settle(tester);
      expect(
        find.byKey(const Key('share-runs-only-on-screen'), skipOffstage: false),
        findsOneWidget,
        reason: 'the service is a positive reading, not the app\'s intent',
      );
      final sb = a.spoken.length;
      await _to(tester, _leave);
      expect(a.spoken.skip(sb).map((x) => x.text).toList(), [_n1]);
      await _to(tester, _back);
      expect(_running(tester), isFalse);
      unawaited(positions.close());
      await _settle(tester);
    },
  );

  testWidgets(
    'control for N2: an error AFTER a fix does not flip a service-mode share',
    (tester) async {
      final (a, positions) = await _bootAndShare(tester, canPost: true);
      await _drive(tester, positions);
      positions.addError(StateError('test: one bad event'));
      await _settle(tester);
      final sb = a.spoken
          .where((x) => x.text != _slowDown && x.text != _stopLine)
          .length;
      await _to(tester, _leave);
      final after = a.spoken
          .where((x) => x.text != _slowDown && x.text != _stopLine)
          .length;
      expect(after - sb, 0);
      await _to(tester, _back);
      expect(_running(tester), isTrue);
      unawaited(positions.close());
      await _settle(tester);
    },
  );

  testWidgets(
    'N3: a share without its service says, as it runs, that it runs only '
    'while the app is on screen; one with its service does not',
    (tester) async {
      final (_, p1) = await _bootAndShare(tester, canPost: false);
      expect(
        find.byKey(const Key('share-runs-only-on-screen'), skipOffstage: false),
        findsOneWidget,
      );
      unawaited(p1.close());
      await _settle(tester);
    },
  );

  testWidgets('control for N3: with its service the row does not say it', (
    tester,
  ) async {
    final (_, p2) = await _bootAndShare(tester, canPost: true);
    expect(
      find.byKey(const Key('share-runs-only-on-screen'), skipOffstage: false),
      findsNothing,
    );
    unawaited(p2.close());
    await _settle(tester);
  });

  testWidgets(
    'after the app ended a share while she was away, a new share she starts '
    'and stops herself leaves no notice saying the app left the screen',
    (tester) async {
      // A reproduction's mutant showed nothing held this (2026-10-06): a new
      // share that did not clear the previous share's notice survived the
      // whole suite, and under it her own 停止 was followed by 「アプリが画面
      // から離れたため、現在地の警告は止まりました。」, which is false: she
      // stopped it.
      final (a, positions) =
          await _bootAndShare(tester, canPost: false, broadcast: true);
      await _drive(tester, positions);
      await _to(tester, _leave);
      await _silence(tester, 5);
      await _to(tester, _back);
      expect(find.byKey(const Key('share-away-notice')), findsOneWidget,
          reason: 'control: the app ended the share and says so');

      final share = find.byKey(const Key('share-location-button'));
      await tester.ensureVisible(share);
      await tester.pump();
      await tester.tap(share);
      await _settle(tester);
      expect(_running(tester), isTrue, reason: 'control: a new share runs');
      await _drive(tester, positions);

      final stop = find.widgetWithText(TextButton, '停止');
      await tester.ensureVisible(stop);
      await tester.pump();
      await tester.tap(stop);
      await _settle(tester);
      expect(_running(tester), isFalse, reason: 'control: she stopped it');
      expect(
        find.byKey(const Key('share-away-notice'), skipOffstage: false),
        findsNothing,
        reason: 'she stopped this share herself: her screen must not say the '
            'app left the screen',
      );
      unawaited(positions.close());
      await _settle(tester);
    },
  );
}
