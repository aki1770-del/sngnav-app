/// OPS-066 render-SEE captures for the N15 feed-loss visible counterparts
/// (session-scope; NOT a CI pixel assertion) — produces PNGs into
/// `ladder_out/feed_loss/` so the reviewer can LOOK at the new cards before
/// the change lands:
///
///   feed_loss_stale_ice_ja.png — stale banner + retained fields + the
///     visible stale black-ice card (the exact spoken stamped line)
///   feed_loss_forecast_memory_ja.png — empty-observation note + the visible
///     forecast-memory card (the exact spoken plan-time line + capture caption)
///
/// Run with:
///   flutter test --update-goldens test/render_see/feed_loss_panel_capture_test.dart
///
/// The injected [SngnavApp.jmaFetch]/[SngnavApp.jmaForecastFetch] + clock
/// drive the REAL failure panel hermetically — the same code path a live
/// feed loss drives. On-device render remains the device hour's job.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/forecast_validity.dart';
import 'package:sngnav_app/services/jma_forecast_fetch.dart';

import '../support/fake_alert_actuators.dart';

const String _key0630 = '20260115063000';

DateTime _clockAt(Duration age) => DateTime.utc(2026, 1, 15, 6, 30, 0)
    .subtract(const Duration(hours: 9))
    .add(age);

// The founding radiative-frost window: +2°C / 70% / measured no precip.
JmaObservation _iceObs() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 2.0,
      humidityPercent: 70,
      windMetersPerSecond: 1.5,
      snowDepthCm: 12,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: _key0630,
      fetchedAt: DateTime(2026, 1, 15, 6, 30),
    );

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    final tmp = await Directory.systemTemp.createTemp('fm_cache_feed_loss');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  Future<void> sizeAndShow(WidgetTester tester, Finder anchor) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    await tester.ensureVisible(find.text('Retry'));
    await tester.pump();
    await tester.ensureVisible(anchor);
    await tester.pump();
  }

  testWidgets('feed loss — stale banner + retained fields + stale-ice card',
      (tester) async {
    JmaResult next = JmaSuccess(_iceObs());
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 30)),
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();

    next = const JmaFailure('offline');
    await tester.ensureVisible(find.text('Re-fetch'));
    await tester.pump();
    await tester.tap(find.text('Re-fetch'));
    await tester.pump();
    await tester.pump();

    // Anchor on the BANNER so the full failure panel (banner → retained
    // fields → hazard card) fits in one frame.
    await sizeAndShow(tester, find.byKey(const Key('jma-stale-banner')));
    expect(find.byKey(const Key('stale-ice-visible')), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../ladder_out/feed_loss/feed_loss_stale_ice_ja.png'),
    );
  });

  testWidgets('dead zone — empty-observation note + forecast-memory card',
      (tester) async {
    var now = _clockAt(const Duration(minutes: 5));
    JmaResult next = JmaSuccess(_iceObs());
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      clock: () => now,
      jmaFetch: () async => next,
      jmaForecastFetch: () async => JmaForecastSuccess(
        hazards: [
          ForecastHazard(
            kind: ForecastHazardKind.snow,
            window: ValidityWindow(
              start: DateTime.utc(2026, 1, 14, 21, 0), // 06:00 JST
              end: DateTime.utc(2026, 1, 15, 3, 0), // 12:00 JST
              provenance: ValidityProvenance.publisherDeclared,
            ),
            publisherText: '雪　所により　ふぶく',
            source: 'JMA 秋田地方気象台',
            issuedAt: DateTime.utc(2026, 1, 14, 20, 0),
            areaName: '沿岸',
          ),
        ],
        issuedAt: DateTime.utc(2026, 1, 14, 20, 0),
      ),
    ));
    await tester.pump();
    await tester.pump();

    now = _clockAt(const Duration(minutes: 90)); // T+90: observation expired
    next = const JmaFailure('the centre is gone');
    await tester.ensureVisible(find.text('Re-fetch'));
    await tester.pump();
    await tester.tap(find.text('Re-fetch'));
    await tester.pump();
    await tester.pump();

    await sizeAndShow(
        tester, find.byKey(const Key('forecast-memory-visible')));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
          '../../ladder_out/feed_loss/feed_loss_forecast_memory_ja.png'),
    );
  });
}
