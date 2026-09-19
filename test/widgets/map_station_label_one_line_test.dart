/// The station label on her map is one word on one line, at every text size
/// a driver can choose, on the English page.
///
/// Why, written before the act (2026-09-19). The label was the kanji 秋田 on
/// every page. On the English page it is now "Akita", which is wider, and the
/// marker box it sits in is 60 px. Rendered at text scale 2.0 on a phone-sized
/// page, the box broke the word into "Akit" and "a", on two lines. A place name
/// broken in the middle is a word she has to reassemble at a glance.
///
/// Read with Roboto, the face Android draws this word in, found inside the
/// Flutter SDK running the test. Without it the widths are not Android's and
/// the test fails rather than measuring something else.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../render_see/render_see_env.dart';
import '../support/fake_alert_actuators.dart';

int _lines(RenderParagraph ro) {
  final tp = TextPainter(
    text: ro.text,
    textDirection: ro.textDirection,
    textScaler: ro.textScaler,
    maxLines: ro.maxLines,
  )..layout(maxWidth: ro.softWrap ? ro.constraints.maxWidth : double.infinity);
  final n = tp.computeLineMetrics().length;
  tp.dispose();
  return n;
}

void main() {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('map_label');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('en, text scale $scale: "Akita" on the map is one line',
        (tester) async {
      final loaded = await tester.runAsync(
              () => loadDiscoveredFace('Roboto', FaceSearch.roboto)) ??
          false;
      expect(loaded, isTrue,
          reason: 'without Roboto the word is not measured at Android\'s width');
      // A phone's geometry: 1080 x 2340 at 2.75, status and navigation bars.
      tester.view.devicePixelRatio = 2.75;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.padding = const FakeViewPadding(top: 73, bottom: 130);
      tester.view.viewPadding = const FakeViewPadding(top: 73, bottom: 130);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.reset();
      });

      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('en'),
        clock: () => DateTime.utc(2026, 1, 14, 21),
        jmaFetch: () async => const JmaFailure('no network in this test'),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);

      final label =
          find.descendant(of: find.byType(AkitaMap), matching: find.text('Akita'));
      expect(label, findsOneWidget, reason: 'control: the label is drawn');
      final ro = tester.renderObject<RenderParagraph>(
          find.descendant(of: label, matching: find.byType(RichText)));
      final lines = _lines(ro);
      // ignore: avoid_print
      print('MAP_LABEL scale $scale: 「Akita」 $lines line(s), '
          '${ro.size.width.toStringAsFixed(1)} x '
          '${ro.size.height.toStringAsFixed(1)} logical px');
      expect(lines, 1,
          reason: 'the station name is broken across $lines lines');
    });
  }
}
