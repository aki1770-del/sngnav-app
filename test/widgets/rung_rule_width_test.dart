/// The rung's width rule, held on the real banner: 20 dp on 停車の検討, 8 dp on
/// 注意して走行, none on the lowest rung.
///
/// Why, written before the act (2026-10-07). The rule is the one channel that
/// tells the three rungs apart when hue is gone: as fills alone, 停車の検討 and
/// 注意して走行 are 1.200:1 apart and 注意して走行 and the lowest rung 1.011:1.
/// Nothing in the suite read the rule. Golden 03 holds the top rung's rule and
/// golden 02 the lowest rung's absence of one, but no golden draws the middle
/// rung from the app, and the two capture files that draw it copy the banner
/// into their own source, so they cannot fail when the app's banner changes.
///
/// What this holds, on the app's own banner (`_driveHudPanel` in lib/main.dart),
/// in Japanese and English, each state reached through measured inputs and the
/// real share, never through a test value:
///   - a measured 80 m whiteout, no share: 停車の検討, a 20 dp rule;
///   - a share with a trusted fix and no weather reading: 注意して走行, 8 dp;
///   - a share with a trusted fix under a measured clear 1500 m: the lowest
///     rung, and no rule at all.
/// Where there is a rule, it runs the banner's full height at its leading edge
/// and is drawn in the rung's own ink, so it cannot be present and invisible.
///
/// Bound: host widget test with the test font; it reads layout boxes and widget
/// colours, not a seen frame. Whether 20 dp against 8 dp is told apart at a
/// glance has not been tested with a person.
library;

import 'dart:async';

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/akita_map.dart' show akitaStation;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/assessed_fix.dart';
import '../support/fake_alert_actuators.dart';
import '../support/rung_on_card.dart';

final _t0 = DateTime.utc(2026, 1, 14, 21);

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

Future<JmaResult> Function() _measured(int visibility) =>
    () async => JmaSuccess(JmaObservation(
          stationId: '32402',
          stationName: '秋田',
          temperatureCelsius: 5,
          humidityPercent: 50,
          windMetersPerSecond: 2,
          snowDepthCm: null,
          precipitation10mMm: 0,
          visibilityMeters: visibility,
          observedAtJstKey: _jstKey(_t0),
          fetchedAt: _t0,
        ));

Future<JmaResult> _noReading() async =>
    const JmaFailure('test: no observation');

PositionAvailable _fixAtAkita(DateTime at) => PositionAvailable(
      latitude: akitaStation.latitude,
      longitude: akitaStation.longitude,
      accuracyMeters: 35,
      timestamp: at,
    );

const _bannerKey = Key('drive-hud-caution-banner');
const _ruleKey = Key('drive-hud-rung-rule');
const _headlineKey = Key('drive-hud-rung');

/// Boots the app; with [share], she shares and the GPS gives one trusted fix
/// (a share's first fix is held: the same place one second earlier first).
Future<void> _reach(
  WidgetTester tester,
  String lang,
  Future<JmaResult> Function() jma, {
  required bool share,
}) async {
  final positions = StreamController<PositionFix>.broadcast();
  addTearDown(positions.close);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    key: UniqueKey(),
    actuators: FakeAlertActuators(),
    locale: Locale(lang),
    clock: () => _t0,
    jmaFetch: jma,
    locationConsent: true,
    positionSource: () => positions.stream,
    developerPageEntry: false,
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  if (!share) return;
  final control = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(control);
  await tester.pump();
  await tester.tap(control);
  await tester.pump();
  positions.add(justBefore(_fixAtAkita(_t0)));
  await tester.pump();
  positions.add(_fixAtAkita(_t0));
  await tester.pump();
  await tester.pump();
}

void _expectRule(WidgetTester tester, DriveAction rung, double? width) {
  expect(rungOnCard(), rung,
      reason: 'control: the card shows the rung this case names');
  final banner = find.byKey(_bannerKey);
  expect(banner, findsOneWidget, reason: 'control: the banner is drawn');
  if (width == null) {
    expect(find.byKey(_ruleKey), findsNothing,
        reason: 'the lowest rung carries no rule; one is drawn');
    return;
  }
  final rule = find.descendant(of: banner, matching: find.byKey(_ruleKey));
  expect(rule, findsOneWidget,
      reason: 'the ${rung.name} rung must carry its rule inside its banner');
  final r = tester.getRect(rule);
  final b = tester.getRect(banner);
  expect(r.width, closeTo(width, 0.01),
      reason: 'the ${rung.name} rule is ${r.width} dp wide, not $width dp');
  expect(r.left, closeTo(b.left, 0.01),
      reason: 'the rule is not at the banner\'s leading edge: $r in $b');
  expect(r.top, closeTo(b.top, 0.01), reason: 'the rule starts below the '
      'banner\'s top: $r in $b');
  expect(r.bottom, closeTo(b.bottom, 0.01), reason: 'the rule stops above '
      'the banner\'s bottom: $r in $b');
  final ruleInk = tester.widget<Container>(find.byKey(_ruleKey)).color;
  final headlineInk = tester.widget<Text>(find.byKey(_headlineKey)).style?.color;
  expect(ruleInk, isNotNull, reason: 'the rule has no colour of its own');
  expect(ruleInk, headlineInk,
      reason: 'the rule is not drawn in the rung\'s own ink: rule $ruleInk, '
          'headline $headlineInk');
}

void main() {
  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang: a measured 80 m whiteout, no share: 20 dp on the top '
        'rung', (tester) async {
      await _reach(tester, lang, _measured(80), share: false);
      _expectRule(tester, DriveAction.considerStopping, 20);
    });

    testWidgets('$lang: a share with no weather reading: 8 dp on the middle '
        'rung', (tester) async {
      await _reach(tester, lang, _noReading, share: true);
      _expectRule(tester, DriveAction.heightenedCaution, 8);
    });

    testWidgets('$lang: a share under a measured clear 1500 m: no rule on the '
        'lowest rung', (tester) async {
      await _reach(tester, lang, _measured(1500), share: true);
      _expectRule(tester, DriveAction.continueDriving, null);
    });
  }
}
