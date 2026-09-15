/// What a driver is given before and after her first trusted fix of a share,
/// where a measured condition raises caution: five cases the band tests do
/// not reach.
///
/// Why, written before the act. Ruled 2026-09-15: before a share's first
/// trusted fix, a position failure is an unlocated position that compounds
/// with what is measured; from 999 m to 500 m she is given heightened caution,
/// as a positioned driver there is. Ruled 2026-09-14: that keying is "no
/// trusted fix", never the event's type; a later share is judged by that share
/// alone; and a failure after a trusted fix in the same share is unchanged,
/// because that is the loss of a position she was relying on. Each case below
/// holds one of those, and each fails under a plausible landing that passes
/// every band test.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import 'support/fake_alert_actuators.dart';

const _stopLine = '安全にできるときは、安全な場所での停車も選べます。';
const _slowLine = '速度を落とし、車間を広げて、前方に注意してください。';

final _start = DateTime.utc(2026, 1, 14, 21);
var _now = _start;
int? _vis;

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

Future<JmaResult> _jma() async => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: _vis,
      observedAtJstKey: _jstKey(_now),
      fetchedAt: _now,
    ));

/// The caution banner's rung, read from its colour under its key.
String _rung(WidgetTester t) {
  final f = find.byKey(const Key('drive-hud-caution-banner'));
  if (f.evaluate().isEmpty) return 'none';
  final color =
      (t.widget<Container>(f.first).decoration! as BoxDecoration).color;
  if (color == Colors.red.shade100) return 'considerStopping';
  if (color == Colors.amber.shade100) return 'heightenedCaution';
  if (color == Colors.grey.shade200) return 'continueDriving';
  return 'unreadable $color';
}

List<String> _spoken(FakeAlertActuators a, [int from = 0]) =>
    [for (final s in a.spoken.skip(from)) s.text];
List<String> _felt(FakeAlertActuators a, [int from = 0]) =>
    [for (final h in a.haptics.skip(from)) '$h'.split('.').last];

Future<FakeAlertActuators> _boot(WidgetTester t,
    Stream<PositionFix> Function() source) async {
  final a = FakeAlertActuators();
  _now = _start;
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump();
  await t.pumpWidget(SngnavApp(
    actuators: a,
    locale: const Locale('ja'),
    clock: () => _now,
    jmaFetch: _jma,
    positionSource: source,
  ));
  await t.pump();
  await t.pump();
  return a;
}

Future<void> _advance(WidgetTester t, Duration d,
    {void Function()? each}) async {
  var left = d;
  while (left > Duration.zero) {
    final step =
        left > const Duration(seconds: 15) ? const Duration(seconds: 15) : left;
    _now = _now.add(step);
    each?.call();
    await t.pump(step);
    left -= step;
  }
  for (var i = 0; i < 3; i++) {
    await t.pump();
  }
}

Future<void> _share(WidgetTester t) async {
  final b = find.byKey(const Key('share-location-button'));
  await t.ensureVisible(b);
  await t.pump();
  await t.tap(b);
  for (var i = 0; i < 5; i++) {
    await t.pump();
  }
  expect(find.byKey(const Key('share-location-button')), findsNothing,
      reason: 'control: sharing started');
}

Future<void> _stop(WidgetTester t) async {
  final s = find.text('停止');
  await t.ensureVisible(s.first);
  await t.pump();
  await t.tap(s.first);
  await t.pump();
}

Position _position(DateTime at, {bool hasAccuracy = true}) => Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: at,
      accuracy: hasAccuracy ? 10 : 0,
      hasAccuracy: hasAccuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Stream<PositionFix> _granted(StreamController<Position> p) => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => p.stream,
    );

Stream<PositionFix> _failedStart() => herPositionStream(
    isServiceEnabled: () async => throw StateError('no location provider'));

void main() {
  testWidgets(
      'a first sample with no measured accuracy under a measured 700 m is '
      'given what a positioned driver there is given, at 1 s and 61 s',
      (tester) async {
    _vis = 700;
    final ok = StreamController<Position>();
    final positioned = await _boot(tester, () => _granted(ok));
    await _share(tester);
    ok.add(_position(_now));
    await _advance(tester, const Duration(seconds: 1),
        each: () => ok.add(_position(_now)));
    expect(_rung(tester), 'heightenedCaution', reason: 'control');
    expect(_spoken(positioned), [_slowLine], reason: 'control');
    expect(_felt(positioned), ['warning'], reason: 'control');

    final p = StreamController<Position>();
    final a = await _boot(tester, () => _granted(p));
    await _share(tester);
    p.add(_position(_now, hasAccuracy: false));
    for (final (label, step) in [
      ('1 s', const Duration(seconds: 1)),
      ('61 s', const Duration(seconds: 60)),
    ]) {
      await _advance(tester, step);
      expect(_rung(tester), 'heightenedCaution', reason: 'at $label');
      expect(_spoken(a), [_slowLine], reason: 'at $label');
      expect(_felt(a), ['warning'], reason: 'at $label');
    }
  });

  testWidgets(
      'a stream error under a measured 700 m, then a trusted fix, then '
      'silence: losing that fix is told at the top rung within 76 s',
      (tester) async {
    _vis = 700;
    final p = StreamController<Position>();
    final a = await _boot(tester, () => _granted(p));
    await _share(tester);
    p.addError(StateError('provider hiccup'));
    await _advance(tester, const Duration(seconds: 5));
    p.add(_position(_now));
    await _advance(tester, const Duration(seconds: 1));
    expect(_rung(tester), 'heightenedCaution',
        reason: 'control: the trusted fix under 700 m');
    final s0 = a.spoken.length;
    final h0 = a.haptics.length;
    await _advance(tester, const Duration(seconds: 75));
    expect(_rung(tester), 'considerStopping',
        reason: 'the position she was given is lost');
    expect(_spoken(a, s0), contains(_stopLine));
    expect(_felt(a, h0), contains('critical'));
  });

  testWidgets(
      'a later share is judged by that share alone: a failed share under a '
      'measured 300 m, then 20 min later a failed share under 700 m is given '
      'heightened caution', (tester) async {
    _vis = 300;
    final a = await _boot(tester, _failedStart);
    await _share(tester);
    await _advance(tester, const Duration(seconds: 1));
    expect(_rung(tester), 'considerStopping', reason: 'control: first share');
    await _stop(tester);
    _vis = 700;
    await _advance(tester, const Duration(minutes: 20));
    await _share(tester);
    for (final (label, step) in [
      ('1 s', const Duration(seconds: 1)),
      ('61 s', const Duration(seconds: 60)),
    ]) {
      await _advance(tester, step);
      expect(_rung(tester), 'heightenedCaution', reason: 'at $label');
    }
    expect(a.spoken, isNotEmpty, reason: 'control: the first share was told');
  });

  testWidgets(
      'a positioned driver\'s first trusted fix under a measured 300 m is '
      'spoken to and felt at heightened caution, never the top rung',
      (tester) async {
    _vis = 300;
    final p = StreamController<Position>();
    final a = await _boot(tester, () => _granted(p));
    await _share(tester);
    p.add(_position(_now));
    await _advance(tester, const Duration(seconds: 1),
        each: () => p.add(_position(_now)));
    expect(_rung(tester), 'heightenedCaution');
    expect(_spoken(a), [_slowLine]);
    expect(_felt(a), ['warning']);
  });

  testWidgets(
      'a failed start held under a measured clear 1,500 m, then 700 m from '
      'the 10-minute refresh: heightened caution, spoken and felt',
      (tester) async {
    _vis = 1500;
    final a = await _boot(tester, _failedStart);
    await _share(tester);
    await _advance(tester, const Duration(seconds: 1));
    expect(_rung(tester), 'none', reason: 'control: held, nothing given');
    _vis = 700;
    await _advance(tester, const Duration(minutes: 10, seconds: 15));
    expect(_rung(tester), 'heightenedCaution');
    expect(_spoken(a), [_slowLine]);
    expect(_felt(a), ['warning']);
  });
}
