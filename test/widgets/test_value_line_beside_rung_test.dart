/// The test-value line sits directly above the rung banner (display review, 2026-09-16).
///
/// Why, written before the act. At 12bdd13 the display review's frame SHARED_E/F14 drew the
/// line at y 189 and the rung banner from y 280, with two position rows
/// between them. Someone who looks at the red banner and its cause does not
/// see that a test value set the step. The line qualifies the step, so it is
/// read in the same glance: nothing between them, and at most 8 px apart.
///
/// Bound: host widget test, test font; the measure is the layout boxes, not a
/// seen frame. Nothing heard or felt.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

final _start = DateTime.utc(2026, 1, 14, 21);
var _now = _start;

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

Future<JmaResult> _jma() async => JmaSuccess(
      JmaObservation(
        stationId: '32402',
        stationName: '秋田',
        temperatureCelsius: 5,
        humidityPercent: 50,
        windMetersPerSecond: 2,
        snowDepthCm: null,
        precipitation10mMm: 0,
        visibilityMeters: 700,
        observedAtJstKey: _jstKey(_now),
        fetchedAt: _now,
      ),
    );

const _line = Key('drive-hud-test-value');
const _banner = Key('drive-hud-caution-banner');

Future<void> _openDevPage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('developer-page-entry')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.byKey(const Key('developer-page')), findsOneWidget,
      reason: 'control: the development page opened');
}

Future<void> _closeDevPage(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  for (final lang in const ['ja', 'en']) {
    testWidgets(
        '$lang: a demo 80 m under a measured 700 m: the line is directly '
        'above the banner', (tester) async {
      _now = _start;
      await tester.pumpWidget(SngnavApp(
        key: UniqueKey(),
        actuators: FakeAlertActuators(),
        locale: Locale(lang),
        clock: () => _now,
        jmaFetch: _jma,
        developerPageEntry: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _openDevPage(tester);
      final mock = find.byKey(const Key('use-mock-button'));
      final band = find.byKey(const Key('drive-hud-visibility'));
      final onDev = mock.evaluate().isNotEmpty;
      expect(onDev, isTrue, reason: 'control: the mock is on the dev page');
      await tester.ensureVisible(mock);
      await tester.pump();
      await tester.tap(mock);
      await tester.pump();
      await tester.pump();
      if (band.evaluate().isNotEmpty) {
        await tester.ensureVisible(band);
        await tester.pump();
        await tester.tap(band);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find
            .byWidgetPredicate((w) => w is DropdownMenuItem && w.value == 80.0)
            .last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await _closeDevPage(tester);
      for (var i = 0; i < 3; i++) {
        _now = _now.add(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 5));
      }
      expect(find.byKey(_line), findsOneWidget,
          reason: 'control: a test value is what the card shows');
      expect(find.byKey(_banner), findsOneWidget,
          reason: 'control: the rung banner is drawn');
      await tester.ensureVisible(find.byKey(_banner));
      await tester.pump();
      final line = tester.getRect(find.byKey(_line));
      final banner = tester.getRect(find.byKey(_banner));
      expect(line.bottom, lessThanOrEqualTo(banner.top),
          reason: 'the line is above the banner: line $line, banner $banner');
      expect(banner.top - line.bottom, lessThanOrEqualTo(8),
          reason: 'the line is ${banner.top - line.bottom} px above the '
              'banner; a glance at the step does not reach it');
      final between = find.byWidgetPredicate((w) => w is Text).evaluate().where(
        (e) {
          final r = tester.getRect(find.byWidget(e.widget).first);
          return r.top >= line.bottom - 0.5 &&
              r.bottom <= banner.top + 0.5 &&
              r.height > 0;
        },
      );
      expect(between, isEmpty,
          reason: 'text between the line and the banner: '
              '${between.map((e) => (e.widget as Text).data).toList()}');
    });
  }
}
