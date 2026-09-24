/// After she refuses location, the map's words for it are chosen in one place.
///
/// WHY. What the map should show after her "no" was under review, so the
/// refusal was first carried to the map with its behaviour unchanged: the same
/// black 現在地不明 pill as a GPS that never found her. The decision of
/// 2026-09-13 gave it its own words, 位置情報オフ, in that one branch; the
/// words and the line under the map are pinned in
/// `her_location_off_words_test.dart`.
///
/// Pinned here:
/// * `isLocationRefusal` is true exactly for her "no" (now or for good), read
///   from the real position stream, and false for the platform failing;
/// * the refusal reaches the map as `positionRefused`;
/// * in the real app the refusal and location services off now say different
///   things, and only the refusal is flagged.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_map_inputs.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_controller.dart';

import '../support/fake_alert_actuators.dart';

const _unknownKey = ValueKey('her-position-unknown-label');
const _offKey = ValueKey('her-location-off-label');

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

Stream<PositionFix> _refusing() => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async => LocationPermission.denied,
    );

Stream<PositionFix> _refusingForGood() => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.deniedForever,
    );

Stream<PositionFix> _servicesOff() =>
    herPositionStream(isServiceEnabled: () async => false);

void main() {
  group('isLocationRefusal, read from the real position stream', () {
    test('her "no" now', () async {
      expect(isLocationRefusal(await _refusing().first), isTrue);
    });

    test('her "no" for good', () async {
      expect(isLocationRefusal(await _refusingForGood().first), isTrue);
    });

    test('location services off is not her refusal', () async {
      final fix = await _servicesOff().first;
      expect(fix, isA<PositionUnavailable>(), reason: 'control');
      expect(isLocationRefusal(fix), isFalse);
    });

    test('a permission request that never answers is not her refusal',
        () async {
      final fix = await herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () => Completer<LocationPermission>().future,
        permissionRequestTimeout: const Duration(milliseconds: 40),
      ).first;
      expect(fix, isA<PositionUnavailable>(), reason: 'control');
      expect(isLocationRefusal(fix), isFalse);
    });

    test('a stream error, a fix, and nothing are not', () {
      expect(isLocationRefusal(const PositionUnavailable('GPS stream error')),
          isFalse);
      expect(
          isLocationRefusal(PositionAvailable(
            latitude: 39.7,
            longitude: 140.1,
            accuracyMeters: 15,
            timestamp: DateTime.utc(2026, 1, 15),
          )),
          isFalse);
      expect(isLocationRefusal(null), isFalse);
    });
  });

  test('herMapInputs carries the refusal, and nothing else changes', () async {
    final refusal = await _refusing().first;
    final off = await _servicesOff().first;
    HerMapInputs inputs(PositionFix fix) {
      final h = DriveHudController(
          actuators: FakeAlertActuators(), localeTag: 'ja');
      h.onPositionFix(fix, now: DateTime.utc(2026, 1, 15));
      expect(h.estimate!.mode, LocalizationMode.lost, reason: 'control');
      return herMapInputs(
          fix: fix,
          estimate: h.estimate,
          isMock: false,
          anchoredThisSession: false);
    }

    final r = inputs(refusal), o = inputs(off);
    expect(r.refused, isTrue);
    expect(o.refused, isFalse);
    expect((r.position, r.accuracyMeters, r.degraded, r.lost),
        (o.position, o.accuracyMeters, o.degraded, o.lost));
  });

  group('in the real app', () {
    Future<void> share(
        WidgetTester tester, Stream<PositionFix> Function() source) async {
      // A fresh app each time: pumping the same widget type again would keep
      // the previous run's state, already sharing.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(SngnavApp(
      // Not about the consent act; that is guarded in
      // test/widgets/location_consent_act_and_privacy_surface_test.dart.
      locationConsent: true,

        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        clock: DateTime.now,
        jmaFetch: () async => JmaSuccess(_clearObs()),
        positionSource: source,
      ));
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('現在地を共有'));
      await tester.pump();
      await tester.tap(find.text('現在地を共有'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    ({Key? key, String? words, bool refused}) mapSays(WidgetTester tester) {
      Key? key;
      for (final k in const [_unknownKey, _offKey]) {
        if (find.byKey(k).evaluate().isNotEmpty) key = k;
      }
      final text = key == null
          ? null
          : find.descendant(of: find.byKey(key), matching: find.byType(Text));
      return (
        key: key,
        words: text == null ? null : tester.widget<Text>(text).data,
        refused:
            tester.widget<AkitaMap>(find.byType(AkitaMap)).positionRefused,
      );
    }

    testWidgets(
        'after her "no" the map says 位置情報オフ; with location services off '
        'it still says 現在地不明; only the refusal is flagged', (tester) async {
      await share(tester, _refusing);
      final refusal = mapSays(tester);

      await share(tester, _servicesOff);
      final off = mapSays(tester);

      expect(refusal.refused, isTrue);
      expect(off.refused, isFalse);
      expect((refusal.key, refusal.words), (_offKey, '位置情報オフ'));
      expect((off.key, off.words), (_unknownKey, '現在地不明'));
    });
  });
}
