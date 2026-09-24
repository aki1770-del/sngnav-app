/// Where the app asks for weather warnings after a share ends.
///
/// Why, written before the act. The 10-minute refresh asked for warnings at
/// the last position of a share, and nothing cleared that position: after
/// 停止, or after she refused location, the app went on asking about the
/// place she had been, for the life of the app, while a driver who never
/// shared is asked about the station's place. Warnings raise her caution
/// rung, so a share she ended still decided what she was shown. Nothing may
/// come from a share she ended: after it ends, the point the refresh asks is
/// the never-shared driver's. No surface shows the point, so these tests
/// read it at the publisher.
library;

import 'dart:async';

import 'package:condition_aggregator/condition_aggregator.dart'
    show Advisory, AdvisoryProvider, AdvisorySource;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/provider_coverage.dart';

import '../support/fake_alert_actuators.dart';

const _words = AppL10n(Locale('ja'));

/// Her share's place, about 60 km from the station: far enough that no
/// rounding can make the two points the same.
const _herLat = 39.3100;
const _herLon = 140.5600;

final _start = DateTime.utc(2026, 1, 14, 21);
var _now = _start;

typedef _Point = ({double latitude, double longitude});

class _RecordingPublisher implements AdvisoryProvider {
  final asked = <_Point>[];

  @override
  AdvisorySource get source => AdvisorySource.jmaJapan;

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    asked.add((latitude: latitude, longitude: longitude));
    return const [];
  }
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
      observedAtJstKey: '202601150600',
      fetchedAt: _now,
    ));

Future<_RecordingPublisher> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
}) async {
  final publisher = _RecordingPublisher();
  _now = _start;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
      // Not about the consent act; that is guarded in
      // test/widgets/location_consent_act_and_privacy_surface_test.dart.
      locationConsent: true,

    actuators: FakeAlertActuators(),
    locale: const Locale('ja'),
    clock: () => _now,
    jmaFetch: _jma,
    positionSource: source,
    advisoryProviders: [
      CoveredProvider(provider: publisher, covers: (_, _) => true),
    ],
  ));
  await tester.pump();
  await tester.pump();
  return publisher;
}

Future<void> _advance(WidgetTester tester, Duration d,
    {void Function()? each}) async {
  var left = d;
  while (left > Duration.zero) {
    final step =
        left > const Duration(seconds: 15) ? const Duration(seconds: 15) : left;
    _now = _now.add(step);
    each?.call();
    await tester.pump(step);
    left -= step;
  }
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

Future<void> _tapShare(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  expect(find.byKey(const Key('share-location-button')), findsNothing,
      reason: 'control: sharing started');
}

Future<void> _tapStop(WidgetTester tester) async {
  final s = find.widgetWithText(TextButton, _words.stop);
  expect(s, findsOneWidget, reason: 'control: the row offers 停止');
  await tester.ensureVisible(s);
  await tester.pump();
  await tester.tap(s);
  await tester.pump();
  await tester.pump();
}

bool _isHers(_Point p) => p.latitude == _herLat && p.longitude == _herLon;

/// The point a driver who never shared is asked about at the 10-minute
/// refresh, measured through the app, not written down here.
Future<_Point> _neverSharedPoint(WidgetTester tester) async {
  final publisher = await _boot(tester);
  final before = publisher.asked.length;
  await _advance(tester, const Duration(minutes: 10, seconds: 5));
  expect(publisher.asked.length, greaterThan(before),
      reason: 'control: the 10-minute refresh asked the publisher');
  final p = publisher.asked.last;
  expect(_isHers(p), isFalse, reason: 'control: the station is not her place');
  return p;
}

void main() {
  late StreamController<PositionFix> positions;

  void fix() => positions.add(PositionAvailable(
        latitude: _herLat,
        longitude: _herLon,
        accuracyMeters: 10,
        timestamp: _now,
      ));

  setUp(() => positions = StreamController<PositionFix>.broadcast());
  tearDown(() => positions.close());

  testWidgets(
      'after 停止 the 10-minute refresh asks where it asks for a driver who '
      'never shared, and never again at the place the ended share was',
      (tester) async {
    final never = await _neverSharedPoint(tester);

    final publisher = await _boot(tester, source: () => positions.stream);
    await _tapShare(tester);
    fix();
    await _advance(tester, const Duration(seconds: 30), each: fix);
    expect(publisher.asked.where(_isHers), isNotEmpty,
        reason: 'control: while she shares, the app asks at her place');

    await _tapStop(tester);
    final atStop = publisher.asked.length;
    await _advance(tester, const Duration(minutes: 10));
    final after = publisher.asked.sublist(atStop);
    expect(after, isNotEmpty, reason: 'control: the refresh ran after 停止');
    expect(after.where(_isHers), isEmpty,
        reason: 'after 停止: nothing asked at the ended share\'s place');
    expect(after.last, never,
        reason: 'after 停止: the never-shared driver\'s point');

    await _advance(tester, const Duration(minutes: 20));
    expect(publisher.asked.sublist(atStop).where(_isHers), isEmpty,
        reason: '30 min after 停止: still nothing at her old place');
  });

  testWidgets(
      'after she refuses location mid-share, the refresh asks where it asks '
      'for a driver who never shared', (tester) async {
    final never = await _neverSharedPoint(tester);

    final publisher = await _boot(tester, source: () => positions.stream);
    await _tapShare(tester);
    fix();
    await _advance(tester, const Duration(seconds: 30), each: fix);
    expect(publisher.asked.where(_isHers), isNotEmpty,
        reason: 'control: while she shares, the app asks at her place');

    positions.add(const PositionUnavailable('revoked',
        cause: PositionUnavailableCause.permissionDenied));
    await _advance(tester, const Duration(seconds: 1));
    final atRefusal = publisher.asked.length;
    await _advance(tester, const Duration(minutes: 10));
    final after = publisher.asked.sublist(atRefusal);
    expect(after, isNotEmpty, reason: 'control: the refresh ran');
    expect(after.where(_isHers), isEmpty,
        reason: 'after her no: nothing asked at her last place');
    expect(after.last, never,
        reason: 'after her no: the never-shared driver\'s point');
  });

  testWidgets(
      'a new share at the same place asks at her place again at its first '
      'position, not only at the next refresh', (tester) async {
    final publisher = await _boot(tester, source: () => positions.stream);
    await _tapShare(tester);
    fix();
    await _advance(tester, const Duration(seconds: 30), each: fix);
    await _tapStop(tester);
    await _advance(tester, const Duration(minutes: 10));
    final beforeShare = publisher.asked.length;
    expect(_isHers(publisher.asked.last), isFalse,
        reason: 'control: the refresh after 停止 asked elsewhere');

    await _tapShare(tester);
    fix();
    await _advance(tester, const Duration(seconds: 30), each: fix);
    expect(publisher.asked.sublist(beforeShare).where(_isHers), isNotEmpty,
        reason: 'the new share asks at her place within 30 s');
  });
}
