/// At the large system text a driver can choose, the map's first screen lays
/// out without a single overflow.
///
/// Why this test exists. Rendered 2026-09-14 at text scale 2.0 with real CJK
/// fonts, on a 393x852 phone: the 秋田 station marker overflowed its marker
/// box by 5 px (akita_map.dart, `_StationMarker`), and the "no fetch yet" row
/// of the advisory card by 82 px (widgets/advisory_cards.dart). An overflow is
/// a layout defect at any scale: in a debug build it paints warning stripes,
/// and in any build the content no longer fits where it was put.
///
/// The rule tested here: no exception while her first screen lays out at
/// scale 1.5 or 2.0, at launch and after a refusal for good. The positions of
/// the map, the line under it and 閉じる against the fold are printed as
/// MEASURES, not asserted: where they should sit at large text is not decided.
///
/// Real glyph metrics matter here: with the default test font the marker
/// fits, so this test loads a real CJK face first and refuses to pass without
/// one.
library;

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../render_see/render_see_env.dart';
import '../support/fake_alert_actuators.dart';

// The face is discovered on this host (render_see_env.dart,
// japaneseFontSearchOrder) rather than named by absolute path. Those paths
// lived here until 2026-09-18 and are why this suite failed on the first CI
// run, 35300438549: a runner has neither of them installed. Any face that
// really covers Japanese serves here — what this suite needs is real glyph
// metrics rather than the test font's uniform boxes, not one particular
// design. On the dev host and on CI the search returns the same two Debian
// files it used to name, so the measured overflows do not move.

Future<void> _frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _rect(WidgetTester tester, Finder f) {
  if (f.evaluate().isEmpty) return 'not found';
  final r = tester.getRect(f.first);
  return '${r.top.toStringAsFixed(0)}..${r.bottom.toStringAsFixed(0)}';
}

String _first(Object? e) =>
    e == null ? 'none' : '$e'.split('\n').firstWhere((l) => l.trim().isNotEmpty);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('her_map_large_text');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  for (final scale in const [1.5, 2.0]) {
    testWidgets('text scale $scale: no layout overflow on her first screen',
        (tester) async {
      final fontsLoaded = await tester.runAsync(
              () => loadDiscoveredFace('Roboto', FaceSearch.japanese)) ??
          false;
      await tester.runAsync(loadMaterialIconsFont);
      expect(fontsLoaded, isTrue,
          reason: 'without real glyph metrics this test cannot fail');

      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(393 * 2.0, 852 * 2.0);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final positions = StreamController<PositionFix>.broadcast();
      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        clock: () => DateTime.utc(2026, 1, 14, 21),
        jmaFetch: () async => const JmaFailure('no network in this test'),
        positionSource: () => positions.stream,
      ));
      await _frames(tester, 12);
      final atLaunch = tester.takeException();
      final mapAtLaunch = _rect(tester, find.byType(AkitaMap));

      final share = find.byKey(const Key('share-location-button'));
      await tester.ensureVisible(share);
      await tester.pump();
      await tester.tap(share);
      await tester.pump();
      final refusal = await tester.runAsync(() => herPositionStream(
            isServiceEnabled: () async => true,
            checkPermission: () async => LocationPermission.deniedForever,
            requestPermission: () async => LocationPermission.denied,
          ).first);
      positions.add(refusal!);
      await _frames(tester, 8);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await _frames(tester, 4);
      final afterRefusal = tester.takeException();
      print('[LARGE_TEXT] scale $scale phone 393x852 logical, fold at 852: '
          'map at launch $mapAtLaunch · after denied for good: map '
          '${_rect(tester, find.byType(AkitaMap))}, line '
          '${_rect(tester, find.byKey(const Key('her-status-line')))}, 閉じる '
          '${_rect(tester, find.widgetWithText(TextButton, '閉じる'))}');
      print('[LARGE_TEXT] scale $scale first exception at launch: '
          '${_first(atLaunch)} · after the refusal: ${_first(afterRefusal)}');
      await positions.close();

      expect(atLaunch, isNull, reason: _first(atLaunch));
      expect(afterRefusal, isNull, reason: _first(afterRefusal));
    });
  }
}
