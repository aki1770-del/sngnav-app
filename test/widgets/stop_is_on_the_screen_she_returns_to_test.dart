/// After she leaves the app during a drive, the screen she comes back to
/// shows 停止.
///
/// WHY, written before the act (FSE, R122 round 4b). The drive notification's
/// body is 「タップ→「停止」で終了」 / "Tap, then Stop, to end.": it promises
/// that a tap leads to 停止. HIE measured on an Android 14 emulator that the
/// tap brings the running app forward at her last scroll position, and that
/// after a deep scroll 停止 was about four screens away. Read at source
/// (sngnav-app 2d51bdc): the page is one SingleChildScrollView with no
/// controller, and nothing in the app listens to the lifecycle, so nothing
/// moves the page when she comes back. Vision 20: stopping must cost less
/// than what it stops. A stop four screens from where our own notification
/// puts her costs a search on the phone,
/// for a driver in unexpected snow possibly a search in a moving car.
///
/// THE INVARIANT, neutral between designs: with a drive running, after she
/// leaves the app and comes back, a 停止 she can tap lies on the visible
/// screen at her geometry. Scrolling to the top on return passes; a 停止 that
/// never scrolls away passes.
///
/// Her geometry: DPR 2.75, 1080x2340 px, insets 73/130 px (HIE's round-4b
/// probe). Text scales 1.0 and 1.3.
///
/// BOUNDS.
/// - A widget test cannot tap a notification. The Flutter-side trace of that
///   tap from the background is paused -> resumed, sent here through the
///   lifecycle channel the engine uses. A tap from the shade pulled over the
///   running app may give only inactive -> resumed; this test does not cover
///   that path, and a 停止 that never scrolls away is the only design that
///   does.
/// - The test font is not her font. The invariant is on-screen or not, and
///   the deep scroll puts the in-page 停止 thousands of dp away.
library;

import 'dart:async';
import 'dart:math' as math;

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

const _dpr = 2.75;
const _physical = Size(1080, 2340);
const _insetTop = 73.0;
const _insetBottom = 130.0;
const double _safeTop = _insetTop / _dpr;
final double _safeBottom = (_physical.height - _insetBottom) / _dpr;

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

/// The lifecycle message the engine sends, through the channel it uses.
Future<void> _lifecycle(WidgetTester tester, AppLifecycleState s) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(s.toString()),
    (_) {},
  );
  await tester.pump();
}

Finder _stops() => find.widgetWithText(TextButton, _ja.stop);

/// The page's own Scrollable: the nearest one above the status line.
Finder _page() => find
    .ancestor(
      of: find.byKey(const Key('her-status-line')),
      matching: find.byType(Scrollable),
    )
    .first;

/// Whether some 停止 is tappable at its centre inside the safe screen area.
bool _someStopTappable(WidgetTester tester) {
  for (final e in _stops().hitTestable().evaluate()) {
    final box = e.renderObject! as RenderBox;
    final c = box.localToGlobal(box.size.center(Offset.zero));
    if (c.dy >= _safeTop && c.dy <= _safeBottom) return true;
  }
  return false;
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets(
        'scale $scale: the screen she returns to during a drive shows 停止',
        (tester) async {
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
      ));
      await tester.pump();
      await tester.pump();
      await _lifecycle(tester, AppLifecycleState.resumed);

      // She starts the drive from the top of the page, as she opens it.
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

      final page = tester.state<ScrollableState>(_page());
      page.position.jumpTo(0);
      await tester.pump();

      // CONTROL 1: the instrument can see a hit. At the top of the page, the
      // row under the map offers a tappable 停止 on her screen.
      expect(_someStopTappable(tester), isTrue,
          reason: 'control: at the top of the page 停止 must be on screen, '
              'or the check below cannot mean anything');

      // She reads down the page: four screens, or to the end if it is shorter.
      final viewport = tester.getRect(_page()).height;
      page.position
          .jumpTo(math.min(page.position.maxScrollExtent, 4 * viewport));
      await tester.pump();

      // CONTROL 2: the instrument can see a miss. The in-page 停止 is off the
      // screen now.
      final inPage = find.descendant(of: _page(), matching: _stops());
      expect(inPage, findsOneWidget, reason: 'control: the row\'s 停止 exists');
      final r = tester.getRect(inPage);
      final v = tester.getRect(_page());
      expect(r.bottom <= v.top || r.top >= v.bottom, isTrue,
          reason: 'control: after the deep scroll the in-page 停止 must be '
              'outside the viewport (it is at $r, the viewport is $v)');

      // She leaves the app (Home, or the screen goes off), and the drive
      // notification brings the running app back.
      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(_someStopTappable(tester), isTrue,
          reason: 'the drive notification says 「タップ→「停止」で終了」, and '
              'the screen its tap returns her to has no 停止 on it: the page '
              'is where she left it, ${page.position.pixels.toStringAsFixed(0)}'
              ' dp down (Vision 20)');
    });
  }
}
