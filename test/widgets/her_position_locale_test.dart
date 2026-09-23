/// What the app says about her position follows the app's locale.
///
/// WHY, written before the act. The app follows the device locale and ships
/// English, but two lines about her position were hardcoded Japanese: the line
/// under the map in dead reckoning passed `'ja'` to the mode label and joined
/// a Japanese literal to it, and the drive panel's position-trust row passed
/// `'ja'` too. An English-locale driver read 「GPS 途絶（推測航法） · 最後の
/// 位置 ±135m」 under her map. The localizer already carries the English.
///
/// Pinned in the real app, through its own localization delegates:
/// * English: the dead-reckoning line under the map, and the drive panel's
///   mode value, are English; the lost line and the map words (landed with
///   the words at the top of the map) stay English;
/// * Japanese: the same lines are byte-identical to what they were.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

const _statusKey = Key('her-status-line');
const _unknownKey = ValueKey('her-position-unknown-label');

JmaObservation _clearObs() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 15.0,
      humidityPercent: 30,
      windMetersPerSecond: 1.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260115063000',
      fetchedAt: DateTime(2026, 7, 15, 6, 30),
    );

void main() {
  final start = DateTime.utc(2026, 1, 15, 6, 30);
  var now = start;

  /// Share, one trusted fix, then [silence] with no fix while sharing stays
  /// on: the blackout watchdog's next 15 s tick polls at the injected clock.
  Future<StreamController<PositionFix>> sharedThenSilent(
    WidgetTester tester, {
    required Locale locale,
    required String shareLabel,
    required Duration silence,
  }) async {
    now = start;
    final positions = StreamController<PositionFix>.broadcast();
    await tester.pumpWidget(SngnavApp(
      // Not about the consent act; that is guarded in
      // test/widgets/location_consent_act_and_privacy_surface_test.dart.
      locationConsent: true,

      actuators: FakeAlertActuators(),
      locale: locale,
      clock: () => now,
      jmaFetch: () async => JmaSuccess(_clearObs()),
      positionSource: () => positions.stream,
    ));
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.text(shareLabel));
    await tester.pump();
    await tester.tap(find.text(shareLabel));
    await tester.pump();
    positions.add(PositionAvailable(
      latitude: 39.7195,
      longitude: 140.1180,
      accuracyMeters: 15,
      timestamp: start,
    ));
    await tester.pump();
    now = start.add(silence);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    return positions;
  }

  String? statusLine(WidgetTester tester) {
    final f = find.byKey(_statusKey);
    return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
  }

  group('English', () {
    testWidgets('dead reckoning: the line under the map is English, whole',
        (tester) async {
      final positions = await sharedThenSilent(tester,
          locale: const Locale('en'),
          shareLabel: 'Share my location',
          silence: const Duration(seconds: 60));

      expect(statusLine(tester),
          'GPS lost — dead reckoning · last position ±135 m');
      expect(find.textContaining('最後の位置'), findsNothing);
      expect(find.textContaining('推測航法'), findsNothing);
      await positions.close();
    });

    testWidgets(
        'dead reckoning: the drive panel names the position mode in English',
        (tester) async {
      final positions = await sharedThenSilent(tester,
          locale: const Locale('en'),
          shareLabel: 'Share my location',
          silence: const Duration(seconds: 60));

      expect(find.text('GPS lost — dead reckoning'), findsOneWidget);
      expect(find.text('GPS 途絶（推測航法）'), findsNothing);
      await positions.close();
    });

    testWidgets('lost: the map words and the line are English (control)',
        (tester) async {
      final positions = await sharedThenSilent(tester,
          locale: const Locale('en'),
          shareLabel: 'Share my location',
          silence: const Duration(seconds: 180));

      expect(statusLine(tester), 'Position unknown · last position 3 min ago');
      expect(
          find.descendant(
              of: find.byKey(_unknownKey),
              matching: find.text('Position unknown')),
          findsOneWidget);
      expect(find.text('現在地不明'), findsNothing);
      await positions.close();
    });
  });

  group('English: the whole drive panel (decided 2026-09-13)', () {
    // The panel's driver-facing rows and caution banner. Its developer
    // controls (the demo visibility bands, the blackout button) are not rows
    // she reads, and are not asserted here.
    final cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff]');

    List<String> textsUnder(WidgetTester tester, Finder root) => [
          for (final e in find
              .descendant(of: root, matching: find.byType(Text))
              .evaluate())
            (e.widget as Text).data ?? '',
        ];

    testWidgets(
        'dead reckoning: row labels, values and the caution banner are all '
        'English', (tester) async {
      final positions = await sharedThenSilent(tester,
          locale: const Locale('en'),
          shareLabel: 'Share my location',
          silence: const Duration(seconds: 60));

      for (final k in ['Position trust:', 'Uncertainty:']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
      for (final k in ['現在地の信頼度:', '誤差:', '理由:', '不明な点:', '目安速度:']) {
        expect(find.text(k), findsNothing, reason: k);
      }
      expect(find.text('within ~135 m'), findsOneWidget);

      final banner = find.byKey(const Key('drive-hud-caution-banner'));
      expect(banner, findsOneWidget, reason: 'control: the banner is drawn');
      final bannerTexts = textsUnder(tester, banner);
      expect(bannerTexts.where((t) => t.isNotEmpty), isNotEmpty);
      expect(bannerTexts.where(cjk.hasMatch), isEmpty,
          reason: 'the caution banner an English reader sees: $bannerTexts');

      // Every row this panel labels, English label and English value.
      for (final (label, rowName) in [
        ('Why:', 'reasons'),
        ('Unknowns:', 'unknowns'),
        ('Speed hint:', 'sight hint'),
      ]) {
        final f = find.text(label);
        if (f.evaluate().isEmpty) continue;
        final row = find.ancestor(of: f, matching: find.byType(Row)).first;
        final rowTexts = textsUnder(tester, row);
        expect(rowTexts.where(cjk.hasMatch), isEmpty,
            reason: '$rowName row: $rowTexts');
      }
      expect(find.text('Why:'), findsOneWidget,
          reason: 'control: dead reckoning gives reasons');
      expect(find.text('Unknowns:'), findsOneWidget,
          reason: 'control: dead reckoning gives unknowns');
      await positions.close();
    });
  });

  group('Japanese: unchanged', () {
    testWidgets('dead reckoning: byte-identical line and panel value',
        (tester) async {
      final positions = await sharedThenSilent(tester,
          locale: const Locale('ja'),
          shareLabel: '現在地を共有',
          silence: const Duration(seconds: 60));

      expect(statusLine(tester), 'GPS 途絶（推測航法） · 最後の位置 ±135m');
      expect(find.text('GPS 途絶（推測航法）'), findsOneWidget);
      for (final k in ['現在地の信頼度:', '誤差:', '理由:', '不明な点:']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
      expect(find.text('誤差 約 135 m'), findsOneWidget);
      await positions.close();
    });
  });
}
