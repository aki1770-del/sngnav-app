/// The dead-zone forecast never calls a forecast fetched during the drive
/// 出発前 / "before departure".
///
/// WHY, written before the act (FSE, R122 round 4b). The forecast memory is
/// re-captured by the 10-minute observation refresh once the held memory is
/// 3 hours old, and nothing gates that on the drive (sngnav-app 2d51bdc,
/// main.dart: the ticker calls _refreshJma; its success calls
/// _captureTripHazardMemory; neither reads _driveActive). So on a drive that
/// outlasts the memory's age, the memory she hears in the dead zone was
/// fetched AFTER she left, and both the spoken line (「出発前に取得した…」) and
/// the caption (「出発前 HH:MM に取得した…」) still call it 出発前. The caption
/// then prints the contradiction on one line: a time after she left, labelled
/// before she left. The error runs toward "older than it is", so the line
/// never sounds live; it is still untrue, and a driver in unexpected snow who
/// catches one untrue clause has reason to doubt the true ones beside it.
///
/// Scenario, on the real app path, both languages: the memory is captured at
/// 06:35 JST at launch; she starts a drive at 06:40; at 09:40 the ticker's
/// observation refresh succeeds and re-captures (the memory is 3 h 05 min
/// old); at 10:50 the observation feed is lost past its 60-minute retain
/// bound, and the forecast memory is spoken and shown.
///
/// Controls: the forecast was fetched twice (launch, then mid-drive); the
/// caption shows the mid-drive capture time, so the test is reading the
/// re-captured memory and not the launch one; in Japanese the forecast line
/// was spoken. If a later change stops re-capturing during a drive, the first
/// two controls fail, and that change has to be decided on its own: a memory
/// never refreshed on a long drive is staler, not truer.
///
/// BOUNDS. Lexical on the words: it reads what is drawn and what the app
/// asked to speak, not what she hears.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/forecast_validity.dart';
import 'package:sngnav_app/services/jma_forecast_fetch.dart';
import 'package:sngnav_app/widgets/keep_together.dart';

import '../support/fake_alert_actuators.dart';

/// A JST wall-clock time on 2026-01-15, as a UTC instant.
DateTime _jst(int h, int m) =>
    DateTime.utc(2026, 1, 15, h, m).subtract(const Duration(hours: 9));

JmaObservation _obs(String observedAtJstKey) => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 8.0,
      humidityPercent: 70,
      windMetersPerSecond: null,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: observedAtJstKey,
      fetchedAt: DateTime(2026, 1, 15, 6, 30),
    );

/// Snow on JMA's own 6-hourly boundaries, 06:00 to 12:00 JST,
/// publisher-declared: valid for the whole scenario.
ForecastHazard _snowHazard() => ForecastHazard(
      kind: ForecastHazardKind.snow,
      window: ValidityWindow(
        start: DateTime.utc(2026, 1, 14, 21, 0),
        end: DateTime.utc(2026, 1, 15, 3, 0),
        provenance: ValidityProvenance.publisherDeclared,
      ),
      publisherText: '雪　所により　ふぶく',
      source: 'JMA 秋田地方気象台',
      issuedAt: DateTime.utc(2026, 1, 14, 20, 0),
      areaName: '沿岸',
    );

void main() {
  for (final (lang, departure) in [
    ('ja', '出発前'),
    ('en', 'before departure'),
  ]) {
    testWidgets(
        '$lang: a forecast fetched mid-drive is not called "$departure"',
        (tester) async {
      final fake = FakeAlertActuators();
      final ctrl = StreamController<PositionFix>.broadcast();
      addTearDown(ctrl.close);
      var now = _jst(6, 35);
      JmaResult next = JmaSuccess(_obs('20260115063000'));
      final forecastFetchedAt = <DateTime>[];

      Future<void> fixAt(DateTime t) async {
        ctrl.add(PositionAvailable(
          latitude: 39.7186,
          longitude: 140.1024,
          accuracyMeters: 8,
          timestamp: t,
        ));
        await tester.pump();
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(SngnavApp(
        locationConsent: true,
        actuators: fake,
        locale: Locale(lang),
        clock: () => now,
        jmaFetch: () async => next,
        jmaForecastFetch: () async {
          forecastFetchedAt.add(now);
          return JmaForecastSuccess(
            hazards: [_snowHazard()],
            issuedAt: DateTime.utc(2026, 1, 14, 20, 0),
          );
        },
        positionSource: () => ctrl.stream,
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      // 06:40: she starts the drive.
      now = _jst(6, 40);
      final share = find.byKey(const Key('share-location-button'));
      await tester.ensureVisible(share);
      await tester.pump();
      await tester.tap(share);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(ctrl.hasListener, isTrue, reason: 'control: a drive is running');
      await fixAt(now);

      // 09:40, still driving: the ticker's observation refresh succeeds, and
      // the 3-hour-old memory is re-captured.
      now = _jst(9, 40);
      next = JmaSuccess(_obs('20260115093000'));
      await fixAt(now);
      await tester.pump(const Duration(minutes: 10));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(forecastFetchedAt, [_jst(6, 35), _jst(9, 40)],
          reason: 'control: the forecast is fetched at launch and again '
              'mid-drive, three hours into it');

      // 10:50, still driving: the observation feed is lost past its bound.
      now = _jst(10, 50);
      next = const JmaFailure('dead zone');
      await fixAt(now);
      await tester.pump(const Duration(minutes: 10));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      final card = find.byKey(const Key('forecast-memory-visible'));
      expect(card, findsOneWidget,
          reason: 'control: the dead-zone forecast card is drawn');
      final line = tester
          .widget<Text>(
              find.descendant(of: card, matching: find.byType(Text)).first)
          .data!;
      final caption = tester
          .widget<KeepTogetherText>(
              find.descendant(of: card, matching: find.byType(KeepTogetherText)))
          .data;
      final midDrive = DateFormat('HH:mm').format(_jst(9, 40).toLocal());
      expect(caption, contains(midDrive),
          reason: 'control: the caption must show the mid-drive capture '
              '($midDrive), or this test is reading the launch memory');

      // Every channel is read before the verdict, so one failure cannot
      // hide another.
      final untrue = <String>[];
      if (caption.contains(departure)) {
        untrue.add('the caption, drawn: "$caption"');
      }
      if (line.contains(departure)) {
        untrue.add('the forecast line, drawn: "$line"');
      }
      if (lang == 'ja') {
        final spoken = fake.spoken
            .where((s) => s.text.contains('これは観測ではなく予報です'))
            .toList();
        expect(spoken, isNotEmpty,
            reason: 'control: the forecast line was spoken in Japanese');
        for (final s in spoken) {
          if (s.text.contains(departure)) {
            untrue.add('the forecast line, spoken: "${s.text}"');
          }
        }
      }
      expect(untrue, isEmpty,
          reason: 'a forecast fetched at $midDrive, three hours after the '
              'drive began at 06:40 JST, is called "$departure" by: '
              '${untrue.join(' | ')}');
    });
  }
}
