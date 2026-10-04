/// 停止 is named to Android as a rect to keep clear of floating windows.
///
/// WHY (2026-10-04). On an Android 14 emulator at her geometry, Google Maps'
/// picture-in-picture window sat over 停止 while a drive ran. Her tap went to
/// Maps' window (com.android.wm.shell.pip.phone.PipTouchHandler) and the drive
/// kept running. lib/services/keep_clear.dart says what Android offers for
/// this, from API 33, and where it does not reach.
///
/// THE INVARIANT, at HER geometry (DPR 2.75, 1080x2340 px):
/// 1. While a drive runs, the platform is asked to keep clear exactly one rect:
///    停止's own rect in physical pixels, rounded outward.
/// 2. When the page scrolls, the rect asked for moves with 停止.
/// 3. After 停止, nothing is asked: the last request is empty.
/// And at the source: the Kotlin side answers this channel, and calls
/// View.setPreferKeepClearRects only after an API 33 check.
///
/// RED on fc53fd6: nothing is ever sent on this channel there.
///
/// BOUNDS. The channel is answered by the test here. Whether Android moves
/// Maps' window off the rect is for an emulator to show
/// (outputs/android-app-engineer/pip_over_stop_2026_10_04/).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/keep_clear.dart';

import '../support/fake_alert_actuators.dart';

const _ja = AppL10n(Locale('ja'));
final _now = DateTime.utc(2026, 1, 14, 21, 40);

const _dpr = 2.75;
const _physical = Size(1080, 2340);

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

/// The drive-stop 停止 in the status-line row (the one main.dart keys with
/// _driveStopKey), found the way the other 停止 tests find it.
Finder _driveStop() {
  final row = find
      .ancestor(
        of: find.byKey(const Key('her-status-line')),
        matching: find.byType(Row),
      )
      .first;
  return find.descendant(
      of: row, matching: find.widgetWithText(TextButton, _ja.stop));
}

/// 停止's rect as the platform should receive it: physical pixels, outward.
List<int> _expectedEdges(Rect logical) => [
      (logical.left * _dpr).floor(),
      (logical.top * _dpr).floor(),
      (logical.right * _dpr).ceil(),
      (logical.bottom * _dpr).ceil(),
    ];

List<List<int>> _rectsOf(MethodCall call) => [
      for (final r in call.arguments as List) [for (final e in r as List) e as int],
    ];

void main() {
  testWidgets(
      'during a drive the platform is asked to keep 停止 clear, the request '
      'follows a scroll, and 停止 withdraws it', (tester) async {
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = _physical;
    tester.view.padding = const FakeViewPadding(top: 73, bottom: 130);
    tester.view.viewPadding = const FakeViewPadding(top: 73, bottom: 130);
    addTearDown(tester.view.reset);

    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(KeepClear.channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(KeepClear.channel, null));

    final ctrl = StreamController<PositionFix>.broadcast();
    addTearDown(ctrl.close);

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

    // Before any drive there is no 停止, and nothing is asked.
    expect(find.byKey(const Key('her-status-line')), findsNothing);
    expect(calls, isEmpty,
        reason: 'no rect may be asked for before a drive runs');

    final share = find.byKey(const Key('share-location-button'));
    await tester.ensureVisible(share);
    await tester.pump();
    await tester.tap(share);
    ctrl.add(PositionAvailable(
      latitude: 39.7186,
      longitude: 140.1024,
      accuracyMeters: 8,
      timestamp: _now,
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 1. One rect, 停止's own.
    expect(_driveStop(), findsOneWidget);
    expect(calls, isNotEmpty,
        reason: 'a drive is running and 停止 is on the page, yet the platform '
            'was never asked to keep it clear of floating windows');
    expect(calls.every((c) => c.method == 'setPreferKeepClearRects'), isTrue);
    final atStart = tester.getRect(_driveStop());
    expect(_rectsOf(calls.last), [_expectedEdges(atStart)],
        reason: 'the rect asked for must be 停止\'s, in physical pixels, '
            'rounded outward');

    // 2. The page scrolls; the request follows 停止.
    final page = tester.state<ScrollableState>(find
        .ancestor(of: _driveStop(), matching: find.byType(Scrollable))
        .first);
    final before = calls.length;
    // A fractional scroll puts 停止's top and bottom on fractional physical
    // pixels, so rounding inward and rounding outward give different rects
    // (at her geometry the left and right edges land on whole pixels,
    // 816 and 992, where the two roundings agree).
    page.position.jumpTo(page.position.pixels + 40.3);
    await tester.pump();
    await tester.pump();
    final afterScroll = tester.getRect(_driveStop());
    expect(afterScroll.top, isNot(atStart.top),
        reason: 'the scroll must move 停止 for this check to mean anything');
    expect(calls.length, greaterThan(before),
        reason: 'the page scrolled and the rect was not sent again');
    expect(_rectsOf(calls.last), [_expectedEdges(afterScroll)]);
    expect((afterScroll.top * _dpr) % 1, isNot(0),
        reason: 'the scroll must leave 停止\'s top on a fractional pixel, or '
            'this step cannot tell outward rounding from inward');

    // A frame with nothing moved sends nothing.
    final settled = calls.length;
    await tester.pump();
    await tester.pump();
    expect(calls.length, settled,
        reason: 'an unchanged rect must not be sent again');

    // 3. 停止 ends the drive and withdraws the request.
    await tester.ensureVisible(_driveStop());
    await tester.pump();
    await tester.tap(_driveStop());
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('her-status-line')), findsNothing,
        reason: '停止 must have ended the drive');
    expect(_rectsOf(calls.last), isEmpty,
        reason: 'after 停止 nothing may be kept clear on her behalf');
  });

  test('the Kotlin side answers sngnav/keep_clear and calls '
      'setPreferKeepClearRects only from API 33', () {
    final kt = File(
            'android/app/src/main/kotlin/dev/aki1770del/sngnav_app/MainActivity.kt')
        .readAsStringSync();
    expect(kt, contains('"${KeepClear.channel.name}"'),
        reason: 'MainActivity must register the channel Dart calls');
    expect(kt, contains('"setPreferKeepClearRects" ->'),
        reason: 'MainActivity must answer the method Dart calls');
    final guard = kt.indexOf(
        'if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false');
    final call = kt.indexOf('view.setPreferKeepClearRects(');
    expect(guard, isNonNegative, reason: 'the API 33 check is missing');
    expect(call, isNonNegative, reason: 'the platform call is missing');
    expect(guard, lessThan(call),
        reason: 'setPreferKeepClearRects must come after the API 33 check');
  });
}
