/// A share that runs without its foreground service is not read as a GPS loss
/// when the app leaves the screen, and she is told it is not running.
///
/// Why, written before the act (2026-10-06). The app starts the drive's
/// foreground service only when it can post her a notification (canPostToHer:
/// the Android 13 permission AND notifications switched on for the app, which
/// can be off at any API level). Without the service, Android throttles a
/// background app's location, and geolocator_android 4.6.2 stops the stream
/// outright on any activity detach (StreamHandlerImpl.java:46-52). Either way,
/// fixes stop for a reason that is not the sky. Today the drive brain cannot
/// tell: it reads that silence as a GPS blackout, degrades her position, and
/// tells her the caution for a GPS loss that is not there, while the warnings
/// she believes are running are not.
///
/// The share starts through the app's real path: its notification read and
/// ask, its location permission, and the settings it hands to geolocator. So
/// which branch a share is on is read from what the app asked for (a
/// foreground notification config, or none), not from a test seam.
///
/// The rules these tests hold (the safety ruling of 2026-10-06, its audit,
/// and the lifecycle ruling of the same day):
/// - The trigger is the app leaving the screen: `hidden` or `paused`, never
///   `inactive`, and never before the position stream has subscribed. A
///   return from `paused` also reports `hidden` on its way back; that is not
///   a leave.
/// - If the stream subscribes while the app reads `hidden` or `paused`, a
///   return may still be in flight: N1 waits a settle window, cancelled by
///   `inactive` or `resumed`, and fires once at its end if she is still away.
/// - Not a GPS loss: after that trigger, a share with no foreground service is
///   never read as a GPS loss. No drought line is told, and on her return the
///   position row gives no drought verdict (「GPS 途絶（推測航法）」 or
///   「現在地 不明」) for it.
/// - She is told. When she leaves: exactly one line and at least one haptic,
///   and nothing repeated while she stays away. On her return: a notice that
///   the share was not running (placeholder key 'share-away-notice').
/// - A share HELD as not running and resumed on her return gets a fresh
///   drought wait from her return, and she is told it runs again. A share
///   ENDED is simply not running. The test reads which one by whether the
///   position stream has a listener after her return.
/// - `inactive` (a pulled shade, a dialog, split screen) is in front: the
///   drought runs through it, nothing restarts on her return from it, and no
///   line is told for it.
/// - The branch is the subscription's: a change of the notification setting
///   mid-share does not flip how its silence is read, either way.
/// - On the service branch no lifecycle state changes anything.
///
/// No placeholder WORDS are pinned: the told line is pinned by count and by
/// not being a drought line, the notice by its key. The words come later,
/// with their own test.
///
/// FAULTS are red on main 54b00cb. CONTROLS are green on main and must stay
/// green: a fix in the wrong place fails one of them.
///
/// What these tests do NOT hold: anything on a device, how a real phone
/// throttles, whether a line is heard as the app goes to the background, the
/// order in which a permission answer and the return to the front reach the
/// app, or what words she is told.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/route_act.dart' show kPositionDrought;
import 'package:sngnav_app/services/notification_permission.dart';

import '../support/fake_alert_actuators.dart';

const String _slowDown = '速度を落とし、車間を広げて、前方に注意してください。';
const String _stopLine = '安全にできるときは、安全な場所での停車も選べます。';
const double _v = 15;

/// One second less than the app's own drought bound, so a fresh wait from
/// her return cannot have run out inside it, while the window still spans the
/// app's drought check (every 15 s on main, every second on the faster branch).
final int _returnWindowSeconds = kPositionDrought.inSeconds - 1;

/// The start guard's settle window: when the share subscribes while the app
/// reads hidden or paused, a return may still be in flight, so N1 waits this
/// long, on its own timer, and fires only if she is still away. Provisional
/// (2 s, a chosen margin); a device read of the gap between a permission
/// answer and the return replaces it, and it never reaches the drought bound
/// less one second. When the app carries its own constant, read that instead.
const Duration _settleWindow = Duration(seconds: 2);

/// One step of a quarter second, for timing the settle window.
Future<void> _step(WidgetTester tester) async {
  await _advance(tester, const Duration(milliseconds: 250));
  await _settle(tester);
}

/// The placeholder for the notice she sees on return; the words come later.
const Key _awayNotice = Key('share-away-notice');

var _clockNow = DateTime.utc(2026, 1, 14, 21);

/// geolocator's platform edge. Location permission is granted unless a test
/// says otherwise; a request is answered only when the test says.
class _FakeGeolocator extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  Completer<LocationPermission>? _answer;
  final positions = StreamController<Position>.broadcast();
  int streamsStarted = 0;
  LocationSettings? lastSettings;

  bool get asking => _answer != null;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() =>
      (_answer = Completer<LocationPermission>()).future;

  void answer(LocationPermission p) {
    permission = p;
    _answer?.complete(p);
    _answer = null;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamsStarted++;
    lastSettings = locationSettings;
    return positions.stream;
  }
}

/// What the app asked geolocator for: a foreground service with its
/// notification, or none.
bool _withService(_FakeGeolocator geo) {
  final s = geo.lastSettings;
  return s is AndroidSettings && s.foregroundNotificationConfig != null;
}

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

/// A clear day where no measured-weather watch fires.
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

/// The app's notification channel: [canPost] true is "can post" (a share
/// starts with its foreground service); false is "cannot post", and an ask
/// is answered no.
void _setNotifications(WidgetTester tester, {required bool canPost}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    NotificationPermission.channel,
    (call) async => call.method == 'read'
        ? <String, dynamic>{
            'granted': canPost,
            'enabled': canPost,
            'needsRuntimeRequest': false,
          }
        : canPost,
  );
}

/// Boots the app and taps the share control. Returns once the share has
/// asked for location; with permission already granted its stream has then
/// subscribed. A fresh geolocator edge per boot.
Future<(FakeAlertActuators, _FakeGeolocator)> _bootAndTapShare(
  WidgetTester tester, {
  required bool canPost,
  LocationPermission permission = LocationPermission.whileInUse,
}) async {
  final tmp = Directory.systemTemp.createTempSync('sngnav_no_service');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tmp.path,
  );
  _setNotifications(tester, canPost: canPost);
  final original = GeolocatorPlatform.instance;
  final geo = _FakeGeolocator()..permission = permission;
  GeolocatorPlatform.instance = geo;
  addTearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(NotificationPermission.channel, null);
    GeolocatorPlatform.instance = original;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });
  await _toFront(tester);
  addTearDown(() => _toFront(tester));
  final a = FakeAlertActuators();
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    SngnavApp(
      // Not about the consent act.
      locationConsent: true,
      actuators: a,
      locale: const Locale('ja'),
      clock: () => _clockNow,
      jmaFetch: () async => JmaSuccess(_clearObs()),
    ),
  );
  await _settle(tester);
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  await _settle(tester);
  return (a, geo);
}

/// A share whose stream has subscribed, on the branch [canPost] gives it.
Future<(FakeAlertActuators, _FakeGeolocator)> _bootAndShare(
  WidgetTester tester, {
  required bool canPost,
}) async {
  final (a, geo) = await _bootAndTapShare(tester, canPost: canPost);
  expect(geo.streamsStarted, 1, reason: 'the share subscribed');
  expect(
    _withService(geo),
    canPost,
    reason: 'the share is on the branch this test is about',
  );
  return (a, geo);
}

Future<void> _drive(WidgetTester tester, _FakeGeolocator geo) async {
  var north = 0.0;
  for (var i = 0; i < 4; i++) {
    if (i > 0) {
      await _advance(tester, const Duration(seconds: 5));
      north += _v * 5;
    }
    geo.positions.add(_fix(north));
    await _settle(tester);
  }
}

Future<void> _setLifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

/// Back to resumed from wherever the lifecycle is, by valid steps only
/// (paused -> hidden -> inactive -> resumed). A fix that listens to the
/// lifecycle asserts on a skipped step, so the test never makes one.
Future<void> _toFront(WidgetTester tester) async {
  const order = [
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];
  final now = tester.binding.lifecycleState;
  if (now == AppLifecycleState.resumed) return;
  if (now == null) {
    // A test binding starts with no state; a launched app is resumed.
    await _setLifecycle(tester, const [AppLifecycleState.resumed]);
    return;
  }
  final from = order.indexOf(now);
  if (from < 0) return;
  await _setLifecycle(tester, order.sublist(from + 1));
}

Future<void> _leaveFront(WidgetTester tester) => _setLifecycle(tester, const [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
]);

Future<void> _returnToFront(WidgetTester tester) =>
    _setLifecycle(tester, const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);

/// What has been told so far: lines and cues. Every cue is counted from `felt`,
/// which records the ended cue too: since 2026-10-10 the line told when the
/// app ends a share without its service carries the ended cue (one long
/// pulse), which `haptics`, the warning grammar alone, never records.
(int, int) _mark(FakeAlertActuators a) => (a.spoken.length, a.felt.length);

/// What was told since [mark].
(List<String>, int) _since(FakeAlertActuators a, (int, int) mark) => (
  a.spoken.skip(mark.$1).map((x) => x.text).toList(),
  a.felt.length - mark.$2,
);

/// [seconds] of silence, one second at a time; returns what was told.
Future<(List<String>, int)> _silence(
  WidgetTester tester,
  FakeAlertActuators a,
  int seconds,
) async {
  final sb = a.spoken.length, hb = a.felt.length;
  for (var s = 0; s < seconds; s++) {
    await _advance(tester, const Duration(seconds: 1));
  }
  await _settle(tester);
  return (a.spoken.skip(sb).map((x) => x.text).toList(), a.felt.length - hb);
}

bool _isDroughtLine(String s) => s == _slowDown || s == _stopLine;

List<String> _told(FakeAlertActuators a) =>
    a.spoken.map((x) => x.text).toList();

/// The second, counted from the start of the silence, at which the first
/// drought line is told; null if none in [seconds]. [at] runs before a
/// given second.
Future<int?> _firstDroughtSecond(
  WidgetTester tester,
  FakeAlertActuators a,
  int seconds, {
  Map<int, List<AppLifecycleState>> at = const {},
}) async {
  final before = a.spoken.length;
  for (var s = 1; s <= seconds; s++) {
    final change = at[s];
    if (change != null) await _setLifecycle(tester, change);
    await _advance(tester, const Duration(seconds: 1));
    await _settle(tester);
    if (a.spoken.skip(before).any((x) => _isDroughtLine(x.text))) return s;
  }
  return null;
}

/// The drought's own verdict on her position, as the drive card's position
/// row shows it: exactly 「GPS 途絶（推測航法）」 while dead reckoning, exactly
/// 「現在地 不明」 once lost. Exact matches, because the card's description
/// (key drive-hud-description) names the same words inside a sentence on every
/// screen, which a substring match reads as a verdict.
bool _droughtVerdictShown(WidgetTester tester) =>
    find.text('GPS 途絶（推測航法）', skipOffstage: false).evaluate().isNotEmpty ||
    find.text('現在地 不明', skipOffstage: false).evaluate().isNotEmpty;

/// The position row's label for a fix with no fault found.
bool _goodFixShown(WidgetTester tester) =>
    find.text('GPS 良好', skipOffstage: false).evaluate().isNotEmpty;

/// The away notice is on screen and says something.
bool _awayNoticeShown(WidgetTester tester) {
  final notice = find.byKey(_awayNotice, skipOffstage: false);
  if (notice.evaluate().isEmpty) return false;
  return find
      .descendant(
        of: notice,
        matching: find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').trim().isNotEmpty,
        ),
        matchRoot: true,
        skipOffstage: false,
      )
      .evaluate()
      .isNotEmpty;
}

Future<void> _end(WidgetTester tester, _FakeGeolocator geo) async {
  await _toFront(tester);
  unawaited(geo.positions.close());
  await _settle(tester);
}

void main() {
  testWidgets(
    'FAULT (not a GPS loss): no foreground service, the app leaves the '
    'screen, 75 s with no fix: no drought line is told, and no drought '
    'verdict on return',
    (tester) async {
      final (a, geo) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, geo);
      await _leaveFront(tester);
      final (spoken, _) = await _silence(tester, a, 75);
      expect(
        spoken,
        isNot(contains(_slowDown)),
        reason: 'the platform stopped her fixes; the sky did not: $spoken',
      );
      expect(
        spoken,
        isNot(contains(_stopLine)),
        reason: 'a stop invitation for a GPS loss that is not there: $spoken',
      );
      await _returnToFront(tester);
      await _settle(tester);
      expect(
        _droughtVerdictShown(tester),
        isFalse,
        reason:
            'on her return the position row gives the drought\'s verdict '
            'for a stop the platform made',
      );
      await _end(tester, geo);
    },
  );

  testWidgets(
    'FAULT (told, at leave): when she leaves without the service she is told '
    'once, by voice and haptic, and nothing is repeated while she is away',
    (tester) async {
      final (a, geo) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, geo);
      // Counted from before she leaves: a fix may tell her on the lifecycle
      // change itself.
      final beforeLeave = _mark(a);
      await _leaveFront(tester);
      await _silence(tester, a, 2);
      final (atLeave, hapticsAtLeave) = _since(a, beforeLeave);
      expect(
        atLeave,
        hasLength(1),
        reason:
            'a share that stops running when she leaves must say so as she '
            'leaves; no notification can reach her later: $atLeave',
      );
      expect(
        _isDroughtLine(atLeave.single),
        isFalse,
        reason: 'the told line is not a GPS-loss line: $atLeave',
      );
      expect(hapticsAtLeave, greaterThan(0), reason: 'voice AND haptic');
      final (later, hapticsLater) = await _silence(tester, a, 73);
      expect(later, isEmpty, reason: 'told once, not repeated: $later');
      expect(hapticsLater, 0, reason: 'no repeated haptic while away');
      await _returnToFront(tester);
      await _end(tester, geo);
    },
  );

  testWidgets(
    'FAULT (told, on return): the screen says the share was not running',
    (tester) async {
      final (a, geo) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, geo);
      await _leaveFront(tester);
      await _silence(tester, a, 75);
      await _returnToFront(tester);
      await _settle(tester);
      expect(
        _awayNoticeShown(tester),
        isTrue,
        reason:
            'the told line may not have been heard as the app left the '
            'screen; the screen she returns to is the backstop',
      );
      await _end(tester, geo);
    },
  );

  testWidgets(
    'FAULT (return): a held share gets a fresh drought wait and she is told '
    'it runs again; an ended share claims nothing',
    (tester) async {
      final (a, geo) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, geo);
      await _leaveFront(tester);
      await _silence(tester, a, 75);
      final beforeReturn = _mark(a);
      await _returnToFront(tester);
      await _silence(tester, a, 2);
      final (atReturn, _) = _since(a, beforeReturn);
      final (inWindow, _) = await _silence(tester, a, _returnWindowSeconds - 2);
      final told = [...atReturn, ...inWindow];
      expect(
        told.where(_isDroughtLine),
        isEmpty,
        reason:
            'the time she was away is not a GPS loss, on her return '
            'either: $told',
      );
      if (geo.positions.hasListener) {
        // HELD, and running again.
        expect(
          atReturn,
          hasLength(1),
          reason: 'she is told once that the share runs again: $atReturn',
        );
        expect(
          _droughtVerdictShown(tester) || _goodFixShown(tester),
          isFalse,
          reason:
              'with no fix since her return, the position row neither '
              'blames the GPS nor shows the fix from before she left as good',
        );
      } else {
        // ENDED.
        expect(
          atReturn,
          isEmpty,
          reason: 'an ended share is not announced as running: $atReturn',
        );
      }
      await _end(tester, geo);
    },
  );

  testWidgets(
    'FAULT (per share): a share started without the service stays read as '
    'without it when the setting turns on mid-share',
    (tester) async {
      final (a, geo) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, geo);
      _setNotifications(tester, canPost: true);
      // In front, with fixes: any re-read the app makes has its chance.
      for (var i = 0; i < 16; i++) {
        await _advance(tester, const Duration(seconds: 1));
        geo.positions.add(_fix(4 * _v * 5 + (i + 1) * _v));
        await _settle(tester);
      }
      expect(geo.streamsStarted, 1, reason: 'the same subscription');
      await _leaveFront(tester);
      final (spoken, _) = await _silence(tester, a, 75);
      expect(
        spoken.where(_isDroughtLine),
        isEmpty,
        reason:
            'the subscription was built without the service; the setting '
            'changing later starts no service for it: $spoken',
      );
      await _returnToFront(tester);
      await _end(tester, geo);
    },
  );

  testWidgets(
    'CONTROL (start dialog): a permission dialog over the share start '
    '(inactive, then resumed) tells nothing; the share runs, and a later '
    'real gap is still told',
    (tester) async {
      final (a, geo) = await _bootAndTapShare(
        tester,
        canPost: false,
        permission: LocationPermission.denied,
      );
      expect(geo.asking, isTrue, reason: 'the location dialog is up');
      await _setLifecycle(tester, const [AppLifecycleState.inactive]);
      await _advance(tester, const Duration(seconds: 3));
      await _setLifecycle(tester, const [AppLifecycleState.resumed]);
      geo.answer(LocationPermission.whileInUse);
      await _settle(tester);
      expect(geo.streamsStarted, 1, reason: 'the share subscribed');
      expect(_withService(geo), isFalse);
      expect(_told(a), isEmpty, reason: 'nothing told for a dialog');
      expect(geo.positions.hasListener, isTrue, reason: 'the share runs');
      await _drive(tester, geo);
      final (spoken, haptics) = await _silence(tester, a, 75);
      expect(
        spoken.any(_isDroughtLine),
        isTrue,
        reason: 'a real gap in front is told: $spoken',
      );
      expect(haptics, greaterThan(0));
      await _end(tester, geo);
    },
  );

  testWidgets(
    'CONTROL (start guard): a full-screen permission screen over the share '
    'start (inactive, hidden, paused) tells nothing before the stream '
    'subscribes, and the share runs',
    (tester) async {
      final (a, geo) = await _bootAndTapShare(
        tester,
        canPost: false,
        permission: LocationPermission.denied,
      );
      expect(geo.asking, isTrue, reason: 'the location screen is up');
      await _leaveFront(tester);
      await _advance(tester, const Duration(seconds: 3));
      await _settle(tester);
      expect(
        _told(a),
        isEmpty,
        reason: 'no stream has subscribed; nothing has stopped running',
      );
      await _returnToFront(tester);
      geo.answer(LocationPermission.whileInUse);
      await _settle(tester);
      expect(geo.streamsStarted, 1, reason: 'the share subscribed');
      expect(_told(a), isEmpty, reason: 'nothing told at the start');
      expect(geo.positions.hasListener, isTrue, reason: 'the share runs');
      expect(_awayNoticeShown(tester), isFalse);
      await _drive(tester, geo);
      final (spoken, _) = await _silence(tester, a, 75);
      expect(spoken.any(_isDroughtLine), isTrue, reason: '$spoken');
      await _end(tester, geo);
    },
  );

  testWidgets(
    'CONTROL (answer before return): the share subscribes while the app '
    'reads paused, and her return arrives 0.5 s later: nothing is told, and '
    'the share runs',
    (tester) async {
      final (a, geo) = await _bootAndTapShare(
        tester,
        canPost: false,
        permission: LocationPermission.denied,
      );
      expect(geo.asking, isTrue, reason: 'the location screen is up');
      await _leaveFront(tester);
      geo.answer(LocationPermission.whileInUse);
      await _settle(tester);
      expect(
        geo.streamsStarted,
        1,
        reason: 'the share subscribed while the app read paused',
      );
      expect(tester.binding.lifecycleState, AppLifecycleState.paused);
      expect(_withService(geo), isFalse);
      await _step(tester);
      await _step(tester);
      // Back to the front by valid steps: hidden, inactive, resumed.
      await _toFront(tester);
      for (var i = 0; i < 4 * _settleWindow.inSeconds + 8; i++) {
        await _step(tester);
      }
      expect(
        _told(a),
        isEmpty,
        reason:
            'she came back to her own share; nothing stopped running, and '
            'the hidden reported on her way back is not a leave',
      );
      expect(geo.positions.hasListener, isTrue, reason: 'the share runs');
      expect(_awayNoticeShown(tester), isFalse);
      await _drive(tester, geo);
      final (spoken, _) = await _silence(tester, a, 75);
      expect(spoken.any(_isDroughtLine), isTrue, reason: '$spoken');
      await _end(tester, geo);
    },
  );

  testWidgets(
    'FAULT (truly away at subscribe): the share subscribes while the app '
    'reads paused and she stays away: she is told once, at the settle window '
    'and not before, and nothing more while she is away',
    (tester) async {
      final (a, geo) = await _bootAndTapShare(
        tester,
        canPost: false,
        permission: LocationPermission.denied,
      );
      expect(geo.asking, isTrue, reason: 'the location screen is up');
      await _leaveFront(tester);
      final beforeSubscribe = _mark(a);
      geo.answer(LocationPermission.whileInUse);
      await _settle(tester);
      expect(
        geo.streamsStarted,
        1,
        reason: 'the share subscribed while the app read paused',
      );
      expect(_withService(geo), isFalse);
      final steps = _settleWindow.inMilliseconds ~/ 250;
      for (var i = 0; i < steps - 1; i++) {
        await _step(tester);
      }
      final (beforeS, hapticsBeforeS) = _since(a, beforeSubscribe);
      expect(
        beforeS,
        isEmpty,
        reason:
            'nothing is told before the settle window ends: her return may '
            'still be in flight: $beforeS',
      );
      expect(hapticsBeforeS, 0);
      for (var i = 0; i < 3; i++) {
        await _step(tester);
      }
      final (atS, hapticsAtS) = _since(a, beforeSubscribe);
      expect(
        atS,
        hasLength(1),
        reason:
            'a share running unseen from its first second is named not '
            'running when the settle window ends: $atS',
      );
      expect(_isDroughtLine(atS.single), isFalse, reason: '$atS');
      expect(hapticsAtS, greaterThan(0), reason: 'voice AND haptic');
      final (later, hapticsLater) = await _silence(tester, a, 75);
      expect(
        later,
        isEmpty,
        reason: 'told once; no drought line while she is away: $later',
      );
      expect(hapticsLater, 0);
      await _returnToFront(tester);
      await _settle(tester);
      expect(_awayNoticeShown(tester), isTrue);
      await _end(tester, geo);
    },
  );

  testWidgets(
    'CONTROL (long inactive): no service, inactive for 75 s with no fix: the '
    'drought is told and nothing else',
    (tester) async {
      final (a, geo) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, geo);
      await _setLifecycle(tester, const [AppLifecycleState.inactive]);
      final (spoken, haptics) = await _silence(tester, a, 75);
      expect(
        spoken.any(_isDroughtLine),
        isTrue,
        reason:
            'inactive is on screen: a real loss there is told, not '
            'suppressed: $spoken',
      );
      expect(haptics, greaterThan(0));
      expect(
        spoken.where((s) => !_isDroughtLine(s)),
        isEmpty,
        reason: 'no line saying the app left the screen: $spoken',
      );
      expect(geo.positions.hasListener, isTrue, reason: 'the share runs');
      await _end(tester, geo);
    },
  );

  testWidgets(
    'CONTROL (shade pull): a short inactive inside one silence tells nothing '
    'at the pull, and the drought wait counts through it',
    (tester) async {
      // The reference: the same silence, in front throughout.
      var (a, geo) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, geo);
      final reference = await _firstDroughtSecond(tester, a, 75);
      expect(reference, isNotNull, reason: 'the reference gap is told');
      expect(reference, greaterThan(8));
      await _end(tester, geo);

      (a, geo) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, geo);
      final pullAt = reference! - 6;
      final before = a.spoken.length;
      final first = await _firstDroughtSecond(
        tester,
        a,
        75,
        at: {
          pullAt: const [AppLifecycleState.inactive],
          pullAt + 5: const [AppLifecycleState.resumed],
        },
      );
      expect(
        first,
        isNotNull,
        reason: 'the gap with a shade pull in it is told',
      );
      expect(
        first,
        lessThanOrEqualTo(reference),
        reason:
            'the pull did not restart the wait: told at ${first}s, '
            'against ${reference}s without it',
      );
      final told = a.spoken.skip(before).map((x) => x.text);
      expect(
        told.where((s) => !_isDroughtLine(s)),
        isEmpty,
        reason: 'nothing told for a shade pull: ${told.toList()}',
      );
      await _end(tester, geo);
    },
  );

  testWidgets(
    'CONTROL (per share): a share started with the service stays read as '
    'with it when the setting turns off mid-share',
    (tester) async {
      final (a, geo) = await _bootAndShare(tester, canPost: true);
      await _drive(tester, geo);
      _setNotifications(tester, canPost: false);
      for (var i = 0; i < 16; i++) {
        await _advance(tester, const Duration(seconds: 1));
        geo.positions.add(_fix(4 * _v * 5 + (i + 1) * _v));
        await _settle(tester);
      }
      expect(geo.streamsStarted, 1, reason: 'the same subscription');
      await _leaveFront(tester);
      final (spoken, haptics) = await _silence(tester, a, 75);
      expect(
        spoken.any(_isDroughtLine),
        isTrue,
        reason:
            'the service started with the share runs on; its silence is '
            'the sky: $spoken',
      );
      expect(haptics, greaterThan(0));
      await _returnToFront(tester);
      await _end(tester, geo);
    },
  );

  testWidgets(
    'CONTROL: with the foreground service, the same silence while away is '
    'still read as a GPS loss and told, and nothing else is told',
    (tester) async {
      final (a, geo) = await _bootAndShare(tester, canPost: true);
      await _drive(tester, geo);
      await _leaveFront(tester);
      final (spoken, haptics) = await _silence(tester, a, 75);
      expect(
        spoken.any(_isDroughtLine),
        isTrue,
        reason: 'with the service running, silence is the sky: $spoken',
      );
      expect(haptics, greaterThan(0));
      expect(
        spoken.where((s) => !_isDroughtLine(s)),
        isEmpty,
        reason: 'on the service branch no lifecycle line is told: $spoken',
      );
      await _returnToFront(tester);
      await _end(tester, geo);
    },
  );

  testWidgets(
    'CONTROL: no foreground service but the app stays in front through a '
    'real gap: the drought is still told',
    (tester) async {
      final (a, geo) = await _bootAndShare(tester, canPost: false);
      await _drive(tester, geo);
      final (spoken, haptics) = await _silence(tester, a, 75);
      expect(
        spoken.any(_isDroughtLine),
        isTrue,
        reason: 'in front, the stream lives; silence is the sky: $spoken',
      );
      expect(haptics, greaterThan(0));
      expect(_droughtVerdictShown(tester), isTrue);
      await _end(tester, geo);
    },
  );
}
