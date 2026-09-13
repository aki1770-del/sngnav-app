/// Two English strings, ruled 2026-09-14, byte-exact; the Japanese unchanged.
///
/// 1. The refusal line under the map said the same thing twice in English:
///    "No location access — this app is not allowed to access location." The
///    sentence after the dash now adds only what the head does not: it is a
///    permission, and it is this app's.
/// 2. The drive panel's low-visibility speed row read "Guide speed:
///    Stop-within-sight guide ~N km/h", a stronger claim than the package
///    makes ("a hint to ease toward, never a commanded speed"). It now reads
///    "Speed hint: could stop within sight at ~N km/h": the basis, with the
///    speed left to her.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/fake_alert_actuators.dart';

void main() {
  const ja = AppL10n(Locale('ja'));
  const en = AppL10n(Locale('en'));
  const hud = DriveHudLocalizer();

  group('the refusal line', () {
    test('English, denied', () {
      expect(
        en.locationOffStatus(permanently: false, routeSettingOpen: true),
        'No location access — location permission is off for this app. '
        'The map remains; the route panel still works by tap.',
      );
    });
    test('English, denied for good', () {
      expect(
        en.locationOffStatus(permanently: true, routeSettingOpen: true),
        'No location access — location permission is off for this app. '
        'If you want to change this, you can do so in the device settings. '
        'The map remains; the route panel still works by tap.',
      );
    });
    test('the English line still starts with the words on the map', () {
      for (final permanently in const [false, true]) {
        expect(en.locationOffStatus(permanently: permanently, routeSettingOpen: true),
            startsWith('${en.locationOffLabel} — '));
      }
    });
    test('Japanese unchanged', () {
      expect(
        ja.locationOffStatus(permanently: false, routeSettingOpen: true),
        '位置情報オフ — このアプリには位置情報へのアクセスが許可されていません。'
        '地図は表示されたままです。ルート欄はタップで引き続き使えます。',
      );
      expect(
        ja.locationOffStatus(permanently: true, routeSettingOpen: true),
        '位置情報オフ — このアプリには位置情報へのアクセスが許可されていません。'
        '変更する場合は端末の設定から行えます。'
        '地図は表示されたままです。ルート欄はタップで引き続き使えます。',
      );
    });
  });

  group('the speed row', () {
    // 40 km/h, from the package's metres per second.
    const mps = 40 / 3.6;

    test('English label and value', () {
      expect(en.driveHudGuideSpeedLabel, 'Speed hint');
      expect(hud.sightHintLabel(mps, 'en'), 'could stop within sight at ~40 km/h');
    });
    test('Japanese unchanged', () {
      expect(ja.driveHudGuideSpeedLabel, '目安速度');
      expect(hud.sightHintLabel(mps, 'ja'), '見える範囲で止まれる目安 約 40 km/h');
    });
    testWidgets(
        'in the app, English, whiteout band after a trusted fix: the row reads '
        'the ruled label and value', (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('en'),
        clock: () => DateTime.utc(2026, 1, 14, 21),
        jmaFetch: () async => const JmaFailure('no network in this test'),
        positionSource: () => positions.stream,
      ));
      await tester.pump();
      await tester.pump();
      final share = find.byKey(const Key('share-location-button'));
      await tester.ensureVisible(share);
      await tester.pump();
      await tester.tap(share);
      await tester.pump();
      positions.add(PositionAvailable(
        latitude: 39.7167,
        longitude: 140.0983,
        accuracyMeters: 15,
        timestamp: DateTime.utc(2026, 1, 14, 21),
      ));
      await tester.pump();
      await tester.pump();

      final band = find.byKey(const Key('drive-hud-visibility'));
      await tester.ensureVisible(band);
      await tester.pump();
      await tester.tap(band);
      await tester.pumpAndSettle();
      // English band label since 2026-09-14; the bands were Japanese on
      // every device until then.
      await tester.tap(find.text('Whiteout ~80 m').last);
      await tester.pumpAndSettle();

      final label = find.text('Speed hint:');
      expect(label, findsOneWidget,
          reason: 'the row is drawn under a whiteout reading');
      expect(find.text('Guide speed:'), findsNothing);
      final row = find.ancestor(of: label, matching: find.byType(Row)).first;
      final value = find.descendant(
          of: row,
          matching: find.textContaining(
              RegExp(r'^could stop within sight at ~\d+ km/h$')));
      expect(value, findsOneWidget);
      await positions.close();
    });

    test('the English row names no target, limit or command', () {
      final row =
          '${en.driveHudGuideSpeedLabel}: ${hud.sightHintLabel(mps, 'en')}'
              .toLowerCase();
      for (final word in const [
        'guide',
        'safe speed',
        'recommended',
        'target',
        'limit',
        'advisory speed',
        'slow to',
        'drive at',
      ]) {
        expect(row, isNot(contains(word)), reason: row);
      }
    });
  });
}
