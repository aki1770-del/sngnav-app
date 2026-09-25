/// The design that keeps 停止 on the screen she returns to, at its edges.
///
/// WHY, written before the act (AAE, R122 round 5a). The safety review's rule
/// is held by stop_is_on_the_screen_she_returns_to_test.dart: after she leaves
/// the app during a drive and comes back (paused, then resumed), a 停止 she can
/// tap is on her screen. The design built brings 停止 onto her screen on every
/// return during a drive, and only when it is not already there
/// (lib/main.dart, _bringDriveStopIntoView). This file holds the four edges
/// that rule does not reach:
/// - the tap from the shade pulled down over the running app, which gives
///   inactive then resumed and never paused (the review named it uncovered);
/// - a return that already shows 停止 must not move her page;
/// - on a phone with all three alert channels dead, three caution rows sit
///   above the map, and at a large text size 停止 may not reach her first
///   screen even at the top of the page: the page must move far enough;
/// - with no drive running, a return moves nothing.
///
/// Her geometry: DPR 2.75, 1080x2340 px, insets 73/130 px.
///
/// BOUNDS. The lifecycle is sent through the channel the engine uses; which
/// sequence a real shade tap produces on her phone is not measured here. The
/// test font is not her font.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/audio_readiness.dart';
import 'package:sngnav_app/services/haptic_readiness.dart';
import 'package:sngnav_app/services/voice_lane_readiness.dart';

import '../support/fake_alert_actuators.dart';

const _ja = AppL10n(Locale('ja'));
final _now = DateTime.utc(2026, 1, 14, 21, 40);

const _dpr = 2.75;
const _physical = Size(1080, 2340);
const _insetTop = 73.0;
const _insetBottom = 130.0;
const double _safeTop = _insetTop / _dpr;
final double _safeBottom = (_physical.height - _insetBottom) / _dpr;

final class _MutedAudio implements AudioReadinessProbe {
  @override
  Future<AudioReadiness?> read() async => const AudioReadiness(
      mediaVolume: 0, mediaVolumeMax: 15, ttsServiceVisible: true);
}

final class _NoVibrator implements HapticReadinessProbe {
  @override
  Future<bool?> read() async => false;
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

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState s) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(s.toString()),
    (_) {},
  );
  await tester.pump();
}

Finder _stops() => find.widgetWithText(TextButton, _ja.stop);

/// The page's own Scrollable: the nearest one above the map card's title,
/// which is drawn with and without a drive.
Finder _page() => find
    .ancestor(
      of: find.text(_ja.mapSectionTitle),
      matching: find.byType(Scrollable),
    )
    .first;

bool _someStopTappable(WidgetTester tester) {
  for (final e in _stops().hitTestable().evaluate()) {
    final box = e.renderObject! as RenderBox;
    final c = box.localToGlobal(box.size.center(Offset.zero));
    if (c.dy >= _safeTop && c.dy <= _safeBottom) return true;
  }
  return false;
}

/// Her phone, the app, a drive started from the top of the page, one fix.
Future<StreamController<PositionFix>> _drive(
  WidgetTester tester, {
  required double scale,
  bool channelsDead = false,
  bool start = true,
}) async {
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = _physical;
  tester.view.padding =
      const FakeViewPadding(top: _insetTop, bottom: _insetBottom);
  tester.view.viewPadding =
      const FakeViewPadding(top: _insetTop, bottom: _insetBottom);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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
    voiceLaneReader:
        channelsDead ? () async => VoiceLaneVerdict.noJaVoice : null,
    hapticReadinessProbe: channelsDead ? _NoVibrator() : null,
    audioReadinessProbe: channelsDead ? _MutedAudio() : null,
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
  await _lifecycle(tester, AppLifecycleState.resumed);
  if (!start) return ctrl;

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
  return ctrl;
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(_page()).position;

Future<void> _readDown(WidgetTester tester) async {
  final p = _position(tester);
  final viewport = tester.getRect(_page()).height;
  p.jumpTo(math.min(p.maxScrollExtent, 4 * viewport));
  await tester.pump();
  expect(_someStopTappable(tester), isFalse,
      reason: 'control: after reading down the page 停止 is off her screen');
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_stop_on_return');
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

  for (final scale in [1.0, 1.3]) {
    testWidgets('scale $scale: the shade pulled over the running app '
        '(inactive, then resumed, never paused) lands her on 停止',
        (tester) async {
      await _drive(tester, scale: scale);
      await _readDown(tester);

      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await _settle(tester);

      expect(_someStopTappable(tester), isTrue,
          reason: 'the notification she tapped in the shade says tap, then '
              '停止; the page is ${_position(tester).pixels} dp down');
    });
  }

  testWidgets('a return that already shows 停止 does not move her page',
      (tester) async {
    await _drive(tester, scale: 1.0);
    final p = _position(tester);
    // A little way down, 停止 still on her screen.
    p.jumpTo(40);
    await tester.pump();
    expect(_someStopTappable(tester), isTrue,
        reason: 'control: 停止 is on her screen before she leaves');

    await _lifecycle(tester, AppLifecycleState.paused);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _settle(tester);

    expect(p.pixels, 40,
        reason: 'the page moves only when 停止 is not already on her screen');
  });

  for (final scale in [1.3, 1.5, 2.0]) {
    testWidgets('scale $scale, all three alert channels dead (three caution '
        'rows above the map): after a return 停止 is on her screen',
        (tester) async {
      await _drive(tester, scale: scale, channelsDead: true);
      expect(find.byKey(const Key('her-status-line')), findsOneWidget);
      await _readDown(tester);

      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await _settle(tester);

      expect(_someStopTappable(tester), isTrue,
          reason: 'with the caution rows above the map the top of the page '
              'may not reach 停止; the page must move far enough. It is '
              '${_position(tester).pixels} dp down');
    });
  }

  testWidgets('with no drive running, a return moves nothing', (tester) async {
    await _drive(tester, scale: 1.0, start: false);
    final p = _position(tester);
    final viewport = tester.getRect(_page()).height;
    final deep = math.min(p.maxScrollExtent, 2 * viewport);
    p.jumpTo(deep);
    await tester.pump();

    await _lifecycle(tester, AppLifecycleState.paused);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _settle(tester);

    expect(p.pixels, deep, reason: 'nothing runs, so nothing is brought back');
  });
}
