/// The prefecture observations card at phone width, read with one face: the
/// station failure line and the descriptors against the floor, and each value
/// with its unit on one line, with the scale it is drawn at printed.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/corridor_row.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../render_see/render_see_env.dart';
import 'fake_alert_actuators.dart';
import 'painted_text_contrast.dart';

/// Three stations answer, two fail.
http.Client _jmaNetwork() => MockClient((req) async {
  final u = req.url.toString();
  if (u.endsWith('/amedas/data/latest_time.txt')) {
    return http.Response('2026-01-15T06:00:00+09:00', 200);
  }
  final m = RegExp(r'/point/(\d+)/').firstMatch(u);
  if (m != null) {
    const ok = {
      '32286': (-2.1, 30, 7.5),
      '32402': (-1.0, 12, 6.0),
      '32551': (-4.3, 58, 2.1),
    };
    final v = ok[m.group(1)];
    if (v == null) return http.Response('', 500);
    return http.Response(
      '{"20260115060000":{"temp":[${v.$1},0],"snow":[${v.$2},0],'
      '"wind":[${v.$3},0],"humidity":[88,0]}}',
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  return http.Response('', 404);
});

Future<void> _settleReal(WidgetTester tester, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final _valueWithUnit = RegExp(r'^-?\d+(\.\d+)? (cm|°C|m/s)$');

/// Registers the card's tests with [face] loaded as the app's default family,
/// from the font file at [path]. One face per test file: a family loaded once
/// in a test process is not replaced by a second load of the same name.
void prefectureCardTests({required String face, required String path}) {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('prefecture_card');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tmp.path,
        );
  });

  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang, $face, 393 px, two stations failed: the failure '
        'line and the descriptors are above the floor, and every value keeps '
        'its unit on one line', (tester) async {
      final fontsLoaded =
          await tester.runAsync(() => loadCjkFamily('Roboto', [path])) ?? false;
      expect(
        fontsLoaded,
        isTrue,
        reason: 'without real glyph metrics the line test cannot fail',
      );
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(393 * 2.0, 852 * 2.0);
      addTearDown(tester.view.reset);

      await http.runWithClient(() async {
        await tester.pumpWidget(
          SngnavApp(
            actuators: FakeAlertActuators(),
            locale: Locale(lang),
            clock: () => DateTime.utc(2026, 1, 14, 21),
            jmaFetch: () async => const JmaFailure('no network in this test'),
          ),
        );
        await _settleReal(tester);
        final source = find.byKey(const Key('prefecture-observations-source'));
        await Scrollable.ensureVisible(tester.element(source), alignment: 0.7);
        await tester.pump();

        final rows = find.byType(CorridorRow);
        expect(
          rows,
          findsNWidgets(corridorStations.length),
          reason: 'precondition: the card has its rows',
        );
        final failed = find.byKey(const Key('corridor-station-fetch-failed'));
        expect(
          failed,
          findsNWidgets(2),
          reason: 'precondition: two stations failed',
        );

        final inRows = <RenderObject>{
          for (final e
              in find
                  .descendant(of: rows, matching: find.byType(RichText))
                  .evaluate())
            e.renderObject!,
        };
        final painted = paintedTextOutsideMap(tester);
        final problems = <String>[];

        // R3: the failure line.
        final failureLines = painted.where(
          (p) => p.key == 'corridor-station-fetch-failed',
        );
        expect(failureLines, hasLength(2));
        for (final p in failureLines) {
          if (p.foreground != Colors.red.shade900 ||
              (p.fontSize ?? 0) < 11 ||
              p.ratio == null ||
              p.ratio! < kTextContrastFloor) {
            problems.add('failure line: ${p.describe()}');
          }
          // ignore: avoid_print
          print('$lang $face failure line: ${p.describe()}');
        }

        // R6: the descriptors of the rows that answered.
        final descriptors = {for (final s in corridorStations) s.descriptor};
        final shown = painted.where((p) => descriptors.contains(p.text));
        expect(
          shown,
          hasLength(3),
          reason: 'precondition: three answered rows show a descriptor',
        );
        for (final p in shown) {
          if (p.foreground != Colors.grey.shade700 ||
              p.ratio == null ||
              p.ratio! < kTextContrastFloor) {
            problems.add('descriptor: ${p.describe()}');
          }
          // ignore: avoid_print
          print('$lang $face descriptor: ${p.describe()}');
        }

        // R7: every value with its unit, on one line, all of it painted.
        var values = 0;
        for (final ro
            in tester.allRenderObjects.whereType<RenderParagraph>().toSet()) {
          if (!inRows.contains(ro)) continue;
          final text = ro.text.toPlainText();
          if (!_valueWithUnit.hasMatch(text)) continue;
          values++;
          final tp =
              TextPainter(
                text: ro.text,
                textDirection: ro.textDirection,
                textScaler: ro.textScaler,
                maxLines: ro.maxLines,
              )..layout(
                maxWidth: ro.softWrap
                    ? ro.constraints.maxWidth
                    : double.infinity,
              );
          final lines = tp.computeLineMetrics().length;
          tp.dispose();
          final laidOut = ro.size.width;
          final natural = ro.getMaxIntrinsicWidth(double.infinity);
          // The scale it is drawn at: the fitting box's width over the
          // paragraph's, 1 where no fitting box holds it.
          RenderFittedBox? fit;
          for (
            RenderObject? a = ro.parent;
            a != null && a is! RenderFlex;
            a = a.parent
          ) {
            if (a is RenderFittedBox) {
              fit = a;
              break;
            }
          }
          final scale = fit == null
              ? 1.0
              : (fit.size.width / laidOut).clamp(0.0, 1.0);
          // ignore: avoid_print
          print(
            '$lang $face 「$text」 lines $lines, width ${laidOut.toStringAsFixed(1)}'
            ' of ${natural.toStringAsFixed(1)}, drawn at scale '
            '${scale.toStringAsFixed(3)}',
          );
          if (lines != 1 || laidOut + 0.5 < natural) {
            problems.add(
              '「$text」: $lines lines, laid out '
              '${laidOut.toStringAsFixed(1)} of ${natural.toStringAsFixed(1)}',
            );
          }
        }
        expect(
          values,
          9,
          reason: 'precondition: three answered rows, three values each',
        );
        expect(problems, isEmpty, reason: problems.join('\n'));
      }, _jmaNetwork);
    });
  }
}
