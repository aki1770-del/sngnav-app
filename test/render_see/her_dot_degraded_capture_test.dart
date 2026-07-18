/// OPS-066 render-SEE capture — #1≡#4 silent-GPS-blackout fix (2026-07-18).
///
/// The bug: on a silent GPS drought the map dot — the surface HER eyes snap to
/// — kept painting a CONFIDENT blue "you are here" on a road she had passed,
/// while only the HUD text degraded. These captures let VAA LOOK at the fix:
///
///   render_out/14_her_dot_confident.png  — trusted GPS: solid BLUE dot, tight
///                                           blue accuracy circle (honest here).
///   render_out/15_her_dot_degraded.png   — dead-reckoning/lost: GREY stale
///                                           dot, GREY circle grown to the
///                                           honest confidence radius. The map
///                                           can no longer assert a confident
///                                           position it does not have.
///
///   flutter test --update-goldens test/render_see/her_dot_degraded_capture_test.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/akita_map.dart';

import 'render_see_env.dart';

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    // flutter_map's built-in cache calls path_provider — give it a temp dir.
    final tmp = await Directory.systemTemp.createTemp('her_dot_render_see');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  // HER last-known point (near Akita station) — the point `_herFix` freezes on.
  const her = LatLng(39.7167, 140.0983);

  Widget frame(AkitaMap map) => MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(child: SizedBox(width: 600, child: map)),
        ),
      );

  Future<void> settleMap(WidgetTester tester, Widget app) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump(const Duration(milliseconds: 30));
      }
    });
  }

  testWidgets('14 — trusted GPS: confident BLUE dot + tight circle',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(600 * 2, 360 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await settleMap(
      tester,
      frame(const AkitaMap(
        height: 340,
        herPosition: her,
        herAccuracyMeters: 20,
        positionDegraded: false,
      )),
    );
    await expectLater(
      find.byType(AkitaMap),
      matchesGoldenFile('../../render_out/14_her_dot_confident.png'),
    );
  });

  testWidgets('15 — silent drought (dead-reckoning/lost): GREY stale dot + '
      'circle grown to the honest confidence radius', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(600 * 2, 360 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await settleMap(
      tester,
      frame(const AkitaMap(
        height: 340,
        herPosition: her,
        // The map circle grows to the honest, monotonically-growing radius.
        herAccuracyMeters: 380,
        positionDegraded: true,
      )),
    );
    await expectLater(
      find.byType(AkitaMap),
      matchesGoldenFile('../../render_out/15_her_dot_degraded.png'),
    );
  });
}
