/// 現在地を共有 is on her first screen when she opens the app, through text
/// size 1.5, in Japanese and in English.
///
/// WHY, written before the act (AAE, R122 round 5a). A screen review measured
/// the share control below her first screen at text size 1.3 in Japanese: its
/// top at 724 dp on the host and at 725.1 dp on an Android 14 emulator,
/// against her 721 dp fold, with the drive sentences drawn above it. The only
/// control word left on that first screen was 停止, which names a control
/// that does not exist until a drive has started. The review ruled the order
/// status line, then the share control, then the drive sentences, and owed a
/// guard that checks the control itself: her_map_first_screen_test.dart
/// guards the map and the line under it, never the control. Vision 9: the
/// machine itself must catch this, not a reviewer.
///
/// WHAT A PASS MEANS. At her geometry (DPR 2.75, 1080x2340 px, insets
/// 73/130 px), at launch, with no scroll, the whole share control lies between
/// the top of the page and the top of the navigation bar, at text sizes 1.0,
/// 1.15, 1.3 and 1.5, drawn with real faces: a Japanese face for ja, Roboto for
/// en. The test font draws every Latin letter a full em wide, which would put
/// the English control far lower than any phone does. 2.0 is not asserted:
/// the review measured the control's top at 720 dp there, so it cannot fit, and
/// that is a stated bound, printed below as a measure.
///
/// BOUNDS. The Japanese face is the one this host and CI discover
/// (render_see_env.dart); her phone draws Noto Sans CJK JP. The position is
/// laid out, not seen on a device.
library;

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../render_see/render_see_env.dart';
import '../support/fake_alert_actuators.dart';

const _dpr = 2.75;
const _physical = Size(1080, 2340);
const _insetTop = 73.0;
const _insetBottom = 130.0;
final double _safeBottom = (_physical.height - _insetBottom) / _dpr;

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_share_first_screen');
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

  for (final lang in const ['ja', 'en']) {
    for (final scale in const [1.0, 1.15, 1.3, 1.5, 2.0]) {
      final asserted = scale <= 1.5;
      testWidgets(
          '$lang, text size $scale: the share control '
          '${asserted ? 'is on her first screen' : 'is measured (not asserted)'}',
          (tester) async {
        final faceLoaded = await tester.runAsync(() => loadDiscoveredFace(
                'Roboto',
                lang == 'ja' ? FaceSearch.japanese : FaceSearch.roboto)) ??
            false;
        expect(faceLoaded, isTrue,
            reason: 'without a real face this measures the test font, whose '
                'Latin letters are a full em wide: no verdict');

        tester.view.devicePixelRatio = _dpr;
        tester.view.physicalSize = _physical;
        tester.view.padding =
            const FakeViewPadding(top: _insetTop, bottom: _insetBottom);
        tester.view.viewPadding =
            const FakeViewPadding(top: _insetTop, bottom: _insetBottom);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final positions = StreamController<PositionFix>.broadcast();
        addTearDown(positions.close);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(SngnavApp(
          locale: Locale(lang),
          actuators: FakeAlertActuators(),
          clock: () => DateTime.utc(2026, 1, 14, 21),
          jmaFetch: () async => const JmaFailure('test: no observation'),
          positionSource: () => positions.stream,
        ));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final share = find.byKey(const Key('share-location-button'));
        expect(share, findsOneWidget, reason: 'control: the share control');
        final page = find
            .ancestor(of: share, matching: find.byType(Scrollable))
            .first;
        expect(tester.state<ScrollableState>(page).position.pixels, 0,
            reason: 'control: measured as she opens the app, with no scroll');
        final pageTop = tester.getRect(page).top;
        final r = tester.getRect(share);
        final fold = _safeBottom - pageTop;
        print('share control $lang x$scale: ${(r.top - pageTop).toStringAsFixed(1)}'
            '..${(r.bottom - pageTop).toStringAsFixed(1)} dp on the page, '
            'her fold ${fold.toStringAsFixed(1)} dp');
        if (!asserted) return;
        expect(r.top, greaterThanOrEqualTo(pageTop));
        expect(r.bottom, lessThanOrEqualTo(_safeBottom),
            reason: '現在地を共有 is below her first screen at text size '
                '$scale in $lang: ${(r.bottom - pageTop).toStringAsFixed(1)} '
                'dp against her ${fold.toStringAsFixed(1)} dp fold');
      });
    }
  }
}
