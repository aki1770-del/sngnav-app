/// A share's first fix, held: what she is shown and told through the app.
///
/// Why, written before the act (2026-10-05). The GPS trust verdict has
/// nothing to judge a share's first fix against, so the fix is held, not
/// trusted, and the fix after it is judged against it. Three things follow in
/// the app, and each is pinned here because a design that met the verdict's
/// own tests could still get it wrong where she is:
///  1. the next fix, one interval later, anchors her (5 s is the interval the
///     fused provider is asked for when the app sets none);
///  2. under a measured 300 m the held first fix is a share starting normally,
///     not a share that failed to start: she is given the road's own rung, as
///     a positioned driver there is. Given the failed-start rung instead she
///     got the top rung, its critical vibration and the line inviting her to
///     stop at every share start, for one fix interval (measured on this
///     branch before it was fixed);
///  3. a held first fix and then nothing is a start that failed after all: at
///     the drought it takes the failed-start rung. Without that a share whose
///     GPS died after its first fix kept the road's rung for good.
///
/// The helpers are those of her_failed_start_rung_by_band_test.dart. Every fix
/// is synthetic; nothing here is a device reading.
library;

import 'dart:async';

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/fake_alert_actuators.dart';

const _hud = DriveHudLocalizer();
final _stopLine = _hud.spokenGuidance(DriveAction.considerStopping, 'ja');
final _slowLine = _hud.spokenGuidance(DriveAction.heightenedCaution, 'ja');
const _critical = 'HapticCuePattern.critical';
const _warning = 'HapticCuePattern.warning';

final _start = DateTime.utc(2026, 1, 14, 21);
var _clockNow = _start;

typedef _Given = ({String panel, List<String> spoken, List<String> haptics});

/// The caution banner's rung, from its own headline mapped back through the
/// app's localizer: 'no rung' when no banner is built, and a headline no rung
/// produces fails loudly.
String _panel(WidgetTester tester) {
  final banner = find.byKey(const Key('drive-hud-caution-banner'));
  if (banner.evaluate().isEmpty) return 'no rung';
  final texts = [
    for (final e in find
        .descendant(of: banner, matching: find.byType(Text))
        .evaluate())
      (e.widget as Text).data ?? '',
  ];
  final rungs = <String>{
    for (final s in texts)
      for (final r in DriveAction.values)
        for (final advisory in const [false, true])
          for (final measured in const [false, true])
            for (final calm in const [false, true])
              if (s ==
                  _hud.actionHeadline(r, 'ja',
                      advisoryUnconfirmed: advisory,
                      measuredUnconfirmed: measured,
                      calmNoteInForce: calm))
                r.name,
  };
  return rungs.length == 1 ? rungs.single : 'UNREADABLE $texts';
}

_Given _given(WidgetTester tester, FakeAlertActuators a,
        {int spokenFrom = 0, int hapticsFrom = 0}) =>
    (
      panel: _panel(tester),
      spoken: [for (final s in a.spoken.skip(spokenFrom)) s.text],
      haptics: [for (final h in a.haptics.skip(hapticsFrom)) '$h'],
    );

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

/// Warm and dry, stamped when the app fetches it. Wind 2 m/s fires no watch.
JmaResult _observedNow(int? visibilityMeters, {double wind = 2}) =>
    JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: wind,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: visibilityMeters,
      observedAtJstKey: _jstKey(_clockNow),
      fetchedAt: _clockNow,
    ));

Future<void> _advance(WidgetTester tester, Duration d) async {
  var left = d;
  while (left > Duration.zero) {
    final step =
        left > const Duration(seconds: 15) ? const Duration(seconds: 15) : left;
    _clockNow = _clockNow.add(step);
    await tester.pump(step);
    left -= step;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  required Future<JmaResult> Function() jma,
}) async {
  final a = FakeAlertActuators();
  _clockNow = _start;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
      // Not about the consent act; that is guarded in
      // test/widgets/location_consent_act_and_privacy_surface_test.dart.
      locationConsent: true,

    actuators: a,
    locale: const Locale('ja'),
    clock: () => _clockNow,
    jmaFetch: jma,
    positionSource: source,
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _tapShare(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await _settle(tester);
  expect(find.byKey(const Key('share-location-button')), findsNothing,
      reason: 'control: sharing started');
}

Position _position(DateTime t) => Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: t,
      accuracy: 10,
      hasAccuracy: true,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Stream<PositionFix> _granted(StreamController<Position> platform) =>
    herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => platform.stream,
    );

void main() {
  testWidgets(
      'in a measured clear 1,500 m: the first fix is held, her map says '
      '現在地不明 and no rung is given; the next fix, 5 s on, anchors her',
      (tester) async {
    final platform = StreamController<Position>();
    final a = await _boot(tester,
        source: () => _granted(platform), jma: () async => _observedNow(1500));
    await _tapShare(tester);
    platform.add(_position(_clockNow));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('her-dot-real-fix')), findsNothing,
        reason: 'held: nothing to judge it against');
    expect(find.byKey(const ValueKey('her-position-unknown-label')),
        findsOneWidget);
    expect(find.textContaining('GPS 良好'), findsNothing);

    await _advance(tester, const Duration(seconds: 4));
    platform.add(_position(_clockNow));
    await _settle(tester);
    expect(find.byKey(const ValueKey('her-dot-real-fix')), findsOneWidget,
        reason: 'the next fix anchors within one interval');
    expect(find.byKey(const ValueKey('her-position-unknown-label')),
        findsNothing);
    expect(find.textContaining('GPS 良好'), findsWidgets);
    expect(_given(tester, a).haptics, isEmpty,
        reason: 'nothing is felt at a clear start');
    await platform.close();
  });

  testWidgets(
      'under a measured 300 m: the held first fix is a normal start, given the '
      'road\'s own rung, never the top one; the next fix changes nothing told',
      (tester) async {
    final platform = StreamController<Position>();
    final a = await _boot(tester,
        source: () => _granted(platform), jma: () async => _observedNow(300));
    await _tapShare(tester);
    platform.add(_position(_clockNow));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 1));
    final first = _given(tester, a);
    expect(first.panel, 'heightenedCaution',
        reason: 'the rung a positioned driver under 300 m is given');
    expect(first.spoken, [_slowLine]);
    expect(first.haptics, [_warning]);

    await _advance(tester, const Duration(seconds: 4));
    platform.add(_position(_clockNow));
    await _settle(tester);
    final g = _given(tester, a);
    expect(g.panel, 'heightenedCaution');
    expect(g.spoken, [_slowLine], reason: 'nothing more is spoken');
    expect(g.haptics, [_warning], reason: 'nothing more is felt');
    expect(g.spoken, isNot(contains(_stopLine)));
    expect(g.haptics, isNot(contains(_critical)));
    await platform.close();
  });

  testWidgets(
      'under a measured 300 m: the held first fix and then nothing; at the '
      'drought the start has failed after all, and she is given the '
      'failed-start rung', (tester) async {
    final platform = StreamController<Position>();
    final a = await _boot(tester,
        source: () => _granted(platform), jma: () async => _observedNow(300));
    await _tapShare(tester);
    platform.add(_position(_clockNow));
    await _settle(tester);
    await _advance(tester, const Duration(seconds: 1));
    expect(_given(tester, a).panel, 'heightenedCaution', reason: 'control');

    await _advance(tester, const Duration(seconds: 46));
    final g = _given(tester, a);
    expect(g.panel, 'considerStopping',
        reason: 'the failed-start rung at 300 m');
    expect(g.haptics, contains(_critical));
    await platform.close();
  });
}
