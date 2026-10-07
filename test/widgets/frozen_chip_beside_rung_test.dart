/// The frozen-road chip is read in the same glance as the rung it scopes.
///
/// Why, written before the act (2026-10-07). The chip 路面凍結のおそれ was
/// decided on 2026-07-23 as a calm glance surface beside the caution banner,
/// and the banner's headline yields to it (`calmNoteInForce` in
/// lib/main.dart): a chip reading 路面凍結のおそれ beside an unscoped
/// 「特段の注意なし」 would contradict itself. When the banner became the first
/// thing in its card, so that the rung reaches her first screen, the chip was
/// left below the reasons, the unknowns and the announce line. Nothing failed:
/// only a comment said where the chip was, and the comment was then false.
///
/// What this holds, in the real app tree, at launch with no share:
///   1. a measured 80 m whiteout at -3 °C: the banner, then the chip directly
///      under it, nothing between, at most 8 dp apart;
///   2. -3 °C with no visibility reading: no banner, and the chip keeps its old
///      place above the card's description.
///
/// Bound: host widget test with the test font; it measures layout boxes, not a
/// seen frame. Nothing heard or felt, and no timed glance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

final _start = DateTime.utc(2026, 1, 14, 21);

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

Future<JmaResult> Function() _jma({required int? visibility}) =>
    () async => JmaSuccess(
          JmaObservation(
            stationId: '32402',
            stationName: '秋田',
            temperatureCelsius: -3,
            humidityPercent: 90,
            windMetersPerSecond: 2,
            snowDepthCm: null,
            precipitation10mMm: 0,
            visibilityMeters: visibility,
            observedAtJstKey: _jstKey(_start),
            fetchedAt: _start,
          ),
        );

const _chip = Key('subzero-frozen-chip');
const _banner = Key('drive-hud-caution-banner');
const _description = Key('drive-hud-description');

Future<void> _boot(WidgetTester tester, String lang, int? visibility) async {
  await tester.pumpWidget(SngnavApp(
    key: UniqueKey(),
    actuators: FakeAlertActuators(),
    locale: Locale(lang),
    clock: () => _start,
    jmaFetch: _jma(visibility: visibility),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final lang in const ['ja', 'en']) {
    testWidgets(
        '$lang: a measured 80 m whiteout at -3 °C: the chip is directly '
        'under the banner', (tester) async {
      await _boot(tester, lang, 80);
      expect(find.byKey(_banner), findsOneWidget,
          reason: 'control: a measured whiteout draws the rung banner');
      expect(find.byKey(_chip), findsOneWidget,
          reason: 'control: -3 °C draws the frozen-road chip');
      final banner = tester.getRect(find.byKey(_banner));
      final chip = tester.getRect(find.byKey(_chip));
      expect(chip.top, greaterThanOrEqualTo(banner.bottom),
          reason: 'the chip is under the banner: banner $banner, chip $chip');
      expect(chip.top - banner.bottom, lessThanOrEqualTo(8),
          reason: 'the chip is ${chip.top - banner.bottom} dp under the '
              'banner; a glance at the rung does not reach it');
      final between = find.byWidgetPredicate((w) => w is Text).evaluate().where(
        (e) {
          final r = tester.getRect(find.byWidget(e.widget).first);
          return r.top >= banner.bottom - 0.5 &&
              r.bottom <= chip.top + 0.5 &&
              r.height > 0;
        },
      );
      expect(between, isEmpty,
          reason: 'text between the banner and the chip: '
              '${between.map((e) => (e.widget as Text).data).toList()}');
    });

    testWidgets(
        '$lang: -3 °C with no visibility reading: no banner, and the chip '
        'stays above the description', (tester) async {
      await _boot(tester, lang, null);
      expect(find.byKey(_banner), findsNothing,
          reason: 'control: with no whiteout and no share the card draws no '
              'rung');
      expect(find.byKey(_chip), findsOneWidget,
          reason: 'control: -3 °C draws the frozen-road chip');
      final chip = tester.getRect(find.byKey(_chip));
      final description = tester.getRect(find.byKey(_description));
      expect(chip.bottom, lessThanOrEqualTo(description.top),
          reason: 'with no rung the chip keeps its place above the '
              'description: chip $chip, description $description');
    });
  }
}
