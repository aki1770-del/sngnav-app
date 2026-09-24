/// The line under the map must not read a refusal, or any other cause, out of
/// an exception's words.
///
/// Why this test exists. Rendered 2026-09-14: a GPS stream error whose error
/// text was "Location permission denied" drew 現在地不明 on the map, offered
/// 停止, and raised the caution a stream error raises, all correctly from the
/// typed cause. The line under the map said
/// 「GPS を取得できません — 位置情報の許可が拒否されました。…」: a refusal,
/// read from text. The app wraps a stream error as `'GPS stream error: $e'`
/// and an init error as `'GPS init error: $e'`, so the tail is exception text
/// the app does not control. The reason localizer matched the words
/// "permission denied" inside that tail before it ever looked at the wrapper.
///
/// The rule tested here. The wrapper names the failure. Nothing inside an
/// exception's text selects what the line says about the cause.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show PermissionDeniedException;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

/// Every reason text the app itself can produce whose words select a
/// translation. Inside a wrapper, none of them may select anything.
const _contentReasons = [
  'Location services disabled',
  'Location service check timed out — platform did not answer',
  'Location permission check timed out — platform did not answer',
  'Location permission request timed out — no answer from the platform dialog',
  'Location permission denied',
  'Location permission permanently denied — change in OS settings',
  'Degraded GPS fix — non-finite coordinate (lat=NaN, lon=1.0, acc=5.0)',
  'GPS stream ended by the platform',
];

void main() {
  const ja = AppL10n(Locale('ja'));

  group('a wrapped exception text is the failure the wrapper names', () {
    for (final inner in _contentReasons) {
      test('GPS stream error: "$inner"', () {
        final line =
            ja.gpsUnavailable('GPS stream error: $inner', routeSettingOpen: true);
        expect(line, contains('GPSストリームのエラー'),
            reason: 'the wrapper says stream error: $line');
        expect(line, isNot(contains('拒否')), reason: line);
        expect(line, isNot(contains('無効')), reason: line);
        expect(line, isNot(contains('時間がかかりすぎ')), reason: line);
      });
      // Ruled 2026-09-14: an exception while starting, of a type the app
      // does not act on, names no GPS and no error. It gets the no-position line.
      // This pinned 「GPS初期化のエラー」 until then.
      test('GPS init error: "$inner"', () {
        final line =
            ja.gpsUnavailable('GPS init error: $inner', routeSettingOpen: true);
        expect(line, '現在地不明 — 位置を取得できませんでした。地図は表示されたままです。',
            reason: 'nothing inside the wrapper selects the words');
      });
    }

    test('CONTROL: an unwrapped reason keeps its own translation', () {
      expect(
          ja.gpsUnavailable('Location services disabled', routeSettingOpen: true),
          contains('位置情報サービスが無効です'));
      expect(
          ja.gpsUnavailable('GPS stream ended by the platform',
              routeSettingOpen: true),
          contains('GPSの受信が端末側で終了しました'));
      expect(ja.gpsUnavailable('GPS stream error: boom', routeSettingOpen: true),
          contains('GPSストリームのエラー'));
    });
  });

  group('in the app: a stream error whose text reads like a denial', () {
    Future<String?> lineAfter(
        WidgetTester tester, void Function(StreamController<PositionFix>) act) async {
      final positions = StreamController<PositionFix>.broadcast();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(SngnavApp(
      // Not about the consent act; that is guarded in
      // test/widgets/location_consent_act_and_privacy_surface_test.dart.
      locationConsent: true,

        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
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
      act(positions);
      await tester.pump();
      await tester.pump();
      final f = find.byKey(const Key('her-status-line'));
      final line = f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
      await positions.close();
      return line;
    }

    testWidgets('says what a plain stream error says, not that she refused',
        (tester) async {
      final plain = await lineAfter(
          tester, (p) => p.addError(StateError('platform GPS stream failed')));
      final readsDenied = await lineAfter(tester,
          (p) => p.addError(const PermissionDeniedException('Location permission denied')));

      expect(plain, contains('GPSストリームのエラー'),
          reason: 'control: the plain stream error line');
      expect(readsDenied, plain);
      expect(find.byKey(const ValueKey('her-position-unknown-label')),
          findsOneWidget,
          reason: 'the map already follows the typed cause');
    });
  });
}
